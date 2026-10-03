import SwiftUI
import UniformTypeIdentifiers

// 이 SDK(CLT 전용)에는 SwiftUIMacros 플러그인이 없어 @State를 쓸 수 없다. @StateObject로 대체한다.
final class MainUI: ObservableObject {
    @Published var dropTargeted = false
    @Published var showMaterials = false
}
/// 오른쪽 채팅 접기 상태(기억)
final class LayoutState: ObservableObject {
    static let shared = LayoutState()
    @Published var showChat: Bool { didSet { UserDefaults.standard.set(showChat, forKey: "showChat") } }
    init() { showChat = UserDefaults.standard.object(forKey: "showChat") as? Bool ?? true }
}
final class TranscriptState: ObservableObject {
    @Published var transcript: Transcript?
    @Published var rename: RenameTarget?
    @Published var newName = ""
    /// 2단계(실시간): true면 대본이 계속 늘어나며 맨 아래로 자동 스크롤한다.
    @Published var live = false
}

struct MainWindow: View {
    @EnvironmentObject var store: Store
    @StateObject private var ui = MainUI()
    @ObservedObject private var layout = LayoutState.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedID) {
                ForEach(store.jobs) { job in
                    JobRow(job: job).tag(job.id)
                        .contextMenu {
                            if job.status == .failed || job.status == .done {
                                Button("다시 처리") { store.retry(job.id) }
                            }
                            if let t = job.transcriptPath {
                                Button("대본을 Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: t)]) }
                            }
                            if job.status == .done {
                                Button("위키로 보내기") { store.sendToWiki(job.id, manual: true) }
                            }
                            if let w = job.wikiPath, FileManager.default.fileExists(atPath: w) {
                                Button("위키 사본을 Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: w)]) }
                            }
                            Button("원본 오디오를 Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: job.audioPath)]) }
                            Divider()
                            Button("목록에서 삭제", role: .destructive) { store.remove(job.id) }
                        }
                }
            }
            .overlay {
                if store.jobs.isEmpty {
                    Text("녹음하거나\n오디오 파일을 여기로 끌어다 놓으세요")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            if let job = store.jobs.first(where: { $0.id == store.selectedID }) {
                JobDetail(job: job)
            } else {
                Text("항목을 선택하세요").foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("프로필", selection: $store.selectedProfile) {
                    Text("자동(프로필 없음)").tag("")
                    ForEach(store.profiles, id: \.self) { Text($0).tag($0) }
                }
                .disabled(store.isRecording)
                Picker("모드", selection: $store.recordMode) {
                    Text("녹음 후 처리").tag("post")
                    Text("실시간 (2단계 예정)").tag("live").disabled(true)
                }
                .disabled(store.isRecording)
                Button {
                    store.toggleRecording()
                } label: {
                    Label(store.isRecording ? "정지 \(formatTime(store.elapsed))" : "녹음",
                          systemImage: store.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(store.isRecording ? .red : .primary)
                }
                if let job = store.jobs.first(where: { $0.id == store.selectedID }) {
                    Button { ui.showMaterials.toggle() } label: {
                        Label("강의자료 \(ChatHub.shared.session(for: job.id).materials.count)", systemImage: "books.vertical")
                    }
                    .popover(isPresented: $ui.showMaterials, arrowEdge: .bottom) {
                        MaterialsPicker(job: job, session: ChatHub.shared.session(for: job.id))
                    }
                    .help("채팅에 붙일 강의자료 (기본: 자동 선택)")
                }
                BatteryBadge()
                Button { layout.showChat.toggle() } label: {
                    Label("채팅", systemImage: layout.showChat ? "sidebar.trailing" : "bubble.left.and.bubble.right")
                }
                .help("AI 채팅 접기/펴기")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let ok = urls.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            store.importFiles(ok)
            return !ok.isEmpty
        } isTargeted: { ui.dropTargeted = $0 }
        .overlay {
            if ui.dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.08)).padding(6).allowsHitTesting(false)
            }
        }
        .alert("알림", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("확인") { store.message = nil }
        } message: { Text(store.message ?? "") }
        .frame(minWidth: 900, minHeight: 520)
    }
}

struct JobRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject var power = PowerMonitor.shared
    let job: Job
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(job.title).lineLimit(1).font(.body)
            HStack(spacing: 6) {
                Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let d = job.duration { Text("· " + formatTime(d)) }
                Spacer()
                badge
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var badge: some View {
        switch job.status {
        case .processing:
            HStack(spacing: 4) { ProgressView().controlSize(.mini); Text(job.stage ?? "처리 중") }
        case .done: Label("완료", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Label("실패", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .recording: Label("녹음 중", systemImage: "record.circle.fill").foregroundStyle(.red)
        case .queued:
            if store.chargingOnly && !power.onAC { Label("충전 대기", systemImage: "bolt.slash") } else { Label("대기", systemImage: "clock") }
        }
    }
}

struct RenameTarget: Identifiable { let id = UUID(); let name: String }

struct TranscriptView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var power = PowerMonitor.shared
    let job: Job
    @StateObject private var st = TranscriptState()

    private static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .brown, .indigo]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task(id: "\(job.id)-\(job.status.rawValue)-\(store.transcriptRevision)") { load() }
        .sheet(item: $st.rename) { t in
            VStack(alignment: .leading, spacing: 12) {
                Text("화자 이름 바꾸기").font(.headline)
                Text("\"\(t.name)\"의 모든 발언을 새 이름으로 바꾸고 .md 파일에 반영합니다.").font(.callout).foregroundStyle(.secondary)
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
        store.renameSpeaker(job: job, from: t.name, to: st.newName)
        st.rename = nil
    }

    private func load() {
        if job.status == .done, let p = job.transcriptPath { st.transcript = TranscriptIO.load(path: p) } else { st.transcript = nil }
    }

    private var isLoadedHere: Bool { player.loadedPath == job.audioPath }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(job.title).font(.title2.bold()).lineLimit(1)
                Spacer()
                if job.status == .done, let p = job.transcriptPath {
                    Button("복사") {
                        if let s = try? String(contentsOfFile: p, encoding: .utf8) {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
                        }
                    }
                    Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                    Button("위키로 보내기") { store.sendToWiki(job.id, manual: true) }
                    if store.exportEnabled && !store.exportFolder.isEmpty {
                        Button("내보내기") { store.export(path: p) }
                    }
                }
            }
            HStack(spacing: 12) {
                Button {
                    if isLoadedHere && player.isPlaying { player.pause() } else { player.play(path: job.audioPath) }
                } label: { Image(systemName: isLoadedHere && player.isPlaying ? "pause.fill" : "play.fill") }
                if isLoadedHere {
                    Text("\(formatTime(player.currentTime)) / \(formatTime(player.duration))").monospacedDigit().foregroundStyle(.secondary)
                }
                if let e = player.error { Text(e).foregroundStyle(.red).font(.caption) }
                Spacer()
                Text(metaLine).font(.caption).foregroundStyle(.secondary)
            }
            if let w = job.wikiPath {
                HStack(spacing: 6) {
                    Image(systemName: "books.vertical")
                    Text("위키: \((w as NSString).lastPathComponent)").lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: w)]) }.controlSize(.small)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            if job.status == .done, let t = st.transcript, !t.speakers.isEmpty {
                HStack {
                    Text("화자").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(t.speakers.enumerated()), id: \.element) { i, s in
                        Button(s) { openRename(s) }
                            .buttonStyle(.bordered).controlSize(.small)
                            .tint(Self.palette[i % Self.palette.count])
                    }
                    Text("(누르면 이름 변경)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
    }

    private var metaLine: String {
        var parts = ["프로필: \(job.profile.isEmpty ? "자동" : job.profile)"]
        if let d = st.transcript?.meta["duration"] { parts.append("길이 \(d)") }
        if let w = job.avgWatts { parts.append(String(format: "평균 %.1fW", w)) }
        if let u = job.batteryUsedPct, job.avgWatts != nil { parts.append(String(format: "배터리 -%.1f%%p", u)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var content: some View {
        switch job.status {
        case .recording:
            centered { VStack(spacing: 8) {
                Label("녹음 중 \(formatTime(store.elapsed))", systemImage: "record.circle.fill").foregroundStyle(.red)
                Text("대본은 녹음이 끝난 뒤 처리됩니다. 아래 노트에는 지금 시각이 붙습니다.").font(.caption).foregroundStyle(.secondary)
            } }
        case .queued:
            centered { VStack(spacing: 6) {
                Label(store.chargingOnly && !power.onAC ? "충전 연결 대기 중 (설정: 충전 중일 때만 처리)" : "대기 중",
                      systemImage: store.chargingOnly && !power.onAC ? "bolt.slash" : "clock")
            } }
        case .processing:
            centered { VStack(spacing: 10) { ProgressView(); Text(job.stage ?? "처리 중") } }
        case .failed:
            centered {
                VStack(spacing: 10) {
                    Label("처리 실패", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(job.error ?? "").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("다시 처리") { store.retry(job.id) }
                }.padding()
            }
        case .done:
            if let t = st.transcript {
                let speakers = t.speakers
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(t.segments) { seg in
                            let idx = speakers.firstIndex(of: seg.speaker) ?? 0
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Button(seg.timeLabel) { player.play(path: job.audioPath, from: seg.time) }
                                    .buttonStyle(.link).monospacedDigit().frame(width: 56, alignment: .trailing)
                                Text(seg.speaker).bold().foregroundStyle(Self.palette[idx % Self.palette.count])
                                    .frame(width: 70, alignment: .leading)
                                    .onTapGesture { openRename(seg.speaker) }
                                Text(seg.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(6)
                            .background(isActive(seg, t) ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(12)
                }
                .onChange(of: t.segments.count) { _ in
                    if st.live, let last = t.segments.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                }
            } else {
                centered { Text("대본 파일을 읽을 수 없습니다").foregroundStyle(.secondary) }
            }
        }
    }

    private func isActive(_ seg: Segment, _ t: Transcript) -> Bool {
        guard isLoadedHere, player.isPlaying else { return false }
        let next = seg.id + 1 < t.segments.count ? t.segments[seg.id + 1].time : .infinity
        return player.currentTime >= seg.time && player.currentTime < next
    }

    private func centered<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        v().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 가운데(대본 위 / 노트 아래) + 오른쪽(채팅) 구성. 2단계에서 라이브 대본은 TranscriptView(st.live)로 흘려 넣는다.
struct JobDetail: View {
    let job: Job
    @ObservedObject private var layout = LayoutState.shared

    var body: some View {
        HSplitView {
            VSplitView {
                TranscriptView(job: job).frame(minHeight: 180)
                NoteView(job: job).frame(minHeight: 130)
            }
            .frame(minWidth: 400)
            if layout.showChat {
                ChatView(job: job, session: ChatHub.shared.session(for: job.id))
                    .frame(minWidth: 290, idealWidth: 360, maxWidth: 560)
            }
        }
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
