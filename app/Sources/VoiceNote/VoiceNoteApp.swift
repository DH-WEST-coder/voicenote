import SwiftUI

@main
struct VoiceNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let store = Store.shared

    var body: some Scene {
        // 첫 씬이 실행 시 자동으로 열린다. Dock 아이콘을 누르면 다시 열린다.
        Window("VoiceNote", id: "main") {
            MainWindow().environmentObject(store)
        }
        .defaultSize(width: 1180, height: 760)

        MenuBarExtra {
            MenuContent().environmentObject(store)
        } label: {
            MenuLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.menu)

        Window("설정", id: "settings") {
            SettingsView().environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}

/// Dock 앱으로 동작한다. 창을 닫아도 메뉴바·녹음은 계속 돈다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
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
        Button("파일 가져오기…") { show("main"); MaterialImporter.shared.showPicker = true }
        Button("설정…") { show("settings") }
        Divider()
        Button("종료") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

}
