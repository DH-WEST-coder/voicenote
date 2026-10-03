# 구현 계획: 노트 중심 구조 (VNote)

계획: Opus. 구현: Sonnet. 이 문서만 보고 구현할 수 있게 쓴다. 사용자는 한국어 사용자이고 UI 문구는 모두 한국어다.

## 0. 환경·제약 (반드시 지킬 것)

- 앱: `voice/app/` SwiftUI 메뉴바+Dock 앱. **Xcode 없음**, Command Line Tools(Swift 6.4)만. 빌드는 `voice/app/build.sh`(SwiftPM release → 번들 조립 → ad-hoc 서명).
- **SwiftUI 매크로 플러그인이 없다**: `@State`, `@Observable`, `#Preview` 사용 금지. 뷰 로컬 상태는 `ObservableObject` + `@StateObject`/`@ObservedObject`.
- **Regex 리터럴(`/.../`) 금지**(Swift 5 모드). `NSRegularExpression`이나 문자열 처리.
- Swift 6 동시성: `Store`, `ChatSession`, `NoteController` 등은 `@MainActor`. 백그라운드 스레드에서 돌아오면 `MainActor.assumeIsolated` 또는 `await MainActor.run`.
- 엔진: `voice/voicenote.py`(Python, `voice/.venv`). 이번에 `--terms-file`, `--language` 옵션을 이미 추가했다.
- 위키 vault: `~/Library/Application Support/VoiceNote/config.json`의 `vault`·`semester`(+ 새 키 `semester_start`). 실제 값: vault `/Users/DH_WEST/LLMwiki/LLM WIKI for study`, semester `raw/05_UNIST/07_3학년 가을학기`.
- 데이터 경로(`Paths`)·번들 ID(`local.voicenote`)·`~/Library/Application Support/VoiceNote`·`~/Documents/VoiceNote`는 **바꾸지 않는다**(기존 데이터 유지). 이름 변경은 화면에 보이는 이름만.

### 시험 규칙 (사용자 데이터 보호)

- **진짜 위키 vault, `~/Downloads`, Goodnotes, PowerPoint를 시험에 쓰지 않는다.** 앱 시험은 `--sandbox <스크래치 폴더>`로 띄운다(모든 데이터 경로와 config.json이 그 아래로 바뀜). sandbox의 `config.json`에 가짜 vault(`<sb>/vault`, semester `sem`, 과목 폴더 `sem/테스트과목/{lecture,transcript}`, `<sb>/vault/.agents/skills/source-processor/auto-preprocess.dirs`, `wiki/` 아래 시험 페이지 몇 개)를 만든다.
- 사용자가 실제 앱(`build/…app`)을 쓰는 중일 수 있다. 실제 앱을 종료·재시작하기 전에 `~/Library/Application Support/VoiceNote/jobs.json`에 `"status" : "recording"`이 없는지 확인한다. 녹음 중이면 절대 종료하지 않는다.
- AI 엔진(agy/codex) 실제 호출은 짧은 시험 1~2번만. 비용이 든다.
- Goodnotes 전송은 sandbox 시험에서 끈다(확인 창의 "Goodnotes로 보내기" 끄기 또는 디버그 플래그로).

## 1. 이미 된 것 (Opus가 이번 세션에 작성, 아직 컴파일 안 됨)

- `voicenote.py`: `--terms-file`(한 줄에 하나, 프로필 용어에 합쳐 최대 80개, 힌트 누출 필터에도 사용), `--language Korean|English|auto`.
- `Sessions.swift`(새 파일): `Project`, `Session`, `TimelineEntry`, `CombinedTranscript`, `Store` 확장(조회·저장 `sessions.json`/`projects.json`·이전 데이터 이전·`newSession`/`newProject`/`move`/`removeSession`/`removeProject`·누적 시각 `notePosition(for:)`/`seek(session:to:)`/`playPosition(in:)`·`combinedTranscript(of:)`).
- `Store.swift`: `selectedID`→`selectedSessionID`(UserDefaults 기억), `sessions`/`projects` 추가, `pendingAttachments` 제거, `startRecording(into:forceNew:)`(오늘 만든 선택 노트면 이어서, 아니면 새 노트), 녹음 Job을 노트 `recordingIDs`에 추가, `enqueue(_:title:into:)`(노트 미지정이면 파일마다 새 노트), 엔진 호출에 노트 용어 `--terms-file`, 처리 완료 시 위키 자동 보내기 제거 → `AITasks.shared.makeTitle(session:)` 호출(아직 없음), job용 `sendToWiki`/`renameSpeaker(job:)`/`notePosition(for job)`/`seek(job:)` 제거, `renameSpeaker(session:from:to:)`(노트의 모든 녹음 대본에 적용), `saveState()` internal.
  - 확인할 것: `startRecording` 안에서 원래 마이크 권한 처리하던 함수 이름을 `requestMicAndRecord()`로 바꿨다. 그 함수 본문이 `beginRecording()`/`micDenied()`를 부르는지, `beginRecording`이 `_recordTarget`을 쓰는지 확인.
- `Models.swift`: `Job.attachments` 제거, `Paths.sessionsFile`/`projectsFile`.
- `VaultConfig.swift`: `semesterStart`(기본 `2026-08-31`, config.json `semester_start`), `week(of:)`.
- 이미 있던 것(이전 커밋): `LectureMaterials.swift`(다운로드→위키 lecture 이동, PPT→PDF(PowerPoint AppleScript), Goodnotes 전송, `text(of:cap:)`), `MaterialViews.swift`(다운로드 최신순 고르기, 확인 창, PDF/QuickLook 보기, `TopPane` 탭), `ProfileEditor.swift`(프로필 편집·`ModelCatalog`), `Theme.swift`, 노트 우클릭 AI·`NotePrompts`.

## 2. 남은 일

### A. `ChatRunner` 이미지 지원 (`Chat.swift`)
- `run(engine:settings:prompt:images:onDelta:onFinish:)`에 `images: [String] = []` 추가.
- codex: `-i <path>`를 이미지마다 붙인다(마지막 `-`보다 앞).
- agy: 이미지 전용 옵션이 없다. 이미지를 작업 폴더(`Paths.chatScratch`) 아래에 두고 프롬프트 끝에 "다음 이미지 파일을 열어 보고(view_file) 참고하라: <절대경로 목록>"을 붙인다. 실제로 Gemini가 이미지를 읽는지 짧게 한 번 시험하고 결과를 보고에 적는다(안 되면 agy일 때는 이미지 생략).
- lmstudio: 이미지 생략.

### B. `AITasks.swift` (새 파일) — 채팅에서 고른 엔진(`ChatSettings.shared.engine`, 모델 포함)으로 한 번 묻고 답 텍스트를 받는다
- `@MainActor final class AITasks: ObservableObject { static let shared; @Published var running: Set<String> }` (`"terms-<id>"`, `"title-<id>"`).
- `oneShot(prompt:images:completion:(String?, String?) -> Void)`: `ChatRunner`로 실행, delta를 모아 최종 텍스트 반환. 읽기 전용 지시 포함.
- **`extractTerms(session:)`**: 노트에 연결된 자료의 PDF 텍스트(`MaterialImporter.text(of:cap:)`, 합계 40,000자 상한) + 글자 적은 페이지 이미지(아래 C의 `pageImages`, 최대 8장)로 용어 힌트를 뽑는다.
  - 언어: 노트 프로필의 `language`(`Profiles.entry(name).language`). `Korean`→한국어 용어만, `English`→영어 용어만, 빈 값(자동)→한국어·영어 둘 다(같은 개념의 한·영 표기 모두 허용).
  - 지시: 교수가 말로 할 전공 용어·고유명사·기호 읽는 법(예: "듀티비", "freewheeling diode", "PLECS") 위주, 일반 단어 제외, 최대 60개, **JSON 문자열 배열만** 출력.
  - 파싱: 첫 `[`~마지막 `]`를 `[String]`으로 디코드, 공백 정리·중복 제거·60개 컷 → `session.terms`. 실패 시 `termsNote`에 오류 문구.
  - 호출 시점: 자료를 노트에 붙인 직후(`MaterialImporter.finish`), 그리고 사용자가 "다시 뽑기"를 누를 때.
- **`makeTitle(session:)`**: `titleIsAuto`일 때만.
  - 접두는 앱이 정한다: 과목(`Courses.course(forProfile:)`) + `VaultConfig.shared.week(of: session.createdAt)` → `"전력전자 6주차 · "`. 과목 없으면 `"M월 d일 · "`.
  - AI에게는 주제만(20자 이내, 한 줄, 따옴표·마침표 없이) 묻는다. 입력: 자료 파일명 + 첫 2페이지 텍스트(2,000자), 대본 앞부분 3,000자, 노트 앞 1,000자.
  - 호출 시점: 첫 녹음 처리 완료(이미 Store에서 호출), 자료를 처음 붙였을 때(녹음 없어도).
  - 결과 반영 전에 다시 `titleIsAuto`인지 확인(그 사이 사용자가 고쳤을 수 있음).

### C. 자료(`LectureMaterials.swift`, `MaterialViews.swift`)
- 연결 대상은 **노트**: `targetJob` → `targetSession`(녹음 중인 노트 > 선택한 노트 > 없으면 확인 시 새 노트 생성). 확인 창 문구 "연결할 노트: <제목>" / "새 노트를 만듭니다".
- `finish`: `Store.updateSession { attachments += … }`, 탭을 그 자료로(`MaterialTabs` 키를 session id로), 보류 목록 기록(아래), `AITasks.extractTerms`, 제목이 auto면 `makeTitle`.
- **보류 목록**: `<lectureDir>/.voicenote-hold`에 `파일명<TAB>YYYY-MM-DD` 한 줄(중복 없이). 노트에서 자료 연결 해제 시, 노트를 위키로 보낼 때 그 줄 삭제. 파일 쓰기 실패는 로그만.
- `pageImages(_ a: Attachment, minChars: 80, max: 8) -> [String]`: 텍스트가 `minChars` 미만인 페이지를 PNG(긴 변 1600px)로 `Paths.chatScratch/img/<파일 해시>/p<N>.png`에 렌더(이미 있으면 재사용).
- `pendingAttachments`·`targetJob` 관련 코드 제거. `TopPane(job:)` → `TopPane(session:)`, 연결 해제는 `updateSession`.
- 디버그 플래그 `--import-material/--import-course`는 노트 기준으로 맞춘다. sandbox 시험용으로 `--no-goodnotes` 플래그를 추가해 Goodnotes 전송을 끈다.

### D. 채팅 (`Chat.swift`, `ChatView.swift`)
- `ChatSession`·`ChatHub`·노트 파일은 **노트(session) id**로 키를 바꾼다(`jobID` → `sessionID`). `ask(_:session:organize:display:)`.
- **자동 자료 고르기 전부 삭제**: `MaterialIndex`, `Materials`, `MaterialFile`, `pick`, `refreshAutoMaterials`, `materials`/`manualMaterials`(ChatFile 디코드는 옛 필드가 있어도 깨지지 않게 optional 처리), `readMaterials`, `MaterialsPicker`, 도구막대의 책(강의자료) 버튼, `--material-probe`. 단 토크나이저(`MaterialIndex.terms`)는 E에서 재사용하니 옮긴다.
- `ChatContext.build(session:question:now:notes:history:prompts:settings:)`:
  1. 수업 정보(제목, 프로필, 과목, 주차, 현재 누적 시각)
  2. 대본: `combinedTranscript(of:).textLines`를 기존 `trim`으로
  3. 이 노트의 자료: PDF 텍스트(`[p.N]`, 합계 `materialCap`) — 이미 있는 블록 재사용
  4. 위키 참고 페이지(E) — `<위키 페이지 경로="wiki/…">…</위키 페이지>`, "위키는 학생이 정리해 온 지식 베이스다. 읽기만 하고 수정하지 말 것"
  5. 내 노트(이미 있는 문구 유지), 이전 대화, 질문
  - 이미지: 자료의 `pageImages` 최대 8장을 `ChatRunner`에 넘긴다(설정 `sendPageImages` 기본 켬).
- `ChatMessage`에 `wikiRefs: [String]?` 추가. 답변 아래에 "참고한 위키: 이름, 이름" 작은 칩. 칩 누르면 Finder/Obsidian 열기(`NSWorkspace.open`).
- 채팅 아래 자료 막대: 노트의 자료 이름 칩(누르면 그 자료 탭으로). "자동/직접 고름" 문구 삭제.
- `NotePrompts`·노트 보충 버튼 유지.

### E. 위키 본문 참고 (`WikiIndex.swift` 새 파일, 읽기 전용)
- 색인: `<vault>/wiki/**/*.md`, `graphify-out/`·`log.md`·`index.md` 제외. frontmatter의 `courses:`(목록), `type:`, 제목(파일명). 본문 토큰 빈도. 백그라운드에서 한 번 만들고 파일 mtime 바뀌면 다시.
- 고르기: 질의 텍스트 = 질문 + 최근 대본 10분 + 노트 + 자료 앞부분. TF-IDF류 점수, 노트 과목이 `courses`에 있거나 파일명이 과목 허브면 가중치 ×1.5. 상위 4개, 합계 `wikiCap`(기본 40,000자), 페이지당 최대 12,000자.
- 설정: `wikiRefEnabled`(기본 켬), `wikiCap`.
- 쓰기 없음. 열기·읽기만.

### F. 화면 (`MainWindow.swift` 대폭 수정, `Notes.swift`, `VoiceNoteApp.swift`, `SettingsView.swift`)
- **왼쪽 목록**: 프로젝트별 섹션(접기 가능, 펼침 상태 UserDefaults 기억) + 맨 아래 "프로젝트 없음". 섹션 안 노트는 최신순.
  - 노트 행: 상태 아이콘(`StatusIcon`, 녹음 없으면 `note.text` 아이콘), 제목, `날짜 · 총 길이 · 녹음 N개`, 처리 중이면 단계 문구.
  - **끌어다 옮기기**: 노트 행 `.draggable(session.id.uuidString)`, 프로젝트 섹션 머리 `.dropDestination(for: String.self)` → `store.move(session:to:)`. "프로젝트 없음"에도 놓을 수 있게.
  - 노트 우클릭: 이름 바꾸기, 프로젝트로 이동 ▸(목록), 위키로 보내기, Finder(녹음 폴더), 삭제(확인 대화상자 — 녹음 파일은 지우지 않고 목록에서만 뺀다고 명시).
  - 프로젝트 머리 우클릭: 이름 바꾸기, 삭제(노트는 '프로젝트 없음'으로).
  - 아래 막대: `새 노트`, `새 프로젝트`, `파일 가져오기`, 배터리. 처리 중·자료 처리 상태 줄 유지.
- **노트 화면(가운데)**:
  - 머리: 제목 `TextField`(엔터/포커스 잃을 때 `renameSession`), AI 제목 생성 중이면 작은 스피너, 칩들(프로필 메뉴 — 바꾸면 `session.profile`, 프로젝트 메뉴, `용어 힌트 N개` → 시트, 총 길이, 녹음 N개, "위키에 있음"), 버튼(녹음 중이 아니면 `녹음`(녹음 있으면 "이어서 녹음") → `startRecording(into: session.id)`, `위키로 보내기`, `⋯` 메뉴(대본 복사·Finder·내보내기)).
  - **용어 힌트 시트**: 줄바꿈으로 편집하는 TextEditor, 개수, `강의자료에서 다시 뽑기`(AITasks), 상태 문구(`termsNote`), "다음 녹음 처리부터 쓰입니다. 이미 처리된 녹음에 반영하려면 녹음 우클릭 → 다시 처리".
  - 위쪽 영역 `TopPane(session:)`: `[대본 | 자료…]` 탭.
  - **대본(이어 붙인 것)**: 녹음마다 구분 줄 `녹음 N · HH:mm · 길이`(우클릭: 다시 처리, 원본 Finder, 노트에서 빼기). 처리 안 된 녹음은 그 자리에 상태 줄(녹음 중 경과/대기/처리 중 단계/실패+다시 처리). 줄 시각은 누적(`formatTime(line.time)`), 누르면 `seek(session:to:)`. 같은 화자가 이어지면 이름 생략(현재 디자인 유지). 재생 중 줄 강조는 `playPosition(in:)` 기준.
  - 재생 막대: 재생/일시정지(노트의 첫 녹음 또는 현재 위치), 진행 막대·시간은 누적(`playPosition` / `totalDuration`).
  - **화자 칩**: 누르면 현재 재생 위치(없으면 0) 이후 그 화자의 다음 줄로 `seek` + 그 줄로 스크롤. 우클릭 "이름 바꾸기…" → 기존 시트 → `renameSpeaker(session:)`.
  - 아래 노트: `NoteView(session:)` — 시계는 `notePosition(for: session)`, 시각 클릭은 `seek(session:)`. `NoteFile`·`NoteController`는 session id.
  - 오른쪽 `ChatView(session:)`.
- **빈 화면**: "새 노트 만들기"(큰 버튼) + "바로 녹음"(빨간 버튼 → 새 노트로 녹음) + 끌어다 놓기 안내.
- **도구막대**: 다음 노트용 프로필 메뉴(유지), 빨간 녹음 버튼(`startRecording()`), 채팅 접기. 강의자료(책) 버튼 삭제.
- **끌어다 놓기(창 전체)**: 오디오 → 선택한 노트가 있으면 그 노트에 추가(이어 붙임), 없으면 파일마다 새 노트. 자료 → 확인 창.
- **메뉴바**: 녹음 시작/정지, `새 노트`, 프로필, 처리 상태, `VNote 열기`, `파일 가져오기…`, 설정, 종료.
- **설정**: 위키 섹션에 `학기 시작일`(DatePicker, `VaultConfig.semesterStart`), `위키 본문 참고`(토글 + 상한), "위키로 자동 보내기" 토글 삭제(수동 보내기만; `wikiEnabled` 제거). 채팅 섹션에 `자료 페이지 이미지 보내기` 토글.

### G. 위키로 보내기 (`WikiSend.swift` 새 파일) — 형식은 `voice/WIKI_HANDOFF.md` 1절을 그대로 따른다
- 과목: `Courses.course(forProfile: session.profile)`. 없으면 메시지 "노트의 프로필(과목)을 먼저 고르세요".
- 대상: `<vault>/<semester>/<과목>/transcript/<YYYY-MM-DD HHmm> <제목>.session.md`(제목의 `/`·`:` → `-`). 이미 보낸 노트(`wikiPath` 존재)면 같은 파일을 덮어쓴다. 녹음 중이거나 처리 안 된 녹음이 있으면 경고 후 계속할지 묻기(처리된 것만 포함).
- 내용: frontmatter(`type: voicenote-session`, course, title, date, week, language, recordings, duration, `source_paths`(자료 원본의 vault 기준 상대경로; PPT는 원본 .pptx 경로), engine) + `## 내 노트`(노트 파일 원문) + `## 대본` + 녹음마다 `### 녹음 N · HH:mm (m:ss)` + 누적 시각 줄 `[m:ss] 화자: 내용`.
- **감시 폴더 확인**: `<vault>/.agents/skills/source-processor/auto-preprocess.dirs`에 `<semester>/<과목>/lecture`와 `/transcript`가 없으면 확인 대화상자("이 과목은 위키 자동 전처리 감시 대상이 아닙니다. 추가할까요?"). 예 → 두 줄 추가(이미 있는 줄은 건너뜀) → `/bin/bash <…>/scripts/auto_preprocess.sh --init` 실행·종료 대기 → **그 다음에** 묶음 파일 쓰기. 아니오 → 묶음만 쓰고 "자동 전처리되지 않습니다" 안내.
- 쓴 뒤: 보류 목록에서 이 노트 자료 줄 삭제, `session.wikiPath`/`sentAt` 저장, `AutoPreprocess.shared.scheduleAfterWikiSend()`, 로그.

### H. 이름 바꾸기: VNote
- `Info.plist` `CFBundleName`/`CFBundleDisplayName` = `VNote`, 마이크·AppleEvents 설명 문구의 앱 이름. `build.sh` 결과 번들 `build/VNote.app`(실행 파일 이름 `VoiceNote`는 그대로 둬도 됨). 창 제목·메뉴·안내 문구의 "VoiceNote" → "VNote"(데이터 경로 문자열은 제외).
- `voice/README.md` 제목·설명을 VNote와 노트 구조로 갱신. `voice/NOTES_DESIGN.md`에 "노트 구조(프로젝트→노트→녹음)" 절 추가(이 문서 요약). `setup.sh`가 `VoiceNote.app`을 열면 `VNote.app`으로.
- 기존 `build/VoiceNote.app`은 지우지 말고 둔다(사용자가 실행 중일 수 있음). 끝나고 보고에 "새 앱은 build/VNote.app"이라고 적는다.

## 3. 완료 기준

1. `voice/app/build.sh`가 경고 없이(최소한 오류 없이) 성공.
2. sandbox 시험(스크린샷으로 확인):
   - 새 노트 → `--seed-done` 류 디버그로 녹음 2개(같은 노트) 넣기 → 대본이 누적 시각으로 이어져 보이고 구분 줄이 있다. `voice/out/transcript/` 또는 `~/Documents/VoiceNote/transcripts/`의 기존 .md를 복사해 써도 된다(원본 수정 금지). 필요하면 디버그 플래그 `--seed-session <md1>,<md2> --seed-audio <audio>`를 추가.
   - 프로젝트 만들기, 노트를 끌어다 옮기기(또는 우클릭 이동), 앱 재시작 후 유지.
   - 화자 칩으로 다음 발언 이동.
   - 자료 넣기(sandbox, Goodnotes 끔) → 노트에 연결, 보류 목록 기록, 용어 힌트 시트 열림.
   - 위키로 보내기(sandbox vault) → `.session.md` 형식 확인, 감시 목록 추가 흐름(가짜 `auto_preprocess.sh`를 sandbox에 두고 `--init` 호출 여부만 로그로 확인), 보류 줄 삭제.
3. AI 실제 호출 시험 1회씩: 용어 뽑기, 제목, 채팅 질문 1개(위키 참고 칩 표시). 엔진은 사용자 설정(codex)을 쓴다.
4. 커밋(푸시하지 않음). 메시지 끝에 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
5. 보고: 바꾼 파일, 시험 결과(무엇을 확인했고 무엇을 못 했는지), agy 이미지 시험 결과, 남은 문제.
