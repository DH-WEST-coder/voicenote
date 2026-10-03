import SwiftUI

@main
struct VoiceNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(store)
        } label: {
            MenuLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.menu)

        Window("VoiceNote", id: "main") {
            MainWindow().environmentObject(store)
        }
        .defaultSize(width: 980, height: 660)

        Window("설정", id: "settings") {
            SettingsView().environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}

/// 실행 직후 SwiftUI Window 씬이 자동으로 뜨면 닫아서 메뉴바 앱처럼 시작한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--show-window") { return }
        DispatchQueue.main.async {
            for w in NSApp.windows where w.title == "VoiceNote" || w.title == "설정" { w.close() }
        }
    }
}

struct MenuLabel: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if store.isRecording {
            HStack(spacing: 4) {
                Image(systemName: "record.circle.fill")
                Text(formatTime(store.elapsed)).monospacedDigit()
            }
        } else {
            Image(systemName: store.jobs.contains { $0.status == .processing } ? "waveform.badge.magnifyingglass" : "waveform")
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var store: Store
    @ObservedObject var ap = AutoPreprocess.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(store.isRecording ? "녹음 정지 (\(formatTime(store.elapsed)))" : "녹음 시작") {
            store.toggleRecording()
        }
        .keyboardShortcut("r", modifiers: [.option, .command])

        Picker("프로필", selection: $store.selectedProfile) {
            Text("자동(프로필 없음)").tag("")
            ForEach(store.profiles, id: \.self) { Text($0).tag($0) }
        }
        .disabled(store.isRecording)

        if let m = store.message { Text(m) }

        if let j = store.jobs.first(where: { $0.status == .processing }) {
            Divider()
            Text("처리 중: \(j.title) — \(j.stage ?? "")")
        }
        let queued = store.jobs.filter { $0.status == .queued }.count
        if queued > 0 { Text("대기 \(queued)건") }

        Divider()
        Text(ap.menuLine)
        if ap.accessWarning != nil { Text("⚠︎ Google Drive 접근 권한 필요 (설정 참고)") }
        Divider()
        Button("목록 창 열기") { show("main") }
        Button("오디오 파일 가져오기…") { pickFiles() }
        Button("설정…") { show("settings") }
        Divider()
        Button("종료") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func pickFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.allowedContentTypes = [.audio, .movie]
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK { store.importFiles(p.urls) }
    }
}
