import AVFoundation
import AppKit
import Carbon.HIToolbox
import Foundation

let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "flac", "aif", "aiff", "caf", "ogg", "opus", "mp4", "mov", "m4b"]

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var jobs: [Job] = []
    @Published var selectedID: UUID?
    @Published var profiles: [String] = []
    @Published var selectedProfile: String { didSet { UserDefaults.standard.set(selectedProfile, forKey: "profile") } }
    @Published var enginePath: String { didSet { UserDefaults.standard.set(enginePath, forKey: "enginePath") } }
    @Published var exportEnabled: Bool { didSet { UserDefaults.standard.set(exportEnabled, forKey: "exportEnabled") } }
    @Published var exportFolder: String { didSet { UserDefaults.standard.set(exportFolder, forKey: "exportFolder") } }
    @Published var wikiEnabled: Bool { didSet { UserDefaults.standard.set(wikiEnabled, forKey: "wikiEnabled") } }
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

    private init() {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if args.contains("--power-selftest") { print(PowerMonitor.selfTest()); exit(0) }
        if let sb = value("--sandbox") { Paths.sandbox = URL(fileURLWithPath: sb) }
        let d = UserDefaults.standard
        enginePath = value("--engine") ?? d.string(forKey: "enginePath") ?? "/Users/DH_WEST/LocalAI_Project/voice"
        exportEnabled = value("--export-dir") != nil ? true : d.bool(forKey: "exportEnabled")
        exportFolder = value("--export-dir") ?? d.string(forKey: "exportFolder") ?? ""
        wikiEnabled = d.object(forKey: "wikiEnabled") as? Bool ?? true
        selectedProfile = value("--profile") ?? d.string(forKey: "profile") ?? "전력전자"
        chargingOnly = d.bool(forKey: "chargingOnly")

        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        Profiles.ensureDefaults()
        reloadProfiles()
        loadState()
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
        if let probe = value("--material-probe") {
            let v = ChatSettings.shared.vaultPath
            let pre = Materials.prefixes(course: Profiles.course(for: selectedProfile), vault: v)
            print("course=\(Profiles.course(for: selectedProfile) ?? "-") prefixes=\(pre)")
            MaterialIndex.shared.ensureBuilt(vault: v) {
                let t = (try? String(contentsOfFile: probe, encoding: .utf8)) ?? ""
                let ls = ChatContext.transcriptLines(job: Job(audioPath: "", title: "", createdAt: Date(), duration: nil, profile: "", status: .done, transcriptPath: probe))
                let text = ls.isEmpty ? t : ls.map(\.text).joined(separator: "\n")
                print("with course:", MaterialIndex.shared.pick(text: text, prefixes: pre).map(\.name))
                print("no profile :", MaterialIndex.shared.pick(text: text, prefixes: []).map(\.name))
                exit(0)
            }
        }
        let seedT = value("--seed-done"), seedA = value("--seed-audio")
        let chatQ = value("--chat-ask"), chatMat = value("--chat-materials")
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                for f in files { self.enqueue(URL(fileURLWithPath: f)) }
                // 디버그: 처리 없이 완료된 작업을 만든다(채팅/노트 시험용)
                if let t = seedT, let a = seedA {
                    var job = Job(audioPath: a, title: "시험 " + ((t as NSString).lastPathComponent), createdAt: Date(),
                                  duration: (try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: a)))?.duration, profile: self.selectedProfile)
                    job.status = .done; job.transcriptPath = t
                    self.jobs.insert(job, at: 0); self.selectedID = job.id; self.saveState()
                    if let q = chatQ {
                        let sess = ChatHub.shared.session(for: job.id)
                        if let m = chatMat { sess.materials = m.split(separator: ",").map(String.init); sess.manualMaterials = true }
                        else { sess.refreshAutoMaterials(job: job, force: true) }
                        // 색인이 끝날 시간을 준 뒤 질문
                        MaterialIndex.shared.ensureBuilt(vault: ChatSettings.shared.vaultPath) {
                            MainActor.assumeIsolated {
                                sess.refreshAutoMaterials(job: job, force: false)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    MainActor.assumeIsolated { sess.ask(q, job: job, organize: q == "ORGANIZE") }
                                }
                            }
                        }
                    }
                }
                self.pump()
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

    private func saveState() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
        if let d = try? enc.encode(jobs) { try? d.write(to: Paths.stateFile, options: .atomic) }
    }

    func update(_ id: UUID, _ f: (inout Job) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        f(&jobs[i]); saveState()
    }

    func reloadProfiles() {
        profiles = Profiles.names()
        if !selectedProfile.isEmpty, !profiles.contains(selectedProfile) { selectedProfile = "" }
    }

    // MARK: - 녹음

    func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    func startRecording() {
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
        message = "마이크 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 VoiceNote를 허용해 주세요."
        log("mic denied")
    }

    private func beginRecording() {
        guard !isRecording else { return }
        try? FileManager.default.createDirectory(at: Paths.recordings, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmmss"
        let url = Paths.recordings.appendingPathComponent("녹음 \(f.string(from: Date())).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            guard r.prepareToRecord(), r.record() else { message = "녹음을 시작할 수 없습니다."; return }
            recorder = r; recordURL = url; recordStart = Date()
            isRecording = true; elapsed = 0; message = nil
            // 녹음 중에도 노트를 쓸 수 있도록 작업을 바로 만든다(status=recording).
            var job = Job(audioPath: url.path, title: "녹음 " + titleDate(Date()), createdAt: Date(), duration: nil, profile: selectedProfile)
            job.status = .recording
            jobs.insert(job, at: 0); selectedID = job.id; recordingJobID = job.id; saveState()
            trackPower(job.id)
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

    /// 지금 이 작업에서 새 노트 줄에 붙일 시각(초): 녹음 중이면 경과 시간, 재생 중이면 재생 위치.
    func notePosition(for job: Job) -> Double? {
        if job.status == .recording, recordingJobID == job.id, let st = recordStart { return Date().timeIntervalSince(st) }
        let p = AudioPlayer.shared
        if p.loadedPath == job.audioPath { return p.currentTime }
        return nil
    }

    func seek(job: Job, to sec: Double) {
        guard job.status != .recording else { return }
        AudioPlayer.shared.play(path: job.audioPath, from: sec)
    }

    func trackPower(_ id: UUID) {
        let j = jobs.first { $0.id == id }
        PowerMonitor.shared.begin(id, priorSumW: j?.powerSumW, priorN: j?.powerSamples, priorUsed: j?.batteryUsedPct)
    }

    private func titleDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M월 d일 HH:mm"; return f.string(from: d)
    }

    // MARK: - 큐

    func enqueue(_ url: URL, title: String? = nil) {
        let dur = (try? AVAudioPlayer(contentsOf: url))?.duration
        let job = Job(audioPath: url.path,
                      title: title ?? url.deletingPathExtension().lastPathComponent,
                      createdAt: Date(), duration: dur, profile: selectedProfile)
        jobs.insert(job, at: 0)
        selectedID = job.id
        saveState()
        log("enqueue \(url.path) profile=\(selectedProfile)")
        pump()
    }

    func importFiles(_ urls: [URL]) {
        for u in urls.reversed() where audioExtensions.contains(u.pathExtension.lowercased()) { enqueue(u) }
    }

    func retry(_ id: UUID) {
        update(id) { $0.status = .queued; $0.error = nil; $0.stage = nil }
        pump()
    }

    func remove(_ id: UUID) {
        if recordingJobID == id {
            recorder?.stop(); recorder = nil; recordTimer?.invalidate(); isRecording = false; recordingJobID = nil
            PowerMonitor.shared.end(id)
        }
        if runningID == id { runningProcess?.terminate() }
        jobs.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        saveState()
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
        if !job.profile.isEmpty { pargs += ["--profile", job.profile] }   // 비어 있으면 '자동(프로필 없음)'
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
                if wikiEnabled, job.wikiPath.map({ !FileManager.default.fileExists(atPath: $0) }) ?? true {
                    sendToWiki(id, manual: false)
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

    /// 대본을 프로필의 위키 transcript 폴더에 새 파일로 복사한다(덮어쓰기 없음, 다른 파일은 건드리지 않음).
    func sendToWiki(_ id: UUID, manual: Bool) {
        guard let job = jobs.first(where: { $0.id == id }), let src = job.transcriptPath,
              FileManager.default.fileExists(atPath: src) else { return }
        guard let t = Profiles.wikiTarget(for: job.profile) else {
            if manual { message = "프로필 '\(job.profile)'에 위키 폴더(course/wiki_dir)가 설정되어 있지 않습니다." }
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: t.dir, isDirectory: &isDir), isDir.boolValue else {
            log("wiki dir missing \(t.dir)")
            if manual { message = "위키 폴더가 없습니다: \(t.dir)" }
            return
        }
        let meta = TranscriptIO.load(path: src)?.meta ?? [:]
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd HH:mm"
        let when = meta["date"].flatMap { df.date(from: $0) } ?? job.createdAt
        let nf = DateFormatter(); nf.locale = Locale(identifier: "en_US_POSIX"); nf.dateFormat = "yyyy-MM-dd HHmm"
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        }
        let base = "\(clean(t.course)) \(nf.string(from: when)) \(clean(job.title))"
        let dir = URL(fileURLWithPath: t.dir)
        var dest = dir.appendingPathComponent(base + ".md"); var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base) (\(n)).md"); n += 1
        }
        do {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: src), to: dest)
            update(id) { $0.wikiPath = dest.path }
            log("wiki sent \(dest.path)")
        } catch {
            message = "위키로 보내기 실패: \(error.localizedDescription)"
        }
    }

    func renameSpeaker(job: Job, from: String, to: String) {
        let name = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path = job.transcriptPath, !name.isEmpty, !name.contains("\n"), name != from else { return }
        do {
            try TranscriptIO.renameSpeaker(path: path, from: from, to: name)
            transcriptRevision += 1
            export(path: path)
            if let wp = job.wikiPath, FileManager.default.fileExists(atPath: wp) {
                // 앱이 새로 만든 위키 사본만 고친다(다른 raw 파일은 건드리지 않음)
                try TranscriptIO.renameSpeaker(path: wp, from: from, to: name)
            }
            log("rename speaker \(from) -> \(name) in \(path)")
        } catch {
            message = "화자 이름 변경 실패: \(error.localizedDescription)"
        }
    }

    private func shutdown() {
        if isRecording { recorder?.stop() } // 파일은 그대로 남는다
        runningProcess?.terminate()
        saveState()
    }
}
