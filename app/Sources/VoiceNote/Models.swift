import Foundation

enum JobStatus: String, Codable {
    case recording, queued, processing, done, failed
    var label: String {
        switch self {
        case .recording: return "녹음 중"
        case .queued: return "대기"
        case .processing: return "처리 중"
        case .done: return "완료"
        case .failed: return "실패"
        }
    }
}

struct Job: Codable, Identifiable, Equatable {
    var id = UUID()
    var audioPath: String
    var title: String
    var createdAt: Date
    var duration: Double?
    var profile: String
    var status: JobStatus = .queued
    var stage: String?
    var transcriptPath: String?
    /// 위키 transcript 폴더로 보낸 사본 경로(앱이 새로 만든 파일)
    var wikiPath: String?
    var error: String?
    /// 실시간 받아쓰기 초안 파일(transcripts/live/<id>.md). 정밀본이 나와도 지우지 않는다.
    var liveTranscriptPath: String?
    /// 배터리로 돌 때 모은 소비 전력 합계(W)·표본 수·사용한 배터리 %p (PowerMonitor가 갱신)
    var powerSumW: Double?
    var powerSamples: Int?
    var batteryUsedPct: Double?
    var avgWatts: Double? {
        guard let n = powerSamples, n > 0, let s = powerSumW else { return nil }
        return s / Double(n)
    }
}

func formatTime(_ s: Double) -> String {
    let t = Int(max(0, s))
    let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

enum Paths {
    /// --sandbox <dir> 로 지정하면 모든 데이터 경로가 그 아래로 바뀐다(테스트용).
    nonisolated(unsafe) static var sandbox: URL?
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var support: URL {
        sandbox ?? home.appendingPathComponent("Library/Application Support/VoiceNote")
    }
    static var profilesFile: URL { support.appendingPathComponent("profiles.json") }
    static var stateFile: URL { support.appendingPathComponent("jobs.json") }
    static var sessionsFile: URL { support.appendingPathComponent("sessions.json") }
    static var projectsFile: URL { support.appendingPathComponent("projects.json") }
    static var logFile: URL { support.appendingPathComponent("app.log") }
    static var logsDir: URL { support.appendingPathComponent("logs") }
    static var base: URL { sandbox ?? home.appendingPathComponent("Documents/VoiceNote") }
    static var recordings: URL { base.appendingPathComponent("recordings") }
    static var transcripts: URL { base.appendingPathComponent("transcripts") }
    static var liveTranscripts: URL { transcripts.appendingPathComponent("live") }
    static var notes: URL { base.appendingPathComponent("notes") }
    static var chats: URL { base.appendingPathComponent("chats") }
    /// PPTX를 바꾼 PDF(앱 보기·Goodnotes용)
    static var materials: URL { base.appendingPathComponent("materials") }
    /// 채팅 엔진(agy/codex)의 작업 폴더. 앱 전용 임시 폴더이며 위키/사용자 파일과 무관하다.
    static var chatScratch: URL { support.appendingPathComponent("chat-scratch") }
    static var promptsFile: URL { support.appendingPathComponent("chat_prompts.json") }
}

/// 옛 profiles.json(프로필 = 과목 설정). 앱은 이제 쓰지 않고, 프로젝트로 한 번 옮길 때만 읽는다.
enum Profiles {
    struct Legacy { let name: String; let language: String; let terms: [String]; let course: String? }

    static func legacy() -> [Legacy] {
        guard let d = try? Data(contentsOf: Paths.profilesFile),
              let all = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return all.keys.sorted().map { k in
            let o = all[k] as? [String: Any] ?? [:]
            // 과목은 wiki_dir(…/<과목>/transcript)의 부모 폴더 이름을 우선 쓴다.
            var course = o["course"] as? String
            if let w = o["wiki_dir"] as? String, !w.isEmpty {
                let parent = ((w as NSString).deletingLastPathComponent as NSString).lastPathComponent
                if !parent.isEmpty { course = parent }
            }
            return Legacy(name: k, language: o["language"] as? String ?? "",
                          terms: (o["terms"] as? [String] ?? []).filter { !$0.isEmpty },
                          course: (course?.isEmpty ?? true) ? nil : course)
        }
    }
}
