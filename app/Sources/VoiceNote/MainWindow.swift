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
                ForEach(dayGroups, id: \.title) { group in
                Section(group.title) {
                ForEach(group.jobs) { job in
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
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if store.jobs.isEmpty {
                    Text("녹음이 없습니다").foregroundStyle(.tertiary)
                }
            }
            .safeAreaInset(edge: .bottom) { sidebarFooter }
            .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 360)
        } detail: {
            if let job = store.jobs.first(where: { $0.id == store.selectedID }) {
                JobDetail(job: job)
            } else {
                EmptyDetail()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Menu {
                    Picker("과목 프로필", selection: $store.selectedProfile) {
                        Text("자동(프로필 없음)").tag("")
                        ForEach(store.profiles, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(store.selectedProfile.isEmpty ? "프로필 없음" : store.selectedProfile, systemImage: "graduationcap")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(store.isRecording)
                .help("다음 녹음에 쓸 과목 프로필(용어 힌트·위키 폴더)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                // 모드 선택(실시간/녹음 후 처리)은 2단계 실시간 받아쓰기와 함께 다시 넣는다.
                RecordButton()
                if let job = store.jobs.first(where: { $0.id == store.selectedID }) {
                    Button { ui.showMaterials.toggle() } label: {
                        Label("강의자료 \(ChatHub.shared.session(for: job.id).materials.count)", systemImage: "books.vertical")
                    }
                    .popover(isPresented: $ui.showMaterials, arrowEdge: .bottom) {
                        MaterialsPicker(job: job, session: ChatHub.shared.session(for: job.id))
                    }
                    .help("채팅에 붙일 강의자료 (기본: 자동 선택)")
                }
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

private struct DayGroup { let title: String; let jobs: [Job] }

extension MainWindow {
    fileprivate var dayGroups: [DayGroup] {
        let cal = Calendar.current
        var order: [Date] = []
        var map: [Date: [Job]] = [:]
        for j in store.jobs {
            let d = cal.startOfDay(for: j.createdAt)
            if map[d] == nil { order.append(d) }
            map[d, default: []].append(j)
        }
        return order.map { d in
            let title: String
            if cal.isDateInToday(d) { title = "오늘" }
            else if cal.isDateInYesterday(d) { title = "어제" }
            else { title = d.formatted(.dateTime.month().day().weekday(.abbreviated)) }
            return DayGroup(title: title, jobs: map[d] ?? [])
        }
    }

    fileprivate var sidebarFooter: some View {
        let processing = store.jobs.first { $0.status == .processing }
        let queued = store.jobs.filter { $0.status == .queued }.count
        return VStack(alignment: .leading, spacing: 6) {
            if let p = processing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("\(p.stage ?? "처리 중")").lineLimit(1)
                    if queued > 0 { Text("· 대기 \(queued)").foregroundStyle(.secondary) }
                }
                .font(.caption)
            }
            HStack {
                Button { pickAudioFiles(into: store) } label: { Label("파일 가져오기", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderless)
                Spacer()
                BatteryBadge()
            }
            .font(.callout)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.bar)
    }
}

/// 아무것도 고르지 않았을 때: 녹음 시작 안내
struct EmptyDetail: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(LinearGradient(colors: [Theme.record, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 6) {
                Text("수업을 녹음해 보세요").font(.title2.weight(.semibold))
                Text("녹음이 끝나면 화자별 대본이 자동으로 만들어집니다.\n오디오 파일을 이 창에 끌어다 놓아도 됩니다.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            RecordButton(large: true)
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

struct JobRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject var power = PowerMonitor.shared
    let job: Job
    var body: some View {
        HStack(spacing: 10) {
            StatusIcon(status: job.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title).lineLimit(1).font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(job.createdAt.formatted(date: .omitted, time: .shortened))
                    if let d = job.duration { Text("· " + formatTime(d)) }
                    if !job.profile.isEmpty { Text("· " + job.profile).lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let note = statusNote {
                    Text(note).font(.caption2).foregroundStyle(job.status == .failed ? .orange : .secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var statusNote: String? {
        switch job.status {
        case .processing: return job.stage ?? "처리 중"
        case .failed: return "처리 실패 · 우클릭해서 다시 처리"
        case .recording: return "녹음 중"
        case .queued: return store.chargingOnly && !power.onAC ? "충전 연결 대기" : "대기 중"
        case .done: return nil
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.title).font(.title2.weight(.semibold)).lineLimit(1)
                Spacer()
                if job.status == .done, let p = job.transcriptPath {
                    Button { store.sendToWiki(job.id, manual: true) } label: { Label("위키로 보내기", systemImage: "books.vertical") }
                        .controlSize(.small)
                    Menu {
                        Button("대본 복사") {
                            if let s = try? String(contentsOfFile: p, encoding: .utf8) {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
                            }
                        }
                        Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                        if store.exportEnabled && !store.exportFolder.isEmpty {
                            Button("내보내기 폴더로 복사") { store.export(path: p) }
                        }
                        if let w = job.wikiPath {
                            Button("위키 사본 Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: w)]) }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
            HStack(spacing: 6) {
                ForEach(metaChips, id: \.0) { Chip(text: $0.0, systemImage: $0.1) }
                if job.wikiPath != nil { Chip(text: "위키에 있음", systemImage: "checkmark", tint: .green) }
            }
            HStack(spacing: 10) {
                Button {
                    if isLoadedHere && player.isPlaying { player.pause() } else { player.play(path: job.audioPath) }
                } label: {
                    Image(systemName: isLoadedHere && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(Color.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                if isLoadedHere {
                    ProgressView(value: min(player.currentTime, max(player.duration, 0.01)), total: max(player.duration, 0.01))
                        .frame(maxWidth: 220)
                    Text("\(formatTime(player.currentTime)) / \(formatTime(player.duration))").monospacedDigit()
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("재생").font(.caption).foregroundStyle(.secondary)
                }
                if let e = player.error { Text(e).foregroundStyle(.red).font(.caption) }
                Spacer()
                if job.status == .done, let t = st.transcript, !t.speakers.isEmpty {
                    ForEach(Array(t.speakers.enumerated()), id: \.element) { i, s in
                        Button { openRename(s) } label: {
                            HStack(spacing: 4) {
                                Circle().fill(Theme.speakerColor(i)).frame(width: 7, height: 7)
                                Text(s)
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.speakerColor(i).opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("눌러서 이름 바꾸기")
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var metaChips: [(String, String)] {
        var parts = [(job.profile.isEmpty ? "프로필 없음" : job.profile, "graduationcap")]
        if let d = st.transcript?.meta["duration"] { parts.append((d, "clock")) }
        if let w = job.avgWatts { parts.append((String(format: "평균 %.1fW", w), "bolt")) }
        if let u = job.batteryUsedPct, job.avgWatts != nil { parts.append((String(format: "배터리 -%.1f%%p", u), "battery.50")) }
        return parts
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
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(t.segments) { seg in
                            let idx = speakers.firstIndex(of: seg.speaker) ?? 0
                            let first = seg.id == 0 || t.segments[seg.id - 1].speaker != seg.speaker
                            VStack(alignment: .leading, spacing: 3) {
                                if first {
                                    HStack(spacing: 6) {
                                        Circle().fill(Theme.speakerColor(idx)).frame(width: 8, height: 8)
                                        Text(seg.speaker).font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.speakerColor(idx))
                                            .onTapGesture { openRename(seg.speaker) }
                                    }
                                    .padding(.top, seg.id == 0 ? 0 : 12)
                                }
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Button(seg.timeLabel) { player.play(path: job.audioPath, from: seg.time) }
                                        .buttonStyle(.plain).font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                                        .help("여기부터 재생")
                                    Text(seg.text).font(.body).lineSpacing(4).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 5).padding(.horizontal, 6)
                                .background(isActive(seg, t) ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .id(seg.id)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
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
                TranscriptView(job: job).frame(minHeight: 200)
                    .background(Theme.paneBackground)
                NoteView(job: job).frame(minHeight: 140)
            }
            .frame(minWidth: 440)
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
