import AppKit
import PDFKit
import Quartz
import SwiftUI

// MARK: - 다운로드 최신순 고르기

final class DownloadsPickerState: ObservableObject {
    @Published var files: [RecentFile] = []
    @Published var picked: Set<URL> = []
    @Published var loaded = false
}

struct DownloadsPicker: View {
    @ObservedObject var importer = MaterialImporter.shared
    @StateObject private var st = DownloadsPickerState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("파일 가져오기").font(.title3.weight(.semibold))
                    Text("다운로드 폴더 · 최근 받은 순서 · 오디오는 받아쓰기, PDF·PPT는 위키 자료로")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("새로고침")
            }
            .padding(16)
            Divider()
            if !st.loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if st.files.isEmpty {
                Text("다운로드 폴더에 오디오·PDF·PPT 파일이 없습니다").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(st.files) { f in row(f) }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Button("다른 위치에서 찾기…") { other() }
                Spacer()
                Button("취소") { importer.showPicker = false }.keyboardShortcut(.cancelAction)
                Button(st.picked.isEmpty ? "가져오기" : "가져오기 (\(st.picked.count))") {
                    let urls = st.files.map(\.url).filter { st.picked.contains($0) }
                    importer.showPicker = false
                    importer.request(urls)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(st.picked.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 600, height: 520)
        .onAppear { reload() }
    }

    private func row(_ f: RecentFile) -> some View {
        let on = st.picked.contains(f.url)
        return HStack(spacing: 10) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5)).font(.title3)
            Image(systemName: f.icon).foregroundStyle(color(f)).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(f.date.formatted(.relative(presentation: .named)))
                    Text("·"); Text(f.kind)
                    if !f.isDir { Text("·"); Text(ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file)) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if on { st.picked.remove(f.url) } else { st.picked.insert(f.url) }
        }
    }

    private func color(_ f: RecentFile) -> Color {
        if f.isDir { return .blue }
        switch f.kind { case "PDF": return .red; case "PPT": return .orange; default: return .purple }
    }

    private func reload() {
        st.loaded = false
        DispatchQueue.global(qos: .userInitiated).async {
            let files = RecentFile.scanDownloads()
            DispatchQueue.main.async { st.files = files; st.picked = st.picked.filter { u in files.contains { $0.url == u } }; st.loaded = true }
        }
    }

    private func other() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.directoryURL = RecentFile.downloads
        p.allowedContentTypes = [.audio, .movie, .pdf, .presentation, .folder]
        if p.runModal() == .OK {
            importer.showPicker = false
            importer.request(p.urls)
        }
    }
}

// MARK: - 자료 확인 창

struct MaterialImportSheet: View {
    @ObservedObject var importer = MaterialImporter.shared
    @EnvironmentObject var store: Store
    let pending: MaterialImporter.PendingImport

    var body: some View {
        let courses = Courses.list()
        VStack(alignment: .leading, spacing: 14) {
            Text("수업 자료 넣기").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(pending.files, id: \.self) { u in
                    Label(u.lastPathComponent, systemImage: u.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "rectangle.on.rectangle.angled")
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 8))

            Picker("과목", selection: $importer.course) {
                if importer.course.isEmpty { Text("과목 선택").tag("") }
                ForEach(courses, id: \.self) { Text($0).tag($0) }
                if !importer.course.isEmpty && !courses.contains(importer.course) { Text(importer.course + " (새 폴더)").tag(importer.course) }
            }
            if !importer.course.isEmpty {
                Label("위키 …/\(importer.course)/lecture/ 로 옮깁니다 (다운로드에서는 사라짐)", systemImage: "arrow.right.doc.on.clipboard")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Goodnotes로 보내기", isOn: $importer.sendToGoodnotes)
            if importer.sendToGoodnotes {
                Text("Goodnotes에 불러오기 창이 뜨면 확인을 눌러 주세요. Goodnotes에서 \(importer.course.isEmpty ? "과목" : importer.course) 폴더를 열어 두면 그 위치로 들어갑니다. PPT는 PowerPoint로 PDF를 만들어 보냅니다(처음 한 번 폴더 접근 허용 필요).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Label(importer.targetSession.map { "연결할 노트: \($0.title)" } ?? "새 노트를 만듭니다", systemImage: "link")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("취소") { importer.pending = nil }.keyboardShortcut(.cancelAction)
                Button("옮기기") { importer.confirm(pending) }
                    .keyboardShortcut(.defaultAction).disabled(importer.course.isEmpty)
            }
        }
        .padding(20).frame(width: 480)
    }
}

// MARK: - 자료 보기

struct PDFKitView: NSViewRepresentable {
    let path: String
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .windowBackgroundColor
        v.document = PDFDocument(url: URL(fileURLWithPath: path))
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL?.path != path { v.document = PDFDocument(url: URL(fileURLWithPath: path)) }
    }
}

struct QuickLookView: NSViewRepresentable {
    let path: String
    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal)!
        v.previewItem = URL(fileURLWithPath: path) as NSURL
        return v
    }
    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? NSURL)?.path != path { v.previewItem = URL(fileURLWithPath: path) as NSURL }
    }
}

/// 가운데 위쪽: 자료가 있으면 [대본 | 자료…] 탭
struct TopPane: View {
    @ObservedObject var tabs = MaterialTabs.shared
    let session: Session

    var body: some View {
        let atts = session.attachments
        if atts.isEmpty {
            TranscriptView(session: session)
        } else {
            let sel = tabs.selection[session.id] ?? nil
            let current = atts.first { $0.id == sel }
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        tab("대본", icon: "text.alignleft", on: current == nil) { tabs.show(session: session.id, attachment: nil) }
                        ForEach(atts) { a in
                            tab(a.name, icon: a.isPDF ? "doc.richtext" : "rectangle.on.rectangle.angled", on: current?.id == a.id) {
                                tabs.show(session: session.id, attachment: a.id)
                            }
                            .contextMenu {
                                Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: a.path)]) }
                                if let p = a.viewPDF {
                                    Button("Goodnotes로 보내기") {
                                        DispatchQueue.global().async { _ = MaterialImporter.openInGoodnotes([p]) }
                                    }
                                }
                                Divider()
                                Button("이 노트에서 연결 해제") {
                                    HoldList.remove(a)
                                    Store.shared.updateSession(session.id) { $0.attachments.removeAll { $0.id == a.id } }
                                    tabs.show(session: session.id, attachment: nil)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .background(.bar)
                Divider()
                if let a = current {
                    if let pdf = a.viewPDF { PDFKitView(path: pdf) } else { QuickLookView(path: a.path) }
                } else {
                    TranscriptView(session: session)
                }
            }
        }
    }

    private func tab(_ title: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).lineLimit(1).truncationMode(.middle)
                .font(.callout.weight(on ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .frame(maxWidth: 220)
                .background(on ? Color.accentColor.opacity(0.15) : .clear, in: Capsule())
                .foregroundStyle(on ? Color.accentColor : Color.primary)
                .contentShape(Capsule())   // 글자 밖 빈 곳을 눌러도 탭이 바뀌게
        }
        .buttonStyle(.plain)
    }
}
