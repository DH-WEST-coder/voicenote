import AVFoundation
import Foundation

/// 프로젝트 = 과목. 노트 묶음이면서 과목 설정(위키 과목 폴더, 받아쓰기 언어, 고정 용어)을 가진다.
struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    /// 위키 과목 폴더 이름. nil이면 위키로 보내지 않는다.
    var course: String?
    /// "" = 자동(한·영), "Korean", "English"
    var language = ""
    /// 고정 용어 힌트
    var terms: [String] = []

    init(name: String, course: String? = nil, language: String = "", terms: [String] = []) {
        self.name = name; self.course = course; self.language = language; self.terms = terms
    }

    // 옛 projects.json(이름만 있던 형식)도 읽는다.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        course = try c.decodeIfPresent(String.self, forKey: .course)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? ""
        terms = try c.decodeIfPresent([String].self, forKey: .terms) ?? []
    }
}

/// projects.json의 새 형식(version 2 = 과목 설정이 들어 있고 프로필 이전이 끝난 것)
struct ProjectsFile: Codable {
    var version = 2
    var projects: [Project]
}

/// 노트 = 수업 1회. 녹음 여러 개, 내 노트, 자료, 채팅, 용어 힌트가 여기에 붙는다.
struct Session: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// true면 AI 제목이 덮어쓸 수 있다. 사용자가 고치면 false.
    var titleIsAuto = true
    var createdAt: Date
    /// 옛 필드(디코드 호환용, 쓰지 않는다). 과목·언어·고정 용어는 소속 프로젝트에서 읽는다.
    var profile: String
    var projectID: UUID?
    /// 이 노트만 언어를 다르게: nil=프로젝트 따름, "auto", "Korean", "English"
    var languageOverride: String?
    /// 녹음(Job) id, 시간 순서
    var recordingIDs: [UUID] = []
    var attachments: [Attachment] = []
    /// 강의자료에서 AI가 뽑은 용어 힌트(받아쓰기에 프로필 용어와 함께 쓴다)
    var terms: [String] = []
    var termsNote: String?
    /// 위키로 보낸 노트 묶음 경로
    var wikiPath: String?
    var sentAt: Date?
}

/// 노트 안 녹음들을 하나로 이어 붙인 시간축. 녹음 2는 녹음 1이 끝난 시각부터 시작한다.
struct TimelineEntry {
    let job: Job
    let index: Int        // 1부터
    let offset: Double
    var duration: Double { job.duration ?? 0 }
}

extension Store {
    // MARK: 조회

    var selectedSession: Session? { sessions.first { $0.id == selectedSessionID } }

    func session(_ id: UUID?) -> Session? { sessions.first { $0.id == id } }

    func session(ofJob id: UUID) -> Session? { sessions.first { $0.recordingIDs.contains(id) } }

    func recordings(of s: Session) -> [Job] { s.recordingIDs.compactMap { id in jobs.first { $0.id == id } } }

    func timeline(of s: Session) -> [TimelineEntry] {
        var off = 0.0
        return recordings(of: s).enumerated().map { i, j in
            defer { off += (j.status == .recording && recordingJobID == j.id) ? elapsed : (j.duration ?? 0) }
            return TimelineEntry(job: j, index: i + 1, offset: off)
        }
    }

    /// 노트 상태 요약(목록 아이콘용)
    func status(of s: Session) -> JobStatus? {
        let rs = recordings(of: s)
        if rs.contains(where: { $0.status == .recording }) { return .recording }
        if rs.contains(where: { $0.status == .processing }) { return .processing }
        if rs.contains(where: { $0.status == .queued }) { return .queued }
        if rs.contains(where: { $0.status == .failed }) { return .failed }
        return rs.isEmpty ? nil : .done
    }

    func totalDuration(of s: Session) -> Double {
        timeline(of: s).last.map { e in
            e.offset + ((e.job.status == .recording && recordingJobID == e.job.id) ? elapsed : e.duration)
        } ?? 0
    }

    // MARK: 저장

    func saveSessions() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
        if let d = try? enc.encode(sessions) { try? d.write(to: Paths.sessionsFile, options: .atomic) }
        if let d = try? enc.encode(ProjectsFile(projects: projects)) { try? d.write(to: Paths.projectsFile, options: .atomic) }
    }

    func loadSessions() {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let fm = FileManager.default
        // projects.json: 새 형식({"version":2,...})이면 이전 끝, 옛 배열이거나 없으면 이전 대상
        var migrated = false
        if let d = try? Data(contentsOf: Paths.projectsFile) {
            if let f = try? dec.decode(ProjectsFile.self, from: d) { projects = f.projects; migrated = true }
            else { projects = (try? dec.decode([Project].self, from: d)) ?? [] }
        }
        // 이전은 되돌릴 수 있게 먼저 백업한다(어떤 파일도 저장하기 전에).
        if !migrated { backupBeforeMigration() }
        if let d = try? Data(contentsOf: Paths.sessionsFile) {
            sessions = (try? dec.decode([Session].self, from: d)) ?? []
        } else if !jobs.isEmpty {
            // 노트 구조 이전의 녹음(시험용)은 '테스트' 프로젝트의 노트 하나로 모은다.
            let p = Project(name: "테스트")
            var s = Session(title: "기존 테스트 녹음", titleIsAuto: false, createdAt: jobs.map(\.createdAt).min() ?? Date(),
                            profile: "", projectID: p.id)
            s.recordingIDs = jobs.sorted { $0.createdAt < $1.createdAt }.map(\.id)
            projects = [p]; sessions = [s]
            log("migrated \(jobs.count) jobs into test session")
        }
        // 어느 노트에도 없는 녹음(예: 이전 버전에서 가져온 파일)은 각각 노트로 만든다.
        let linked = Set(sessions.flatMap(\.recordingIDs))
        for j in jobs where !linked.contains(j.id) {
            var s = Session(title: j.title, createdAt: j.createdAt, profile: j.profile)
            s.recordingIDs = [j.id]
            sessions.append(s)
        }
        sessions.sort { $0.createdAt > $1.createdAt }
        if !migrated {
            migrateProfilesToProjects()
            saveSessions()
        } else if !fm.fileExists(atPath: Paths.sessionsFile.path) && !sessions.isEmpty {
            saveSessions()
        }
    }

    // MARK: 프로필 → 프로젝트 이전 (한 번만)

    private func backupBeforeMigration() {
        let fm = FileManager.default
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: Date())
        for u in [Paths.sessionsFile, Paths.projectsFile, Paths.profilesFile] where fm.fileExists(atPath: u.path) {
            let dst = u.deletingLastPathComponent().appendingPathComponent(u.lastPathComponent + ".bak-" + stamp)
            do { try fm.copyItem(at: u, to: dst); log("migration backup \(dst.lastPathComponent)") }
            catch { log("migration backup failed \(u.lastPathComponent): \(error.localizedDescription)") }
        }
    }

    private func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }

    /// 프로필마다 프로젝트를 만들고(같은 이름이 있으면 거기에 설정을 넣고), '프로젝트 없음' 노트를 옛 프로필 이름의 프로젝트로 옮긴다.
    private func migrateProfilesToProjects() {
        let legacy = Profiles.legacy()
        var created = 0, filled = 0, moved = 0
        for p in legacy {
            if let i = projects.firstIndex(where: { nfc($0.name) == nfc(p.name) }) {
                projects[i].course = p.course; projects[i].language = p.language; projects[i].terms = p.terms
                filled += 1
            } else {
                projects.append(Project(name: p.name, course: p.course, language: p.language, terms: p.terms))
                created += 1
            }
        }
        for i in sessions.indices {
            let prof = sessions[i].profile
            if sessions[i].projectID == nil {
                guard !prof.isEmpty, let pr = projects.first(where: { nfc($0.name) == nfc(prof) }) else { continue }
                sessions[i].projectID = pr.id; moved += 1
            }
            // 프로젝트 언어와 옛 프로필 언어가 다르면 노트에만 언어를 따로 남긴다(예: 영어 프로필 노트가 한국어 프로젝트에 있는 경우).
            if !prof.isEmpty, let pr = projects.first(where: { $0.id == sessions[i].projectID }),
               let lp = legacy.first(where: { nfc($0.name) == nfc(prof) }), lp.language != pr.language, !lp.language.isEmpty {
                sessions[i].languageOverride = lp.language
            }
        }
        log("migrated profiles -> projects: created=\(created) filled=\(filled) notesMoved=\(moved)")
    }

    func updateSession(_ id: UUID, _ f: (inout Session) -> Void) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        f(&sessions[i]); saveSessions()
    }

    // MARK: 만들기·옮기기·지우기

    @discardableResult
    /// projectID: 생략(nil)=기본 프로젝트, .some(nil)=프로젝트 없음
    func newSession(title: String? = nil, projectID: UUID?? = nil, select: Bool = true) -> Session {
        let now = Date()
        let pid: UUID? = projectID ?? defaultProjectID()
        let s = Session(title: title ?? defaultTitle(now, project: pid), createdAt: now, profile: "", projectID: pid)
        sessions.insert(s, at: 0)
        if select { selectedSessionID = s.id }
        if pid != nil { lastProjectID = pid }
        saveSessions()
        return s
    }

    /// 새 노트·녹음이 들어갈 프로젝트: lastProjectID(노트를 고르면 그 프로젝트로 따라가고, 도구막대 메뉴에서 바꾼다) > 프로젝트 없음
    func defaultProjectID() -> UUID? {
        if let id = lastProjectID, projects.contains(where: { $0.id == id }) { return id }
        return nil
    }

    func defaultTitle(_ d: Date, project: UUID?) -> String {
        let f = DateFormatter(); f.dateFormat = "M월 d일 HH:mm"
        let name = projects.first { $0.id == project }?.name
        return (name.map { $0 + " " } ?? "") + f.string(from: d)
    }

    // MARK: 프로젝트 설정 조회 (과목·언어·용어는 항상 여기서)

    func project(of s: Session) -> Project? { projects.first { $0.id == s.projectID } }
    func project(_ id: UUID?) -> Project? { projects.first { $0.id == id } }

    /// 노트의 위키 과목 폴더(없으면 nil)
    func course(of s: Session) -> String? {
        guard let c = project(of: s)?.course, !c.isEmpty else { return nil }
        return c
    }

    /// 엔진 --language 값: 노트 덮어쓰기 > 프로젝트 > 자동
    func languageArg(of s: Session?) -> String {
        let l = s?.languageOverride ?? s.flatMap { project(of: $0)?.language } ?? ""
        return l.isEmpty ? "auto" : l
    }

    /// 프로젝트 고정 용어 + 노트 용어(중복 제거)
    func allTerms(of s: Session?) -> [String] {
        guard let s else { return [] }
        var seen = Set<String>(), out: [String] = []
        for t in (project(of: s)?.terms ?? []) + s.terms {
            let k = t.lowercased()
            if !t.isEmpty, seen.insert(k).inserted { out.append(t) }
        }
        return out
    }

    /// 엔진에 넘길 --language/--terms-file/--course 인자
    func engineArgs(for s: Session?, course withCourse: Bool = true) -> [String] {
        var a = ["--language", languageArg(of: s)]
        if let s {
            let terms = allTerms(of: s)
            if !terms.isEmpty {
                let tf = Paths.support.appendingPathComponent("terms/\(s.id.uuidString).txt")
                try? FileManager.default.createDirectory(at: tf.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? terms.joined(separator: "\n").write(to: tf, atomically: true, encoding: .utf8)
                a += ["--terms-file", tf.path]
            }
            if withCourse, let c = course(of: s) { a += ["--course", c] }
        }
        return a
    }

    func renameSession(_ id: UUID, _ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        updateSession(id) { $0.title = t; $0.titleIsAuto = false }
    }

    /// 노트를 다른 프로젝트로 옮긴다. 과목·언어·용어는 새 프로젝트 것을 따른다.
    func move(session id: UUID, to project: UUID?) {
        guard session(id)?.projectID != project else { return }
        updateSession(id) { $0.projectID = project }
        log("move session \(id) -> project \(project?.uuidString ?? "none")")
    }

    func removeSession(_ id: UUID) {
        guard let s = session(id) else { return }
        for j in s.recordingIDs { remove(j) }
        sessions.removeAll { $0.id == id }
        if selectedSessionID == id { selectedSessionID = nil }
        saveSessions()
    }

    @discardableResult
    func newProject(_ name: String) -> Project {
        let p = Project(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        projects.append(p); saveSessions(); return p
    }

    func renameProject(_ id: UUID, _ name: String) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].name = name; saveSessions()
    }

    /// 프로젝트 설정 시트에서 저장(없는 id면 새로 만든다)
    func saveProject(_ p: Project) {
        if let i = projects.firstIndex(where: { $0.id == p.id }) { projects[i] = p } else { projects.append(p) }
        saveSessions()
    }

    /// 프로젝트를 지워도 노트는 지우지 않고 '프로젝트 없음'으로 옮긴다.
    func removeProject(_ id: UUID) {
        for i in sessions.indices where sessions[i].projectID == id { sessions[i].projectID = nil }
        projects.removeAll { $0.id == id }
        if lastProjectID == id { lastProjectID = nil }
        saveSessions()
    }

    // MARK: 시각 (노트 줄 머리, 재생)

    /// 노트에 붙일 누적 시각: 이 노트를 녹음 중이면 앞 녹음 길이 + 경과, 재생 중이면 앞 녹음 길이 + 재생 위치.
    func notePosition(for s: Session) -> Double? {
        let tl = timeline(of: s)
        if let e = tl.first(where: { $0.job.status == .recording && $0.job.id == recordingJobID }) { return e.offset + elapsed }
        let p = AudioPlayer.shared
        if let e = tl.first(where: { $0.job.audioPath == p.loadedPath }) { return e.offset + p.currentTime }
        return nil
    }

    /// 누적 시각 → 해당 녹음의 위치로 재생
    func seek(session s: Session, to t: Double) {
        let tl = timeline(of: s).filter { $0.job.status != .recording }
        guard let e = tl.last(where: { $0.offset <= t + 0.01 }) ?? tl.first else { return }
        AudioPlayer.shared.play(path: e.job.audioPath, from: max(0, t - e.offset))
    }

    /// 지금 재생 위치(누적). 이 노트 녹음이 아니면 nil.
    func playPosition(in s: Session) -> Double? {
        let p = AudioPlayer.shared
        guard let e = timeline(of: s).first(where: { $0.job.audioPath == p.loadedPath }) else { return nil }
        return e.offset + p.currentTime
    }

    /// 화자 칩: 지금 위치(pos) 이후 그 화자의 다음 줄(없으면 처음 줄)
    func nextLine(of speaker: String, after pos: Double, in lines: [CombinedTranscript.Line]) -> CombinedTranscript.Line? {
        let mine = lines.filter { $0.speaker == speaker }
        return mine.first(where: { $0.time > pos + 0.05 }) ?? mine.first
    }

    // MARK: 대본 합치기

    /// 노트의 녹음 대본을 누적 시각으로 합친다. 처리 안 된 녹음은 상태 줄로 남긴다.
    func combinedTranscript(of s: Session) -> CombinedTranscript {
        var out = CombinedTranscript()
        for e in timeline(of: s) {
            var part = CombinedTranscript.Part(entry: e, transcript: nil)
            if e.job.status == .done, let p = e.job.transcriptPath { part.transcript = TranscriptIO.load(path: p) }
            // 정밀본이 아직 없으면 실시간 초안을 쓴다(화자 없음)
            if part.transcript == nil {
                let live = LiveTranscriber.shared.lines(for: e.job)
                if !live.isEmpty {
                    var t = Transcript()
                    t.segments = live.enumerated().map { i, l in Segment(id: i, time: l.time, timeLabel: formatTime(l.time), speaker: "실시간", text: l.text) }
                    part.transcript = t; part.isLive = true
                }
            }
            out.parts.append(part)
        }
        return out
    }
}

struct CombinedTranscript {
    struct Part { let entry: TimelineEntry; var transcript: Transcript?; var isLive = false }
    var parts: [Part] = []

    /// 누적 시각이 붙은 줄들
    struct Line: Identifiable { let id: String; let part: Int; let time: Double; let speaker: String; let text: String; let jobID: UUID; var isLive = false }
    var lines: [Line] {
        parts.enumerated().flatMap { pi, p in
            (p.transcript?.segments ?? []).map { seg in
                Line(id: "\(pi)-\(seg.id)", part: pi, time: p.entry.offset + seg.time, speaker: seg.speaker, text: seg.text, jobID: p.entry.job.id, isLive: p.isLive)
            }
        }
    }
    var speakers: [String] {
        var seen: [String] = []
        for l in lines where !l.isLive && !seen.contains(l.speaker) { seen.append(l.speaker) }
        return seen
    }
    /// AI 맥락용 텍스트 줄: "[m:ss] 화자: 내용"
    var textLines: [ChatContext.Line] {
        var out = lines.map { l in
            ChatContext.Line(time: l.time, text: l.isLive ? "[\(formatTime(l.time))] (실시간 초안) \(l.text)" : "[\(formatTime(l.time))] \(l.speaker): \(l.text)")
        }
        if lines.contains(where: \.isLive) {
            out.insert(ChatContext.Line(time: 0, text: "[참고] '(실시간 초안)' 표시가 붙은 줄은 실시간 받아쓰기라 오인식이 더 많을 수 있다."), at: 0)
        }
        return out
    }
}
