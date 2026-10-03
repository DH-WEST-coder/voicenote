import AppKit
import Foundation

/// 위키의 auto_preprocess.sh를 앱의 자식 프로세스로 주기 실행한다.
/// launchd로 띄운 bash는 Google Drive 같은 클라우드 폴더에 TCC로 막히지만, GUI 앱의 자식이면 접근이 앱에 귀속된다.
@MainActor
final class AutoPreprocess: ObservableObject {
    static let shared = AutoPreprocess()

    static let pathEnv = "/Users/DH_WEST/.local/bin:/opt/homebrew/bin:/usr/bin:/bin"
    static let scriptRel = ".agents/skills/source-processor/scripts/auto_preprocess.sh"
    static let runLogRel = ".agents/state/auto-preprocess/run.log"

    private let d = UserDefaults.standard
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "apEnabled"); reschedule() } }
    @Published var intervalMinutes: Int { didSet { d.set(intervalMinutes, forKey: "apInterval"); reschedule() } }
    @Published private(set) var running = false
    @Published private(set) var lastRun: Date?
    @Published private(set) var lastResult: String
    /// 접근 거부(TCC)로 보이는 경우의 한 줄 경고. 다음 성공 실행 때 지워진다.
    @Published private(set) var accessWarning: String?

    static let accessMessage = "Google Drive 폴더에 접근할 수 없습니다. 시스템 설정 → 개인정보 보호 및 보안 → 파일 및 폴더(또는 전체 디스크 접근 권한)에서 VoiceNote를 허용하세요."

    private var timer: Timer?
    private var wikiTimer: Timer?
    private var rerunPending = false
    private var schedulingOff = false
    private var firstDone = false
    private var process: Process?

    private init() {
        enabled = d.object(forKey: "apEnabled") as? Bool ?? true
        let iv = d.object(forKey: "apInterval") as? Int ?? 15
        intervalMinutes = max(1, iv)
        lastRun = d.object(forKey: "apLastRun") as? Date
        lastResult = d.string(forKey: "apLastResult") ?? "아직 실행 안 함"
        accessWarning = d.string(forKey: "apWarning")
    }

    var vault: String { ChatSettings.shared.vaultPath }
    var runLogURL: URL { URL(fileURLWithPath: vault).appendingPathComponent(Self.runLogRel) }
    static var appLogURL: URL { Paths.logsDir.appendingPathComponent("autopreprocess.log") }

    /// 앱 시작 시 호출. 첫 실행은 약 1분 뒤.
    func start(debugDryRunNow: Bool) {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AutoPreprocess.shared.process?.terminate() }
        }
        if debugDryRunNow {
            schedulingOff = true
            run(dryRun: true, reason: "debug-dry-run") { line in
                print(line)
                exit(0)
            }
            return
        }
        scheduleFirst()
    }

    private func scheduleFirst() {
        timer?.invalidate(); timer = nil
        guard enabled, !schedulingOff else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in
            MainActor.assumeIsolated { AutoPreprocess.shared.tick() }
        }
    }

    private func reschedule() {
        guard !schedulingOff else { return }
        timer?.invalidate(); timer = nil
        firstDone = true
        guard enabled else { wikiTimer?.invalidate(); wikiTimer = nil; return }
        // 이미 도는 주기 타이머가 있으면 간격만 새로 맞춘다(설정 변경 직후 바로 실행하지는 않는다)
        timer = Timer.scheduledTimer(withTimeInterval: Double(max(1, intervalMinutes)) * 60, repeats: true) { _ in
            MainActor.assumeIsolated { AutoPreprocess.shared.tick() }
        }
    }

    private func tick() {
        run(dryRun: false, reason: firstDone ? "interval" : "first")
        if !firstDone { firstDone = true; reschedule() }   // 첫 1분 타이머 이후 주기 타이머로 전환
    }

    /// 대본을 위키로 보낸 뒤 호출: 스크립트가 10분 미만 파일을 무시하므로 약 11분 뒤 한 번 더 돈다.
    func scheduleAfterWikiSend() {
        guard enabled, !schedulingOff else { return }
        wikiTimer?.invalidate()
        wikiTimer = Timer.scheduledTimer(withTimeInterval: 11 * 60, repeats: false) { _ in
            MainActor.assumeIsolated { AutoPreprocess.shared.run(dryRun: false, reason: "after-wiki-send") }
        }
    }

    func runNow() { run(dryRun: false, reason: "manual") }

    func openRunLog() {
        let u = runLogURL
        if FileManager.default.fileExists(atPath: u.path) { NSWorkspace.shared.open(u) }
        else { NSWorkspace.shared.activateFileViewerSelecting([Self.appLogURL]) }
    }

    func openAppLog() { NSWorkspace.shared.activateFileViewerSelecting([Self.appLogURL]) }

    var menuLine: String {
        guard let t = lastRun else { return "위키 전처리: 아직 실행 안 함" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "위키 전처리: 마지막 실행 \(f.string(from: t)) (\(lastResult))"
    }

    // MARK: - 실행

    func run(dryRun: Bool, reason: String, completion: ((String) -> Void)? = nil) {
        guard !running else {
            if !dryRun { rerunPending = true }   // 끝나면 한 번 더
            appendLog("skip(이미 실행 중) reason=\(reason)")
            return
        }
        let vaultPath = vault
        let script = vaultPath + "/" + Self.scriptRel
        running = true
        appendLog("start reason=\(reason)\(dryRun ? " --dry-run" : "") script=\(script)")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script] + (dryRun ? ["--dry-run"] : [])
        p.currentDirectoryURL = URL(fileURLWithPath: vaultPath)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.pathEnv
        env["HOME"] = NSHomeDirectory()
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        process = p

        let launchError: String? = {
            do { try p.run(); return nil } catch { return error.localizedDescription }
        }()
        if let e = launchError {
            process = nil
            finish(output: "실행 실패: \(e)", code: -1, dryRun: dryRun, launchFailed: true, completion: completion)
            return
        }
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            let data = handle.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(decoding: data, as: UTF8.self)
            let code = p.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AutoPreprocess.shared.process = nil
                    AutoPreprocess.shared.finish(output: out, code: code, dryRun: dryRun, launchFailed: false, completion: completion)
                }
            }
        }
    }

    private func finish(output: String, code: Int32, dryRun: Bool, launchFailed: Bool, completion: ((String) -> Void)?) {
        running = false
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { appendLog(trimmed, raw: true) }

        let lower = output.lowercased()
        let denied = lower.contains("operation not permitted") || lower.contains("permission denied")
            || (launchFailed && (lower.contains("permission") || lower.contains("not permitted") || lower.contains("couldn’t be opened") || lower.contains("could not be opened")))
        var result: String
        if denied {
            result = "접근 거부"
            accessWarning = Self.accessMessage
        } else {
            accessWarning = nil
            let lines = trimmed.split(separator: "\n").map(String.init)
            if code != 0 {
                result = "실패(코드 \(code))" + (lines.last.map { ": " + String($0.prefix(60)) } ?? "")
            } else if dryRun {
                let n = lines.filter { $0.hasPrefix("처리 대상:") }.count
                result = n == 0 ? "dry-run: 대상 없음" : "dry-run: 대상 \(n)건"
            } else if lower.contains("이미 실행 중") {
                result = "이미 실행 중(건너뜀)"
            } else {
                let done = lines.filter { $0.contains(" done: ") }.count
                let fail = lines.filter { $0.contains(" fail(") }.count
                result = (done + fail) == 0 ? "처리할 대상 없음" : "완료 \(done)건" + (fail > 0 ? ", 실패 \(fail)건" : "")
            }
        }
        if !dryRun || completion == nil {
            lastRun = Date(); lastResult = result
            d.set(lastRun, forKey: "apLastRun"); d.set(result, forKey: "apLastResult"); d.set(accessWarning, forKey: "apWarning")
        }
        appendLog("end code=\(code) result=\(result)")
        if let c = completion {
            c("autopreprocess: \(result)\n" + trimmed)
        }
        if rerunPending && !dryRun {
            rerunPending = false
            run(dryRun: false, reason: "pending")
        }
    }

    private func appendLog(_ s: String, raw: Bool = false) {
        try? FileManager.default.createDirectory(at: Paths.logsDir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let ts = f.string(from: Date())
        let text = raw ? s.split(separator: "\n", omittingEmptySubsequences: false).map { "\(ts)   | \($0)" }.joined(separator: "\n") + "\n"
                       : "\(ts) \(s)\n"
        let url = Self.appLogURL
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
