import AppKit
import SwiftUI

final class ChatUI: ObservableObject {
    @Published var input = ""
    @Published var prompts = ChatPrompts.load()
}

struct ChatView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var settings = ChatSettings.shared
    let job: Job
    @ObservedObject var session: ChatSession
    @StateObject private var ui = ChatUI()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagesList
            Divider()
            materialsBar
            quickBar
            inputBar
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .onAppear { session.refreshAutoMaterials(job: job) }
        .onChange(of: job.status) { _ in session.refreshAutoMaterials(job: job) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("AI 채팅", systemImage: "bubble.left.and.bubble.right").font(.subheadline.bold())
            Spacer()
            Picker("", selection: $settings.engine) {
                ForEach(ChatEngine.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden().frame(maxWidth: 190)
            Button { session.clear() } label: { Image(systemName: "trash") }
                .help("이 세션의 채팅 기록 지우기").disabled(session.busy || session.messages.isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if session.messages.isEmpty {
                        Text("수업에 대해 물어보세요. 대본, 내 노트, 관련 강의자료가 함께 전달됩니다.\n예: \"이 수업 관련 내용 가져와서 정리해\"")
                            .font(.callout).foregroundStyle(.secondary).padding(.top, 16)
                    }
                    ForEach(session.messages) { m in
                        MessageBubble(message: m, streaming: session.busy && m.id == session.messages.last?.id,
                                      waiting: session.waitingFirstToken)
                            .id(m.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: session.messages.last?.text) { _ in
                if let id = session.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var materialsBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(session.manualMaterials ? "자료(직접 고름)" : "자료(자동)").font(.caption2).foregroundStyle(.secondary)
                if session.materials.isEmpty { Text("없음").font(.caption2).foregroundStyle(.tertiary) }
                Spacer()
                if session.manualMaterials {
                    Button("자동으로 다시") { session.refreshAutoMaterials(job: job, force: true) }.controlSize(.mini)
                }
            }
            if !session.materials.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(session.materials, id: \.self) { n in
                            HStack(spacing: 3) {
                                Text(shortName(n)).lineLimit(1)
                                Button { session.removeMaterial(n) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain)
                            }
                            .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .help(n)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 6)
    }

    private func shortName(_ n: String) -> String {
        n.replacingOccurrences(of: ".processed.md", with: "")
    }

    private var quickBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button { session.ask(ui.prompts.organize, job: job, organize: true) } label: {
                    Label("수업 정리", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .help("대본 + 관련 자료로 구조화된 노트 작성")
                ForEach(ui.prompts.quick) { q in
                    Button(q.label) { session.ask(q.prompt, job: job) }.controlSize(.small)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .disabled(session.busy)
        .onAppear { ui.prompts = ChatPrompts.load() }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("질문 입력 (Enter로 보내기)", text: $ui.input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .onSubmit { send() }
            if session.busy {
                Button { session.stop() } label: { Image(systemName: "stop.circle.fill") }.help("중지")
            } else {
                Button { send() } label: { Image(systemName: "paperplane.fill") }
                    .disabled(ui.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
    }

    private func send() {
        let q = ui.input
        guard !session.busy, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ui.input = ""
        session.ask(q, job: job)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let streaming: Bool
    let waiting: Bool

    var body: some View {
        let isUser = message.role == "user"
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Group {
                if streaming && waiting && message.text.isEmpty {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("생각 중…").foregroundStyle(.secondary) }
                } else if message.isError {
                    Text(message.text).foregroundStyle(.red).textSelection(.enabled)
                } else if isUser {
                    Text(message.text).textSelection(.enabled)
                } else {
                    Text(rendered).textSelection(.enabled)
                }
            }
            .padding(10)
            .background(isUser ? Color.accentColor.opacity(0.18) : Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser && !streaming && !message.text.isEmpty && !message.isError {
                HStack(spacing: 10) {
                    Button("노트에 넣기") { NoteController.shared.insertAtCursor(message.text) }.controlSize(.small)
                    Button("복사") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string)
                    }.controlSize(.small)
                    if let t = message.total {
                        Text(String(format: "%@ · 첫 응답 %@ · 총 %.1fs", engineLabel,
                                    message.ttft.map { String(format: "%.1fs", $0) } ?? "-", t))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var engineLabel: String { ChatEngine(rawValue: message.engine ?? "")?.label ?? "" }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: message.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text)
    }
}

/// 강의자료 직접 고르기(자동 선택을 덮어쓴다)
final class MaterialsPickerState: ObservableObject {
    @Published var filter = ""
    @Published var files: [MaterialFile] = []
    @Published var ready = false
}

struct MaterialsPicker: View {
    let job: Job
    @ObservedObject var session: ChatSession
    @StateObject private var st = MaterialsPickerState()

    var body: some View {
        let course = Profiles.course(for: job.profile)
        let prefixes = Materials.prefixes(course: course, vault: ChatSettings.shared.vaultPath)
        let filtered = st.files.filter { st.filter.isEmpty || $0.name.localizedCaseInsensitiveContains(st.filter) }
        let mine = filtered.filter { f in prefixes.contains { f.name.hasPrefix($0 + "_") } }
        let others = filtered.filter { f in !mine.contains(f) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("강의자료").font(.headline)
                Spacer()
                Button("자동으로 다시 고르기") { session.refreshAutoMaterials(job: job, force: true) }
            }
            Text(session.manualMaterials ? "직접 고른 자료만 사용합니다." : "대본 키워드로 자동 선택됨. 바꾸면 직접 고른 목록이 됩니다.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("파일 이름 검색", text: $st.filter).textFieldStyle(.roundedBorder)
            if !st.ready { ProgressView("자료 색인 중…").controlSize(.small) }
            List {
                if !mine.isEmpty {
                    Section(course.map { "과목: \($0)" } ?? "이 과목") { ForEach(mine) { row($0) } }
                }
                Section(mine.isEmpty ? "전체" : "다른 자료") { ForEach(others) { row($0) } }
            }
            .frame(width: 440, height: 340)
        }
        .padding(12)
        .onAppear {
            MaterialIndex.shared.ensureBuilt(vault: ChatSettings.shared.vaultPath) {
                st.files = MaterialIndex.shared.allFiles(); st.ready = true
            }
        }
    }

    private func row(_ f: MaterialFile) -> some View {
        Toggle(isOn: Binding(get: { session.materials.contains(f.name) }, set: { _ in session.toggleMaterial(f.name) })) {
            HStack {
                Text(f.name.replacingOccurrences(of: ".processed.md", with: "")).lineLimit(1)
                Spacer()
                Text("\(f.size / 1024)KB").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
