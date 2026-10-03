import SwiftUI
import UniformTypeIdentifiers

// 이 SDK(CLT 전용)에는 SwiftUIMacros 플러그인이 없어 @State를 쓸 수 없다. @StateObject로 대체한다.

/// 이름 바꾸기·새로 만들기 창이 하는 일
enum RenameTask: Identifiable {
    case newProject, project(UUID), session(UUID)
    var id: String {
        switch self {
        case .newProject: return "new-project"
        case .project(let i): return "p-\(i)"
        case .session(let i): return "s-\(i)"
        }
    }
}

/// 확인 대화상자(삭제 등)
struct ConfirmTask: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let button: String
    let action: () -> Void
}

final class MainUI: ObservableObject {
    @Published var dropTargeted = false
    @Published var rename: RenameTask?
    @Published var renameText = ""
    @Published var confirm: ConfirmTask?
}

/// 오른쪽 채팅 접기 상태(기억)
final class LayoutState: ObservableObject {
    static let shared = LayoutState()
    @Published var showChat: Bool { didSet { UserDefaults.standard.set(showChat, forKey: "showChat") } }
    init() { showChat = UserDefaults.standard.object(forKey: "showChat") as? Bool ?? true }
}

/// 왼쪽 목록에서 접은 프로젝트(기억). 프로젝트 없음은 "none".
final class SidebarState: ObservableObject {
    static let shared = SidebarState()
    @Published var collapsed: Set<String> {
        didSet { UserDefaults.standard.set(Array(collapsed), forKey: "collapsedProjects") }
    }
    init() { collapsed = Set(UserDefaults.standard.stringArray(forKey: "collapsedProjects") ?? []) }
    func binding(_ key: String) -> Binding<Bool> {
        Binding(get: { !self.collapsed.contains(key) },
                set: { if $0 { self.collapsed.remove(key) } else { self.collapsed.insert(key) } })
    }
}

struct MainWindow: View {
    @EnvironmentObject var store: Store
    @StateObject private var ui = MainUI()
    @ObservedObject private var layout = LayoutState.shared
    @ObservedObject private var sidebar = SidebarState.shared
    @ObservedObject fileprivate var importer = MaterialImporter.shared
    @ObservedObject private var profileEditor = ProfileEditorState.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedSessionID) {
                ForEach(store.projects) { p in
                    projectSection(key: p.id.uuidString, project: p)
                }
                projectSection(key: "none", project: nil)
            }
            .listStyle(.sidebar)
            .overlay {
                if store.sessions.isEmpty {
                    Text("노트가 없습니다").foregroundStyle(.tertiary)
                }
            }
            .safeAreaInset(edge: .bottom) { sidebarFooter }
            .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 360)
        } detail: {
            if let s = store.selectedSession {
                NoteDetail(session: s, ui: ui).id(s.id)
            } else {
                EmptyDetail()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Menu {
                    ProfileMenuItems(current: store.selectedProfile) { store.selectedProfile = $0 }
                } label: {
                    Label(store.selectedProfile.isEmpty ? "프로필 없음" : store.selectedProfile, systemImage: "graduationcap")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(store.isRecording)
                .help("다음 새 노트에 쓸 과목 프로필(용어 힌트·위키 폴더)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                // 모드 선택(실시간/녹음 후 처리)은 2단계 실시간 받아쓰기와 함께 다시 넣는다.
                RecordButton()
                Button { layout.showChat.toggle() } label: {
                    Label("채팅", systemImage: layout.showChat ? "sidebar.trailing" : "bubble.left.and.bubble.right")
                }
                .help("AI 채팅 접기/펴기")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let ok = MaterialImporter.expand(urls).filter {
                let e = $0.pathExtension.lowercased(); return audioExtensions.contains(e) || docExtensions.contains(e)
            }
            importer.request(urls)
            return !ok.isEmpty
        } isTargeted: { ui.dropTargeted = $0 }
        .sheet(isPresented: $importer.showPicker) { DownloadsPicker() }
        .sheet(item: $profileEditor.editing) { e in ProfileEditor(editing: e).environmentObject(store) }
        .sheet(item: $importer.pending) { p in MaterialImportSheet(pending: p).environmentObject(store) }
        .sheet(item: $ui.rename) { t in RenameSheet(task: t, ui: ui).environmentObject(store) }
        .overlay {
            if ui.dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.08)).padding(6).allowsHitTesting(false)
            }
        }
        .alert("알림", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("확인") { store.message = nil }
        } message: { Text(store.message ?? "") }
        .alert(ui.confirm?.title ?? "", isPresented: Binding(get: { ui.confirm != nil }, set: { if !$0 { ui.confirm = nil } }),
               presenting: ui.confirm) { c in
            Button(c.button, role: .destructive) { c.action() }
            Button("취소", role: .cancel) {}
        } message: { c in Text(c.message) }
        .frame(minWidth: 900, minHeight: 520)
    }
}

// MARK: - 왼쪽 목록

extension MainWindow {
    /// 프로젝트 하나의 섹션(접기 가능). project가 nil이면 "프로젝트 없음".
    @ViewBuilder fileprivate func projectSection(key: String, project: Project?) -> some View {
        let notes = store.sessions.filter { $0.projectID == project?.id }.sorted { $0.createdAt > $1.createdAt }
        Section(isExpanded: sidebar.binding(key)) {
            ForEach(notes) { s in
                NoteRow(session: s)
                    .tag(s.id)
                    .draggable(s.id.uuidString)
                    .contextMenu { noteMenu(s) }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: project == nil ? "tray" : "folder")
                Text(project?.name ?? "프로젝트 없음")
                Text("\(notes.count)").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                var moved = false
                for i in items { if let id = UUID(uuidString: i), store.session(id) != nil { store.move(session: id, to: project?.id); moved = true } }
                return moved
            }
            .contextMenu {
                if let p = project {
                    Button("이름 바꾸기…") { ui.renameText = p.name; ui.rename = .project(p.id) }
                    Button("프로젝트 삭제…", role: .destructive) {
                        ui.confirm = ConfirmTask(title: "'\(p.name)' 프로젝트를 지울까요?",
                                                 message: "안의 노트는 지워지지 않고 '프로젝트 없음'으로 옮겨집니다.", button: "삭제") {
                            store.removeProject(p.id)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder fileprivate func noteMenu(_ s: Session) -> some View {
        Button("이름 바꾸기…") { ui.renameText = s.title; ui.rename = .session(s.id) }
        Menu("프로젝트로 이동") {
            Button("프로젝트 없음") { store.move(session: s.id, to: nil) }
            Divider()
            ForEach(store.projects) { p in Button(p.name) { store.move(session: s.id, to: p.id) } }
        }
        Button("위키로 보내기") { WikiSender.send(s.id) }
        let files = store.recordings(of: s).map { URL(fileURLWithPath: $0.audioPath) }
        if !files.isEmpty {
            Button("녹음 파일을 Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting(files) }
        }
        Divider()
        Button("노트 삭제…", role: .destructive) {
            ui.confirm = ConfirmTask(title: "'\(s.title)' 노트를 지울까요?",
                                     message: "녹음 파일은 지우지 않고 목록에서만 뺍니다.", button: "삭제") {
                for a in s.attachments { HoldList.remove(a) }
                store.removeSession(s.id)
            }
        }
    }

    fileprivate var sidebarFooter: some View {
        let processing = store.jobs.first { $0.status == .processing }
        let queued = store.jobs.filter { $0.status == .queued }.count
        return VStack(alignment: .leading, spacing: 6) {
            if let s = importer.status {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(s).lineLimit(1) }.font(.caption)
            }
            if let p = processing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("\(p.stage ?? "처리 중")").lineLimit(1)
                    if queued > 0 { Text("· 대기 \(queued)").foregroundStyle(.secondary) }
                }
                .font(.caption)
            }
            HStack {
                Button { store.newSession() } label: { Label("새 노트", systemImage: "square.and.pencil") }
                    .buttonStyle(.borderless)
                Button { ui.renameText = ""; ui.rename = .newProject } label: { Label("새 프로젝트", systemImage: "folder.badge.plus") }
                    .buttonStyle(.borderless)
                Spacer()
            }
            HStack {
                Button { importer.showPicker = true } label: { Label("파일 가져오기", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderless)
                Spacer()
                BatteryBadge()
            }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.bar)
    }
}

/// 이름 바꾸기·새 프로젝트 창
struct RenameSheet: View {
    @EnvironmentObject var store: Store
    let task: RenameTask
    @ObservedObject var ui: MainUI

    private var heading: String {
        switch task {
        case .newProject: return "새 프로젝트"
        case .project: return "프로젝트 이름 바꾸기"
        case .session: return "노트 이름 바꾸기"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(.headline)
            TextField(task.id == "new-project" ? "프로젝트 이름 (예: 전력전자)" : "이름", text: $ui.renameText).onSubmit { apply() }
            HStack {
                Spacer()
                Button("취소") { ui.rename = nil }.keyboardShortcut(.cancelAction)
                Button(task.id == "new-project" ? "만들기" : "변경") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(ui.renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20).frame(width: 380)
    }

    private func apply() {
        let t = ui.renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        switch task {
        case .newProject:
            let p = store.newProject(t)
            // 선택한 노트가 프로젝트 없음이면 새 프로젝트로 옮기지는 않는다(끌어다 놓거나 우클릭으로 이동).
            _ = p
        case .project(let id): store.renameProject(id, t)
        case .session(let id): store.renameSession(id, t)
        }
        ui.rename = nil
    }
}

/// 아무것도 고르지 않았을 때: 새 노트·녹음 시작 안내
struct EmptyDetail: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(LinearGradient(colors: [Theme.record, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 6) {
                Text("수업 노트를 시작해 보세요").font(.title2.weight(.semibold))
                Text("노트 하나에 녹음 여러 개, 내 노트, 강의자료, AI 채팅이 모입니다.\n오디오나 강의자료(PDF·PPT, 폴더도 가능)를 이 창에 끌어다 놓아도 됩니다.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                Button { store.newSession() } label: {
                    Label("새 노트 만들기", systemImage: "square.and.pencil").font(.title3.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button { store.startRecording(forceNew: true) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill").font(.system(size: 13, weight: .bold))
                        Text("바로 녹음")
                    }
                    .font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(Theme.record, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 14) {
                Label(store.selectedProfile.isEmpty ? "프로필 없음" : store.selectedProfile, systemImage: "graduationcap")
                Label("⌥⌘R", systemImage: "keyboard")
            }
            .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paneBackground)
    }
}

/// 왼쪽 목록의 노트 한 줄
struct NoteRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject var power = PowerMonitor.shared
    @ObservedObject var tasks = AITasks.shared
    let session: Session

    var body: some View {
        let st = store.status(of: session)
        HStack(spacing: 10) {
            if let st { StatusIcon(status: st) }
            else {
                Image(systemName: "note.text").font(.title2).foregroundStyle(.secondary).frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).lineLimit(1).font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(session.createdAt.formatted(.dateTime.month().day()))
                    let total = store.totalDuration(of: session)
                    if total > 0 { Text("· " + formatTime(total)) }
                    let n = session.recordingIDs.count
                    if n > 0 { Text("· 녹음 \(n)개") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let note = statusNote(st) {
                    Text(note).font(.caption2).foregroundStyle(st == .failed ? .orange : .secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func statusNote(_ st: JobStatus?) -> String? {
        switch st {
        case .processing: return store.recordings(of: session).first { $0.status == .processing }?.stage ?? "처리 중"
        case .failed: return "처리 실패 · 노트에서 다시 처리"
        case .recording: return "녹음 중"
        case .queued: return store.chargingOnly && !power.onAC ? "충전 연결 대기" : "대기 중"
        default: return nil
        }
    }
}

// MARK: - 노트 화면

final class NoteDetailUI: ObservableObject {
    @Published var title = ""
    @Published var showTerms = false
}

/// 가운데(머리 + 대본/자료 위 / 노트 아래) + 오른쪽(채팅)
struct NoteDetail: View {
    let session: Session
    @ObservedObject var ui: MainUI
    @ObservedObject private var layout = LayoutState.shared

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                NoteHeader(session: session, mainUI: ui)
                Divider()
                VSplitView {
                    TopPane(session: session).frame(minHeight: 200)
                        .background(Theme.paneBackground)
                    NoteView(session: session).frame(minHeight: 140)
                }
            }
            .frame(minWidth: 440)
            if layout.showChat {
                ChatView(note: session, session: ChatHub.shared.session(for: session.id))
                    .frame(minWidth: 290, idealWidth: 360, maxWidth: 560)
            }
        }
    }
}

struct NoteHeader: View {
    @EnvironmentObject var store: Store
    @ObservedObject var tasks = AITasks.shared
    @StateObject private var hs = NoteDetailUI()
    @FocusState private var titleFocused: Bool
    let session: Session
    @ObservedObject var mainUI: MainUI

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("제목", text: $hs.title)
                    .textFieldStyle(.plain).font(.title2.weight(.semibold))
                    .focused($titleFocused)
                    .onSubmit { commitTitle() }
                    .onChange(of: titleFocused) { _, f in if !f { commitTitle() } }
                if tasks.running.contains("title-\(session.id.uuidString)") {
                    ProgressView().controlSize(.small).help("AI가 제목을 짓는 중")
                }
                Spacer()
                HStack(spacing: 8) { actions }.fixedSize()
            }
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Menu {
                    ProfileMenuItems(current: session.profile) { p in store.updateSession(session.id) { $0.profile = p } }
                } label: {
                    Chip(text: session.profile.isEmpty ? "프로필 없음" : session.profile, systemImage: "graduationcap",
                         tint: session.profile.isEmpty ? .orange : .secondary)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("이 노트의 과목 프로필 (받아쓰기 용어·위키로 보낼 과목)")
                Menu {
                    Button("프로젝트 없음") { store.move(session: session.id, to: nil) }
                    Divider()
                    ForEach(store.projects) { p in Button(p.name) { store.move(session: session.id, to: p.id) } }
                } label: {
                    Chip(text: store.projects.first { $0.id == session.projectID }?.name ?? "프로젝트 없음", systemImage: "folder")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                Button { hs.showTerms = true } label: {
                    Chip(text: "용어 힌트 \(session.terms.count)개", systemImage: "text.book.closed",
                         tint: AITasks.shared.running.contains("terms-\(session.id.uuidString)") ? .accentColor : .secondary)
                }
                .buttonStyle(.plain).help("다음 녹음 처리부터 쓰는 용어 목록 보기·고치기")
                let total = store.totalDuration(of: session)
                if total > 0 { Chip(text: formatTime(total), systemImage: "clock") }
                if !session.recordingIDs.isEmpty { Chip(text: "녹음 \(session.recordingIDs.count)개", systemImage: "waveform") }
                if session.wikiPath != nil { Chip(text: "위키에 있음", systemImage: "checkmark", tint: .green) }
            }
            .fixedSize()
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .onAppear { hs.title = session.title }
        .onChange(of: session.title) { _, t in if !titleFocused { hs.title = t } }
        .onDisappear { commitTitle() }
        .sheet(isPresented: $hs.showTerms) { TermsSheet(sessionID: session.id, show: $hs.showTerms).environmentObject(store) }
    }

    private func commitTitle() {
        let t = hs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { hs.title = session.title; return }
        if t != session.title { store.renameSession(session.id, t) }
    }

    @ViewBuilder private var actions: some View {
        let mine = store.recordingJobID.flatMap { store.session(ofJob: $0)?.id } == session.id
        if store.isRecording && mine {
            Button { store.stopRecording() } label: { Label("녹음 정지", systemImage: "stop.fill") }
                .controlSize(.small).tint(Theme.record)
        } else {
            Button { store.startRecording(into: session.id) } label: {
                Label(session.recordingIDs.isEmpty ? "녹음" : "이어서 녹음", systemImage: "circle.fill")
            }
            .controlSize(.small).disabled(store.isRecording)
        }
        Button { WikiSender.send(session.id) } label: { Label("위키로 보내기", systemImage: "books.vertical") }
            .controlSize(.small)
        Menu {
            Button("대본 복사") {
                let text = store.combinedTranscript(of: session).lines.map { "[\(formatTime($0.time))] \($0.speaker): \($0.text)" }.joined(separator: "\n")
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            }
            let ts = store.recordings(of: session).compactMap(\.transcriptPath)
            if !ts.isEmpty {
                Button("대본 파일을 Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting(ts.map { URL(fileURLWithPath: $0) }) }
            }
            if store.exportEnabled && !store.exportFolder.isEmpty && !ts.isEmpty {
                Button("내보내기 폴더로 복사") { ts.forEach { store.export(path: $0) } }
            }
            if let w = session.wikiPath, FileManager.default.fileExists(atPath: w) {
                Button("위키 묶음 파일을 Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: w)]) }
            }
        } label: { Image(systemName: "ellipsis.circle") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

/// 용어 힌트 편집 창
final class TermsSheetState: ObservableObject {
    @Published var text = ""
    @Published var loaded = false
}

struct TermsSheet: View {
    @EnvironmentObject var store: Store
    @ObservedObject var tasks = AITasks.shared
    @StateObject private var st = TermsSheetState()
    let sessionID: UUID
    @Binding var show: Bool

    var body: some View {
        let s = store.session(sessionID)
        let extracting = tasks.running.contains("terms-\(sessionID.uuidString)")
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("용어 힌트").font(.headline)
                Spacer()
                Text("\(lines.count)개").font(.caption).foregroundStyle(.secondary)
            }
            Text("한 줄에 하나씩. 받아쓰기(ASR)가 전공 용어·고유명사를 잘 알아듣도록 프로필 용어와 함께 씁니다.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $st.text)
                .font(.body)
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            HStack(spacing: 8) {
                Button { save(); AITasks.shared.extractTerms(session: sessionID) } label: {
                    Label("강의자료에서 다시 뽑기", systemImage: "sparkles")
                }
                .disabled(extracting || (s?.attachments.isEmpty ?? true))
                if extracting { ProgressView().controlSize(.small) }
                if let n = s?.termsNote { Text(n).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                Spacer()
            }
            Text("다음 녹음 처리부터 쓰입니다. 이미 처리된 녹음에 반영하려면 녹음 우클릭 → 다시 처리")
                .font(.caption2).foregroundStyle(.tertiary)
            HStack {
                Spacer()
                Button("완료") { save(); show = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 460)
        .onAppear { st.text = (s?.terms ?? []).joined(separator: "\n"); st.loaded = true }
        .onChange(of: s?.terms ?? []) { _, t in st.text = t.joined(separator: "\n") }
    }

    private var lines: [String] {
        st.text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func save() {
        guard st.loaded else { return }
        let l = lines
        if l != (store.session(sessionID)?.terms ?? []) { store.updateSession(sessionID) { $0.terms = l } }
    }
}

// MARK: - 대본(이어 붙인 것)

struct RenameTarget: Identifiable { let id = UUID(); let name: String }

final class TranscriptState: ObservableObject {
    enum Row: Identifiable {
        case header(part: Int, entry: TimelineEntry)
        case status(part: Int, entry: TimelineEntry)
        case line(CombinedTranscript.Line, showSpeaker: Bool, first: Bool)
        var id: String {
            switch self {
            case .header(let p, _): return "h-\(p)"
            case .status(let p, _): return "s-\(p)"
            case .line(let l, _, _): return l.id
            }
        }
    }
    @Published var rows: [Row] = []
    @Published var lines: [CombinedTranscript.Line] = []
    @Published var speakers: [String] = []
    @Published var rename: RenameTarget?
    @Published var newName = ""
    @Published var scrollTarget: String?
    /// 2단계(실시간): true면 대본이 계속 늘어나며 맨 아래로 자동 스크롤한다.
    @Published var live = false
}

struct TranscriptView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var power = PowerMonitor.shared
    let session: Session
    @StateObject private var st = TranscriptState()

    /// 대본이 바뀔 때만 다시 읽도록 하는 표식
    private var signature: String {
        store.recordings(of: session).map { "\($0.id)\($0.status.rawValue)\($0.transcriptPath ?? "")\($0.duration ?? 0)" }.joined(separator: ",")
            + "-\(store.transcriptRevision)"
    }

    var body: some View {
        VStack(spacing: 0) {
            playerBar
            Divider()
            content
        }
        .task(id: "\(session.id)-\(signature)") { load() }
        .sheet(item: $st.rename) { t in
            VStack(alignment: .leading, spacing: 12) {
                Text("화자 이름 바꾸기").font(.headline)
                Text("\"\(t.name)\"의 모든 발언을 새 이름으로 바꾸고 이 노트의 모든 녹음 대본(.md)에 반영합니다.").font(.callout).foregroundStyle(.secondary)
                TextField("새 이름 (예: 교수님)", text: $st.newName).onSubmit { applyRename(t) }
                HStack {
                    Spacer()
                    Button("취소") { st.rename = nil }.keyboardShortcut(.cancelAction)
                    Button("변경") { applyRename(t) }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20).frame(width: 380)
        }
    }

    private func openRename(_ name: String) {
        st.newName = name
        st.rename = RenameTarget(name: name)
    }

    private func applyRename(_ t: RenameTarget) {
        store.renameSpeaker(session: session, from: t.name, to: st.newName)
        st.rename = nil
    }

    private func load() {
        let c = store.combinedTranscript(of: session)
        var rows: [TranscriptState.Row] = []
        let all = c.lines
        for (pi, p) in c.parts.enumerated() {
            rows.append(.header(part: pi, entry: p.entry))
            if p.transcript != nil {
                let mine = all.filter { $0.part == pi }
                for (i, l) in mine.enumerated() {
                    rows.append(.line(l, showSpeaker: i == 0 || mine[i - 1].speaker != l.speaker, first: i == 0))
                }
            } else {
                rows.append(.status(part: pi, entry: p.entry))
            }
        }
        st.rows = rows; st.lines = all; st.speakers = c.speakers
    }

    // MARK: 재생 막대·화자 칩

    private var recordingPaths: Set<String> { Set(store.recordings(of: session).map(\.audioPath)) }
    private var isLoadedHere: Bool { player.loadedPath.map { recordingPaths.contains($0) } ?? false }
    private var total: Double { store.totalDuration(of: session) }

    private var playerBar: some View {
        let pos = store.playPosition(in: session) ?? 0
        let canPlay = store.timeline(of: session).contains { $0.job.status != .recording }
        return HStack(spacing: 10) {
            Button {
                if isLoadedHere && player.isPlaying { player.pause() }
                else if isLoadedHere, let p = player.loadedPath { player.play(path: p) }
                else { store.seek(session: session, to: 0) }
            } label: {
                Image(systemName: isLoadedHere && player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Color.accentColor.opacity(canPlay ? 1 : 0.35), in: Circle())
            }
            .buttonStyle(.plain).disabled(!canPlay)
            if isLoadedHere {
                ProgressView(value: min(pos, max(total, 0.01)), total: max(total, 0.01)).frame(maxWidth: 220)
                Text("\(formatTime(pos)) / \(formatTime(total))").monospacedDigit().font(.caption).foregroundStyle(.secondary)
            } else {
                Text(canPlay ? "재생" : "재생할 녹음이 없습니다").font(.caption).foregroundStyle(.secondary)
            }
            if let e = player.error { Text(e).foregroundStyle(.red).font(.caption) }
            Spacer()
            ForEach(Array(st.speakers.enumerated()), id: \.element) { i, s in
                Button { jump(to: s) } label: {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.speakerColor(i)).frame(width: 7, height: 7)
                        Text(s)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.speakerColor(i).opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("누르면 지금 위치 다음의 이 화자 발언으로 이동 (우클릭: 이름 바꾸기)")
                .contextMenu { Button("이름 바꾸기…") { openRename(s) } }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    /// 현재 재생 위치(없으면 0) 이후 그 화자의 다음 줄로 이동(끝이면 처음 줄)
    private func jump(to speaker: String) {
        let pos = store.playPosition(in: session) ?? 0
        guard let l = store.nextLine(of: speaker, after: pos, in: st.lines) else { return }
        store.seek(session: session, to: l.time)
        st.scrollTarget = l.id
    }

    // MARK: 본문

    @ViewBuilder private var content: some View {
        if st.rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 30)).foregroundStyle(.tertiary)
                Text("아직 녹음이 없습니다").foregroundStyle(.secondary)
                Text("위의 '녹음' 버튼이나 ⌥⌘R로 녹음하거나, 오디오 파일을 끌어다 놓으세요.").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let active = activeLineID
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(st.rows) { r in row(r, active: active).id(r.id) }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                }
                .onChange(of: st.scrollTarget) { _, t in
                    if let t { withAnimation { proxy.scrollTo(t, anchor: .center) }; st.scrollTarget = nil }
                }
                .onChange(of: st.rows.count) { _, _ in
                    if st.live, let last = st.rows.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var activeLineID: String? {
        guard isLoadedHere, player.isPlaying, let pos = store.playPosition(in: session) else { return nil }
        return st.lines.last(where: { $0.time <= pos + 0.01 })?.id
    }

    @ViewBuilder private func row(_ r: TranscriptState.Row, active: String?) -> some View {
        switch r {
        case .header(_, let e): header(e)
        case .status(_, let e): statusRow(e)
        case .line(let l, let showSpeaker, let first):
            let idx = st.speakers.firstIndex(of: l.speaker) ?? 0
            VStack(alignment: .leading, spacing: 3) {
                if showSpeaker {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.speakerColor(idx)).frame(width: 8, height: 8)
                        Text(l.speaker).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.speakerColor(idx))
                            .onTapGesture { openRename(l.speaker) }
                    }
                    .padding(.top, first ? 2 : 12)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Button(formatTime(l.time)) { store.seek(session: session, to: l.time) }
                        .buttonStyle(.plain).font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                        .help("여기부터 재생")
                    Text(l.text).font(.body).lineSpacing(4).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 5).padding(.horizontal, 6)
                .background(active == l.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    /// 녹음 구분 줄: `녹음 N · HH:mm · 길이`
    private func header(_ e: TimelineEntry) -> some View {
        let live = store.jobs.first { $0.id == e.job.id } ?? e.job
        let dur = (live.status == .recording && store.recordingJobID == live.id) ? store.elapsed : (live.duration ?? 0)
        return HStack(spacing: 8) {
            VStack { Divider() }
            Text("녹음 \(e.index) · \(live.createdAt.formatted(date: .omitted, time: .shortened)) · \(formatTime(dur))")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary).fixedSize()
            VStack { Divider() }
        }
        .padding(.top, e.index == 1 ? 0 : 16).padding(.bottom, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if live.status == .done || live.status == .failed { Button("다시 처리") { store.retry(live.id) } }
            Button("원본 오디오를 Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: live.audioPath)]) }
            if let t = live.transcriptPath {
                Button("대본 파일을 Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: t)]) }
            }
            Divider()
            Button("이 녹음을 노트에서 빼기", role: .destructive) { store.remove(live.id) }
        }
    }

    /// 처리 안 된 녹음의 상태 줄
    private func statusRow(_ e: TimelineEntry) -> some View {
        let job = store.jobs.first { $0.id == e.job.id } ?? e.job
        return HStack(spacing: 8) {
            switch job.status {
            case .recording:
                Label("녹음 중 \(formatTime(store.elapsed))", systemImage: "record.circle.fill").foregroundStyle(.red)
                Text("대본은 녹음이 끝난 뒤 처리됩니다. 아래 노트에는 누적 시각이 붙습니다.").font(.caption).foregroundStyle(.secondary)
            case .queued:
                Label(store.chargingOnly && !power.onAC ? "충전 연결 대기 중 (설정: 충전 중일 때만 처리)" : "대기 중",
                      systemImage: store.chargingOnly && !power.onAC ? "bolt.slash" : "clock")
            case .processing:
                ProgressView().controlSize(.small); Text(job.stage ?? "처리 중")
            case .failed:
                Label("처리 실패", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(job.error ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                Button("다시 처리") { store.retry(job.id) }.controlSize(.small)
            case .done:
                Label("대본 파일을 읽을 수 없습니다", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                Button("다시 처리") { store.retry(job.id) }.controlSize(.small)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.vertical, 8).padding(.horizontal, 6)
    }
}

struct BatteryBadge: View {
    @ObservedObject var power = PowerMonitor.shared
    var body: some View {
        let pct = power.percent.map { "\($0)%" } ?? ""
        Label(power.onAC ? "충전 중 \(pct)" : "배터리 \(pct)" + (power.lastWatts.map { String(format: " · %.1fW", $0) } ?? ""),
              systemImage: power.onAC ? "bolt.fill" : "battery.50")
            .font(.caption)
            .foregroundStyle(power.onAC ? Color.green : Color.orange)
            .help(power.onAC ? "전원 연결됨" : "배터리 사용 중 (녹음/처리 중 30초마다 소비 전력을 기록)")
    }
}
