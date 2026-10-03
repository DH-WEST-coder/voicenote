import Foundation

/// 위키 vault 위치의 단일 설정. 엔진(voicenote.py)과 같은 파일을 읽는다:
/// ~/Library/Application Support/VoiceNote/config.json  {"vault": "<절대경로>", "semester": "<vault 기준 상대경로>"}
final class VaultConfig: ObservableObject, @unchecked Sendable {
    static let shared = VaultConfig()
    /// config.json이 없을 때 처음 한 번 쓰는 기본값(코드 안의 유일한 vault 경로).
    static let defaultVault = "/Users/DH_WEST/Library/CloudStorage/GoogleDrive-hello430234@gmail.com/내 드라이브/04_LLMwiki/LLM WIKI for study"
    static let defaultSemester = "raw/05_UNIST/07_3학년 가을학기"

    static var file: URL { Paths.support.appendingPathComponent("config.json") }

    @Published var vault: String { didSet { if vault != oldValue { save() } } }
    @Published var semester: String { didSet { if semester != oldValue { save() } } }

    private init() {
        var v = Self.defaultVault, s = Self.defaultSemester
        var exists = false
        if let d = try? Data(contentsOf: Self.file),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            exists = true
            if let x = o["vault"] as? String, !x.isEmpty { v = x }
            if let x = o["semester"] as? String { s = x }
        }
        vault = v; semester = s
        if !exists { save() }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let obj: [String: Any] = ["vault": vault, "semester": semester]
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: Self.file)
        }
    }

    /// 경고 문구(없으면 nil).
    var warning: String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: vault, isDirectory: &isDir), isDir.boolValue else {
            return "vault 폴더가 없습니다: \(vault)"
        }
        if !FileManager.default.fileExists(atPath: vault + "/.agents") { return "vault에 .agents/ 폴더가 없습니다(위키 vault가 맞는지 확인)." }
        return nil
    }

    /// 프로필 wiki_dir 해석: 상대경로는 vault 기준, 절대경로는 그대로.
    nonisolated static func resolve(_ dir: String, vault: String) -> String {
        dir.hasPrefix("/") ? dir : (vault as NSString).appendingPathComponent(dir)
    }
}
