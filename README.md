# VoiceNote

M1 Max 맥에서 완전히 로컬로 돌아가는 수업·회의 녹음 노트 앱. 지금 쓰는 Alt를 대체하려고 만들었다.

- 받아쓰기: Qwen3-ASR 1.7B(MLX) + 과목별 용어 힌트
- 화자 분리: FluidAudio(pyannote community-1 + VBx, CoreML). 토큰·약관 동의가 필요 없다.
- 출력: 화자 라벨이 붙은 Markdown 대본. LLM 위키의 과목 `transcript/` 폴더로 보내면 위키 쪽 자동 전처리(Gemini)가 이어받는다.
- 노트 + AI 채팅(agy/Gemini, codex/GPT, LM Studio): [NOTES_DESIGN.md](NOTES_DESIGN.md)

왜 이 조합인지는 [BENCHMARK.md](BENCHMARK.md)(Alt·Whisper·sherpa-onnx와 비교), 구조는 [DESIGN.md](DESIGN.md)에 있다.

## 설치

```
./setup.sh          # .venv, FluidAudio 빌드, 앱 빌드
open app/build/VoiceNote.app
```

엔진만 쓸 때:

```
.venv/bin/python voicenote.py transcribe 녹음.m4a [--profile 전력전자] [--speakers N]
```

## 구성

| 경로 | 내용 |
|---|---|
| `voicenote.py` | 엔진: 변환 → 받아쓰기 ‖ 화자 분리 → 합치기 → 힌트 누출 제거 → .md |
| `app/` | SwiftUI 메뉴바·노트 앱 (Xcode 없이 `app/build.sh`) |
| `app/Sources/VoiceNote/AutoPreprocess.swift` | 위키 자동 전처리 스케줄러(위키 쪽 `auto_preprocess.sh`를 앱의 자식 프로세스로 15분마다 실행 — launchd는 Drive TCC에 막혀 대체) |
| `merge.py`, `diarize.py`, `bench_whisper.py` | 벤치마크 때 쓴 스크립트 |

위키 vault 위치는 `~/Library/Application Support/VoiceNote/config.json`의 `vault`(+`semester`) 한 곳에서만 바꾼다(앱 설정의 "위키 vault 경로"에서도 가능). 프로필의 `wiki_dir`은 vault 기준 상대경로다. 확인: `.venv/bin/python voicenote.py show-config`.
