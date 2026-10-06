# 배포판 1단계: 엔진 정리 (Codex 작업 지시서)

전체 계획은 [DIST_PLAN.md](DIST_PLAN.md)에 있다. 이 문서는 그중 1단계만 다룬다. 목표는 `voicenote.py` 한 파일을 **플랫폼과 상관없는 공통 부분**과 **맥 전용 백엔드**로 나누고, 윈도우 백엔드가 끼워질 자리를 만드는 것이다. **동작은 바꾸지 않는다.**

## 작업 위치
- 작업 폴더: `/Users/DH_WEST/LocalAI_Project/voice-dist` (git worktree, 브랜치 `dist/1-engine`). **이 폴더 밖은 쓰지 않는다.**
- `.venv`, `vendor`, `audio`는 `../voice/` 쪽을 가리키는 심볼릭 링크다. 읽기만 한다. 패키지는 이미 설치돼 있다: platformdirs, pytest. 새로 설치하지 않는다.
- 사용자가 지금 쓰는 앱은 `../voice/`의 엔진을 쓴다. `../voice/`, `~/Library/Application Support/VoiceNote/`, `~/Documents/VoiceNote/`는 **절대 쓰지 않는다**(읽기는 가능).
- 시험 출력은 `out/dist-test/` 아래에만 쓴다.

## 바꾸면 안 되는 것 (개인용 앱 호환)
개인용 SwiftUI 앱(`app/`)은 엔진을 아래처럼 부른다. 이 명령 형식과 출력은 **그대로** 유지한다.
- `.venv/bin/python voicenote.py transcribe <audio> [--profile] [--speakers] [--out] [--json-progress] [--terms-file] [--language] [--course]`
- `.venv/bin/python voicenote.py live [--model] [--chunk-sec] [--terms-file] [--language] [--profile] [--input-file] [--realtime] [--duration]` (stdin PCM → stdout JSON 줄)
- `.venv/bin/python voicenote.py show-config`
- stdout JSON 메시지의 종류와 필드, 대본 `.md`의 frontmatter와 본문 형식
- 설정 파일 위치: `~/Library/Application Support/VoiceNote/{config.json,profiles.json}`. 맥에서 `platformdirs.user_data_dir("VoiceNote", appauthor=False)`가 바로 이 위치다
- `app/` 안의 Swift 코드는 이번 단계에서 고치지 않는다

## 할 일
1. **구조**
   - `engine/core.py`: 플랫폼과 무관한 것. 프로필·설정 읽기, 용어 처리, 합치기(화자 + 단어 타임스탬프 → 줄), 힌트 누출 제거, `.md` 쓰기, 진행 보고(`Reporter`), 오디오 변환 중 순수 파이썬 부분
   - `engine/backends/base.py`: 백엔드 인터페이스. 최소한 다음이 필요하다: `transcribe(wav, language, terms, on_progress) -> 단어/구간 타임스탬프 목록`, `diarize(wav, speakers) -> 화자 구간 목록`, 실시간용 `live_session(model, terms, language, chunk_sec)`(init/feed/finish). 반환 자료형은 dataclass로 정의한다
   - `engine/backends/mac.py`: 지금의 MLX Qwen3-ASR + aligner + FluidAudio 코드를 옮긴다
   - `engine/backends/win.py`: 인터페이스만 맞춘 자리 표시. 호출하면 `NotImplementedError("윈도우 엔진은 0단계 실측 후 구현")`을 낸다
   - `engine/cli.py`: argparse와 하위 명령. 백엔드는 `sys.platform`으로 고르고, `VNOTE_BACKEND` 환경 변수로 덮어쓸 수 있다
   - `voicenote.py`: `engine.cli.main()`을 부르는 얇은 진입점으로 남긴다(앱이 이 경로를 부른다)
2. **개인 경로 빼기**
   - `DEFAULT_VAULT`(Google Drive 경로와 이메일)와 `DEFAULT_SEMESTER`를 코드에서 지운다. `config.json`이 없거나 `vault`가 비어 있으면 **위키 기능을 끈다**: `wiki_dir` 해석은 `None`을 돌려주고 `show-config`는 "vault 없음"을 출력한다. 오류를 내지 않는다. config.json을 **자동으로 만들지 않는다**
   - 엔진 코드에 `/Users/`가 남아 있지 않아야 한다. 확인: `grep -rn "/Users/" engine voicenote.py` 결과가 없어야 함
   - `PROFILES`, `CONFIG`, `DEFAULT_OUT`은 platformdirs로 정한다. 맥에서는 지금과 같은 경로가 나와야 한다. `DEFAULT_OUT`은 `~/Documents/VoiceNote/transcripts` 그대로
3. **모델·바이너리 경로를 인자로**
   - `transcribe`에 `--asr-model`(기본값은 지금의 `moona3k/mlx-qwen3-asr-1.7b-8bit`)과 `--diarizer-bin`(기본값은 지금의 vendor 경로, 환경 변수 `VNOTE_FLUID_BIN`으로 덮어쓰기)을 추가한다. 둘 다 생략하면 지금과 똑같이 동작한다
   - 대본 frontmatter의 `engine:` 값은 실제로 쓴 모델에서 만든다. 기본값일 때는 지금 문자열과 같아야 한다
4. **`ENGINE_PROTOCOL.md`**: 하위 명령과 인자, stdout JSON 메시지의 종류·필드·순서, 종료 코드, `.md` 형식을 지금 실제로 나오는 그대로 적는다. 아래 기준 출력에서 예시를 가져온다. Tauri 앱과 윈도우 엔진이 이 문서만 보고 맞출 수 있어야 한다
5. **테스트 `tests/`** (pytest, 모델 없이 몇 초 안에 끝나야 함)
   - 합치기: 가짜 단어 타임스탬프와 화자 구간 → 줄 나누기(`MAX_GAP`, `MAX_LEN`), 화자 번호
   - 힌트 누출 제거: 누출 있음/없음/경계(`LEAK_MIN`)
   - 설정: config 없음 → 위키 기능 끔. config 있음 → wiki_dir 해석. 임시 폴더와 환경 변수로 실제 사용자 폴더를 건드리지 않게 한다
   - 백엔드 선택: `VNOTE_BACKEND=win` → NotImplementedError

## 회귀 확인 (반드시 실제로 돌리고 결과를 보고)
기준 출력은 리팩터링 전 엔진으로 미리 만들어 두었다: `out/dist-test/baseline/`
- 대본: `2026-10-06 1424 clip_ko_3min.md`, `2026-10-06 1424 clip_en_2min.md`
- 진행 메시지: `clip_*.progress.jsonl`
- 실시간: `live_ko_30s.jsonl`

명령(새 출력은 `out/dist-test/after/`에):
```
.venv/bin/python voicenote.py transcribe out/dist-test/clip_ko_3min.wav --json-progress --out out/dist-test/after
.venv/bin/python voicenote.py transcribe out/dist-test/clip_en_2min.wav --json-progress --out out/dist-test/after
.venv/bin/python voicenote.py live --input-file out/dist-test/clip_ko_3min.wav --duration 30 > out/dist-test/after/live_ko_30s.jsonl
.venv/bin/python -m pytest -q tests
```
**통과 조건:**
- 대본 `.md`는 `date:`와 `source:` 줄만 빼고 기준과 **똑같아야** 한다(diff로 보여 줄 것)
- 진행 메시지는 `progress` 값을 빼고 종류와 순서가 같아야 한다
- 실시간 출력은 메시지 종류와 순서가 같고 `commit` 텍스트가 같아야 한다(`stats`의 시간 값은 달라도 됨)

처음 aligner를 불러올 때 "Server disconnected"로 실패할 수 있다(HF 다운로드가 일시적으로 끊긴 것). 한 번 다시 돌려 본다. 계속 실패하면 sandbox 네트워크나 Metal 제한일 수 있으니, 코드 문제와 구분해서 보고한다.

## 마무리
- 작업 단위마다 `dist/1-engine` 브랜치에 커밋한다(한국어 메시지). push와 main 병합은 하지 않는다
- `README.md`의 "구성" 표를 새 구조에 맞게 고친다
- 끝나면 보고한다: 바꾼 파일 목록, 회귀 확인에서 실제로 돌린 명령과 결과(diff 포함), pytest 결과, 판단이 필요했던 점, 남은 문제
