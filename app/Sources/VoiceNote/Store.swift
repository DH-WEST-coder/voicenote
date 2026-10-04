import AVFoundation
import AppKit
import Carbon.HIToolbox
import Foundation

let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "flac", "aif", "aiff", "caf", "ogg", "opus", "mp4", "mov", "m4b"]

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    /// 녹음 하나하나(받아쓰기 단위)
    @Published var jobs: [Job] = []
    /// 노트(수업 1회)와 프로젝트
    @Published var sessions: [Session] = []
    @Published var projects: [Project] = []
    @Published var selectedSessionID: UUID? {
        didSet {
            UserDefaults.standard.set(selectedSessionID?.uuidString, forKey: "selectedSession")
            if let p = selectedSession?.projectID { lastProjectID = p }
        }
    }
    /// 다음 새 노트·녹음이 들어갈 프로젝트(선택한 노트의 프로젝트를 따라가고, 도구막대 메뉴에서 바꿀 수 있다)
    @Published var lastProjectID: UUID? { didSet { UserDefaults.standard.set(lastProjectID?.uuidString, forKey: "lastProject") } }
    @Published var enginePath: String { didSet { UserDefaults.standard.set(enginePath, forKey: "enginePath") } }
    @Published var exportEnabled: Bool { didSet { UserDefaults.standard.set(exportEnabled, forKey: "exportEnabled") } }
    @Published var exportFolder: String { didSet { UserDefaults.standard.set(exportFolder, forKey: "exportFolder") } }
    @Published var chargingOnly: Bool { didSet { UserDefaults.standard.set(chargingOnly, forKey: "chargingOnly"); pump() } }
    @Published var recordMode = "post"   // post(녹음 후 처리) / live(2단계, 아직 없음)
    @Published var recordingJobID: UUID?
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var message: String?
    @Published var transcriptRevision = 0

    private var recorder: AVAudioRecorder?
    private var recordURL: URL?
    private var recordStart: Date?
    private var recordTimer: Timer?
    private var runningID: UUID?
    private var runningProcess: Process?
    private var _recordTarget: UUID?
    /// 디버그: 마이크 대신 이 오디오 파일을 실시간 속도로 엔진에 넣고 녹음처럼 동작한다(--live-input-file)
    nonisolated(unsafe) static var liveInputFile: String?

    private init() {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if args.contains("--power-selftest") { print(PowerMonitor.selfTest()); exit(0) }
        if let sb = value("--sandbox") { Paths.sandbox = URL(fileURLWithPath: sb) }
        if let lf = value("--live-input-file") { Store.liveInputFile = lf }
        let d = UserDefaults.standard
        enginePath = value("--engine") ?? d.string(forKey: "enginePath") ?? "/Users/DH_WEST/LocalAI_Project/voice"
        exportEnabled = value("--export-dir") != nil ? true : d.bool(forKey: "exportEnabled")
        exportFolder = value("--export-dir") ?? d.string(forKey: "exportFolder") ?? ""
        lastProjectID = d.string(forKey: "lastProject").flatMap(UUID.init(uuidString:))
        chargingOnly = d.bool(forKey: "chargingOnly")

        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        loadState()
        loadSessions()
        selectedSessionID = d.string(forKey: "selectedSession").flatMap(UUID.init(uuidString:)).flatMap { id in sessions.first { $0.id == id }?.id }
        log("launch args=\(args.dropFirst())")
        if let v = value("--chat-engine"), let e = ChatEngine(rawValue: v) { ChatSettings.shared.engine = e }
        if args.contains("--charging-only") { chargingOnly = true }
        ChatPrompts.ensureFile()
        let pm = PowerMonitor.shared
        pm.onChange = { Store.shared.pump() }
        pm.onSample = { id, sum, n, used in
            let st = Store.shared
            st.update(id) { $0.powerSumW = sum; $0.powerSamples = n; $0.batteryUsedPct = used }
        }
        pm.start()
        pm.sampleNow()   // 시작 시 한 번 읽어 로그에 남긴다(AC면 W 미기록)

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        }
        let ok = HotKey.register(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | optionKey)) {
            MainActor.assumeIsolated { Store.shared.toggleRecording() }
        }
        log("hotkey registered=\(ok)")

        // 디버그: --enqueue <file> (여러 번 가능)
        var files: [String] = []
        for (i, a) in args.enumerated() where a == "--enqueue" && i + 1 < args.count { files.append(args[i + 1]) }
        // 디버그: --import-material <파일> --import-course <과목> (확인 창 없이 자료 넣기)
        if let f = value("--import-material"), let c = value("--import-course") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    let mi = MaterialImporter.shared
                    mi.request([URL(fileURLWithPath: f)])
                    mi.course = c
                    if let p = mi.pending { mi.confirm(p) }
                }
            }
        }
        if args.contains("--no-goodnotes") { MaterialImporter.debugNoGoodnotes = true }
        // 디버그: --seed-session <대본.md[,대본2.md…]> --seed-audio <오디오[,오디오2…]> [--seed-title 제목]
        //   처리 없이 완료된 녹음 여러 개를 가진 노트를 만든다(--seed-done은 같은 뜻의 옛 이름). 대본 파일은 복사하지 않고 그대로 가리킨다.
        let seedT = value("--seed-session") ?? value("--seed-done"), seedA = value("--seed-audio"), seedTitle = value("--seed-title")
        let chatQ = value("--chat-ask")
        let snapshot = value("--snapshot"), snapAfter = Double(value("--snapshot-after") ?? "") ?? 5
        let selectTitle = value("--select-session")
        let wikiSend = args.contains("--wiki-send")
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 디버그: --debug-new-in <프로젝트 이름>  그 프로젝트의 '+' 버튼처럼 새 노트를 만들고 --enqueue 파일을 거기에 넣는다.
                var newNote: UUID?
                if let pn = value("--debug-new-in"), let p = self.projects.first(where: { $0.name == pn }) {
                    newNote = self.newSession(projectID: p.id).id
                }
                for f in files { self.enqueue(URL(fileURLWithPath: f), into: newNote) }
                if let t = seedT, let a = seedA {
                    let ts = t.split(separator: ",").map(String.init), au = a.split(separator: ",").map(String.init)
                    var ids: [UUID] = []
                    for (i, tp) in ts.enumerated() {
                        let ap = au[min(i, au.count - 1)]
                        var job = Job(audioPath: ap, title: "시험 " + ((tp as NSString).lastPathComponent), createdAt: Date().addingTimeInterval(Double(i)),
                                      duration: (try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: ap)))?.duration, profile: "")
                        job.status = .done; job.transcriptPath = tp
                        self.jobs.insert(job, at: 0); ids.append(job.id)
                    }
                    self.saveState()
                    let sess = self.newSession(title: seedTitle ?? "시험 노트")
                    self.updateSession(sess.id) { $0.recordingIDs = ids; if seedTitle != nil { $0.titleIsAuto = false } }
                    if let q = chatQ, let s = self.session(sess.id) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            MainActor.assumeIsolated { ChatHub.shared.session(for: s.id).ask(q, session: s, organize: q == "ORGANIZE") }
                        }
                    }
                }
                if let ts = selectTitle, let s = self.sessions.first(where: { $0.title.contains(ts) }) { self.selectedSessionID = s.id }
                if wikiSend, let id = self.selectedSessionID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { WikiSender.send(id) } }
                }
                // 디버그: --debug-project <이름>  새 프로젝트를 만들고 선택한 노트를 그 안으로 옮긴다(끌어다 놓기와 같은 store 함수).
                if let pn = value("--debug-project"), let sid = self.selectedSessionID {
                    let p = self.projects.first { $0.name == pn } ?? self.newProject(pn)
                    self.move(session: sid, to: p.id)
                    self.log("debug project \(pn) moved \(sid)")
                }
                // 디버그: --debug-jump <화자>  화자 칩이 가려는 줄을 로그로 남긴다(재생하지 않음).
                if let sp = value("--debug-jump"), let s = self.selectedSession {
                    let ls = self.combinedTranscript(of: s).lines
                    let a = self.nextLine(of: sp, after: 0, in: ls), b = self.nextLine(of: sp, after: a?.time ?? 0, in: ls)
                    self.log("debug jump from 0 -> \(a.map { formatTime($0.time) } ?? "-"), then -> \(b.map { formatTime($0.time) } ?? "-")")
                }
                // 디버그: --debug-record <초>  1.5초 뒤 녹음을 시작하고 N초 뒤 정지한다(--live-input-file과 함께 sandbox 시험용).
                if let rs = value("--debug-record"), let secs = Double(rs) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        MainActor.assumeIsolated {
                            Store.shared.startRecording()
                            DispatchQueue.main.asyncAfter(deadline: .now() + secs) { MainActor.assumeIsolated { Store.shared.stopRecording() } }
                        }
                    }
                }
                if let snap = snapshot { DebugSnapshot.schedule(path: snap, after: snapAfter, quit: args.contains("--snapshot-quit")) }
                self.pump()
                AutoPreprocess.shared.start(debugDryRunNow: args.contains("--autopreprocess-dry-run-now"))
            }
        }
    }

    // MARK: - 로그 / 상태 저장

    func log(_ s: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: Paths.logFile) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(to: Paths.logFile, atomically: true, encoding: .utf8)
        }
    }

    private func loadState() {
        guard let d = try? Data(contentsOf: Paths.stateFile) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        jobs = (try? dec.decode([Job].self, from: d)) ?? []
        // 앱이 처리 도중 종료됐다면 대기로 되돌려 다시 처리한다.
        for i in jobs.indices where jobs[i].status == .processing {
            jobs[i].status = .queued; jobs[i].stage = nil
        }
        // 녹음 중 앱이 죽었다면 파일이 남아 있는 경우 처리 대기로 되돌린다.
        for i in jobs.indices.reversed() where jobs[i].status == .recording {
            let u = URL(fileURLWithPath: jobs[i].audioPath)
            let size = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0
            if size > 0 {
                jobs[i].status = .queued
                jobs[i].duration = (try? AVAudioPlayer(contentsOf: u))?.duration
            } else { jobs.remove(at: i) }
        }
    }

    func saveState() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
        if let d = try? enc.encode(jobs) { try? d.write(to: Paths.stateFile, options: .atomic) }
    }

    func update(_ id: UUID, _ f: (inout Job) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        f(&jobs[i]); saveState()
    }

    // MARK: - 녹음

    func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    /// 단축키·메뉴바·빈 화면 녹음: 지금 연 노트가 오늘 것이면 이어서, 아니면 새 노트.
    func startRecording(into session: UUID? = nil, forceNew: Bool = false) {
        if forceNew { _recordTarget = nil }
        else if let session { _recordTarget = session }
        else if let s = selectedSession, Calendar.current.isDateInToday(s.createdAt) || s.recordingIDs.isEmpty { _recordTarget = s.id }
        else { _recordTarget = nil }
        requestMicAndRecord()
    }

    private func requestMicAndRecord() {
        if Store.liveInputFile != nil { beginRecording(); return }   // 디버그: 마이크 안 씀
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: beginRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if ok { Store.shared.beginRecording() } else { Store.shared.micDenied() }
                    }
                }
            }
        default: micDenied()
        }
    }

    private func micDenied() {
        message = "마이크 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 VNote를 허용해 주세요."
        log("mic denied")
    }

    private func beginRecording() {
        guard !isRecording else { return }
        try? FileManager.default.createDirectory(at: Paths.recordings, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmmss"
        var url = Paths.recordings.appendingPathComponent("녹음 \(f.string(from: Date())).m4a")
        if let lf = Store.liveInputFile { url = URL(fileURLWithPath: lf) }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            if Store.liveInputFile == nil {
                let r = try AVAudioRecorder(url: url, settings: settings)
                guard r.prepareToRecord(), r.record() else { message = "녹음을 시작할 수 없습니다."; return }
                recorder = r
            }
            recordURL = url; recordStart = Date()
            isRecording = true; elapsed = 0; message = nil
            // 녹음 중에도 노트를 쓸 수 있도록 작업을 바로 만든다(status=recording).
            let target = session(_recordTarget) ?? newSession()
            var job = Job(audioPath: url.path, title: "녹음 " + titleDate(Date()), createdAt: Date(), duration: nil, profile: "")
            job.status = .recording
            jobs.insert(job, at: 0); recordingJobID = job.id; saveState()
            updateSession(target.id) { $0.recordingIDs.append(job.id) }
            selectedSessionID = target.id
            trackPower(job.id)
            if LiveSettings.shared.enabled {
                LiveTranscriber.shared.start(jobID: job.id, args: engineArgs(for: target, course: false), inputFile: Store.liveInputFile)
            }
            recordTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let s = Store.shared
                    if let st = s.recordStart { s.elapsed = Date().timeIntervalSince(st) }
                }
            }
            log("recording start \(url.path)")
        } catch {
            message = "녹음 시작 실패: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard isRecording, let url = recordURL else { return }
        recorder?.stop(); recorder = nil
        recordTimer?.invalidate()
        isRecording = false
        if let id = recordingJobID { LiveTranscriber.shared.stop(jobID: id) }
        log("recording stop \(url.path) \(elapsed)s")
        if let id = recordingJobID, jobs.contains(where: { $0.id == id }) {
            let dur = elapsed
            PowerMonitor.shared.end(id)
            update(id) { $0.status = .queued; $0.duration = dur }
            recordingJobID = nil
            pump()
        } else {
            recordingJobID = nil
            enqueue(url, title: "녹음 " + titleDate(Date()))
        }
    }

    func trackPower(_ id: UUID) {
        let j = jobs.first { $0.id == id }
        PowerMonitor.shared.begin(id, priorSumW: j?.powerSumW, priorN: j?.powerSamples, priorUsed: j?.batteryUsedPct)
    }

    private func titleDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M월 d일 HH:mm"; return f.string(from: d)
    }

    // MARK: - 큐

    /// 오디오 파일을 노트에 넣고 처리 큐에 올린다. 노트를 정하지 않으면 파일마다 새 노트를 만든다.
    func enqueue(_ url: URL, title: String? = nil, into sessionID: UUID? = nil) {
        let dur = (try? AVAudioPlayer(contentsOf: url))?.duration
        let name = title ?? url.deletingPathExtension().lastPathComponent
        let target = session(sessionID) ?? newSession(title: name)
        let job = Job(audioPath: url.path, title: name, createdAt: Date(), duration: dur, profile: "")
        jobs.insert(job, at: 0)
        updateSession(target.id) { $0.recordingIDs.append(job.id) }
        selectedSessionID = target.id
        saveState()
        log("enqueue \(url.path) project=\(project(of: target)?.name ?? "-")")
        pump()
    }

    func importFiles(_ urls: [URL], into sessionID: UUID? = nil) {
        for u in urls where audioExtensions.contains(u.pathExtension.lowercased()) { enqueue(u, into: sessionID) }
    }

    func retry(_ id: UUID) {
        update(id) { $0.status = .queued; $0.error = nil; $0.stage = nil }
        pump()
    }

    func remove(_ id: UUID) {
        if recordingJobID == id {
            recorder?.stop(); recorder = nil; recordTimer?.invalidate(); isRecording = false; recordingJobID = nil
            PowerMonitor.shared.end(id)
            LiveTranscriber.shared.abort()
        }
        if runningID == id { runningProcess?.terminate() }
        jobs.removeAll { $0.id == id }
        for i in sessions.indices { sessions[i].recordingIDs.removeAll { $0 == id } }
        saveState(); saveSessions()
    }

    func pump() {
        guard runningID == nil, let job = jobs.last(where: { $0.status == .queued }) else { return }
        if chargingOnly && !PowerMonitor.shared.onAC { return } // 충전 연결 시까지 큐에서 기다린다
        start(job)
    }

    private func start(_ job: Job) {
        let engine = enginePath
        let py = engine + "/.venv/bin/python"
        let script = engine + "/voicenote.py"
        guard FileManager.default.isExecutableFile(atPath: py), FileManager.default.fileExists(atPath: script) else {
            update(job.id) { $0.status = .failed; $0.error = "엔진을 찾을 수 없습니다: \(engine) (설정에서 경로를 확인하세요)" }
            log("engine missing \(engine)")
            pump(); return
        }
        try? FileManager.default.createDirectory(at: Paths.transcripts, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Paths.logsDir, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: py)
        var pargs = [script, "transcribe", job.audioPath]
        let sess = session(ofJob: job.id)
        pargs += engineArgs(for: sess)   // 프로젝트의 언어·용어·과목
        pargs += ["--json-progress", "--out", Paths.transcripts.path]
        p.arguments = pargs
        p.currentDirectoryURL = URL(fileURLWithPath: engine)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        let outPipe = Pipe()
        p.standardOutput = outPipe
        let errURL = Paths.logsDir.appendingPathComponent("\(job.id.uuidString).log")
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        p.standardError = try? FileHandle(forWritingTo: errURL)
        p.standardInput = FileHandle.nullDevice

        do { try p.run() } catch {
            update(job.id) { $0.status = .failed; $0.error = "엔진 실행 실패: \(error.localizedDescription)" }
            pump(); return
        }
        runningID = job.id; runningProcess = p
        trackPower(job.id)
        update(job.id) { $0.status = .processing; $0.stage = "시작 중"; $0.error = nil }
        log("engine start job=\(job.id) \(p.arguments ?? [])")

        let id = job.id
        Thread.detachNewThread {
            var buf = Data()
            let h = outPipe.fileHandleForReading
            while true {
                let d = h.availableData
                if d.isEmpty { break }
                buf.append(d)
                while let nl = buf.firstIndex(of: 10) {
                    let line = String(decoding: buf[buf.startIndex..<nl], as: UTF8.self)
                    buf.removeSubrange(buf.startIndex...nl)
                    DispatchQueue.main.async { MainActor.assumeIsolated { Store.shared.handle(id, line: line) } }
                }
            }
            if !buf.isEmpty {
                let line = String(decoding: buf, as: UTF8.self)
                DispatchQueue.main.async { MainActor.assumeIsolated { Store.shared.handle(id, line: line) } }
            }
            p.waitUntilExit()
            let code = p.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { Store.shared.finish(id, code: code, errLog: errURL) } }
        }
    }

    private static let stageLabels = ["convert": "변환 중", "asr": "받아쓰기 중", "diarize": "화자 분리 중", "merge": "대본 합치는 중"]

    private func handle(_ id: UUID, line: String) {
        guard let d = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let stage = o["stage"] as? String else { return }
        log("progress \(line)")
        switch stage {
        case "done":
            if let out = o["output"] as? String { update(id) { $0.transcriptPath = out } }
        case "error":
            update(id) { $0.error = (o["message"] as? String) ?? "알 수 없는 오류" }
        default:
            if (o["status"] as? String) == "start", let l = Store.stageLabels[stage] {
                update(id) { $0.stage = l }
            }
        }
    }

    private func finish(_ id: UUID, code: Int32, errLog: URL) {
        runningID = nil; runningProcess = nil
        PowerMonitor.shared.end(id)
        if let job = jobs.first(where: { $0.id == id }) {
            if code == 0, let path = job.transcriptPath, FileManager.default.fileExists(atPath: path) {
                update(id) { $0.status = .done; $0.stage = nil; $0.error = nil }
                transcriptRevision += 1
                export(path: path)
                // 첫 녹음 처리가 끝났을 때만 AI 제목을 짓는다(자료를 먼저 붙여 지은 제목이 있으면 그대로 두고 대본으로 다시 짓는다).
                if let s = session(ofJob: id), s.titleIsAuto, recordings(of: s).filter({ $0.status == .done }).count == 1 {
                    AITasks.shared.makeTitle(session: s.id)
                }
                log("job done \(path)")
            } else {
                var msg = job.error
                if msg == nil {
                    let tail = (try? String(contentsOf: errLog, encoding: .utf8))?
                        .split(separator: "\n").suffix(3).joined(separator: "\n") ?? ""
                    msg = "엔진이 종료되었습니다 (코드 \(code))" + (tail.isEmpty ? "" : "\n" + tail)
                }
                update(id) { $0.status = .failed; $0.stage = nil; $0.error = msg }
                log("job failed code=\(code) \(msg ?? "")")
            }
        }
        pump()
    }

    // MARK: - 내보내기 / 화자 이름

    func export(path: String) {
        guard exportEnabled, !exportFolder.isEmpty else { return }
        let dir = URL(fileURLWithPath: exportFolder)
        let dest = dir.appendingPathComponent((path as NSString).lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: dest)
            log("exported \(dest.path)")
        } catch {
            message = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    /// 화자 이름을 노트의 모든 녹음 대본에서 바꾼다(위키로 보낸 묶음은 다시 보내야 반영).
    func renameSpeaker(session s: Session, from: String, to: String) {
        let name = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("\n"), name != from else { return }
        do {
            for j in recordings(of: s) {
                if let p = j.transcriptPath { try TranscriptIO.renameSpeaker(path: p, from: from, to: name) }
            }
            transcriptRevision += 1
            log("rename speaker \(from) -> \(name) in session \(s.id)")
        } catch {
            message = "화자 이름 변경 실패: \(error.localizedDescription)"
        }
    }

    private func shutdown() {
        if isRecording { recorder?.stop() } // 파일은 그대로 남는다
        LiveTranscriber.shared.abort()
        runningProcess?.terminate()
        saveState()
    }
}
