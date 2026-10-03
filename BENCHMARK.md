# 음성 노트 벤치마크 (2026-10-03)

Alt(현재 쓰는 로컬 음성 메모 앱)를 대체할지 판단하려고 실제 녹음 두 개로 비교했다. M1 Max 32GB.

- `week5-1`: 영어 전력전자 강의(정류기), 84.7분, 교수 1명 + 학생 짧은 대답
- `2026-10-02`: 한국어 PWM·전류제어 발표와 질의응답, 66.1분, 발표 학생 2명 + 교수 + 대답하는 학생들

## 받아쓰기

| 엔진 | 영어 85분 | 한국어 66분 | 품질 |
|---|---|---|---|
| Alt | (측정 안 함) | (측정 안 함) | 30초 조각 경계에서 단어가 붙거나 잘림(`rememberThe`). 중간에 수십 초씩 빠진 구간 있음 |
| Qwen3-ASR 1.7B 8bit | 4.4분 (19배속) | 4.8분 (14배속) | Alt보다 조금 나음(온/오프, S1·S2 정확). 전공 용어는 둘 다 틀림(듀티→DTV, 적분기→접종기) |
| **Qwen3-ASR + 용어 힌트(`--context`)** | – | 5.4분 (12배속) | **확실히 나음.** 듀티비 2→17회, 적분기·PI 제어기·안티 와인드업·PLECS 인식. 단 힌트 목록이 대본에 한 번 그대로 새어 나옴 → 걸러야 함 |
| Whisper large-v3-turbo (MacWhisper 대용) | 5.3분 (16배속) | 4.5분 (15배속) | 41분대에서 `a a a … t t t` 환각, 끝부분에 "감사합니다"를 지어내고 뒤 내용을 놓침. 일부 구어체는 더 자연스러움 |

## 화자 분리 (모두 토큰·약관 동의 필요 없음)

| 엔진 | 영어 85분 | 한국어 66분 | 품질 |
|---|---|---|---|
| sherpa-onnx (pyannote seg-3.0 + WeSpeaker, 단순 군집, CPU) | 14.5분 | 12.0분 | 영어는 좋음(학생 대답 분리). 한국어는 나쁨: 교수가 화자1·2로 번갈아 쪼개지고 발표자와 교수가 섞임 |
| **FluidAudio offline (pyannote community-1 + VBx, CoreML)** | **44초** | **22초 (184배속)** | 한국어: 발표자1 / 교수 / 대답한 학생들 / 다음 발표자로 맞게 나뉨. 경계 몇 군데만 틀림. 영어: 교수 1명으로만 잡음(학생 대답 놓침) |

## 결론

- **조합: Qwen3-ASR 1.7B + 과목별 용어 힌트 + FluidAudio.** 한 시간짜리 녹음 처리에 약 6분.
- **직접 만든다.** MacWhisper Pro(59달러)는 Whisper 기반이라 환각 위험이 있고, 과목별 용어 힌트로 한국어 전공 용어를 고치는 게 핵심 이득인데 그걸 못 한다. 파이프라인은 이미 돌아가므로 남은 건 녹음·목록·내보내기 UI뿐이다.
- 정리는 로컬에서 하지 않는다. 화자 라벨이 붙은 Markdown 대본을 Gemini 전처리 폴더로 넘긴다.
- Whisper는 쓰지 않는다(환각). sherpa-onnx 화자 분리는 FluidAudio로 대체.

## 재현

```
voice/.venv/bin/mlx-qwen3-asr audio/X.wav --model moona3k/mlx-qwen3-asr-1.7b-8bit --timestamps -f json -o out/asr_ctx --context "용어 목록"
voice/vendor/FluidAudio/.build/release/fluidaudiocli process audio/X.wav --mode offline --output out/diar_fluid/X.raw.json
voice/.venv/bin/python merge.py X out/asr_ctx
```

결과물: `out/transcript/`(`*.sherpa.md`는 sherpa-onnx 화자 분리판).
