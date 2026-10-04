import AVFoundation
import Foundation

/// 프로젝트 = 노트를 묶는 폴더(예: 과목, 인턴십)
struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
}

/// 노트 = 수업 1회. 녹음 여러 개, 내 노트, 자료, 채팅, 용어 힌트가 여기에 붙는다.
struct Session: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// true면 AI 제목이 덮어쓸 수 있다. 사용자가 고치면 false.
    var titleIsAuto = true
    var createdAt: Date
    var profile: String
    var projectID: UUID?
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
        if let d = try? enc.encode(projects) { try? d.write(to: Paths.projectsFile, options: .atomic) }
    }

    func loadSessions() {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: Paths.projectsFile) { projects = (try? dec.decode([Project].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: Paths.sessionsFile) {
            sessions = (try? dec.decode([Session].self, from: d)) ?? []
        } else if !jobs.isEmpty {
            // 노트 구조 이전의 녹음(시험용)은 '테스트' 프로젝트의 노트 하나로 모은다.
            let p = Project(name: "테스트")
            var s = Session(title: "기존 테스트 녹음", titleIsAuto: false, createdAt: jobs.map(\.createdAt).min() ?? Date(),
                            profile: "", projectID: p.id)
            s.recordingIDs = jobs.sorted { $0.createdAt < $1.createdAt }.map(\.id)
            projects = [p]; sessions = [s]
            saveSessions()
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
    }

    func updateSession(_ id: UUID, _ f: (inout Session) -> Void) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        f(&sessions[i]); saveSessions()
    }

    // MARK: 만들기·옮기기·지우기

    @discardableResult
    func newSession(title: String? = nil, profile: String? = nil, projectID: UUID? = nil, select: Bool = true) -> Session {
        let now = Date()
        let s = Session(title: title ?? defaultTitle(now), createdAt: now, profile: profile ?? selectedProfile,
                        projectID: projectID ?? selectedSession?.projectID ?? defaultProject(for: profile ?? selectedProfile))
        sessions.insert(s, at: 0)
        if select { selectedSessionID = s.id }
        saveSessions()
        return s
    }

    /// 프로필의 과목 이름과 같은 프로젝트가 있으면 그 프로젝트에 넣는다.
    func defaultProject(for profile: String) -> UUID? {
        guard let c = Courses.course(forProfile: profile) else { return nil }
        return projects.first { $0.name.precomposedStringWithCanonicalMapping == c.precomposedStringWithCanonicalMapping }?.id
    }

    func defaultTitle(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M월 d일 HH:mm"
        let c = Courses.course(forProfile: selectedProfile)
        return (c.map { $0 + " " } ?? "") + f.string(from: d)
    }

    func renameSession(_ id: UUID, _ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        updateSession(id) { $0.title = t; $0.titleIsAuto = false }
    }

    func move(session id: UUID, to project: UUID?) { updateSession(id) { $0.projectID = project } }

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

    /// 프로젝트를 지워도 노트는 지우지 않고 '프로젝트 없음'으로 옮긴다.
    func removeProject(_ id: UUID) {
        for i in sessions.indices where sessions[i].projectID == id { sessions[i].projectID = nil }
        projects.removeAll { $0.id == id }
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
