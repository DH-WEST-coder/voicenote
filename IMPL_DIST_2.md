# 배포판 2단계: 맥 Tauri 앱 (Codex 작업 지시서)

전체 계획은 [DIST_PLAN.md](DIST_PLAN.md), 엔진 계약은 [ENGINE_PROTOCOL.md](ENGINE_PROTOCOL.md)에 있다. 이번 단계에서는 **일반 사용자용 맥 앱 VNote**를 `desktop/`(Tauri v2 + React/TS)에 만든다. 패키징(dmg, 엔진 묶기)은 다음 단계에서 하므로, 이번에는 개발 모드(`npm run tauri dev`)와 `npm run tauri build`(번들은 엔진 없이)까지 동작하면 된다.

참고 구현: 개인용 SwiftUI 앱 `app/Sources/VoiceNote/*.swift`. 동작 규칙은 거기서 가져오되 **위키, Goodnotes, 자동 전처리, agy, LM Studio, 배터리 측정은 넣지 않는다.**

## 작업 위치와 금지 사항
- 작업 폴더: `/Users/DH_WEST/LocalAI_Project/voice-dist` (브랜치 `dist/1-engine`). 이 폴더 밖에는 쓰지 않는다.
- `../voice/`, `~/Library/Application Support/VoiceNote/`, `~/Documents/VoiceNote/`(개인용 앱 데이터)는 읽지도 쓰지도 않는다. `app/`(SwiftUI)는 고치지 않는다.
- 이미 준비된 것:
  - `desktop/`: create-tauri-app 뼈대
    - Rust 의존성: cpal, hound, serde_json, tauri-plugin-dialog, tauri-plugin-shell, dirs, uuid, chrono
    - npm 의존성: @tauri-apps/plugin-dialog, @tauri-apps/plugin-shell, pdfjs-dist, react-markdown
    - 캐시가 데워져 있다.
  - `desktop/src-tauri/binaries/codex-aarch64-apple-darwin`: codex-cli 0.160.1 사이드카, gitignore됨
  - `.venv-dist/`: 엔진 전용 venv. mlx-qwen3-asr, platformdirs, huggingface_hub, pyinstaller, pytest가 들어 있다.
- 네트워크가 막혀 있을 수 있다. `cargo build --offline`, `npm`은 설치된 것만 쓴다. 새 crate나 npm 패키지가 꼭 필요하면 추가하지 말고 보고에 적는다(Opus가 설치한다).
- 샌드박스에서는 Metal(GPU)이 안 된다. 모델을 실제로 돌리는 확인은 Opus가 한다. 너는 빌드, 단위 테스트, 모델이 필요 없는 확인까지 한다.

## 데이터 위치 (개인용과 절대 섞이지 않게)
- 앱 데이터: `~/Library/Application Support/VNote/`(`dirs::data_dir()/VNote`)
  - `projects.json`, `notes.json`, `recordings.json`, `settings.json`
  - `notes/<note id>.md`(내 노트), `chats/<note id>.json`
  - `audio/`(녹음 wav), `transcripts/`, `live/`
  - `materials/`(복사해 둔 PDF), `models/`(HF 캐시), `codex/`(CODEX_HOME), `logs/`
- 엔진을 부를 때 환경 변수:
  - `VNOTE_DATA_DIR`: 앱 데이터 폴더
  - `HF_HOME`: `<앱 데이터>/models`
  - `VNOTE_FLUID_BIN`: fluidaudiocli 경로
- 개발 모드 엔진 명령: 환경 변수 `VNOTE_ENGINE_CMD`가 있으면 그걸 쓴다(예: `/…/voice-dist/.venv-dist/bin/python /…/voice-dist/voicenote.py`). 없으면 번들 사이드카 `vnote-engine`을 쓴다. 사이드카는 다음 단계에서 만든다. 지금은 없을 때 "엔진이 설치되지 않았습니다" 오류를 보여 준다.

## 엔진(Python) 추가 작업 (`engine/`)
1. `VNOTE_DATA_DIR`가 있으면 profiles/config 위치를 그 폴더로 바꾼다. 이 경우 **기본 프로필은 비어 있어야 한다**(`_PE_TERMS` 같은 개인 과목 용어가 나오면 안 됨). 위키 기능은 꺼진 상태다.
2. 새 하위 명령 `models`:
   - `models status --json`: 필요한 모델(ASR 1.7B 8bit, 실시간 0.6B 4bit, aligner `Qwen/Qwen3-ForcedAligner-0.6B`, FluidAudio 화자 분리 모델)이 받아져 있는지, 크기는 얼마인지
   - `models download --set full|lite --json`: huggingface_hub로 받는다. 진행률을 JSON 줄로 내고, 다시 실행하면 이어받는다. `lite`면 일괄 처리도 0.6B를 쓴다. FluidAudio 모델은 fluidaudiocli가 처음 실행될 때 스스로 받는다. 그러니 짧은 무음 wav로 한 번 돌려서 미리 받아 둔다.
   - 모델 세트 설정은 `<VNOTE_DATA_DIR>/config.json`의 `"asr_model"`에 저장하고, transcribe의 기본값으로 쓴다.
3. ENGINE_PROTOCOL.md에 이 둘을 추가한다. 기존 명령과 출력은 바꾸지 않는다(개인용 회귀 유지).
4. pytest를 추가한다(모델 없이).

## 앱 기능
화면 3단 구성은 개인용 앱과 같다. 왼쪽 프로젝트·노트 목록, 가운데 대본/자료 + 내 노트, 오른쪽 AI 채팅(접을 수 있음). UI는 한국어로 하고, 문자열은 `src/i18n/ko.ts` 한 파일에 모은다. 깔끔하고 단순하게, 라이트/다크 모두 지원한다.

1. **데이터:** 프로젝트(이름, 언어 Korean/English/auto, 용어 목록) → 노트(제목, 생성일, 녹음 여러 개, 자료, 용어 힌트) → 녹음(wav 경로, 상태, 대본 경로, 실시간 대본 경로, 길이). 여러 녹음은 누적 시각으로 이어 붙여 보여 준다(개인용 `Sessions.swift` 참고). 저장은 Rust 쪽에서 원자적으로 쓴다(임시 파일 후 rename).
2. **녹음:** cpal로 기본 마이크를 연다 → 16kHz 모노로 리샘플 → `audio/<id>.wav`(hound)에 쓴다. 그와 동시에:
   - **실시간 모드(기본 켬):** 엔진 `live` 하위 명령의 stdin으로 float32 PCM을 보내고, stdout의 `partial`/`commit`을 화면에 띄운다. `live/<id>.jsonl`에 저장한다.
   - 녹음을 멈추면 일괄 처리(`transcribe --json-progress --out <transcripts> --terms-file <tmp> --language <lang>`) 작업을 큐에 넣는다. 한 번에 하나씩 처리하고, 진행률을 표시하고, 완료되면 정밀본 대본으로 바꾼다.
   - 녹음 중 경과 시간을 표시한다. 단축키는 넣지 않는다.
   - 마이크 권한 문구는 `Info.plist`의 `NSMicrophoneUsageDescription`(한국어)에 넣는다. 권한이 거부되면 시스템 설정을 여는 안내를 보여 준다.
3. **오디오 파일 가져오기:** 끌어다 놓거나 파일 선택(m4a, mp3, wav 등) → 선택한 노트에 녹음으로 추가하고 일괄 처리한다.
4. **대본 보기:** 화자 라벨과 `[m:ss]` 시각을 보여 준다. 시각을 누르면 그 위치부터 재생한다(HTML audio + `convertFileSrc`, asset 프로토콜 범위는 앱 데이터 폴더로만 제한). 화자 이름은 노트별로 바꿀 수 있다(표시만 바꾸고 원본 md는 그대로).
5. **내 노트:** 텍스트 편집기, 자동 저장. 새 줄을 시작하면 녹음 중이면 경과 시각, 재생 중이면 재생 위치를 `[m:ss] `로 붙인다(개인용 `Notes.swift` 규칙).
6. **자료:** PDF를 끌어다 놓으면 `materials/`로 **복사**한다(원본은 그대로). 가운데 "자료" 탭에서 pdf.js로 보여 주고, 본문 텍스트를 뽑아 채팅 맥락에 쓴다.
7. **AI 채팅(ChatGPT):**
   - 사이드카 `codex`를 `CODEX_HOME=<앱 데이터>/codex`로 실행한다. 개발 때만 환경 변수 `VNOTE_CODEX_HOME`으로 덮어쓸 수 있다.
   - 호출 인자는 개인용 `Chat.swift`의 codex 경로와 같다: `exec --json -s read-only --skip-git-repo-check --ephemeral -c model_reasoning_effort="low" -C <scratch> [-m model] -`, 프롬프트는 stdin. `item.completed`/`agent_message` 파싱도 같다. 작업 폴더는 `<앱 데이터>/chat-scratch`.
   - 맥락은 이어 붙인 대본(상한 있음) + 자료 텍스트(상한 있음) + 내 노트 + 이전 대화 + 지시다. 지시문은 개인용 `Chat.swift`의 시스템 지시에서 위키 관련 내용만 빼고 가져온다.
   - 빠른 버튼: "방금 내용 설명"(최근 3분), "지금까지 노트 초안", "모르는 용어 찾기". 답변마다 "노트에 넣기" 버튼을 단다.
   - 스트리밍하고 중지할 수 있다. 채팅 기록을 저장한다.
   - **용어 힌트:** 자료를 붙이면 채팅 엔진에게 PDF 텍스트에서 전공 용어를 뽑게 해서 노트 용어에 넣는다(개인용 `AITasks.swift` 참고, 최대 80개). 프로젝트 용어와 합쳐서 `--terms-file`로 넘긴다.
   - 로그인하지 않았으면 채팅 패널에 "ChatGPT로 로그인" 버튼을 보여 준다.
8. **ChatGPT 로그인:** `codex login`을 같은 CODEX_HOME으로 실행한다(브라우저가 열림). `codex login status`를 몇 초마다 확인해서 "연결됨"으로 바꾼다. 설정에 "연결 해제"(`codex logout`)를 둔다. 정식 Sign in with ChatGPT 클라이언트 ID로 바꾸는 건 나중 일이다. 그러니 로그인 부분은 모듈 하나(`src-tauri/src/chatgpt.rs`)로 모아서 교체하기 쉽게 만든다.
9. **첫 실행 순서**(설정에 완료 표시가 없으면 띄움):
   1. 환영: "녹음은 이 맥 안에서만 처리돼요. AI 채팅을 쓸 때만 대본과 노트가 내 ChatGPT 계정으로 OpenAI에 보내져요."
   2. 마이크 권한
   3. 기기 확인(Apple Silicon, 메모리, 남은 디스크) → 모델 세트 추천(메모리 16GB 이상이면 full, 아니면 lite) → `models download` 진행률 표시. 실패하면 다시 시도할 수 있다.
   4. ChatGPT 로그인(건너뛰기 가능)
   5. 끝(테스트 녹음은 선택)
10. **내보내기:** 노트 하나를 `.md`(제목, 날짜, 내 노트, 대본) 또는 `.txt`로 저장한다(저장 대화상자).
11. **설정:** 모델 세트 바꾸기/다시 받기, 실시간 모드 기본값, ChatGPT 연결 상태와 연결 해제, 데이터 폴더 열기, 로그 폴더 열기, 라이선스 보기, 버전.
12. **업데이트 확인:** 시작할 때 `https://api.github.com/repos/DH-WEST-coder/vnote-releases/releases/latest`를 조회한다. 지금 버전보다 새로우면 배너를 띄우고 "다운로드" 버튼으로 페이지를 연다. 실패하거나 404면 조용히 넘어간다. 하루에 한 번만 확인한다.
13. **라이선스 화면:** Qwen3-ASR(Apache-2.0), Qwen3-ForcedAligner(Apache-2.0), mlx / mlx-qwen3-asr(확인한 라이선스), FluidAudio(Apache-2.0), pyannote community-1(CC-BY-4.0, 출처 표기), Codex CLI(Apache-2.0), Tauri(MIT/Apache-2.0).
14. **로그:** `logs/app.log`에 엔진 stderr와 오류를 남긴다. 개인 대본 내용은 로그에 넣지 않는다.

## 구조 가이드
- Rust 모듈: `storage.rs`(모델·저장), `audio.rs`(cpal 녹음, 리샘플, wav), `engine.rs`(엔진 실행, 큐, JSON 줄 파싱 → Tauri 이벤트), `chatgpt.rs`(codex 로그인/채팅), `updates.rs`, `lib.rs`(커맨드 등록)
- 프런트: 화면별 컴포넌트, 상태는 간단한 store(React context 또는 zustand 없이 직접)
- `tauri.conf.json`:
  - productName은 `VNote`, identifier는 `com.vnote.app`
  - `bundle.externalBin`에 `binaries/codex`를 넣는다. 엔진 사이드카는 다음 단계에서 추가한다.
  - capabilities는 필요한 것만 연다(shell sidecar codex, dialog, opener).

## 확인 (실제로 돌리고 보고)
- `cd desktop && npm run build`(tsc + vite) 성공
- `cd desktop/src-tauri && cargo build --offline` 성공, `cargo test --offline` 통과. 리샘플, 저장 원자성, JSON 줄 파서, 대본 md 파서, 누적 시각 계산에 대한 단위 테스트를 넣는다.
- `.venv-dist/bin/python -m pytest -q tests` 통과
- 엔진 회귀: 1단계의 개인용 출력 형식이 그대로인지 `tests/`로 확인한다.

## 마무리
- 작업 단위마다 한국어 메시지로 커밋한다(push와 병합 금지).
- `desktop/README.md`에 개발 실행 방법을 적는다(`VNOTE_ENGINE_CMD` 예시 포함).
- 보고: 만든 기능 목록, 실제로 돌린 확인 명령과 결과, 빠지거나 대충 한 부분(정직하게), Opus가 GPU로 확인해야 할 항목 목록.
