import AVFoundation
import Foundation

/// 실시간 받아쓰기 설정. 녹음을 시작할 때 값을 읽어 그 녹음에만 적용한다(녹음 중 바꾸면 다음 녹음부터).
/// 디버그 인자(저장하지 않음): --live-enabled 0|1, --live-model <ID>, --live-chunk <초>
@MainActor
final class LiveSettings: ObservableObject {
    static let shared = LiveSettings()
    static let models: [(id: String, label: String)] = [
        ("moona3k/mlx-qwen3-asr-0.6b-4bit", "0.6B 4bit (가벼움, 기본)"),
        ("moona3k/mlx-qwen3-asr-1.7b-8bit", "1.7B 8bit (정확, 무거움)"),
    ]
    static let intervals: [Double] = [1, 2, 3, 5]

    @Published var enabled: Bool { didSet { if persist { UserDefaults.standard.set(enabled, forKey: "liveEnabled") } } }
    @Published var model: String { didSet { if persist { UserDefaults.standard.set(model, forKey: "liveModel") } } }
    @Published var chunkSec: Double { didSet { if persist { UserDefaults.standard.set(chunkSec, forKey: "liveChunkSec") } } }

    private var persist = false

    private init() {
        let d = UserDefaults.standard, args = CommandLine.arguments
        func value(_ f: String) -> String? {
            guard let i = args.firstIndex(of: f), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        enabled = d.object(forKey: "liveEnabled") == nil ? true : d.bool(forKey: "liveEnabled")
        model = d.string(forKey: "liveModel") ?? LiveSettings.models[0].id
        let c = d.double(forKey: "liveChunkSec")
        chunkSec = LiveSettings.intervals.contains(c) ? c : 2
        // 디버그 덮어쓰기(저장하지 않음)
        if let v = value("--live-enabled") { enabled = (v != "0") }
        if let v = value("--live-model") { model = v }
        if let v = value("--live-chunk"), let c = Double(v) { chunkSec = c }
        persist = true
    }
}

struct LiveLine: Equatable {
    let time: Double
    let text: String
}

/// 엔진 stdin으로 PCM을 쓰는 직렬 큐. 오디오 스레드를 막지 않고, 엔진이 모델을 올리는 동안은 큐에 쌓아 둔다.
final class LiveWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "vnote.live.writer")
    private let lock = NSLock()
    private var pending = 0
    private var closed = false
    private let maxPending = 16000 * 4 * 900   // 15분치(약 58MB)를 넘으면 버린다

    init(_ h: FileHandle) { handle = h }

    func write(_ d: Data) {
        lock.lock()
        if closed || pending > maxPending { lock.unlock(); return }
        pending += d.count
        lock.unlock()
        queue.async { [self] in
            try? handle.write(contentsOf: d)   // SIGPIPE는 무시(앱 시작 시 설정), 실패는 EPIPE로 돌아온다
            lock.lock(); pending -= d.count; lock.unlock()
        }
    }

    /// 쌓인 쓰기를 모두 보낸 뒤 stdin을 닫는다(엔진이 EOF를 보고 마무리한다).
    func close() {
        lock.lock(); closed = true; lock.unlock()
        queue.async { [handle] in try? handle.close() }
    }
}

/// 마이크 입력 탭: AVAudioEngine 입력을 16 kHz 모노 float32로 바꿔 LiveWriter에 쓴다.
/// 파일 녹음(AVAudioRecorder)과 별개의 입력 클라이언트로 같은 마이크를 동시에 연다.
final class LiveMicTap: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let sink: LiveWriter
    private var converter: AVAudioConverter?
    private var outFormat: AVAudioFormat?

    init(sink: LiveWriter) { self.sink = sink }

    func start() throws {
        let input = engine.inputNode
        let inFmt = input.outputFormat(forBus: 0)
        guard inFmt.sampleRate > 0,
              let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inFmt, to: out) else {
            throw NSError(domain: "VNoteLive", code: 1, userInfo: [NSLocalizedDescriptionKey: "마이크 입력 형식을 변환할 수 없습니다"])
        }
        converter = conv; outFormat = out
        input.installTap(onBus: 0, bufferSize: 4096, format: inFmt) { [weak self] buf, _ in self?.handle(buf) }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func handle(_ buf: AVAudioPCMBuffer) {
        guard let conv = converter, let outFmt = outFormat else { return }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000.0 / buf.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return }
        var supplied = false
        var err: NSError?
        let st = conv.convert(to: out, error: &err) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buf
        }
        guard st != .error, out.frameLength > 0, let ch = out.floatChannelData else { return }
        sink.write(Data(bytes: ch[0], count: Int(out.frameLength) * MemoryLayout<Float>.size))
    }
}

/// 녹음 한 번에 붙는 실시간 엔진 실행 하나
@MainActor
final class LiveRun {
    let jobID: UUID
    let process = Process()
    var writer: LiveWriter?
    var tap: LiveMicTap?
    let fileURL: URL
    var stopped = false
    var ended = false
    init(jobID: UUID, fileURL: URL) { self.jobID = jobID; self.fileURL = fileURL }
}

@MainActor
final class LiveTranscriber: ObservableObject {
    static let shared = LiveTranscriber()

    enum Status: Equatable { case idle, loading, ready, finishing, failed(String) }
    @Published private(set) var status: Status = .idle
    @Published private(set) var partial = ""
    /// 확정 줄이 늘 때마다 올라간다(화면 갱신 표식)
    @Published private(set) var revision = 0

    private var current: LiveRun?
    private var cache: [UUID: [LiveLine]] = [:]

    var activeJobID: UUID? { current?.jobID }
    func isActive(_ id: UUID) -> Bool { current?.jobID == id && !(current?.stopped ?? true) }

    var statusText: String {
        switch status {
        case .idle: return ""
        case .loading: return "실시간 준비 중…"
        case .ready: return "실시간 듣는 중"
        case .finishing: return "실시간 마무리 중…"
        case .failed(let m): return "실시간 받아쓰기 실패: \(m)"
        }
    }

    static func fileURL(for jobID: UUID) -> URL { Paths.liveTranscripts.appendingPathComponent("\(jobID.uuidString).md") }

    // MARK: 읽기

    func lines(for job: Job) -> [LiveLine] {
        if let c = cache[job.id] { return c }
        guard let p = job.liveTranscriptPath, let s = try? String(contentsOfFile: p, encoding: .utf8) else { return [] }
        var out: [LiveLine] = []
        for l in s.components(separatedBy: "\n") {
            guard l.hasPrefix("["), let close = l.range(of: "] ") else { continue }
            let label = String(l[l.index(after: l.startIndex)..<close.lowerBound])
            out.append(LiveLine(time: TranscriptIO.seconds(label), text: String(l[close.upperBound...])))
        }
        if current?.jobID != job.id { cache[job.id] = out }
        return out
    }

    // MARK: 시작·정지

    /// 녹음 시작 때 호출. inputFile이 있으면(디버그) 마이크 대신 엔진이 그 파일을 실시간 속도로 읽는다.
    func start(jobID: UUID, profile: String, terms: [String], sessionID: UUID, inputFile: String?) {
        signal(SIGPIPE, SIG_IGN)
        let store = Store.shared
        if let old = current { old.process.terminate(); finishRun(old) }
        let settings = LiveSettings.shared
        let model = settings.model, chunk = settings.chunkSec   // 이 녹음에만 적용
        let engine = store.enginePath
        let py = engine + "/.venv/bin/python", script = engine + "/voicenote.py"
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: py), fm.fileExists(atPath: script) else {
            status = .failed("엔진을 찾을 수 없습니다"); store.log("live: engine missing"); return
        }
        try? fm.createDirectory(at: Paths.liveTranscripts, withIntermediateDirectories: true)
        try? fm.createDirectory(at: Paths.logsDir, withIntermediateDirectories: true)
        let file = LiveTranscriber.fileURL(for: jobID)
        fm.createFile(atPath: file.path, contents: nil)
        cache[jobID] = []
        store.update(jobID) { $0.liveTranscriptPath = file.path }

        let run = LiveRun(jobID: jobID, fileURL: file)
        var args = [script, "live", "--model", model, "--chunk-sec", String(chunk)]
        if !profile.isEmpty { args += ["--profile", profile] }
        if !terms.isEmpty {
            let tf = Paths.support.appendingPathComponent("terms/\(sessionID.uuidString).txt")
            try? fm.createDirectory(at: tf.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? terms.joined(separator: "\n").write(to: tf, atomically: true, encoding: .utf8)
            args += ["--terms-file", tf.path]
        }
        if let f = inputFile { args += ["--input-file", f, "--realtime"] }
        let p = run.process
        p.executableURL = URL(fileURLWithPath: py)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: engine)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        let outPipe = Pipe()
        p.standardOutput = outPipe
        let errURL = Paths.logsDir.appendingPathComponent("live-\(jobID.uuidString).log")
        fm.createFile(atPath: errURL.path, contents: nil)
        p.standardError = try? FileHandle(forWritingTo: errURL)
        let inPipe = Pipe()
        if inputFile == nil { p.standardInput = inPipe } else { p.standardInput = FileHandle.nullDevice }

        do { try p.run() } catch {
            status = .failed(error.localizedDescription); store.log("live: run failed \(error)"); return
        }
        current = run; status = .loading; partial = ""
        store.log("live start job=\(jobID) model=\(model) chunk=\(chunk)s file=\(inputFile ?? "mic") args=\(args.dropFirst())")

        if inputFile == nil {
            let w = LiveWriter(inPipe.fileHandleForWriting)
            run.writer = w
            let tap = LiveMicTap(sink: w)
            do { try tap.start(); run.tap = tap } catch {
                store.log("live: mic tap failed \(error.localizedDescription)")
                status = .failed("마이크 탭 실패: \(error.localizedDescription)")
                w.close(); p.terminate()
            }
        }

        let id = jobID
        Thread.detachNewThread {
            var buf = Data()
            let h = outPipe.fileHandleForReading
            func deliver(_ line: String) {
                DispatchQueue.main.async { MainActor.assumeIsolated { LiveTranscriber.shared.handle(line, run: run, id: id) } }
            }
            while true {
                let d = h.availableData
                if d.isEmpty { break }
                buf.append(d)
                while let nl = buf.firstIndex(of: 10) {
                    deliver(String(decoding: buf[buf.startIndex..<nl], as: UTF8.self))
                    buf.removeSubrange(buf.startIndex...nl)
                }
            }
            p.waitUntilExit()
            let code = p.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { LiveTranscriber.shared.processEnded(run, code: code) } }
        }
    }

    /// 녹음 정지 때: 입력을 닫고 엔진이 남은 글을 확정하도록 기다린다(최대 20초).
    func stop(jobID: UUID) {
        guard let run = current, run.jobID == jobID, !run.stopped else { return }
        run.stopped = true
        run.tap?.stop(); run.tap = nil
        run.writer?.close()
        if status != .idle, !isFailed { status = .finishing }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            MainActor.assumeIsolated {
                if !run.ended, run.process.isRunning {
                    Store.shared.log("live: finish timeout, terminating")
                    run.process.terminate()
                }
            }
        }
    }

    /// 녹음을 지우거나 앱을 끌 때: 기다리지 않고 끝낸다.
    func abort() {
        guard let run = current else { return }
        run.tap?.stop(); run.tap = nil
        run.writer?.close()
        run.stopped = true
        run.process.terminate()
    }

    private var isFailed: Bool { if case .failed = status { return true } else { return false } }

    private func finishRun(_ run: LiveRun) {
        run.ended = true
        if current === run { current = nil; partial = "" }
        revision += 1
    }

    private func processEnded(_ run: LiveRun, code: Int32) {
        let wasCurrent = current === run
        let failed = isFailed
        finishRun(run)
        Store.shared.log("live ended job=\(run.jobID) code=\(code)")
        if wasCurrent { status = failed ? status : (code == 0 || run.stopped ? .idle : .failed("엔진이 종료되었습니다 (코드 \(code))")) }
        Store.shared.transcriptRevision += 1
    }

    // MARK: 엔진 출력

    private func handle(_ line: String, run: LiveRun, id: UUID) {
        guard let d = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let type = o["type"] as? String else { return }
        let isCurrent = current === run
        switch type {
        case "loading": if isCurrent { status = .loading }
        case "ready": if isCurrent, !run.stopped { status = .ready }
        case "partial":
            if isCurrent { partial = (o["text"] as? String) ?? "" }
        case "commit":
            guard let text = o["text"] as? String, !text.isEmpty else { return }
            let start = (o["start"] as? Double) ?? 0
            cache[id, default: []].append(LiveLine(time: start, text: text))
            appendToFile(run.fileURL, "[\(formatTime(start))] \(text)\n")
            if isCurrent { partial = "" }
            revision += 1
        case "stats":
            Store.shared.log("live stats \(line)")
        case "error":
            let m = (o["message"] as? String) ?? "알 수 없는 오류"
            Store.shared.log("live error \(m)")
            if isCurrent { status = .failed(m) }
        case "done":
            Store.shared.log("live done job=\(id)")
        default: break
        }
    }

    private func appendToFile(_ url: URL, _ s: String) {
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(s.utf8)); try? h.close()
        } else {
            try? s.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
