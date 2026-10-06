# VNote 배포판 계획 (2026-10-06)

개인용 VNote(위키 연동)를 **아무것도 모르는 일반 사용자**가 맥과 윈도우에서 쓸 수 있는 앱으로 만든다. 계획과 검토는 Opus가 하고, 구현은 Codex(`gpt-6.1-sol`, medium)가 한다.

## 결정 사항

| 항목 | 결정 |
|---|---|
| 플랫폼 | macOS(Apple Silicon) + Windows 10/11 x64 |
| 받아쓰기·화자 분리 | **로컬, 앱에 포함.** 모델은 Qwen3-ASR(용어 힌트가 핵심). 맥과 윈도우는 엔진만 따로 만든다 |
| 채팅·요약·용어 뽑기 | **사용자의 ChatGPT 구독.** "Sign in with ChatGPT" + Codex app-server를 앱에 넣는다. API 키, agy, LM Studio는 넣지 않는다 |
| 위키 연동 | 배포판에서 뺀다(vault, 위키로 보내기, 자동 전처리, 위키 색인, Goodnotes). 대신 Markdown·텍스트로 내보내기를 넣는다 |
| 화면 | Tauri v2 앱 하나로 맥과 윈도우를 같이 만든다. 지금 SwiftUI 앱(`app/`)은 **개인용으로 그대로 둔다** |
| 서명 | 처음엔 **서명 없이** 배포(Apple Developer $99, 윈도우 인증서 없음). 사용자가 늘면 그때 붙인다 |
| 저장소 | 소스는 지금 비공개 저장소(`DH-WEST-coder/voicenote`)에 둔다. 배포는 **공개 저장소를 따로**(`vnote-releases`, 설치 파일과 안내 문서만) 만든다. 비공개 저장소의 커밋 기록에 개인 경로와 이메일이 있어서 공개로 돌리지 않는다 |

## 구조

```
desktop/ (Tauri: Rust + 웹 UI)
  ├─ 녹음: Rust(cpal)로 마이크 → 16kHz 모노 float32
  ├─ 엔진 sidecar ── JSON 줄 ── 받아쓰기 엔진 (플랫폼별)
  │     맥:     MLX Qwen3-ASR + FluidAudio(CoreML)   ← 지금 voicenote.py
  │     윈도우: Qwen3-ASR(ONNX/GGUF/PyTorch 중 0단계 실측으로 결정) + pyannote community-1
  └─ 채팅 sidecar ── JSON 줄 ── codex app-server (ACCESS_TOKEN = ChatGPT OAuth 토큰)
```

엔진 공통 부분은 플랫폼과 상관없이 같은 코드를 쓴다. 대본 합치기, 힌트 누출 제거, Markdown 출력이 여기에 들어간다. 맥과 윈도우가 다른 건 받아쓰기와 화자 분리를 돌리는 백엔드뿐이다.

## 단계

### 0단계: 사용자 준비 + 윈도우 실측 (구현 전)

**사용자가 할 일** (Codex가 대신할 수 없는 것):
- [ ] Sign in with ChatGPT 클라이언트 ID 신청: [developers.openai.com/siwc](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server)
- [ ] 윈도우 시험 기기: NVIDIA GPU PC 1대 + GPU 없는 노트북 1대. M1의 Parallels(ARM 윈도우)로는 실제 사용 환경을 재현할 수 없다
- [ ] 무료 배포인지 유료 판매인지 정하기

**윈도우 실측** (Codex가 스크립트를 쓰고, 실행은 윈도우 기기에서):
- 받아쓰기 후보 세 가지를 같은 한국어 15분 클립(`audio/2026-10-02` 5~20분)으로 비교한다:
  [ONNX 변환본](https://huggingface.co/OpenVoiceOS/qwen3-asr-1.7b-onnx)(onnxruntime CPU/DirectML), [GGUF](https://huggingface.co/Renesas/Qwen3-ASR-1.7B-GGUF)(llama.cpp), 공식 PyTorch.
  **통과 조건:** ① 용어 힌트(context)가 들어감 ② 단어 단위 타임스탬프가 나옴(화자 분리와 합칠 때 필요. 맥은 aligner를 씀) ③ GPU 없이 15분 클립을 1.7B로 15분 안에 처리. 못 하면 0.6B로 내린다
- 화자 분리: pyannote community-1(PyTorch CPU) 속도를 재고, 맥 FluidAudio 결과(`out/`)와 화자 경계를 비교한다

### 1단계: 엔진 정리 (맥에서 진행, 개인용 앱이 계속 돌아가야 함)
- `voicenote.py`를 `engine/core.py`(합치기, 누출 필터, md 출력), `engine/backend_mac.py`, `engine/backend_win.py`(0단계 결과로 결정), `engine/cli.py`로 나눈다
- 사용자 경로를 코드에서 뺀다(`/Users/DH_WEST`, `DEFAULT_VAULT`). 설정 폴더는 OS 표준 위치에 두고 `platformdirs`로 찾는다. 위키 관련 옵션(`show-config`, `wiki_dir`)은 개인용 플래그가 있을 때만 켠다
- 엔진 메시지 형식을 `ENGINE_PROTOCOL.md`로 고정한다. 지금 쓰는 메시지가 기준이다. 일괄 처리: `convert`/`diarize`/`asr`/`merge`의 `start`·`progress`·`done`, 그리고 `error`, `done`. 실시간: `loading`, `ready`, `partial`, `commit`, `stats`, `error`, `done`
- 모델 경로는 인자로 받는다. 앱이 받아 둔 위치를 넘긴다
- **확인:** 개인용 `app/build/VNote.app`이 새 엔진으로 지금처럼 일괄 처리와 실시간 받아쓰기를 둘 다 해낸다

### 2단계: Tauri 앱 (`desktop/`)
- 데이터 구조는 지금과 같다: 프로젝트 → 노트(수업 1회) → 녹음, 그리고 내 노트, 강의자료(PDF 보기), 채팅, 용어 힌트
- 녹음: 일괄 처리와 실시간 받아쓰기 둘 다 넣는다. 실시간은 0단계 결과에 따라 기기 성능이 될 때만 켠다
- 내보내기: 노트 하나를 `.md`나 `.txt`로
- 넣지 않는 것: 위키, Goodnotes, 자동 전처리, 배터리 측정(맥 전용 ioreg)
- 한국어 UI. 문자열은 나중에 번역할 수 있게 한 파일에 모은다

### 3단계: ChatGPT 연결
- codex 바이너리(Apache-2.0)를 플랫폼별로 넣고 `app-server`를 자식 프로세스로 띄운다. 모델 공급자는 `openai_chatgpt_plan`으로 한다
- 로그인: 브라우저에서 OAuth PKCE(0단계에서 받은 클라이언트 ID) → 루프백으로 돌아옴 → 토큰을 맥 키체인이나 윈도우 자격 증명 관리자에 저장 → 만료되면 갱신하고 app-server를 다시 띄운다
- 모델 목록은 `model/list`로 채운다
- 채팅은 읽기 전용이다. 작업 폴더는 앱 전용 임시 폴더로 하고, 파일 수정을 금지하는 지시를 넣는다. 지금 `Chat.swift`와 같은 규칙이다
- 클라이언트 ID가 나오기 전에는 개발용으로만 codex 자체 로그인(`codex login`)을 쓴다. **이 상태로는 배포하지 않는다**

### 4단계: 첫 실행 순서 (아무것도 모르는 사용자 기준)
1. 환영: 녹음은 이 컴퓨터 안에서만 처리된다고 안내
2. 마이크 권한(맥은 시스템 대화상자, 윈도우는 개인정보 설정 안내)
3. 기기 확인 → 받아쓰기 모델 고르기(1.7B 또는 0.6B) → 다운로드(진행률 표시, 이어받기, 해시 확인, 남은 디스크 공간 확인)
4. "ChatGPT로 로그인"(**건너뛸 수 있음.** 로그인하지 않아도 받아쓰기는 된다) → 브라우저 → 돌아오면 "연결됨"
5. 10초 시험 녹음 → 대본이 나오는지 확인 → 끝
- 설정 화면에 "ChatGPT 연결 해제", "모델 다시 받기", "로그 폴더 열기"를 둔다

### 5단계: 패키징과 배포
- 맥: 엔진을 PyInstaller로 묶는다(MLX를 묶었을 때 실제로 도는지 먼저 확인). `fluidaudiocli`는 미리 빌드해서 넣는다. ad-hoc 서명만 하고 `.dmg`로 낸다. Apple Silicon 전용이고 최소 macOS 버전을 명시한다
  - 첫 실행이 막히면 안내: 시스템 설정 → 개인정보 보호 및 보안 → "그래도 열기"(스크린샷 포함). 지금 macOS 27에서 이 경로가 맞는지 실제로 확인한다
  - ad-hoc 서명은 빌드마다 바뀌어서 업데이트 후 마이크 권한을 다시 물을 수 있다. 안내 문구에 적는다
- 윈도우: 엔진을 묶어서 넣고 NSIS 설치 파일을 만든다. 서명이 없으면 SmartScreen이 막으므로 "추가 정보 → 실행" 안내를 넣는다
- 올리는 곳: 공개 저장소 `vnote-releases`의 GitHub Releases + README(설치 안내, 첫 실행 허용 방법, 라이선스, 개인정보 안내)
- 설치 파일에는 모델을 넣지 않는다. 첫 실행 때 받는다
- 업데이트: 앱이 `vnote-releases`의 최신 릴리스를 확인해서 "새 버전이 있어요"를 띄우고 다운로드 페이지를 연다. 서명이 없으니 자동 설치는 하지 않는다

### 6단계: 법적 사항과 운영
- 라이선스 화면: Qwen3-ASR(Apache-2.0), pyannote community-1(CC-BY-4.0, **출처 표기 필수**, 재배포 가능), FluidAudio(라이선스 확인 필요), codex(Apache-2.0)
- 개인정보 안내: 오디오와 대본은 로컬에 둔다. 채팅에 넣은 대본·노트·자료는 사용자 ChatGPT 계정으로 OpenAI에 간다
- 녹음 동의 안내 문구
- 오류 로그는 로컬에 남기고, 보내기는 사용자가 직접 누를 때만 한다

## Codex 작업 규칙
- `voice/` 안에서만 작업한다. 단계마다 `dist/<단계>` 브랜치에 커밋한다
- **건드리지 말 것:** `app/build/`, `~/Library/Application Support/VoiceNote/`, `~/Documents/VoiceNote/`(사용자 실제 데이터), `audio/`·`out/` 원본(읽기만)
- 시험 출력은 `out/dist-test/` 아래에만 쓴다
- 단계마다 끝나면 무엇을 했는지, 어떻게 확인했는지(실제로 돌린 명령과 결과), 남은 문제를 적어서 보고한다. Opus가 검토한 뒤 다음 단계로 넘어간다

## 열린 질문
- 무료인지 유료인지(유료면 결제와 라이선스 키가 필요)
- 앱 이름(VNote 그대로 쓸지)
- 맥 최소 사양(1.7B 8bit 실시간이면 16GB 이상 권장으로 볼지, 측정 필요)
