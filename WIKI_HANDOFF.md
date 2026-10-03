# LLM Wiki 쪽 수정 요청 (VoiceNote 노트 묶음 전처리)

아래를 LLM Wiki 에이전트에게 그대로 전달한다.

---

## 0. VoiceNote와 위키가 어떻게 연동되는지 (전체 그림)

VoiceNote는 이 맥에서 도는 수업 녹음·노트 앱이다(코드: `/Users/DH_WEST/LocalAI_Project/voice`). 위키 vault 위치는 VoiceNote 설정 `~/Library/Application Support/VoiceNote/config.json`의 `vault`·`semester` 한 곳에서 읽는다.

| 방향 | 무엇을 | 위키 경로 | 언제 |
|---|---|---|---|
| 앱 → 위키 (쓰기) | 강의 PDF·PPT 원본 이동 | `<과목>/lecture/` | 수업 시작 때 학생이 다운로드에서 끌어다 놓으면 |
| 앱 → 위키 (쓰기) | 보류 목록 한 줄 추가/삭제 | `<과목>/lecture/.voicenote-hold` | PDF를 노트에 넣을 때 / 노트를 보낼 때 |
| 앱 → 위키 (쓰기) | 노트 묶음 `.session.md` | `<과목>/transcript/` | 수업 끝나고 학생이 "위키로 보내기"를 누르면 |
| 앱 → 위키 (쓰기·실행) | 감시 폴더 추가: `auto-preprocess.dirs`에 그 과목 `lecture`·`transcript` 두 줄 추가 후 `auto_preprocess.sh --init` | `.agents/skills/source-processor/` | 감시 목록에 없는 과목의 노트를 처음 보낼 때, 학생 확인 후. `--init`은 묶음 파일을 쓰기 **전에** 돌린다(묶음이 '본 것'으로 기록되지 않게) |
| 앱 → 위키 (실행) | `auto_preprocess.sh` | `.agents/skills/source-processor/scripts/` | 앱이 켜져 있는 동안 15분마다, 보내기 직후 한 번 더 |
| 위키 → 앱 (읽기 전용) | `wiki/` 개념·공식·과목 페이지 | `wiki/**/*.md` (`graphify-out/`, `log.md` 제외) | 수업 중 AI 채팅 질문마다 관련 페이지 3~4개를 맥락으로 넣음. frontmatter `courses:`로 과목 우선 |
| 위키 → 앱 (읽기 전용) | `course-prefixes.md` | `.agents/skills/source-processor/` | 과목 이름 확인 |

- 앱이 위키에 쓰는 것은 위 네 가지(`lecture/` 원본, `.voicenote-hold`, `transcript/*.session.md`, `auto-preprocess.dirs` 줄 추가)뿐이다. `wiki/`와 `.agents/cache/`는 읽기만 하고 고치지 않는다. 앱의 AI 채팅 엔진(agy·codex)도 읽기 전용 샌드박스로 돈다.
- 수업 중 AI는 전처리 캐시가 아니라 그 수업 PDF 원본과 `wiki/` 본문을 참고한다. 전처리는 수업이 끝난 뒤 노트 묶음 단위로 한 번 한다.
- 그러니 `wiki/` 페이지의 frontmatter `courses:`와 과목 허브 이름이 지금처럼 일관되게 유지되면 앱 쪽 참고 품질이 좋아진다. 형식을 바꾸게 되면 알려 줘.

## 요청

VoiceNote(수업 녹음 노트 앱)가 이제 "수업 1회 = 노트 1개" 단위로 위키에 보낸다. 노트 하나에는 녹음 여러 개의 대본, 학생이 쓴 노트, 그 수업에 넣은 강의 PDF가 묶여 있다. 이것을 전처리 캐시 **하나**(extracted 1개 + processed 1개)로 만들 수 있게 `source-processor`를 고쳐 줘. 기존 2계층 규칙(원문 보존형 extracted, 정보 보존형 processed, provenance·마커 보존, 외부 지식 금지, raw 불변)은 그대로 유지한다.

## 1. VoiceNote가 보내는 파일

- 위치: `raw/05_UNIST/07_3학년 가을학기/<과목>/transcript/<YYYY-MM-DD HHmm> <제목>.session.md`
- 같은 노트를 다시 보내면 같은 파일을 덮어쓴다.
- 형식:

```markdown
---
type: voicenote-session
course: 전력전자
title: 전력전자 6주차 · 전파 정류기
date: 2026-10-05 10:30
week: 6
language: Korean          # Korean | English | auto(한·영 혼합)
recordings: 2
duration: 74:10
source_paths:             # 이 수업에 넣은 강의 PDF (vault 기준 상대경로)
  - raw/05_UNIST/07_3학년 가을학기/전력전자/lecture/Lecture_Note4_Full-Wave_Rectifiers.pdf
engine: qwen3-asr-1.7b-8bit + fluidaudio-offline
---

## 내 노트
[12:34] 학생이 수업 중에 쓴 메모 (시각은 아래 대본과 같은 누적 시각)

## 대본
### 녹음 1 · 10:30 (52:10)
[0:00] 화자1: …
### 녹음 2 · 11:25 (22:00)
[52:10] 화자1: …      ← 녹음 2부터는 앞 녹음 길이를 더한 누적 시각
```

## 2. 수업 중 PDF를 따로 전처리하지 않기 (보류 목록)

학생은 수업 시작할 때 PDF를 `<과목>/lecture/`에 넣는다. 지금 `auto_preprocess.sh`는 15분마다 돌아서, 수업 중에 그 PDF를 단독으로 전처리해 버린다. 수업이 끝나고 노트 묶음과 함께 한 번만 처리해야 한다.

- VoiceNote는 아직 보내지 않은 노트에 연결된 PDF 이름을 `<과목>/lecture/.voicenote-hold`에 한 줄에 하나씩(`파일명<TAB>추가한 날짜 YYYY-MM-DD`) 적고, 노트를 보내면 그 줄을 지운다.
- `auto_preprocess.sh`는 `.voicenote-hold`에 있는 PDF를 건너뛴다. 단, 추가한 날짜로부터 14일이 지난 줄은 무시하고 평소처럼 처리한다(노트를 끝내 안 보낸 경우 대비).

## 3. `auto_preprocess.sh` 수정

- 한 번 실행할 때 `*.session.md`를 PDF보다 **먼저** 처리한다. 노트 묶음 캐시의 frontmatter `source_paths`에 PDF 파일명이 들어가므로, 그 뒤 PDF 차례에서는 기존 `already_cached` 검사로 자연스럽게 건너뛰어진다. 이 동작이 실제로 그렇게 되는지 확인해 줘(파일명 NFC/NFD 차이 포함).
- `*.session.md`용 작업 지시(`kind_note`)를 새로 만든다. 기존 `*.md` transcript 지시보다 먼저 매칭되게 한다.
- 캐시 파일명: `<과목 prefix>_session_<YYYY-MM-DD>_<영문_slug>` (prefix는 course-prefixes.md).

## 4. `SKILL.md`에 노트 묶음(session) 처리 규칙 추가

- `source_kind: mixed`, frontmatter는 `source_paths: [<session.md 경로>, <PDF 경로들>]`. PDF의 `source_page_count`는 PDF별로 기록한다(예: `source_page_counts: {파일명: N}`).
- **extracted.md** 구성: 원본별 절로 나눈다.
  1. `## 강의자료: <파일명>` — 기존 PDF 규칙 그대로(`<!-- PDF_PAGE: n -->` 마커, Visual Landmark 등).
  2. `## 대본` — 기존 VoiceNote transcript 규칙 그대로(원래 언어, timestamp 단위, 번역·요약 금지, 화자 라벨 유지). 녹음 경계(`### 녹음 N`)를 보존한다.
  3. `## 학생 노트` — 원문 그대로. 학생이 쓴 것이므로 강의 내용과 구분되는 **학생 작성(student-authored)** 상태로 둔다(Preserve epistemic status). 노트의 질문·추측을 사실로 바꾸지 않는다.
- **processed.md**: 기존 "Mixed (슬라이드 PDF + 전사본)" 전략을 따른다. 대본 설명을 슬라이드 페이지와 매핑하고(`[mm:ss] ↔ p.N`), 학생 노트 항목은 `[학생 노트]`로 표시해 대본·슬라이드 근거와 연결한다. 노트와 대본·자료가 어긋나면 `[Source inconsistency]`로 남긴다.
- 기존 단독 PDF·단독 transcript 처리 규칙은 바꾸지 않는다. "여러 원본을 합칠 때는 사용자가 요청한 경우만 한다"에 `.session.md`는 사용자가 미리 요청한 묶음으로 본다는 예외를 적는다.

## 5. 확인 후 알려 줄 것

- 바꾼 파일 목록과 요약
- `.session.md` 시험 파일 하나로 `auto_preprocess.sh --dry-run` 결과(어떤 순서로 무엇을 처리/건너뛰는지)
- 캐시 파일명 예시
