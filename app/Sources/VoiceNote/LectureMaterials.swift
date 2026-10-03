import AppKit
import Foundation
import CryptoKit
import PDFKit

/// 수업 자료(PDF·PPTX) 넣기: 다운로드 → 위키 `<semester>/<과목>/lecture/`로 이동 → 노트에 연결 → Goodnotes로 넘기기.
let docExtensions: Set<String> = ["pdf", "pptx", "ppt"]

/// 노트에 연결된 자료. path는 위키로 옮긴 원본, pdfPath는 PPTX를 바꾼 PDF(앱 보기·Goodnotes·채팅용).
struct Attachment: Codable, Hashable, Identifiable {
    var path: String
    var pdfPath: String?
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var isPDF: Bool { path.lowercased().hasSuffix(".pdf") }
    /// 앱에서 보여 주고 Goodnotes로 넘길 PDF(없으면 nil: 아직 변환 전/실패)
    var viewPDF: String? { isPDF ? path : pdfPath }
}

enum Courses {
    static var semesterDir: URL {
        URL(fileURLWithPath: VaultConfig.resolve(VaultConfig.shared.semester, vault: VaultConfig.shared.vault))
    }

    /// 이번 학기 과목 폴더 이름들
    static func list() -> [String] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: semesterDir, includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent).sorted()
    }

    /// 프로필 → 과목 폴더 이름. 프로필의 wiki_dir(…/<과목>/transcript)의 부모 폴더 이름을 우선 쓴다.
    static func course(forProfile p: String) -> String? {
        guard !p.isEmpty else { return nil }
        if let t = Profiles.wikiTarget(for: p) {
            let parent = ((t.dir as NSString).deletingLastPathComponent as NSString).lastPathComponent
            if !parent.isEmpty { return parent }
        }
        return Profiles.course(for: p)
    }

    static func lectureDir(_ course: String) -> URL {
        semesterDir.appendingPathComponent(course).appendingPathComponent("lecture")
    }
}

/// 다운로드 폴더 최근 파일
struct RecentFile: Identifiable, Hashable {
    let url: URL
    let date: Date
    let size: Int
    let isDir: Bool
    var id: URL { url }
    var ext: String { url.pathExtension.lowercased() }
    var kind: String {
        if isDir { return "폴더" }
        if ext == "pdf" { return "PDF" }
        if ext == "pptx" || ext == "ppt" { return "PPT" }
        return "오디오"
    }
    var icon: String {
        if isDir { return "folder.fill" }
        if ext == "pdf" { return "doc.richtext.fill" }
        if ext == "pptx" || ext == "ppt" { return "rectangle.on.rectangle.angled.fill" }
        return "waveform"
    }

    static var downloads: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads") }

    /// 다운로드 폴더에서 오디오·PDF·PPT·폴더를 받은 날짜(없으면 수정 날짜) 최신순으로
    static func scanDownloads(limit: Int = 80) -> [RecentFile] {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey, .fileSizeKey, .isDirectoryKey, .isPackageKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        var out: [RecentFile] = []
        for u in items {
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { continue }
            let dir = (v.isDirectory ?? false) && !(v.isPackage ?? false)
            let ext = u.pathExtension.lowercased()
            guard dir || docExtensions.contains(ext) || audioExtensions.contains(ext) else { continue }
            if dir && MaterialImporter.expand([u]).isEmpty { continue }   // 넣을 파일이 없는 폴더는 숨김
            out.append(RecentFile(url: u, date: v.addedToDirectoryDate ?? v.contentModificationDate ?? .distantPast,
                                  size: v.fileSize ?? 0, isDir: dir))
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(limit))
    }
}

@MainActor
final class MaterialImporter: ObservableObject {
    static let shared = MaterialImporter()

    @Published var showPicker = false
    /// 확인 창에 올릴 자료(nil이면 창 닫힘)
    @Published var pending: PendingImport?
    @Published var course = ""
    @Published var sendToGoodnotes: Bool { didSet { UserDefaults.standard.set(sendToGoodnotes, forKey: "sendToGoodnotes") } }
    @Published var status: String?
    @Published var busy = false
    /// 디버그(--no-goodnotes): Goodnotes 전송을 끈다(저장 안 함).
    nonisolated(unsafe) static var debugNoGoodnotes = false

    struct PendingImport: Identifiable { let id = UUID(); let files: [URL] }

    init() { sendToGoodnotes = UserDefaults.standard.object(forKey: "sendToGoodnotes") as? Bool ?? true }

    /// 폴더는 한 단계 아래까지 펼친다(숨김 파일 제외).
    nonisolated static func expand(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for u in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let inner = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                out += inner.filter { let e = $0.pathExtension.lowercased(); return docExtensions.contains(e) || audioExtensions.contains(e) }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } else {
                out.append(u)
            }
        }
        return out
    }

    /// 끌어다 놓기·가져오기 공통 입구: 오디오는 받아쓰기 큐로(선택한 노트가 있으면 그 노트에, 없으면 파일마다 새 노트), 자료는 확인 창으로.
    func request(_ urls: [URL]) {
        let all = Self.expand(urls)
        let audio = all.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        let docs = all.filter { docExtensions.contains($0.pathExtension.lowercased()) }
        if !audio.isEmpty { Store.shared.importFiles(audio, into: Store.shared.selectedSessionID) }
        if !docs.isEmpty {
            course = defaultCourse() ?? ""
            pending = PendingImport(files: docs)
        }
    }

    /// 자료를 연결할 노트: 녹음 중인 노트 > 선택한 노트. 없으면 확인 시 새 노트를 만든다.
    var targetSession: Session? {
        let s = Store.shared
        if let id = s.recordingJobID, let ss = s.session(ofJob: id) { return ss }
        return s.selectedSession
    }

    func defaultCourse() -> String? {
        let s = Store.shared
        let profile = targetSession?.profile ?? s.selectedProfile
        let c = Courses.course(forProfile: profile) ?? Courses.course(forProfile: s.selectedProfile)
        if let c, Courses.list().contains(c) { return c }
        return c
    }

    func confirm(_ p: PendingImport) {
        guard !course.isEmpty else { return }
        let files = p.files, course = course, gn = sendToGoodnotes && !Self.debugNoGoodnotes
        let sessionID = targetSession?.id
        pending = nil
        busy = true; status = "자료 옮기는 중…"
        Task.detached {
            let result = Self.process(files: files, course: course, goodnotes: gn) { msg in
                Task { @MainActor in MaterialImporter.shared.status = msg }
            }
            await MainActor.run {
                MaterialImporter.shared.finish(result, sessionID: sessionID, course: course, goodnotes: gn)
            }
        }
    }

    private func finish(_ r: ProcessResult, sessionID: UUID?, course: String, goodnotes: Bool) {
        let s = Store.shared
        var lines = ["\(r.attachments.count)개 자료를 위키 \(course)/lecture 로 옮겼습니다."]
        if !r.attachments.isEmpty {
            // 노트가 없으면 새로 만든다(프로필은 과목에 맞는 것이 있으면 그것).
            let sid: UUID
            if let id = sessionID, s.session(id) != nil { sid = id }
            else {
                let profile = s.profiles.first { Courses.course(forProfile: $0) == course } ?? s.selectedProfile
                sid = s.newSession(profile: profile).id
                lines.append("새 노트를 만들어 연결했습니다.")
            }
            let firstTime = s.session(sid)?.attachments.isEmpty ?? true
            s.updateSession(sid) { ss in
                for x in r.attachments where !ss.attachments.contains(where: { $0.path == x.path }) { ss.attachments.append(x) }
            }
            for a in r.attachments { HoldList.add(a) }
            MaterialTabs.shared.show(session: sid, attachment: r.attachments[0].id)
            AITasks.shared.extractTerms(session: sid)
            if firstTime { AITasks.shared.makeTitle(session: sid) }
        }
        if goodnotes && r.sentToGoodnotes > 0 { lines.append("Goodnotes에서 '불러오기'를 눌러 주세요 (\(course) 폴더를 열어 두면 그 위치로 들어갑니다).") }
        lines += r.errors
        busy = false
        status = nil
        s.message = lines.joined(separator: "\n")
        s.log("materials course=\(course) n=\(r.attachments.count) goodnotes=\(r.sentToGoodnotes) errors=\(r.errors)")
    }

    struct ProcessResult: Sendable { var attachments: [Attachment] = []; var sentToGoodnotes = 0; var errors: [String] = [] }

    nonisolated static func process(files: [URL], course: String, goodnotes: Bool,
                                    progress: @escaping @Sendable (String) -> Void) -> ProcessResult {
        var r = ProcessResult()
        let fm = FileManager.default
        let dest = Courses.lectureDir(course)
        do { try fm.createDirectory(at: dest, withIntermediateDirectories: true) } catch {
            r.errors.append("위키 폴더를 만들 수 없습니다: \(dest.path)"); return r
        }
        for (i, src) in files.enumerated() {
            progress("위키로 옮기는 중 (\(i + 1)/\(files.count)) \(src.lastPathComponent)")
            guard let moved = moveIntoWiki(src, dir: dest, errors: &r.errors) else { continue }
            var a = Attachment(path: moved.path)
            if !a.isPDF {
                progress("PowerPoint로 PDF 만드는 중 \(src.lastPathComponent)")
                switch convertToPDF(moved) {
                case .success(let pdf): a.pdfPath = pdf.path
                case .failure(let e): r.errors.append("\(src.lastPathComponent): PDF 변환 실패 (\(e.localizedDescription)). 원본은 위키에 있습니다.")
                }
            }
            r.attachments.append(a)
        }
        let pdfs = r.attachments.compactMap(\.viewPDF)
        if goodnotes && !pdfs.isEmpty {
            progress("Goodnotes로 보내는 중…")
            if openInGoodnotes(pdfs) { r.sentToGoodnotes = pdfs.count } else { r.errors.append("Goodnotes를 열 수 없습니다.") }
        }
        return r
    }

    /// 이동(다운로드에서 사라짐). 같은 이름이 있으면 내용이 같을 때는 원본을 휴지통으로, 다르면 " (2)"를 붙인다.
    nonisolated static func moveIntoWiki(_ src: URL, dir: URL, errors: inout [String]) -> URL? {
        let fm = FileManager.default
        var target = dir.appendingPathComponent(src.lastPathComponent)
        if src.standardizedFileURL.path == target.standardizedFileURL.path { return target }   // 이미 위키 안
        if fm.fileExists(atPath: target.path) {
            if fm.contentsEqual(atPath: src.path, andPath: target.path) {
                try? fm.trashItem(at: src, resultingItemURL: nil)
                return target
            }
            let base = src.deletingPathExtension().lastPathComponent, ext = src.pathExtension
            var n = 2
            repeat { target = dir.appendingPathComponent("\(base) (\(n)).\(ext)"); n += 1 } while fm.fileExists(atPath: target.path)
        }
        do { try fm.moveItem(at: src, to: target); return target } catch {
            errors.append("\(src.lastPathComponent): 옮기기 실패 (\(error.localizedDescription))"); return nil
        }
    }

    /// PowerPoint(AppleScript)로 PDF를 만든다. 처음 한 번은 PowerPoint가 materials 폴더 접근 권한을 묻는다.
    nonisolated static func convertToPDF(_ pptx: URL) -> Result<URL, Error> {
        let outDir = Paths.materials
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var out = outDir.appendingPathComponent(pptx.deletingPathExtension().lastPathComponent + ".pdf")
        var n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = outDir.appendingPathComponent(pptx.deletingPathExtension().lastPathComponent + " (\(n)).pdf"); n += 1
        }
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let script = """
        with timeout of 600 seconds
            tell application "Microsoft PowerPoint"
                open (POSIX file "\(esc(pptx.path))")
                set p to active presentation
                save p in (POSIX file "\(esc(out.path))") as save as PDF
                close p saving no
            end tell
        end timeout
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let err = Pipe(); proc.standardError = err; proc.standardOutput = Pipe()
        do { try proc.run() } catch { return .failure(error) }
        proc.waitUntilExit()
        if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: out.path) { return .success(out) }
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .failure(NSError(domain: "VoiceNote", code: Int(proc.terminationStatus),
                                userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "PowerPoint 오류" : msg]))
    }

    /// Goodnotes는 꺼져 있다가 `open`으로 켜지면 파일을 무시한다(실측). 먼저 켜고 기다린 뒤 넘긴다.
    nonisolated static func openInGoodnotes(_ paths: [String]) -> Bool {
        let id = "com.goodnotesapp.x"
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil else { return false }
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            run("/usr/bin/open", ["-g", "-b", id])
            Thread.sleep(forTimeInterval: 5)
        }
        return run("/usr/bin/open", ["-b", id] + paths) == 0
    }

    @discardableResult nonisolated static func run(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        do { try p.run() } catch { return -1 }
        p.waitUntilExit(); return p.terminationStatus
    }

    /// 채팅 맥락용: 연결된 자료 PDF의 본문(페이지 표시 포함). maxPages가 있으면 앞 N페이지만.
    nonisolated static func text(of a: Attachment, cap: Int, maxPages: Int? = nil) -> String? {
        guard let p = a.viewPDF, let doc = PDFDocument(url: URL(fileURLWithPath: p)) else { return nil }
        var out = ""
        for i in 0..<min(doc.pageCount, maxPages ?? Int.max) {
            guard let s = doc.page(at: i)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { continue }
            out += "[p.\(i + 1)]\n\(s)\n\n"
            if out.count > cap { out = String(out.prefix(cap)) + "\n[… 이후 생략 …]"; break }
        }
        return out.isEmpty ? nil : out
    }

    /// 글자가 minChars 미만인 페이지(그림·수식 위주)를 PNG(긴 변 1600px)로 그려 경로를 돌려준다. 최대 max장.
    /// 파일은 Paths.chatScratch/img/<파일 해시>/p<N>.png (이미 있으면 재사용). 엔진 작업 폴더 아래라 agy도 열 수 있다.
    nonisolated static func pageImages(_ a: Attachment, minChars: Int = 80, max: Int = 8) -> [String] {
        guard max > 0, let p = a.viewPDF, let doc = PDFDocument(url: URL(fileURLWithPath: p)) else { return [] }
        let attrs = try? FileManager.default.attributesOfItem(atPath: p)
        let sig = "\(p)|\(attrs?[.size] ?? 0)|\((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        let hash = SHA256.hash(data: Data(sig.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        let dir = Paths.chatScratch.appendingPathComponent("img/\(hash)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [String] = []
        for i in 0..<doc.pageCount where out.count < max {
            guard let page = doc.page(at: i) else { continue }
            let chars = page.string?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
            if chars >= minChars { continue }
            let png = dir.appendingPathComponent("p\(i + 1).png")
            if !FileManager.default.fileExists(atPath: png.path) {
                let box = page.bounds(for: .mediaBox)
                guard box.width > 0, box.height > 0 else { continue }
                let k = 1600 / Swift.max(box.width, box.height)
                let img = page.thumbnail(of: NSSize(width: box.width * k, height: box.height * k), for: .mediaBox)
                guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let data = rep.representation(using: .png, properties: [:]) else { continue }
                try? data.write(to: png)
            }
            out.append(png.path)
        }
        return out
    }
}

/// 위키 lecture 폴더의 보류 목록: 노트에 연결만 하고 아직 위키로 보내지 않은 자료는 위키 자동 전처리가 건너뛴다.
/// `<lectureDir>/.voicenote-hold` 한 줄 = `파일명<TAB>YYYY-MM-DD`. 쓰기 실패는 로그만 남긴다.
enum HoldList {
    static func file(for a: Attachment) -> URL {
        URL(fileURLWithPath: (a.path as NSString).deletingLastPathComponent).appendingPathComponent(".voicenote-hold")
    }

    static func add(_ a: Attachment) {
        let f = file(for: a)
        var lines = ((try? String(contentsOf: f, encoding: .utf8)) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
        if lines.contains(where: { $0.components(separatedBy: "\t").first == a.name }) { return }
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
        lines.append("\(a.name)\t\(df.string(from: Date()))")
        write(lines, to: f)
    }

    static func remove(_ a: Attachment) {
        let f = file(for: a)
        guard let text = try? String(contentsOf: f, encoding: .utf8) else { return }
        let all = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        let kept = all.filter { $0.components(separatedBy: "\t").first != a.name }
        if kept.count != all.count { write(kept, to: f) }
    }

    private static func write(_ lines: [String], to f: URL) {
        do { try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(to: f, atomically: true, encoding: .utf8) }
        catch { Task { @MainActor in Store.shared.log("hold list write failed \(f.path): \(error.localizedDescription)") } }
    }
}

/// 가운데 위쪽 탭(대본 / 자료) 상태. 노트별로 마지막 탭을 기억한다.
@MainActor
final class MaterialTabs: ObservableObject {
    static let shared = MaterialTabs()
    /// 노트 id → 고른 자료 id(nil이면 대본 탭)
    @Published var selection: [UUID: String] = [:]
    func show(session: UUID, attachment: String?) { selection[session] = attachment }
}
