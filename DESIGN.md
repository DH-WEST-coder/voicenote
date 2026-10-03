# VoiceNote 설계 (Alt 대체 앱)

근거: [BENCHMARK.md](BENCHMARK.md). 목표는 Alt처럼 "녹음 → 자동 받아쓰기"가 되는 로컬 맥 앱이다. 여기에 **화자 분리**와 **과목별 용어 힌트**를 더한다. 정리(요약)는 하지 않고, 화자 라벨이 붙은 Markdown 대본을 Gemini 전처리 폴더로 넘긴다.

## 구성

두 부분으로 나눈다. 엔진은 앱 없이도 터미널에서 돌아가야 한다.

### 1. 엔진: `voice/voicenote.py` (파이썬 CLI, `voice/.venv` 사용)

```
voicenote.py transcribe <오디오 파일> [--profile 이름] [--speakers N] [--out 폴더] [--json-progress]
```

순서:
1. **변환:** 어떤 형식(m4a, mp3, wav 등)이든 `afconvert -f WAVE -d LEI16@16000 -c 1`로 임시 16kHz 모노 WAV를 만든다. ffmpeg는 쓰지 않는다.
2. **받아쓰기:** `mlx-qwen3-asr`, 모델 `moona3k/mlx-qwen3-asr-1.7b-8bit`, `--timestamps -f json`. 프로필에 용어가 있으면 `--context "용어 목록"`을 붙인다. 프로필에 언어가 있으면 `--language`도 붙인다. 가능하면 CLI 대신 파이썬 API를 쓴다(패키지 소스 확인).
3. **화자 분리:** `vendor/FluidAudio/.build/release/fluidaudiocli process <wav> --mode offline --output <json>`. `segments[].speakerId/startTimeSeconds/endTimeSeconds`를 읽는다. `--speakers`를 주면 그에 맞는 옵션을 찾아 넘긴다(fluidaudiocli 소스 확인). 2·3단계는 서로 독립이라 동시에 돌려도 된다(ASR은 GPU, FluidAudio는 ANE).
4. **합치기:** 기존 `merge.py`의 로직(원문 띄어쓰기 복원, 단어별 화자 겹침 판정, 2초 쉼·60초 길이 기준으로 줄 나누기)을 모듈로 옮겨 재사용한다.
5. **힌트 누출 제거:** 용어 힌트 목록이 대본에 그대로 새어 나오는 경우가 있다(실측 1회). 프로필 용어가 원래 순서대로 연속 4개 이상 나오는 구간은 지운다.
6. **출력:** `<출력 폴더>/<YYYY-MM-DD HHmm> <제목>.md`

```markdown
---
date: 2026-10-02 14:00
duration: 66:05
profile: 전력전자
speakers: 4
source: <원본 오디오 경로>
engine: qwen3-asr-1.7b-8bit + fluidaudio-offline
---

[0:00] 화자1: …

[1:44] 화자2: …
```

- `--json-progress`: 단계마다 stdout에 JSON 한 줄씩 출력한다(`{"stage":"asr","status":"start"}`, `{"stage":"done","output":"..."}`, 실패 시 `{"stage":"error","message":"..."}`). 앱이 이걸 읽어 진행 상황을 표시한다.
- 실패하면 0이 아닌 종료 코드를 반환한다. 임시 파일은 정리한다.

### 프로필: `~/Library/Application Support/VoiceNote/profiles.json`

```json
{
  "전력전자": {"language": "Korean", "terms": ["PWM", "듀티비", "캐리어", "적분기", "PI 제어기", "안티 와인드업", "..."]},
  "Power Electronics (EN)": {"language": "English", "terms": ["freewheeling diode", "rectifier", "Fourier series", "harmonics", "ripple"]}
}
```

처음 실행할 때 위 두 개를 기본값으로 만든다. 전력전자 용어는 벤치마크에서 쓴 목록을 그대로 쓴다:
`전력전자 PWM 듀티 듀티비 캐리어 삼각파 스위칭 주파수 인덕터 리플 RL 부하 역기전력 전향 보상 PI 제어기 적분기 안티 와인드업 연속 제어 이산 제어 샘플링 피크 밸리 Simulink PLECS 서브시스템 트리거 레그 암 단락 데드타임`

### 2. 앱: `voice/app/` (SwiftUI 메뉴바 앱)

**제약:** 이 맥에는 Xcode가 없고 Command Line Tools(Swift 6.4)만 있다. SwiftPM 실행 파일로 빌드하고, 스크립트(`app/build.sh`)로 `VoiceNote.app` 번들(Info.plist에 `NSMicrophoneUsageDescription`, `LSUIElement=true`)을 조립한 뒤 ad-hoc 서명(`codesign -s -`)한다. macOS 14 이상을 대상으로 한다.

기능(Alt처럼 동작):
- **메뉴바 아이콘:** 녹음 시작/정지, 녹음 중이면 경과 시간 표시, 단축키(⌥⌘R)로 토글
- **녹음:** AVAudioRecorder, AAC m4a 모노 48kHz. `~/Documents/VoiceNote/recordings/`에 저장한다. 녹음 중 앱이 죽어도 파일이 남게 한다.
- **자동 처리:** 녹음이 끝나면 엔진을 백그라운드 프로세스로 실행한다. 큐를 둬서 한 번에 하나씩 처리한다. 진행 단계를 표시한다.
- **가져오기:** 기존 오디오 파일을 창이나 메뉴바 아이콘에 끌어다 놓으면 큐에 들어간다.
- **목록 창:** 녹음 목록(날짜, 길이, 상태: 대기/처리 중/완료/실패). 항목을 고르면 대본을 보여 준다. 대본에서 시간을 누르면 그 위치부터 재생한다.
- **화자 이름 바꾸기:** "화자2 → 교수님"처럼 바꾸면 .md 파일에 반영한다.
- **녹음 전 프로필 선택:** 메뉴바에서 고른다(마지막 선택 기억).
- **내보내기:** 완료된 대본을 설정한 "Gemini 전처리 폴더"로 자동 복사한다(설정에서 켜고 끄기, 폴더 지정). 기본값은 꺼짐이다. 대본은 항상 `~/Documents/VoiceNote/transcripts/`에 저장한다.
- **설정:** 엔진 경로(기본 `/Users/DH_WEST/LocalAI_Project/voice`), 내보내기 폴더, 프로필 편집(JSON 파일을 Finder에서 열기 정도면 충분).

하지 않는 것: 실시간 받아쓰기, 요약, 클라우드 전송, 앱 안에서 모델 다운로드 UI(첫 실행 시 엔진이 자동으로 받음).

## 수용 기준

1. `voicenote.py transcribe "~/Documents/2026 10 02.mp3" --profile 전력전자` 실행 → 10분 안에 화자 4명 안팎의 .md가 생기고, 힌트 목록 누출이 없다.
2. `week5-1.mp3`를 영어 프로필로 실행해도 같은 형식으로 나온다.
3. `app/build.sh` 실행 → `VoiceNote.app`이 만들어지고, 실행하면 메뉴바에 뜬다.
4. 앱에서 10초 녹음 → 자동 처리 → 목록에 완료로 표시되고 대본이 보인다.
5. mp3 파일을 끌어다 놓으면 처리된다.
