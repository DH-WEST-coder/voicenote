import AppKit
import Foundation

/// 노트 묶음을 위키로 보낸다. 형식은 voice/WIKI_HANDOFF.md 1절.
/// 위키에 쓰는 것은 `<과목>/transcript/*.session.md`, 보류 목록 줄 삭제, 감시 폴더 목록(auto-preprocess.dirs) 줄 추가뿐이다.
@MainActor
enum WikiSender {
    /// 디버그(--wiki-auto-yes): 확인 창을 모두 '예'로 답한다.
    private static var autoYes: Bool { CommandLine.arguments.contains("--wiki-auto-yes") }
    static let dirsRel = ".agents/skills/source-processor/auto-preprocess.dirs"
    static let scriptRel = ".agents/skills/source-processor/scripts/auto_preprocess.sh"

    /// 버튼 3개 확인 창. 0=첫째, 1=둘째, 2=셋째
    private static func ask(_ title: String, _ info: String, _ buttons: [String]) -> Int {
        if autoYes { return 0 }
        let a = NSAlert()
        a.messageText = title; a.informativeText = info
        for b in buttons { a.addButton(withTitle: b) }
        let r = a.runModal()
        return r.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    static func send(_ id: UUID) {
        let store = Store.shared
        guard let s = store.session(id) else { return }
        guard let course = Courses.course(forProfile: s.profile) else {
            store.message = "노트의 프로필(과목)을 먼저 고르세요. 제목 아래 주황색 '프로필 없음'을 눌러 과목 프로필을 고른 뒤 다시 보내세요."
            return
        }
        NoteController.shared.flush()
        let notes = NoteFile.load(id).trimmingCharacters(in: .whitespacesAndNewlines)
        let recs = store.recordings(of: s)
        let combined = store.combinedTranscript(of: s)
        let included = combined.parts.enumerated().filter { $0.element.transcript != nil }
        if included.isEmpty && notes.isEmpty && s.attachments.isEmpty {
            store.message = "보낼 내용이 없습니다. 녹음 대본, 내 노트, 강의자료 중 하나는 있어야 합니다."
            return
        }
        if recs.contains(where: { $0.status != .done }) {
            let n = recs.filter { $0.status != .done }.count
            if ask("처리가 끝나지 않은 녹음이 있습니다",
                   "녹음 중이거나 처리 중·대기·실패인 녹음이 \(n)개 있습니다. 대본이 만들어진 \(included.count)개만 포함해서 보낼까요? (나머지는 처리된 뒤 다시 보내면 같은 파일을 덮어씁니다)",
                   ["계속", "취소"]) != 0 { return }
        }
        let vault = VaultConfig.shared.vault
        let semester = VaultConfig.shared.semester
        let courseDir = Courses.semesterDir.appendingPathComponent(course)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: courseDir.path, isDirectory: &isDir), isDir.boolValue else {
            store.message = "위키에 과목 폴더가 없습니다: \(courseDir.path)"
            return
        }
        let transDir = courseDir.appendingPathComponent("transcript")
        do { try FileManager.default.createDirectory(at: transDir, withIntermediateDirectories: true) }
        catch { store.message = "위키 transcript 폴더를 만들 수 없습니다: \(error.localizedDescription)"; return }

        // 감시 폴더 확인: 없으면 추가할지 묻고, 추가했다면 --init을 묶음 파일을 쓰기 전에 돌린다.
        let want = ["\(semester)/\(course)/lecture", "\(semester)/\(course)/transcript"]
        let dirsFile = URL(fileURLWithPath: vault).appendingPathComponent(Self.dirsRel)
        let have = Set(((try? String(contentsOf: dirsFile, encoding: .utf8)) ?? "").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping })
        let missing = want.filter { !have.contains($0.precomposedStringWithCanonicalMapping) }
        var addDirs = false, notWatched = false
        if !missing.isEmpty {
            switch ask("이 과목은 위키 자동 전처리 감시 대상이 아닙니다",
                       "'\(course)' 과목의 lecture·transcript 폴더를 감시 목록에 추가할까요? 추가하지 않으면 묶음 파일만 쓰고 자동 전처리는 되지 않습니다.",
                       ["추가", "추가하지 않음", "취소"]) {
            case 0: addDirs = true
            case 1: notWatched = true
            default: return
            }
        }

        let content = render(s, course: course, notes: notes, parts: combined.parts)
        let nf = DateFormatter(); nf.locale = Locale(identifier: "en_US_POSIX"); nf.dateFormat = "yyyy-MM-dd HHmm"
        func clean(_ x: String) -> String { x.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
        var dest = transDir.appendingPathComponent("\(nf.string(from: s.createdAt)) \(clean(s.title)).session.md")
        if let w = s.wikiPath, FileManager.default.fileExists(atPath: w) { dest = URL(fileURLWithPath: w) }   // 다시 보내면 같은 파일 덮어쓰기
        let title = s.title

        Task { @MainActor in
            if addDirs {
                Self.appendLines(missing, to: dirsFile)
                store.log("wiki watch dirs added \(missing)")
                let script = URL(fileURLWithPath: vault).appendingPathComponent(Self.scriptRel).path
                let out: String = await withCheckedContinuation { cont in
                    DispatchQueue.global(qos: .utility).async { cont.resume(returning: Self.runInit(script: script, vault: vault)) }
                }
                store.log("wiki auto_preprocess --init: \(out)")
            }
            do {
                try content.write(to: dest, atomically: true, encoding: .utf8)
            } catch {
                store.message = "위키로 보내기 실패: \(error.localizedDescription)"; return
            }
            for a in s.attachments { HoldList.remove(a) }
            store.updateSession(id) { $0.wikiPath = dest.path; $0.sentAt = Date() }
            AutoPreprocess.shared.scheduleAfterWikiSend()
            store.log("wiki sent \(dest.path) recordings=\(included.count)")
            var msg = "위키로 보냈습니다.\n\(course)/transcript/\(dest.lastPathComponent)"
            if notWatched { msg += "\n이 과목은 감시 목록에 없어 자동 전처리되지 않습니다." }
            _ = title
            store.message = msg
        }
    }

    // MARK: - 묶음 파일 내용

    private static func mmss(_ t: Double) -> String { let n = Int(max(0, t)); return String(format: "%d:%02d", n / 60, n % 60) }

    private static func yamlString(_ s: String) -> String {
        if s.contains(":") || s.contains("#") || s.contains("\"") || s.hasPrefix("-") || s.hasPrefix("[") || s.hasPrefix("{") {
            return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return s
    }

    static func render(_ s: Session, course: String, notes: String, parts: [CombinedTranscript.Part]) -> String {
        let done = parts.enumerated().filter { $0.element.transcript != nil }
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd HH:mm"
        let hm = DateFormatter(); hm.locale = Locale(identifier: "en_US_POSIX"); hm.dateFormat = "HH:mm"
        let vault = VaultConfig.shared.vault
        let lang = Profiles.entry(s.profile).language
        let total = done.reduce(0.0) { $0 + $1.element.entry.duration }
        let engine = done.compactMap { $0.element.transcript?.meta["engine"] }.first ?? "unknown"
        var o = "---\ntype: voicenote-session\ncourse: \(yamlString(course))\ntitle: \(yamlString(s.title))\ndate: \(df.string(from: s.createdAt))\n"
        if let w = VaultConfig.shared.week(of: s.createdAt) { o += "week: \(w)\n" }
        o += "language: \(lang.isEmpty ? "auto" : lang)\nrecordings: \(done.count)\nduration: \(mmss(total))\n"
        if !s.attachments.isEmpty {
            o += "source_paths:\n"
            for a in s.attachments {
                let rel = a.path.hasPrefix(vault + "/") ? String(a.path.dropFirst(vault.count + 1)) : a.path
                o += "  - \(rel)\n"
            }
        }
        o += "engine: \(engine)\n---\n\n"
        o += "## 내 노트\n\(notes)\n\n## 대본\n"
        let all = CombinedTranscript(parts: parts).lines
        for (pi, p) in done {
            o += "### 녹음 \(p.entry.index) · \(hm.string(from: p.entry.job.createdAt)) (\(mmss(p.entry.duration)))\n"
            for l in all where l.part == pi {
                o += "[\(formatTime(l.time))] \(l.speaker): \(l.text)\n"
            }
        }
        return o
    }

    // MARK: - 감시 폴더

    /// 파일 권한을 바꾸지 않도록 끝에 이어 쓴다.
    private static func appendLines(_ lines: [String], to f: URL) {
        var text = (try? String(contentsOf: f, encoding: .utf8)) ?? ""
        var add = ""
        if !text.isEmpty && !text.hasSuffix("\n") { add = "\n" }
        add += lines.joined(separator: "\n") + "\n"
        if let h = try? FileHandle(forWritingTo: f) {
            h.seekToEndOfFile(); h.write(Data(add.utf8)); try? h.close()
        } else {
            text += add
            try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: f, atomically: true, encoding: .utf8)
        }
    }

    nonisolated static func runInit(script: String, vault: String) -> String {
        guard FileManager.default.fileExists(atPath: script) else { return "스크립트 없음: \(script)" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script, "--init"]
        p.currentDirectoryURL = URL(fileURLWithPath: vault)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/Users/DH_WEST/.local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        env["HOME"] = NSHomeDirectory()
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return "실행 실패: \(error.localizedDescription)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return "code=\(p.terminationStatus) " + String(decoding: data, as: UTF8.self).suffix(300)
    }
}

/// 디버그: 창 내용을 PNG로 저장한다(--snapshot <경로> [--snapshot-after 초] [--snapshot-quit]).
@MainActor
enum DebugSnapshot {
    static func schedule(path: String, after: Double, quit: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            MainActor.assumeIsolated {
                if let w = NSApp.windows.first(where: { $0.title == "VNote" }), let v = w.contentView,
                   let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    if let d = rep.representation(using: .png, properties: [:]) { try? d.write(to: URL(fileURLWithPath: path)) }
                    Store.shared.log("snapshot saved \(path)")
                } else { Store.shared.log("snapshot failed: no window") }
                if quit { NSApp.terminate(nil) }
            }
        }
    }
}
