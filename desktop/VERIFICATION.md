# 배포판 2단계 검증 보고

브랜치: `dist/1-engine`. 기존 `a558438` 및 미커밋 코드를 이어서 구현했다. 검증일: 2026-10-06.

## 만든 기능

- Rust 저장 모델과 원자 저장, 중단 복구, 필드별 메타데이터 갱신.
- cpal 녹음, 16kHz 모노 리샘플, WAV, live PCM/JSONL, 실시간 초안, 단일 정밀본 큐/진행률/재시도, 종료 정리.
- 프로젝트·노트 목록과 언어·용어 편집, 여러 녹음의 누적 시각, 화자 표시 이름, 오디오 가져오기/끌어 놓기, 대본 위치 재생.
- 타임스탬프가 붙는 자동 저장 노트, PDF 복사/페이지 보기/본문 추출, 여러 자료의 AI 용어 추출·대기 처리.
- Codex 읽기 전용 채팅과 상한 있는 맥락, 빠른 질문, 메시지 스트리밍/중지/기록/노트 삽입. 개발용 로그인·상태 폴링·로그아웃을 별도 모듈에 격리.
- 첫 실행 5단계, 모델 추천/진행률/재시도, 로그인 건너뛰기, 선택적 10초 녹음.
- Markdown/텍스트 내보내기, 라이트/다크, 설정/폴더 열기/라이선스/버전, 하루 한 번 업데이트 확인.
- 앱 내부 미디어만 허용하는 asset 프로토콜, Range/HEAD 처리, 대본을 제외한 로그.
- 엔진 FluidAudio 캐시 격리, HF tokenizer·가중치 shard 완전성 점검, 모델 없는 테스트, 개인용 계약 회귀 유지.

## 실제 실행과 결과

| 명령·확인 | 결과 |
|---|---|
| `cd desktop && npm run build` | 성공. tsc + vite. PDF 코드는 별도 청크, CMap/폰트/WASM/ICC 자산 포함 |
| `cd desktop/src-tauri && cargo build --offline` | 성공 |
| `cd desktop/src-tauri && cargo test --offline` | **18 passed** |
| `.venv-dist/bin/python -m pytest -q tests` | **35 passed**. 개인용 일괄/실시간/Markdown 계약 테스트 포함 |
| `cd desktop && npm run tauri build -- -- --offline` | 성공. **VNote.app 238.70 MiB**, 엔진 없이 Codex 포함 |
| 프로젝트 안의 `VNOTE_DATA_DIR`/`HF_HOME`으로 `models status --json` | 성공. 필요한 4개 모델을 미설치/0 byte로 보고. 모델 로드 없음 |
| 같은 시험 폴더로 `show-config` | 성공. 프로젝트 내부 config 경로, vault 없음, 기본 프로필 없음 |
| Foundation 경로 확인 (`CFFIXED_USER_HOME`, 프로젝트 내부 Swift module cache) | Application Support가 지정한 시험 홈 아래로 이동함을 확인 |
| `/bin/kill -TERM -- -<시험 프로세스 그룹>` | 성공. 실제 macOS 프로세스 그룹 종료 구문 확인 |
| 빌드된 PDF 보조 자산 확인 | 한국어 CMap·표준 폰트·폰트 라이선스·WASM·ICC 존재 확인 |
| 번들 Info.plist와 MacOS 바이너리 확인 | identifier, 한국어 마이크 권한 문구, Codex 포함/엔진 미포함 확인 |
| `git diff --check` | 성공 |
| `git diff --name-only -- app` | 비어 있음. Swift 참고 구현 수정 없음 |

빌드 산출물: `desktop/src-tauri/target/release/bundle/macos/VNote.app`.
빌드 로그: `out/dist-test/frontend-build.log`, `out/dist-test/tauri-build.log`.

## 빠지거나 실제 확인하지 못한 부분

- `npm run tauri dev -- --no-watch -- --offline`은 Vite의 `listen EPERM ::1:1420`으로 실패했다. `TAURI_DEV_HOST=127.0.0.1`도 1420/1421에서 같은 오류였다. 샌드박스가 로컬 포트 열기를 차단해 개발 UI는 실행 확인하지 못했다.
- 실제 마이크/오디오 재생/한글 조합/PDF 화면 검증, Metal 모델 실행, 온라인 모델 다운로드·이어받기, ChatGPT 로그인/응답, 실제 GitHub 업데이트 조회는 확인하지 않았다.
- Codex exec 계약과 Swift 구현에 맞춘 **메시지 단위 스트리밍**이다. 토큰 단위 스트리밍으로 포장하지 않았다.
- 로그는 stderr 원문을 보존하지 않는다. 대본 누출 방지를 위해 발생/예외 종류/처리 단계와 실패 종류만 남긴다.
- 스캔 PDF의 OCR, 엔진/FluidAudio 번들, DMG, 정식 Sign in with ChatGPT 클라이언트는 이번 지시 범위 밖이며 구현하지 않았다.
- 새 crate/npm 의존성은 추가하지 않았다. `rustfmt`가 설치되지 않아 실행하지 못했다.
- **작업 단위별 커밋은 못 했다.** `git add`가 worktree 바깥 `../voice/.git/worktrees/voice-dist/index.lock` 생성에서 `Operation not permitted`로 거부됐다. 작업 폴더 밖 쓰기를 하지 않고 변경을 작업 트리에 보존했다. push/병합도 하지 않았다. README에 커밋 단위와 한국어 메시지를 기록했다.
- 작업 중 나타난 미추적 `IMPL_DIST_3.md`는 읽거나 수정하지 않았다.

## Opus가 일반 맥/GPU로 확인할 항목

1. 프로젝트 내부 `VNOTE_DATA_DIR`로 개발 UI 시작. 라이트/다크, 3단 화면, 프로젝트/노트 편집, 화자 이름 변경.
2. 마이크 허용/거부 및 시스템 설정 안내, 10초 시험 녹음, WAV 헤더/길이, 44.1/48kHz 장치의 리샘플.
3. full/lite 다운로드, HF 이어받기, FluidAudio의 격리된 캐시 생성과 상태 표시, 모델 전환/실패 시 기존 설정 유지.
4. MLX 실시간 partial/commit과 일괄 화자 분리/aligner. live 실패 때 녹음 지속, 정밀본 대체, 단일 큐/재시도, 종료 후 복구.
5. 여러 녹음/가져온 m4a·mp3의 누적 시각과 재생 seek, 노트의 녹음/재생 시각, 한글 첫 자모 입력.
6. 한글·영어·그림/수식 PDF의 페이지/본문 추출, 여러 자료 용어 추출/채팅 중 대기, 용어가 실제 ASR context에 반영되는지.
7. 격리 CODEX_HOME의 브라우저 로그인, 연결 상태, 질문/빠른 버튼/중지/노트 삽입/대화 저장/로그아웃.
8. 내보낸 md/txt의 날짜·누적 시각·화자 표시, 설정 폴더·라이선스, 최신/404/오프라인 업데이트 동작.
9. 실제 한국어/영어·실시간 입력으로 1단계 기준과 회귀 비교. 이번에는 모델 없는 계약 테스트만 실행했다.
