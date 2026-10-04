# 구현 계획: 실시간 받아쓰기 (켜고 끌 수 있게)

계획: Opus. 구현: Sonnet. `IMPL_PLAN.md` 0절(환경·제약·시험 규칙)을 그대로 따른다. 앱 이름은 VNote, 결과 번들은 `voice/app/build/VNote.app`.

## 진행 단계 (중요: 전력 측정과 겹침)

지금 사용자가 이 맥에서 **Alt 배터리 측정(약 40분)**을 하고 있다. 측정 중에는 CPU·GPU를 쓰면 결과가 틀어진다.

- **1단계(지금): 코드만 쓴다.** `build.sh`, `swift build`, 파이썬 모델 실행, 모델 다운로드, 앱 실행, 무거운 명령(전체 grep 반복 등)을 하지 않는다. 파일 읽기·쓰기만. 1단계가 끝나면 "1단계 완료"와 무엇을 썼는지 짧게 보고하고 멈춘다.
- **2단계: Opus가 "측정 끝, 2단계 진행" 메시지를 보낸 뒤에만** 빌드·모델 다운로드·시험을 한다.

## 목표

- 녹음하는 동안 대본 초안이 바로바로 뜬다(실시간). **설정에서 켜고 끌 수 있다(기본 켬).** 도구막대에서도 빠르게 켜고 끈다.
- 녹음이 끝나면 지금처럼 정밀본(1.7B + 화자 분리)이 돌아 실시간 초안을 대체한다(실시간을 꺼도 정밀본은 그대로).
- 실시간 대본은 화자 분리 없음.
- 수업 중 AI 채팅·노트 보충·"방금 내용 설명"이 실시간 대본을 맥락으로 쓴다.
- 배터리 비교 시험을 할 수 있게 간격·모델을 설정으로 뺀다.

## A. 엔진: `voicenote.py live`

```
voicenote.py live [--model ID] [--chunk-sec 2.0] [--terms-file F] [--language Korean|English|auto] [--profile 이름]
                  [--input-file 오디오 --realtime]
```

- 기본: stdin으로 **16 kHz 모노 float32 little-endian PCM**을 받는다. `--input-file`이면 그 파일을 16 kHz 모노로 읽어 넣고, `--realtime`이면 실제 시간 속도로 나눠 넣는다(시험·벤치마크용).
- `mlx_qwen3_asr.streaming`의 `init_streaming(model=…, context=" ".join(terms), chunk_size_sec=…, …)`, `feed_audio`, `finish_streaming`을 쓴다. 소스(`voice/.venv/lib/python3.12/site-packages/mlx_qwen3_asr/streaming.py`)를 읽고 정확한 시그니처·상태 필드(`committed_text`, `window_text`, `text`, 창 시작 시각 등)를 확인해서 쓴다. 30초 창 단위 확정(commit) 구조다.
- 출력(stdout, 한 줄에 JSON 하나, flush):
  - `{"type":"ready","model":…}` 모델 로드 끝
  - `{"type":"commit","start":초,"end":초,"text":"확정된 창의 글"}` 창이 확정될 때마다(시각은 녹음 시작 기준)
  - `{"type":"partial","start":초,"text":"지금 창의 임시 글"}` 청크마다
  - `{"type":"stats","audio_sec":…,"proc_ms_avg":…}` 30초마다(성능 기록)
  - `{"type":"done"}`, 오류 `{"type":"error","message":…}`
- 용어·언어는 transcribe와 같은 규칙(프로필 + `--terms-file`, `--language`). 힌트 누출 필터(`find_leaks`)를 확정 글에 적용.
- 기본 모델 `moona3k/mlx-qwen3-asr-0.6b-4bit`(없으면 첫 실행 때 받음, 진행을 `{"type":"loading"}`로 알림). 설정에서 1.7B-8bit 선택 가능.
- stdin EOF → `finish_streaming` → 남은 글 commit → done → 종료.

## B. 앱

- **설정(채팅과 별개 "실시간 받아쓰기" 절)**: 켜기/끄기(`liveEnabled`, 기본 켬), 모델(0.6B 4bit 기본 / 1.7B 8bit), 간격(1·2·3·5초, 기본 2초). 도구막대에 작은 토글 버튼(파형 아이콘, 켜짐/꺼짐 표시). 녹음 중에는 바꿔도 다음 녹음부터.
- **오디오**: 지금 녹음 파일(`AVAudioRecorder`, m4a)은 그대로 둔다(녹음 중 앱이 죽어도 파일 남는 성질 유지). 실시간이 켜져 있으면 `AVAudioEngine` 입력 탭을 따로 열어 16 kHz 모노 float32로 변환(`AVAudioConverter`)해 엔진 stdin에 쓴다. 두 입력이 동시에 되는지 확인하고, 안 되면 `AVAudioEngine` 하나로 파일(AVAudioFile, AAC)과 실시간을 같이 처리하도록 바꾸되 크래시 시 파일 보존(주기적 flush)을 지킨다. 어떻게 했는지 보고.
- **엔진 프로세스**: 녹음 시작 때 `live`를 띄우고(모델 로드 동안 "실시간 준비 중"), 녹음 정지 때 stdin 닫기 → done 기다리기(최대 20초) → 종료. 실패하면 녹음은 계속하고 "실시간 받아쓰기 실패: …" 표시. 처리 큐(정밀본)와 동시에 돌 수 있다(정밀본은 녹음이 끝나야 시작하므로 보통 겹치지 않음).
- **저장**: 실시간 글을 `~/Documents/VoiceNote/transcripts/live/<job id>.md`에 commit마다 덧붙여 저장(`[m:ss] 내용`, 녹음 기준 시각). 앱이 죽어도 남는다. Job에 `liveTranscriptPath`.
- **화면**: 노트 대본에서 녹음 중인 녹음(또는 정밀본이 아직 없는 녹음) 자리에, 실시간 확정 줄들(누적 시각 + 글, 화자 없음)과 마지막에 회색 임시 글(partial)을 보여 주고 자동 스크롤(`TranscriptState.live` 개념 유지). 줄 머리에 작은 "실시간" 표시. 정밀본이 끝나면 정밀본으로 바뀐다(실시간 파일은 지우지 않음).
- **AI 맥락**: `combinedTranscript`/`textLines`가 정밀본이 없는 녹음에 대해 실시간 줄을 쓴다(지시문에 "실시간 초안이라 오인식이 더 많을 수 있다" 한 줄).
- **전력 기록**: 녹음 중 기존 `PowerMonitor` 기록 유지. 엔진 `stats`를 app.log에 남긴다.
- 디버그: `--live-input-file <오디오>`(마이크 대신 파일을 실시간 속도로 넣어 녹음처럼 동작, sandbox 시험용).

## C. 시험 (2단계)

1. 엔진 단독: `voicenote.py live --input-file "~/Documents/2026 10 02.mp3"`의 앞 3분을 `--realtime`으로 → commit/partial이 나오고 처리 속도가 실시간보다 빠른지(stats). 0.6B와 1.7B 각각.
2. 앱 sandbox(`--sandbox`, `--live-input-file`): 녹음 시작 → 실시간 줄이 뜨고 → 정지 → 정밀본으로 교체. 스크린샷 대신 `--snapshot` 플래그로 확인.
3. 실시간 끄기 → 녹음 → 실시간 줄 없이 기존처럼 동작.
4. 실제 마이크 시험은 하지 않는다(사용자가 할 것).
5. 커밋(푸시 안 함), `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. 보고: 바꾼 파일, 시험 결과, 두 입력 동시 사용 결과, 모델별 처리 속도(stats), 남은 문제.

## D. 하지 않는 것

실시간 화자 분리, 실시간 결과로 정밀본 생략, 클라우드.
