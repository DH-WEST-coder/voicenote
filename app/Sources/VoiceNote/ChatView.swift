import AppKit
import SwiftUI

final class ChatUI: ObservableObject {
    @Published var input = ""
    @Published var prompts = ChatPrompts.load()
}

struct ChatView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var settings = ChatSettings.shared
    let note: Session
    @ObservedObject var session: ChatSession
    @StateObject private var ui = ChatUI()
    @ObservedObject private var catalog = ModelCatalog.shared

    private var engineTitle: String {
        switch settings.engine {
        case .agy:
            let m = settings.agyModel
            return "Gemini · " + (m.isEmpty ? "기본" : catalog.agy.first { $0.id == m }?.label ?? m)
        case .codex:
            let m = settings.codexModel
            return "GPT · " + (m.isEmpty ? "기본" : catalog.codex.first { $0.id == m }?.label ?? m)
        case .lmstudio: return settings.engine.label
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagesList
            VStack(spacing: 0) {
                materialsBar
                quickBar
                inputBar
            }
            .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("AI 채팅", systemImage: "sparkles").font(.headline)
            Spacer()
            Menu {
                Picker("엔진", selection: $settings.engine) {
                    ForEach(ChatEngine.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                if settings.engine == .agy {
                    Divider()
                    Picker("Gemini 모델", selection: $settings.agyModel) {
                        Text("기본값").tag("")
                        ForEach(catalog.agy, id: \.id) { Text($0.label).tag($0.id) }
                        if !settings.agyModel.isEmpty && !catalog.agy.contains(where: { $0.id == settings.agyModel }) {
                            Text(settings.agyModel).tag(settings.agyModel)
                        }
                    }
                    .pickerStyle(.inline)
                } else if settings.engine == .codex {
                    Divider()
                    Picker("GPT 모델", selection: $settings.codexModel) {
                        Text("기본값 (codex 설정)").tag("")
                        ForEach(catalog.codex, id: \.id) { Text($0.label).tag($0.id) }
                        if !settings.codexModel.isEmpty && !catalog.codex.contains(where: { $0.id == settings.codexModel }) {
                            Text(settings.codexModel).tag(settings.codexModel)
                        }
                    }
                    .pickerStyle(.inline)
                }
            } label: { Text(engineTitle).font(.caption) }
            .menuStyle(.borderlessButton).fixedSize()
            .onAppear { catalog.load() }
            Button { session.clear() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("이 노트의 채팅 기록 지우기").disabled(session.busy || session.messages.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if session.messages.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(.tertiary)
                            Text("수업에 대해 물어보세요").font(.headline)
                            Text("대본, 내 노트, 이 노트의 강의자료, 관련 위키 페이지가 함께 전달됩니다.\n아래 버튼으로 바로 정리할 수도 있어요.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    ForEach(session.messages) { m in
                        MessageBubble(message: m, streaming: session.busy && m.id == session.messages.last?.id,
                                      waiting: session.waitingFirstToken)
                            .id(m.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: session.messages.last?.text) { _, _ in
                if let id = session.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    /// 이 노트에 넣은 자료 칩(누르면 그 자료 탭으로)
    @ViewBuilder private var materialsBar: some View {
        if !note.attachments.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("이 노트의 자료 · 질문에 함께 전달", systemImage: "doc.richtext")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(note.attachments) { a in
                            Button { MaterialTabs.shared.show(session: note.id, attachment: a.id) } label: {
                                Text(a.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: 200)
                                    .font(.caption2).padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                            }
                            .buttonStyle(.plain).help(a.name)
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 10)
        }
    }

    private var quickBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button { session.ask(ui.prompts.organize, session: note, organize: true) } label: {
                    Label("수업 정리", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .help("대본 + 자료 + 위키 참고로 구조화된 노트 작성")
                Button { session.ask(NotePrompts.fill, session: note, display: "내 노트 기준으로 보충") } label: {
                    Label("노트 보충", systemImage: "note.text.badge.plus")
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                .help("내 노트를 기준으로 대본·자료에서 빠진 내용을 채움 (노트에서 글을 골라 우클릭해도 됩니다)")
                ForEach(ui.prompts.quick) { q in
                    Button(q.label) { session.ask(q.prompt, session: note) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .disabled(session.busy)
        .onAppear { ui.prompts = ChatPrompts.load() }
    }

    private var inputBar: some View {
        let empty = ui.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("질문 입력 (Enter로 보내기)", text: $ui.input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .onSubmit { send() }
                .padding(.vertical, 6)
            if session.busy {
                Button { session.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("중지")
            } else {
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                        .foregroundStyle(empty ? Color.secondary.opacity(0.5) : Color.accentColor)
                }
                .buttonStyle(.plain).disabled(empty)
            }
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 3)
        .background(Theme.paneBackground, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.12)))
        .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 2)
    }

    private func send() {
        let q = ui.input
        guard !session.busy, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ui.input = ""
        session.ask(q, session: note)
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
                    MarkdownText(text: message.text)
                }
            }
            .padding(.horizontal, isUser ? 12 : 14).padding(.vertical, isUser ? 8 : 12)
            .background(isUser ? Color.accentColor.opacity(0.16) : Theme.paneBackground,
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                if !isUser { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07)) }
            }
            .padding(.leading, isUser ? 40 : 0)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser && !streaming && !message.text.isEmpty && !message.isError {
                HStack(spacing: 10) {
                    Button { NoteController.shared.insertAtCursor(message.text) } label: {
                        Label("노트에 넣기", systemImage: "text.insert")
                    }
                    Button {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string)
                    } label: { Label("복사", systemImage: "doc.on.doc") }
                    if let t = message.total {
                        Text(String(format: "%@ · 첫 응답 %@ · 총 %.1fs", engineLabel,
                                    message.ttft.map { String(format: "%.1fs", $0) } ?? "-", t))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 4)
                if let refs = message.wikiRefs, !refs.isEmpty {
                    WikiRefChips(refs: refs).padding(.leading, 4)
                }
            }
        }
    }

    private var engineLabel: String { ChatEngine(rawValue: message.engine ?? "")?.label ?? "" }
}

/// 답변 아래 "참고한 위키: 이름, 이름" 칩. 누르면 Finder에서 보여 준다(읽기 전용, 열기만).
struct WikiRefChips: View {
    let refs: [String]
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "books.vertical").font(.caption2)
            Text("참고한 위키:").font(.caption2)
            ForEach(refs, id: \.self) { r in
                Button(((r as NSString).lastPathComponent as NSString).deletingPathExtension) { open(r) }
                    .buttonStyle(.plain)
                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.green.opacity(0.14), in: Capsule())
                    .help(r)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func open(_ rel: String) {
        let url = URL(fileURLWithPath: VaultConfig.shared.vault).appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // Obsidian이 있으면 거기서, 없으면 Finder에서 보여 준다.
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
