# VoiceNote 엔진 프로토콜 (배포판 1단계)

개인용 SwiftUI 앱과 배포판 sidecar가 공유하는 계약. 진입점은 `voicenote.py`.
stdout에는 아래 JSONL 또는 명령별 텍스트만 쓴다. 모델 라이브러리 로그와 진단은 stderr로 보낸다.
JSON은 한 줄에 객체 하나이며 매 메시지마다 flush한다. 키 순서는 계약이 아니다.
일괄 JSON은 `ensure_ascii=False`, 실시간 JSON은 기본 ASCII escape를 사용한다.

## 실행과 종료 코드

```sh
.venv/bin/python voicenote.py transcribe <audio> [옵션]
.venv/bin/python voicenote.py live [옵션]
.venv/bin/python voicenote.py show-config
```

- 성공: `0`. transcribe/live 처리 중 예외(KeyboardInterrupt 포함): JSON `error` 후 `1`.
- argparse 오류(명령 누락, 알 수 없는 인자, 숫자 변환 실패): stderr 사용법, `2`. JSON 없음.
- `--help`: stdout 사용법, `0`.
- show-config의 파일 읽기/프로필 파싱 오류: 일반 Python 오류, `1`. JSON 없음.
- OS 강제 종료나 프로세스 충돌은 JSON `error`를 보장하지 않는다.
- transcribe/live는 `.venv/bin/python`이 존재하고 현재 인터프리터가 다른 환경이면 그 인터프리터로 재실행한다. show-config는 재실행하지 않는다.

백엔드 기본 선택: `sys.platform == 'darwin'`은 `mac`, `'win32'`는 `win`.
`VNOTE_BACKEND=mac|win`으로 덮어쓴다. 다른 플랫폼/값은 처리 오류.
Windows 백엔드 호출은 `NotImplementedError("윈도우 엔진은 0단계 실측 후 구현")`.

## transcribe

| 인자 | 자료형/기본값 | 의미 |
|---|---|---|
| `audio` | 필수 경로 | 입력 오디오. `~` 확장 후 절대경로로 해석 |
| `--profile` | 이름/없음 | 프로필 선택. 이름은 NFC 정규화. 없는 이름은 오류 |
| `--speakers` | int/없음 | FluidAudio `--num-speakers`. 생략 또는 0은 자동 추정 |
| `--out` | 경로/없음 | 출력 폴더. 기본 OS Documents 아래 `VoiceNote/transcripts` |
| `--json-progress` | bool/false | stdout JSONL 활성화 |
| `--terms-file` | 경로/없음 | 한 줄당 용어 하나. 빈 줄 제거. 프로필 용어 뒤에 추가 |
| `--language` | 문자열/없음 | 프로필 언어 덮어쓰기. `auto`는 자동 감지(None). 예: `Korean`, `English` |
| `--course` | 문자열/없음 | frontmatter 과목. 프로필 값을 덮어씀 |
| `--asr-model` | 문자열/`moona3k/mlx-qwen3-asr-1.7b-8bit` | HF 모델 ID 또는 로컬 모델 폴더 |
| `--diarizer-bin` | 경로/환경 변수 또는 vendor 경로 | 인자, `VNOTE_FLUID_BIN`, 프로젝트 `vendor/FluidAudio/.build/release/fluidaudiocli` 순서 |

용어는 대소문자를 무시하고 중복을 제거하며 앞 80개만 사용한다. 언어·용어가 없으면 자동 언어 감지와 빈 context.
화자 분리와 ASR은 동시 실행한다. ASR 단어/구간 타임스탬프와 화자 구간을 공통 로직에서 합친다.

### JSON 메시지

| stage | 추가 필드 | 발생 |
|---|---|---|
| `config` | `vault`: string, `wiki_dir`: string 또는 null | `--profile`이 있을 때만. `wiki_dir` 키가 없는 프로필은 `"-"` |
| `convert` | `status`: `start` 또는 `done` | 변환 전/후 |
| `diarize` | `status`: `start` 또는 `done` | 화자 분리 전/후 |
| `asr` | `status`: `start`, `progress`, `done` | ASR 전/진행/후 |
| `asr` (`progress`) | `progress`: number | 라이브러리 진행률을 정수 퍼센트로 절삭. 퍼센트가 바뀔 때만 출력 |
| `merge` | `status`: `start` | 합치기 시작 |
| `merge` | `status`: `leak_removed`, `count`: int | 힌트 누출 구간을 제거한 경우만 |
| `merge` | `status`: `done`, `lines`: int, `speakers`: int | 파일 쓰기 완료 |
| `done` | `output`: string | 생성된 .md 경로. `--out`이 상대경로면 상대경로 |
| `error` | `message`: string | 예외 문자열. 빈 문자열이면 예외 클래스명. 뒤에 done 없음 |

`progress`는 보통 0~1이며 백엔드 콜백 값을 사용한다. convert/diarize/merge는 숫자 진행률을 내지 않는다.
`config?`, convert start/done 뒤 diarize와 asr가 시작된다. 두 작업의 메시지는 스레드 스케줄에 따라 섞인다.
각 작업 안의 start/progress/done 순서는 유지된다. 둘 다 성공한 뒤 merge start, leak_removed?, merge done, 최종 done.
오류는 실패 지점까지의 메시지 뒤에 온다. ASR 오류도 화자 분리 스레드 종료를 기다린 후 error를 낸다.

기준 `clip_ko_3min.progress.jsonl` 예시(중간 진행 메시지 생략):

```jsonl
{"stage": "convert", "status": "start"}
{"stage": "convert", "status": "done"}
{"stage": "diarize", "status": "start"}
{"stage": "asr", "status": "start"}
{"stage": "asr", "status": "progress", "progress": 0.0}
{"stage": "diarize", "status": "done"}
{"stage": "asr", "status": "progress", "progress": 1.0}
{"stage": "asr", "status": "done"}
{"stage": "merge", "status": "start"}
{"stage": "merge", "status": "done", "lines": 6, "speakers": 2}
{"stage": "done", "output": "out/dist-test/baseline/2026-10-06 1424 clip_ko_3min.md"}
```

`--json-progress`가 없으면 진행은 stderr의 `[stage] key=value ...` 텍스트. stdout에는 성공 시 파일 경로 한 줄만 출력한다.

## live

| 인자 | 자료형/기본값 | 의미 |
|---|---|---|
| `--model` | 문자열/`moona3k/mlx-qwen3-asr-0.6b-4bit` | 실시간 모델 ID 또는 로컬 경로 |
| `--chunk-sec` | float/2.0 | 모델 청크 길이(초) |
| `--terms-file` | 경로/없음 | 프로필 뒤에 용어 추가. 없는 파일은 무시 |
| `--language` | 문자열/없음 | 프로필 덮어쓰기. `auto`는 None |
| `--profile` | 이름/없음 | NFC 정규화. 없는 이름은 빈 프로필로 처리 |
| `--input-file` | 경로/없음 | 시험용. stdin 대신 파일을 16kHz 모노로 변환해 공급 |
| `--realtime` | bool/false | 파일 입력을 오디오 시간에 맞춰 공급. stdin에서는 영향 없음 |
| `--duration` | float/없음 | 파일의 앞 N초만 공급. stdin에서는 영향 없음 |

기본 stdin 입력: **16,000Hz, 모노, float32 little endian, 헤더 없는 PCM**.
최대 `max(1600, int(chunk_sec * 16000 / 2))` 표본씩 읽는다. EOF는 finish 신호.
읽기 경계의 불완전한 4바이트 표본은 다음 읽기에 이어 붙이고, EOF의 잔여 바이트는 버린다.
실시간 모드는 화자 분리/Markdown 파일 생성을 하지 않는다. stdout JSONL은 항상 활성화.

### JSON 메시지

| type | 추가 필드 | 의미 |
|---|---|---|
| `loading` | `model`: string | 모델 로드 직전 |
| `ready` | `model`: string | 초기화 완료. PCM 공급 가능 |
| `partial` | `start`: number, `text`: string | 현재 창의 임시 텍스트. 이전 partial을 대체 |
| `commit` | `start`: number, `end`: number, `text`: string | 확정 텍스트. 대본에 추가 |
| `stats` | `audio_sec`: number, `proc_ms_avg`: number, `chunks`: int | 표본 누적 시간/청크 처리 평균 ms/처리 청크 수 |
| `stats` (최종) | 위 필드 + `final`: true | finish 후 최종 통계 |
| `done` | 없음 | 정상 완료 |
| `error` | `message`: string | 실패. 뒤에 done 없음 |

start/end는 공급 오디오 기준 초, 소수 둘째 자리까지 반올림. audio_sec/proc_ms_avg는 소수 첫째 자리.
partial은 창 텍스트가 바뀔 때만 출력하며 빈 text도 가능하다. commit은 반복/힌트 누출 제거 후 빈 문자열이면 생략한다.
partial은 다음 추론에서 바뀔 수 있다. 원래 창 텍스트를 기준으로 변경을 감지하므로 필터 후 같은 text가 다시 나올 수도 있다.

정상 순서: loading, ready, (commit? 후 partial? 반복, 30초 경계마다 stats), EOF의 commit?, 최종 stats, done.
중간 창 확정은 기존 창 commit 후 새 창 partial. EOF에서 확정되지 않은 tail도 commit으로 출력한다.
오류는 발생 지점 뒤에 error. 모델 초기화 오류는 loading, error만 출력한다.

기준 `live_ko_30s.jsonl`: loading, ready, partial 15회, stats, commit, 최종 stats, done.
기준 파일의 필드 예시:

```jsonl
{"type": "loading", "model": "moona3k/mlx-qwen3-asr-0.6b-4bit"}
{"type": "ready", "model": "moona3k/mlx-qwen3-asr-0.6b-4bit"}
{"type": "partial", "start": 0.0, "text": "\uac8c\ub294 \uc774 \uc2dc\uc810\uc740, \uac8c\uc0c1\uc740 \ubcf4\uba74."}
{"type": "stats", "audio_sec": 30.0, "proc_ms_avg": 457.9, "chunks": 15}
{"type": "stats", "audio_sec": 30.0, "proc_ms_avg": 457.9, "chunks": 15, "final": true}
{"type": "done"}
```

위 예시에는 commit/나머지 partial을 생략했다. 실제 기준 commit 객체는 아래와 같으며 wire에서는 text가 ASCII escape된다.

```json
{"type": "commit", "start": 0.0, "end": 30.0, "text": "예능의 시점은, 게상은 보면은 총 D T가 되게 오퍼레이너의 시점이예요, 그리고는 총 O minus T가 되게 T O이제요, 계산을 할 수 있습니다. 따라서 이 전화 시령을 설정하고 이 전화 시령이 어떻게 되게 D T를 정해서 이제 D T 방안의 전화도 인터파이트를 보면은 저희가 원하는 폰트 전화를 이제 원정을 할 수 있습니다. 따라서 D T 시령으로 저희가 스위치."}
```

## show-config와 설정 경로

stdout은 일반 텍스트. `config: <경로>`, `vault: <vault 또는 vault 없음>`, `semester: <문자열>`,
프로필별 `profile <이름>: wiki_dir=<해석된 경로 또는 None>` 순서. JSON 없음.

`config.json`과 `profiles.json`은 `platformdirs.user_data_dir("VoiceNote", appauthor=False)` 아래.
macOS: `~/Library/Application Support/VoiceNote/`. 기본 출력은 platformdirs의 Documents 아래
`VoiceNote/transcripts`이며 macOS에서는 `~/Documents/VoiceNote/transcripts`.
설정/프로필은 읽기만 한다. config가 없거나 vault가 비어 있으면 wiki_dir은 절대경로여도 None.
config의 semester는 vault 기준 상대경로. 프로필 wiki_dir은 vault 기준 상대경로 또는 절대경로.
프로필 파일이 없으면 메모리의 기본 프로필을 쓴다. 설정 파일을 자동 생성하지 않는다.

## Markdown 파일

입력 **mtime**의 로컬 시각으로 `YYYY-MM-DD HHMM <입력 stem>.md`를 만든다.
이름이 겹치면 ` (2)`, ` (3)` 등을 붙인다. UTF-8 텍스트, LF 줄바꿈.
frontmatter 순서: date, duration, profile, speakers, source, engine, 선택 course와 provenance.
기존 형식 그대로 값을 YAML quoting하지 않는다.

- date: 입력 mtime, `YYYY-MM-DD HH:MM`.
- duration: 변환된 WAV 길이를 정수 초로 절삭한 `분:두자리초`(분은 60 이상 가능).
- profile: 선택 이름 또는 `-`.
- speakers: 누출 제거 후 남은 단어에 등장한 화자 수. 화자 번호는 첫 발화 순서로 1부터 부여.
- source: 원본 오디오 절대경로.
- engine: 모델 ID/경로의 마지막 이름에서 선두 `mlx-`를 제거하고 ` + fluidaudio-offline`을 붙임.
  기본 모델은 `qwen3-asr-1.7b-8bit + fluidaudio-offline`.
- course가 있으면 바로 다음에 아래 provenance 줄도 추가:
  `provenance: VoiceNote 자동 전사(Qwen3-ASR + FluidAudio 화자 분리). 오인식 교정 없음. 화자N 라벨은 자동 추정.`

frontmatter 종료 뒤 빈 줄, 각 발화는 `[시간] 화자N: 본문`과 빈 줄.
시간은 1시간 미만 `분:두자리초`, 이상 `시:두자리분:두자리초`. 소수 초 절삭.
화자가 바뀌거나 같은 화자의 단어 간격이 2초 초과면 줄 분리.
한 줄 60초 초과는 직전 본문이 `.?!`로 끝날 때만 분리.
힌트의 서로 다른 용어 4개 이상이 순서대로 연속 등장하면 누출 구간 제거.

기준 영어 대본의 앞부분(source만 이식 가능한 예시 경로로 교체):

```markdown
---
date: 2026-10-06 14:24
duration: 2:00
profile: -
speakers: 2
source: /path/to/clip_en_2min.wav
engine: qwen3-asr-1.7b-8bit + fluidaudio-offline
---

[0:00] 화자1: Output of VO is calculated by

[0:06] 화자1: average in one period, and the result is
```

## 백엔드 내부 계약

`engine/backends/base.py`의 dataclass가 플랫폼 사이의 경계다.
`transcribe(wav, language, terms, on_progress)`는 원문 `Transcript.text`와
`WordTimestamp(text,start,end)` 목록을 반환한다. 시간 단위는 초. 정렬 결과 또는 ASR 구간을 그대로 전달한다.
`on_progress`는 기존 라이브러리 이벤트 dict를 받으며 CLI가 정수 퍼센트 중복을 제거한다.
`diarize(wav, speakers)`는 `SpeakerSegment(speaker,start,end)` 목록을 반환한다.
`live_session(model,terms,language,chunk_sec)`의 init/feed/finish는 각각 `LiveState` 스냅샷을 반환한다.
chunk_id, committed_text, window_text, buffer_samples, audio_samples를 통해 공통 CLI가
commit/partial 시간과 통계를 계산한다. MLX 객체는 맥 백엔드 밖으로 노출하지 않는다.

## 회귀 비교

`tests/compare_regression.py`는 `out/dist-test/baseline/`과 `after/`를 비교한다.
대본은 date/source 줄만 제외. 일괄은 stage/status 순서, 실시간은 type 순서와 commit text를 비교한다.
진행률·통계 시간·출력 폴더는 비교 대상이 아니다. 결과는 `after/regression.diff`, 통과 0/불일치 1.
병렬 작업의 메시지 교차 순서는 기존부터 비결정적이므로 실제 diff가 있으면 숨기지 않고 보고한다.
2026-10-06 맥(Metal 사용 가능)에서 실행: 한국어·영어 대본은 date/source 외 동일, 실시간 type 순서와 commit text 동일. 영어 진행 메시지에서 asr progress와 diarize done 순서만 바뀜(병렬 처리로 원래 비결정적).

## 배포판 설정 격리와 models (2단계)

`VNOTE_DATA_DIR`가 있으면 config/profiles는 그 폴더, 기본 출력은 그 아래
`transcripts/`를 사용한다. 기본 프로필은 `{}`, 위키는 항상 꺼진다.
개인용(환경 변수 없음) 경로·기본 프로필·JSONL·Markdown 계약은 그대로다.
배포판 transcribe의 `--asr-model` 생략값은 config.json의 `asr_model`이며,
설정이 없으면 기존 1.7B 모델이다. 명시한 인자는 항상 우선한다.

- `models status --json`: `{stage:"models",status:"status",models:[{id,downloaded,size_bytes}]}`.
  ASR 1.7B 8bit, live 0.6B 4bit, Qwen/Qwen3-ForcedAligner-0.6B, FluidAudio를 점검한다.
- `models download --set full|lite --json`: JSONL
  `{stage:"models",status:"download",model,progress,downloaded?,total?}`.
  HF 캐시를 재사용해 이어받는다. full은 1.7B+0.6B+aligner, lite는 0.6B+aligner.
  FluidAudio는 3초 무음으로 준비한다. 모든 준비가 성공한 뒤 config의 asr_model을 원자 저장한다.
  완료 `{stage:"models",status:"done",model_set,asr_model}`; 실패
  `{stage:"models",status:"error",message}`와 종료 코드 1. status 성공은 0.
- HF 캐시는 `HF_HOME/hub` 또는 `VNOTE_DATA_DIR/models/hub`.
  모델 관리에 두 환경 변수가 모두 없으면 오류. 모델을 로드하지 않고 캐시만 점검한다.
