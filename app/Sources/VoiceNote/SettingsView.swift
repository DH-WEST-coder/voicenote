import SwiftUI

struct SettingsView: View {
    @ObservedObject private var profileEditor = ProfileEditorState.shared
    @EnvironmentObject var store: Store
    @ObservedObject var chat = ChatSettings.shared
    @ObservedObject var vault = VaultConfig.shared
    @ObservedObject var ap = AutoPreprocess.shared
    @ObservedObject var live = LiveSettings.shared

    var body: some View {
        let engineOK = FileManager.default.isExecutableFile(atPath: store.enginePath + "/.venv/bin/python")
            && FileManager.default.fileExists(atPath: store.enginePath + "/voicenote.py")
        Form {
            Section("엔진") {
                HStack {
                    TextField("엔진 경로", text: $store.enginePath)
                    Button("선택…") { if let p = chooseFolder() { store.enginePath = p } }
                }
                Label(engineOK ? "엔진을 찾았습니다" : "voicenote.py 또는 .venv/bin/python 이 없습니다",
                      systemImage: engineOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(engineOK ? .green : .orange)
            }
            Section("AI 채팅") {
                Picker("엔진", selection: $chat.engine) { ForEach(ChatEngine.allCases) { Text($0.label).tag($0) } }
                switch chat.engine {
                case .agy:
                    TextField("agy 경로", text: $chat.agyPath)
                    TextField("모델 (비우면 기본)", text: $chat.agyModel)
                case .codex:
                    TextField("codex 경로", text: $chat.codexPath)
                    TextField("모델 (비우면 기본)", text: $chat.codexModel)
                case .lmstudio:
                    TextField("서버 주소", text: $chat.lmURL)
                    TextField("모델 (비우면 로드된 첫 모델)", text: $chat.lmModel)
                }
                Toggle("위키 vault를 읽기 전용으로 붙여 엔진이 직접 더 찾게 하기", isOn: $chat.attachVault)
                Toggle("자료 페이지 이미지 보내기", isOn: $chat.sendPageImages)
                Text("글자가 적은 자료 페이지(그림·수식 위주)를 이미지로 최대 8장 함께 보냅니다. Codex·Gemini만 지원, LM Studio는 보내지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("대본 글자 수 상한: \(chat.transcriptCap)", value: $chat.transcriptCap, in: 5000...300000, step: 5000)
                Stepper("강의자료 글자 수 상한: \(chat.materialCap)", value: $chat.materialCap, in: 10000...400000, step: 10000)
                Stepper("항상 전부 보내는 최근 구간: \(chat.recentMinutes)분", value: $chat.recentMinutes, in: 1...60)
                HStack {
                    Button("프롬프트 설정 파일 열기") {
                        ChatPrompts.ensureFile()
                        NSWorkspace.shared.activateFileViewerSelecting([Paths.promptsFile])
                    }
                }
                Text("엔진은 앱 전용 임시 폴더에서 읽기 전용(agy: --sandbox+헤드리스 권한 자동 거부, codex: read-only 샌드박스)으로 실행됩니다. 빠른 버튼·지시문은 chat_prompts.json에서 고칩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("실시간 받아쓰기") {
                Toggle("녹음 중 실시간으로 대본 초안 보기", isOn: $live.enabled)
                Picker("모델", selection: $live.model) {
                    ForEach(LiveSettings.models, id: \.id) { Text($0.label).tag($0.id) }
                }
                Picker("갱신 간격", selection: $live.chunkSec) {
                    ForEach(LiveSettings.intervals, id: \.self) { Text("\(Int($0))초").tag($0) }
                }
                Text("녹음이 끝나면 정밀 받아쓰기(1.7B + 화자 분리)가 따로 돌아 초안을 대체합니다. 실시간은 화자 구분이 없고 오인식이 더 많을 수 있습니다. 간격이 짧을수록 빨리 보이지만 전력을 더 씁니다. 값은 녹음을 시작할 때 읽으니 녹음 중에 바꾸면 다음 녹음부터 적용됩니다. 처음 쓰는 모델은 내려받느라 시간이 걸립니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("배터리") {
                Toggle("충전 중일 때만 처리", isOn: $store.chargingOnly)
                Text("켜면 녹음 후 처리 작업이 전원이 연결될 때까지 큐에서 기다립니다. 배터리로 녹음·처리하는 동안 30초마다 소비 전력(W)을 app.log에 기록하고 세션 정보에 평균 W와 사용한 %p를 보여 줍니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("내보내기") {
                Toggle("완료되면 Gemini 전처리 폴더로 자동 복사", isOn: $store.exportEnabled)
                HStack {
                    TextField("Gemini 전처리 폴더", text: $store.exportFolder)
                    Button("선택…") { if let p = chooseFolder() { store.exportFolder = p } }
                }
                Text("대본은 항상 ~/Documents/VoiceNote/transcripts/ 에 저장됩니다.").font(.caption).foregroundStyle(.secondary)
            }
            Section("위키") {
                HStack {
                    TextField("위키 vault 경로", text: $vault.vault)
                    Button("선택…") { if let p = chooseFolder() { vault.vault = p } }
                }
                TextField("학기 폴더 (vault 기준)", text: $vault.semester)
                if let w = vault.warning {
                    Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                }
                Text("vault 위치는 여기 한 곳(config.json)에서만 바꿉니다. 프로필 wiki_dir은 vault 기준 상대경로입니다. 채팅·자동 전처리·엔진이 모두 이 값을 씁니다.")
                    .font(.caption).foregroundStyle(.secondary)
                DatePicker("학기 시작일", selection: Binding(get: { vault.semesterStartDate }, set: { vault.setSemesterStart($0) }),
                           displayedComponents: .date)
                Text("노트 제목의 'N주차' 계산에 씁니다(시작일이 1주차 첫날).").font(.caption).foregroundStyle(.secondary)
                Toggle("위키 본문 참고", isOn: $chat.wikiRefEnabled)
                Stepper("위키 참고 글자 수 상한: \(chat.wikiCap)", value: $chat.wikiCap, in: 5000...200000, step: 5000)
                    .disabled(!chat.wikiRefEnabled)
                Text("AI 채팅 질문마다 wiki/ 에서 관련 페이지 최대 4개를 골라 맥락에 넣습니다(읽기 전용, 위키는 고치지 않음). 노트는 '위키로 보내기' 버튼을 눌러야 위키로 갑니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("위키 자동 전처리") {
                Toggle("앱이 켜져 있는 동안 자동 실행", isOn: $ap.enabled)
                Stepper("실행 간격: \(ap.intervalMinutes)분", value: $ap.intervalMinutes, in: 1...240)
                HStack {
                    Button(ap.running ? "실행 중…" : "지금 실행") { ap.runNow() }.disabled(ap.running)
                    Button("run.log 열기") { ap.openRunLog() }
                    Button("앱 로그 보기") { ap.openAppLog() }
                }
                Text(ap.menuLine).font(.caption)
                if let w = ap.accessWarning {
                    Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
                Text("위키의 auto_preprocess.sh를 앱의 자식 프로세스로 실행합니다(첫 실행은 시작 1분 뒤, 대본을 위키로 보낸 뒤 약 11분 후에도 실행). 로그: ~/Library/Application Support/VoiceNote/logs/autopreprocess.log")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("프로필") {
                HStack {
                    Button("새 프로필…") { ProfileEditorState.shared.new() }
                    Menu("프로필 고치기") {
                        ForEach(store.profiles, id: \.self) { p in Button(p) { ProfileEditorState.shared.edit(p) } }
                    }
                    .fixedSize()
                    Button("profiles.json을 Finder에서 열기") {
                        Profiles.ensureDefaults()
                        NSWorkspace.shared.activateFileViewerSelecting([Paths.profilesFile])
                    }
                    Button("다시 읽기") { store.reloadProfiles() }
                }
                Text("용어/언어/course/wiki_dir을 수정한 뒤 '다시 읽기'를 누르세요. 단축키: ⌥⌘R (녹음 시작/정지)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .sheet(item: $profileEditor.editing) { e in ProfileEditor(editing: e).environmentObject(store) }
        .padding(.vertical, 8)
    }

    private func chooseFolder() -> String? {
        let p = NSOpenPanel()
        p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        return p.runModal() == .OK ? p.url?.path : nil
    }
}
