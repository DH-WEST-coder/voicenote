# VNote (옛 이름 VoiceNote)

M1 Max 맥에서 완전히 로컬로 돌아가는 수업·회의 녹음 노트 앱. 구조는 프로젝트 → 노트(수업 1회) → 녹음: 노트 하나에 녹음 여러 개, 내 노트, 강의자료, AI 채팅, 용어 힌트가 모이고, 노트 단위로 위키에 보낸다. 지금 쓰는 Alt를 대체하려고 만들었다.

- 받아쓰기: Qwen3-ASR 1.7B(MLX) + 과목별 용어 힌트
- 화자 분리: FluidAudio(pyannote community-1 + VBx, CoreML). 토큰·약관 동의가 필요 없다.
- 출력: 화자 라벨이 붙은 Markdown 대본. 노트의 "위키로 보내기"를 누르면 노트 묶음(`*.session.md`: 내 노트 + 이어 붙인 대본 + 자료 경로)이 과목 `transcript/`로 가고 위키 쪽 자동 전처리가 이어받는다(형식: [WIKI_HANDOFF.md](WIKI_HANDOFF.md)).
- 노트 + AI 채팅(agy/Gemini, codex/GPT, LM Studio): [NOTES_DESIGN.md](NOTES_DESIGN.md)

왜 이 조합인지는 [BENCHMARK.md](BENCHMARK.md)(Alt·Whisper·sherpa-onnx와 비교), 구조는 [DESIGN.md](DESIGN.md)에 있다.

## 설치

```
./setup.sh          # .venv, FluidAudio 빌드, 앱 빌드
open app/build/VNote.app
```

엔진만 쓸 때:

```
.venv/bin/python voicenote.py transcribe 녹음.m4a [--profile 전력전자] [--speakers N]
```

## 구성

| 경로 | 내용 |
|---|---|
| `voicenote.py` | 앱 호환 엔진 진입점 (`engine.cli.main`) |
| `engine/cli.py` | 기존 CLI·JSONL, 백엔드 선택, 일괄·실시간 처리 순서 |
| `engine/core.py` | 설정·프로필, 합치기, 힌트 누출 제거, Markdown, 진행 보고 |
| `engine/backends/base.py` | 백엔드·실시간 세션 인터페이스와 dataclass |
| `engine/backends/mac.py` | MLX Qwen3-ASR·aligner, FluidAudio, afconvert |
| `engine/backends/win.py` | 0단계 실측 전 Windows 자리 표시 |
| `ENGINE_PROTOCOL.md` | CLI 인자·JSONL·종료 코드·Markdown 계약 |
| `tests/` | 모델 없는 pytest와 기준 출력 비교 도구 |
| `app/` | SwiftUI 메뉴바·노트 앱 (Xcode 없이 `app/build.sh`) |
| `app/Sources/VoiceNote/AutoPreprocess.swift` | 위키 자동 전처리 스케줄러(위키 쪽 `auto_preprocess.sh`를 앱의 자식 프로세스로 15분마다 실행 — launchd는 Drive TCC에 막혀 대체) |
| `merge.py`, `diarize.py`, `bench_whisper.py` | 벤치마크 때 쓴 스크립트 |

위키 vault 위치는 `~/Library/Application Support/VoiceNote/config.json`의 `vault`(+`semester`) 한 곳에서만 바꾼다(앱 설정의 "위키 vault 경로"에서도 가능). 프로필의 `wiki_dir`은 vault 기준 상대경로다. 확인: `.venv/bin/python voicenote.py show-config`.


## Current Work

- **NOW**: 0.1.1 HF XET 기본 비활성화로 `.incomplete` 바이트 진행률·이어받기 개선. 온보딩 테스트 녹음은 일반 시작/정지 경로 재사용, 실패 오류 표시. pytest 45개·Rust 20개·프런트 빌드 통과; 앱 번들과 DMG 생성·검증 완료(샌드박스에서 attach 실패).
- **NEXT**: Opus가 설치본에서 실제 네트워크 다운로드와 온보딩 테스트 녹음 GUI 확인.
- **DONE (2026-10-06)**: 0.1.0 배포 구성·문서·라이선스 및 검증.
