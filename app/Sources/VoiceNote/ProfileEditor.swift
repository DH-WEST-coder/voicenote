import AppKit
import SwiftUI

/// 프로필 = 과목 하나의 받아쓰기 설정: 언어, 용어 힌트, 위키 과목 폴더.
extension Profiles {
    struct Entry {
        var name = ""
        var language = ""      // "", "Korean", "English"
        var terms = ""         // 줄바꿈·쉼표로 구분
        var course = ""
    }

    static func entry(_ name: String) -> Entry {
        let key = name.precomposedStringWithCanonicalMapping
        guard let d = try? Data(contentsOf: Paths.profilesFile),
              let all = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return Entry(name: name) }
        for (k, v) in all where k.precomposedStringWithCanonicalMapping == key {
            let o = v as? [String: Any] ?? [:]
            return Entry(name: k, language: o["language"] as? String ?? "",
                         terms: (o["terms"] as? [String] ?? []).joined(separator: ", "),
                         course: o["course"] as? String ?? "")
        }
        return Entry(name: name)
    }

    /// profiles.json에 저장(같은 이름이면 덮어쓰기, oldName이 다르면 이름 바꾸기). 엔진도 같은 파일을 읽는다.
    static func save(_ e: Entry, oldName: String?) {
        var all: [String: Any] = [:]
        if let d = try? Data(contentsOf: Paths.profilesFile),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { all = o }
        if let old = oldName, old != e.name { all.removeValue(forKey: old) }
        var o = all[e.name] as? [String: Any] ?? [:]
        if e.language.isEmpty { o.removeValue(forKey: "language") } else { o["language"] = e.language }
        o["terms"] = e.terms.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if e.course.isEmpty {
            o.removeValue(forKey: "course"); o.removeValue(forKey: "wiki_dir")
        } else {
            o["course"] = e.course
            o["wiki_dir"] = "\(VaultConfig.shared.semester)/\(e.course)/transcript"
        }
        all[e.name] = o
        if let d = try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: Paths.profilesFile)
        }
    }

    static func delete(_ name: String) {
        guard let d = try? Data(contentsOf: Paths.profilesFile),
              var all = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        all.removeValue(forKey: name)
        if let d = try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: Paths.profilesFile)
        }
    }
}

/// 프로필 만들기·고치기 창의 상태
@MainActor
final class ProfileEditorState: ObservableObject {
    static let shared = ProfileEditorState()
    struct Editing: Identifiable { let id = UUID(); let oldName: String? }
    @Published var editing: Editing?
    @Published var entry = Profiles.Entry()

    func new() {
        let c = Courses.course(forProfile: Store.shared.selectedProfile) ?? ""
        entry = Profiles.Entry(name: "", language: "", terms: "", course: c)
        editing = Editing(oldName: nil)
    }
    func edit(_ name: String) { entry = Profiles.entry(name); editing = Editing(oldName: name) }
}

struct ProfileEditor: View {
    @EnvironmentObject var store: Store
    @ObservedObject var st = ProfileEditorState.shared
    let editing: ProfileEditorState.Editing

    var body: some View {
        let courses = Courses.list()
        VStack(alignment: .leading, spacing: 14) {
            Text(editing.oldName == nil ? "새 프로필" : "프로필 고치기").font(.title3.weight(.semibold))
            Text("과목 하나의 받아쓰기 설정입니다. 녹음 전에 고르면 용어 힌트로 전공 용어 인식이 좋아지고, 대본과 자료가 이 과목 위키 폴더로 갑니다.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("이름", text: $st.entry.name, prompt: Text("예: 물리전자, Power Electronics (EN)"))
                Picker("위키 과목 폴더", selection: $st.entry.course) {
                    Text("없음 (위키로 보내지 않음)").tag("")
                    ForEach(courses, id: \.self) { Text($0).tag($0) }
                    if !st.entry.course.isEmpty && !courses.contains(st.entry.course) { Text(st.entry.course).tag(st.entry.course) }
                }
                Picker("언어", selection: $st.entry.language) {
                    Text("자동 감지 (한·영 섞인 수업)").tag("")
                    Text("한국어만").tag("Korean")
                    Text("영어만").tag("English")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("용어 힌트")
                    TextEditor(text: $st.entry.terms)
                        .font(.body).frame(height: 110)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                    Text("쉼표나 줄바꿈으로 구분. 교수님이 자주 쓰는 전공 용어·고유명사를 넣으면 받아쓰기가 정확해집니다(30~60개 권장).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                if let old = editing.oldName {
                    Button("삭제", role: .destructive) {
                        Profiles.delete(old); store.reloadProfiles(); st.editing = nil
                    }
                }
                Spacer()
                Button("취소") { st.editing = nil }.keyboardShortcut(.cancelAction)
                Button("저장") {
                    let e = st.entry
                    Profiles.save(e, oldName: editing.oldName)
                    store.reloadProfiles()
                    if editing.oldName == nil || store.selectedProfile == editing.oldName { store.selectedProfile = e.name }
                    st.editing = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(st.entry.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 520)
    }
}

/// 프로필 고르기 메뉴(도구막대·녹음 머리 공용). onPick이 nil이면 다음 녹음 프로필을 바꾼다.
struct ProfileMenuItems: View {
    @EnvironmentObject var store: Store
    var current: String
    var onPick: (String) -> Void

    var body: some View {
        Button { onPick("") } label: { check("프로필 없음", current.isEmpty) }
        Divider()
        ForEach(store.profiles, id: \.self) { p in
            Button { onPick(p) } label: { check(p, current == p) }
        }
        Divider()
        Button("새 프로필 만들기…") { ProfileEditorState.shared.new() }
        if !current.isEmpty { Button("'\(current)' 고치기…") { ProfileEditorState.shared.edit(current) } }
    }

    private func check(_ t: String, _ on: Bool) -> some View {
        on ? AnyView(Label(t, systemImage: "checkmark")) : AnyView(Text(t))
    }
}

// MARK: - 채팅 모델 목록

@MainActor
final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()
    struct Model: Hashable { let id: String; let label: String }
    @Published var agy: [Model] = []
    @Published var codex: [Model] = []
    private var loaded = false

    func load() {
        guard !loaded else { return }
        loaded = true
        // codex: ~/.codex/models_cache.json
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
        if let d = try? Data(contentsOf: cache), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let ms = o["models"] as? [[String: Any]] {
            codex = ms.compactMap { m in
                guard let s = m["slug"] as? String, !s.contains("review") else { return nil }
                return Model(id: s, label: (m["display_name"] as? String) ?? s)
            }
        }
        // agy: `agy models` (탭 구분: id \t 이름)
        let path = ChatSettings.shared.agyPath
        Task.detached {
            let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = ["models"]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            guard (try? p.run()) != nil else { return }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let list = (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").compactMap { l -> Model? in
                let parts = l.split(separator: "\t", maxSplits: 1).map(String.init)
                return parts.count == 2 ? Model(id: parts[0], label: parts[1]) : nil
            }
            await MainActor.run { ModelCatalog.shared.agy = list }
        }
    }
}
