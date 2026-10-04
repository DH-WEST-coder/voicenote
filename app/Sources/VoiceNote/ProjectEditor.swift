import AppKit
import SwiftUI

/// 프로젝트 설정 창의 상태: 프로젝트 = 과목 하나의 설정(이름, 위키 과목 폴더, 받아쓰기 언어, 고정 용어)
@MainActor
final class ProjectEditorState: ObservableObject {
    static let shared = ProjectEditorState()
    struct Editing: Identifiable { let id = UUID(); let projectID: UUID; let isNew: Bool }
    @Published var editing: Editing?
    @Published var name = ""
    @Published var course = ""
    @Published var language = ""
    @Published var terms = ""

    func new() {
        name = ""; course = ""; language = ""; terms = ""
        editing = Editing(projectID: UUID(), isNew: true)
    }

    func edit(_ id: UUID) {
        guard let p = Store.shared.project(id) else { return }
        name = p.name; course = p.course ?? ""; language = p.language; terms = p.terms.joined(separator: "\n")
        editing = Editing(projectID: id, isNew: false)
    }

    func save(_ e: Editing) {
        let store = Store.shared
        var p = store.project(e.projectID) ?? Project(name: "")
        p.id = e.projectID
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.course = course.isEmpty ? nil : course
        p.language = language
        p.terms = terms.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        store.saveProject(p)
        if e.isNew { store.lastProjectID = p.id }
        editing = nil
    }
}

/// 프로젝트 설정 시트(새로 만들기·고치기)
struct ProjectEditor: View {
    @EnvironmentObject var store: Store
    @ObservedObject var st = ProjectEditorState.shared
    let editing: ProjectEditorState.Editing

    var body: some View {
        let courses = Courses.list()
        VStack(alignment: .leading, spacing: 14) {
            Text(editing.isNew ? "새 프로젝트" : "프로젝트 설정").font(.title3.weight(.semibold))
            Text("이 프로젝트에서 만든 노트는 이 설정으로 받아쓰고 이 과목 위키로 보냅니다.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("이름", text: $st.name, prompt: Text("예: 전력전자, Power Electronics (EN), PESL 인턴십"))
                Picker("위키 과목 폴더", selection: $st.course) {
                    Text("없음 (위키로 보내지 않음)").tag("")
                    ForEach(courses, id: \.self) { Text($0).tag($0) }
                    if !st.course.isEmpty && !courses.contains(st.course) { Text(st.course).tag(st.course) }
                }
                Picker("언어", selection: $st.language) {
                    Text("자동(한·영)").tag("")
                    Text("한국어만").tag("Korean")
                    Text("영어만").tag("English")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("고정 용어 힌트")
                    TextEditor(text: $st.terms)
                        .font(.body).frame(height: 110)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                    Text("쉼표나 줄바꿈으로 구분. 교수님이 자주 쓰는 전공 용어·고유명사를 넣으면 받아쓰기가 정확해집니다(30~60개 권장). 강의자료에서 AI가 뽑은 용어는 노트마다 따로 더해집니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("취소") { st.editing = nil }.keyboardShortcut(.cancelAction)
                Button(editing.isNew ? "만들기" : "저장") { st.save(editing) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(st.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 520)
    }
}

/// 프로젝트 고르기 메뉴(도구막대·노트 머리 공용)
struct ProjectMenuItems: View {
    @EnvironmentObject var store: Store
    var current: UUID?
    var onPick: (UUID?) -> Void

    var body: some View {
        Button { onPick(nil) } label: { check("프로젝트 없음", current == nil) }
        Divider()
        ForEach(store.projects) { p in
            Button { onPick(p.id) } label: { check(p.name, current == p.id) }
        }
        Divider()
        Button("새 프로젝트…") { ProjectEditorState.shared.new() }
        if let c = current, let p = store.project(c) { Button("'\(p.name)' 설정…") { ProjectEditorState.shared.edit(c) } }
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
