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

struct WikiTarget { let course: String; let dir: String }

enum Profiles {
    static let defaultTerms = "전력전자 PWM 듀티 듀티비 캐리어 삼각파 스위칭 주파수 인덕터 리플 RL 부하 역기전력 전향 보상 PI 제어기 적분기 안티 와인드업 연속 제어 이산 제어 샘플링 피크 밸리 Simulink PLECS 서브시스템 트리거 레그 암 단락 데드타임"
        .split(separator: " ").map(String.init)

    /// 기본 프로필의 wiki_dir은 vault 기준 상대경로(semester/과목/transcript).
    static func wiki(_ course: String) -> [String: Any] {
        ["course": course, "wiki_dir": "\(VaultConfig.shared.semester)/\(course)/transcript"]
    }

    static func ensureDefaults() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: Paths.profilesFile.path) else { return }
        try? fm.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let obj: [String: Any] = [
            "전력전자": ["language": "Korean", "terms": defaultTerms].merging(wiki("전력전자")) { a, _ in a },
            "Power Electronics (EN)": ["language": "English",
                "terms": ["freewheeling diode", "rectifier", "Fourier series", "harmonics", "ripple"]]
                .merging(wiki("전력전자")) { a, _ in a },
            "물리전자": ["language": "Korean", "terms": [String]()].merging(wiki("물리전자")) { a, _ in a },
            "인턴십 PESL": ["language": "Korean", "terms": defaultTerms].merging(wiki("인턴십")) { a, _ in a },
        ]
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: Paths.profilesFile)
        }
    }

    private static func load() -> [String: Any] {
        guard let d = try? Data(contentsOf: Paths.profilesFile),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return obj
    }

    static func names() -> [String] { load().keys.sorted() }

    static func course(for name: String) -> String? {
        let key = name.precomposedStringWithCanonicalMapping
        for (k, v) in load() where k.precomposedStringWithCanonicalMapping == key {
            return (v as? [String: Any])?["course"] as? String
        }
        return nil
    }

    /// 프로필에 course와 wiki_dir이 둘 다 있으면 위키 대상으로 돌려준다(폴더 존재 여부는 호출 쪽에서 확인).
    static func wikiTarget(for name: String) -> WikiTarget? {
        let key = name.precomposedStringWithCanonicalMapping
        for (k, v) in load() where k.precomposedStringWithCanonicalMapping == key {
            guard let o = v as? [String: Any], let c = o["course"] as? String, let d = o["wiki_dir"] as? String,
                  !c.isEmpty, !d.isEmpty else { return nil }
            return WikiTarget(course: c, dir: VaultConfig.resolve(d, vault: VaultConfig.shared.vault))
        }
        return nil
    }
}
