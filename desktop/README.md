# VNote 맥 데스크톱 앱

Tauri v2 + React/TypeScript. 배포판 3단계. 엔진 onedir·FluidAudio·Codex를 묶어 ad-hoc 서명 DMG를 만든다. `app/`의 개인용 SwiftUI 구현과 데이터는 사용하지 않는다.

## Current Work

- **NOW**: 0.1.0 맥 패키징 구현·서명된 앱 검증 완료. DMG 전체 빌드·서명·번들 smoke test 완료. 커밋은 환경 제한으로 미완료.
- **NEXT**: 권한 있는 환경에서 A/B 커밋 및 Opus 실제 Metal·모델·마이크·설치 확인.
- **DONE**: 2단계 UI와 엔진 연결, Opus 다운로드 버그 수정, rustfmt·TSX 정리. pytest 42개·Rust 18개·프런트 빌드 통과.

## 개발 실행

의존성은 준비된 `node_modules`, Cargo 캐시, `.venv-dist`만 사용한다. 설치 명령은 필요 없다. Apple Silicon 맥에서 실행한다.

프로젝트 루트 기준:

```sh
cd /Users/DH_WEST/LocalAI_Project/voice-dist/desktop
VNOTE_DATA_DIR="$(pwd)/../out/dist-test/app-data" \
VNOTE_ENGINE_CMD="'$(pwd)/../.venv-dist/bin/python' '$(pwd)/../voicenote.py'" \
VNOTE_FLUID_BIN="$(pwd)/../vendor/FluidAudio/.build/release/fluidaudiocli" \
npm run tauri dev -- -- --offline
```

`VNOTE_ENGINE_CMD`는 shell로 실행하지 않고 따옴표를 해석해 프로그램·인자로 나눈다. 공백 경로를 위처럼 인용한다. 지정하지 않으면 `<resource_dir>/vnote-engine/vnote-engine`을 실행하고, 없으면 **엔진이 설치되지 않았습니다**를 표시한다. `fluidaudiocli`를 못 찾으면 모델 준비/일괄 처리가 실패한다.

`VNOTE_ENGINE_CMD`는 정식 빌드에도 적용한다. 개발 모드에서는 `VNOTE_DATA_DIR`로 시험 데이터를 프로젝트 안에 둔다. 정식 빌드에서는 이 덮어쓰기를 무시하고 `~/Library/Application Support/VNote`를 쓴다. 개인용 `VoiceNote` 경로는 쓰지 않는다. `HF_HOME`은 앱 데이터의 `models`, 엔진과 Codex의 `TMPDIR`은 앱 데이터의 `tmp`로 지정한다. FluidAudio의 Foundation 홈은 `models/fluid-home`으로 격리한다.

Codex CLI는 준비된 `src-tauri/binaries/codex-aarch64-apple-darwin`을 사용한다. `CODEX_HOME`은 앱 데이터의 `codex`다. 개발 모드만 `VNOTE_CODEX_HOME`을 지원한다. 개발용 로그인은 `codex login`이며 정식 Sign in with ChatGPT 클라이언트는 이후 교체한다.

## 빌드와 테스트

```sh
# desktop/
npm run build
npm run tauri build -- -- --offline

# desktop/src-tauri/
cargo build --offline
cargo test --offline

# 프로젝트 루트
.venv-dist/bin/python -m pytest -q tests
VNOTE_DATA_DIR="$(pwd)/out/dist-test/model-status" \
HF_HOME="$(pwd)/out/dist-test/model-status/models" \
.venv-dist/bin/python voicenote.py models status --json
```

전체 패키징은 프로젝트 루트에서 `scripts/build_mac.sh`로 실행한다. 새 설치 없이 `.venv-dist`, npm/Cargo 캐시, 빌드된 FluidAudio, 기존 Codex 사이드카를 사용한다. `scripts/vnote-engine.spec`는 GPU를 초기화하지 않는 정적 수집으로 MLX·ASR·huggingface_hub를 포함한다. 빌드 임시 폴더는 `dist-build/`다.

타깃은 `aarch64-apple-darwin`만 지원한다. `MACOSX_DEPLOYMENT_TARGET=14.0`과 Cargo offline을 적용한다. `.venv-dist`의 MLX·mlx-metal 0.32.3은 `macosx_14_0_arm64` 휠이어야 하며, 빌드 후 앱의 모든 Mach-O `LC_BUILD_VERSION minos`가 14.0 이하인지 검사한다. 따라서 지원 최소 버전은 macOS 14.0 (Sonoma)이다.

빌드 순서: 엔진 → FluidAudio 사이드카·SwiftPM 리소스 → Tauri app → PyInstaller 원본 symlink 복원 → 모든 Mach-O/프레임워크 ad-hoc 서명 → 번들 엔진 모델 없는 smoke test → 앱 minos 검사 → 수정된 앱으로 DMG 생성·검증 및 마운트 내 symlink 검사. 기본 `hdiutil create`가 디스크 장치 오류로 실패하면 HFS hybrid 파일을 생성하고 UDZO로 변환한다. `--options 0`으로 hardened runtime의 Python dylib Team ID 충돌을 피한다. Apple Developer ID·공증은 없다.

결과: `src-tauri/target/aarch64-apple-darwin/release/bundle/macos/VNote.app`, `src-tauri/target/aarch64-apple-darwin/release/bundle/dmg/VNote_0.1.0_aarch64.dmg`. 사용자 문서·라이선스는 루트 `release/`, 작업 검증·Opus 명령은 `DIST_3_REPORT.md`다.

테스트 출력은 `out/dist-test` 아래에만 만든다. pytest collection 때 OS 설정 경로를 시험 경로로 바꿔 개인용 설정 읽기도 막는다. 실제 MLX 모델은 로드하지 않는다.

## 동작

- 프로젝트 언어/용어와 노트 용어를 합쳐 중복 제거 후 최대 80개를 엔진에 전달한다.
- 마이크의 F32/I16/U16 표본을 16kHz 모노로 리샘플한다. WAV는 16bit PCM, live stdin은 float32 little endian이다.
- 실시간 확정문/임시문을 표시하고 JSONL을 저장한다. 실시간 실패에도 WAV 녹음은 계속한다. 중지 후 단일 일괄 큐에서 정밀본을 만들고 초안을 대체한다.
- 저장된 녹음 순서와 길이로 누적 시각을 계산한다. 가져온 오디오 길이는 hound/맥의 afinfo로 먼저 점검한다. 앱을 종료하면 WAV를 마무리하고 엔진/Codex 프로세스 그룹을 정리한다. 비정상 중단 상태는 다음 시작 때 재처리 가능한 실패로 바꾼다.
- 대본 시각을 누르면 해당 녹음 위치를 재생한다. `convertFileSrc`를 쓰는 자체 `asset` 프로토콜은 canonical 경로로 앱의 `audio/`, `materials/`만 허용한다. Range/HEAD 요청을 처리하고, 미디어 읽기는 별도 스레드에서 한다. 추가 `http-range` crate 없이 구현했다.
- 새 줄에 첫 글자(한글 조합 포함)를 입력하면 현재 녹음/재생의 누적 시각을 붙인다. 텍스트와 채팅 기록은 Rust의 임시 파일·fsync·rename으로 저장한다.
- PDF는 원본을 유지하고 앱 데이터로 복사한다. pdf.js로 페이지를 보여 주고 본문을 추출한다. CJK CMap·표준 폰트·WASM/ICC 자산은 설치된 pdfjs-dist에서 빌드에 포함하므로 CDN 없이 동작한다. 여러 자료의 용어를 함께 추출하며, 채팅 중이면 완료 뒤 실행한다. 스캔 PDF의 OCR은 이번 지시 범위 밖이다.
- 채팅은 읽기 전용 Codex exec JSONL을 사용한다. Swift 참고 구현과 같이 `item.completed/agent_message` 단위로 답을 전달한다. 토큰 단위 이벤트를 지원하지 않는 exec 계약이므로 **메시지 단위 스트리밍**이다. 응답 중지, 답을 노트에 넣기, 로그인 상태 폴링과 로그아웃을 지원한다.
- 채팅 맥락 상한: 대본 60,000자, 자료 40,000자, 내 노트 40,000자, 최근 대화 8개/30,000자. 최근 내용 버튼은 현재 시각의 앞 3분을 사용한다.
- 첫 실행: 개인정보 안내, 마이크, 메모리/디스크와 모델 추천·다운로드/재시도, 로그인/건너뛰기, 완료와 선택적 10초 녹음. 모델 세트는 다운로드와 설정 저장이 성공한 뒤 적용한다.
- `.md`/`.txt` 내보내기는 제목·생성일·내 노트·누적 대본을 포함한다. 화자 표시 이름은 원본 대본을 바꾸지 않는다.
- 업데이트는 하루 한 번 GitHub 최신 릴리스를 확인하고 실패/404는 무시한다. 새 버전은 링크만 열며 자동 설치하지 않는다.
- `logs/app.log`에는 실패 종류, 엔진 stderr 발생/예외 종류/처리 단계만 기록한다. stderr에 대본이나 용어가 섞일 수 있어 원문과 프롬프트는 기록하지 않는다.
- 라이선스 표시는 `src/i18n/ko.ts`에 있다. mlx의 MIT, mlx-qwen3-asr의 Apache-2.0은 설치된 패키지 metadata로 확인했다. FluidAudio는 vendor/LICENSE로 확인했다. pyannote community-1 출처와 저작자 표시를 포함한다.

## 검증 한계와 후속 확인

모델 없는 단위 테스트와 엔진 smoke test만 실행한다. 실제 모델 다운로드·Metal·마이크·GUI·ChatGPT 로그인·온라인 업데이트는 Opus가 확인한다. 서명·DMG와 Git 쓰기 제한의 최종 결과는 `../DIST_3_REPORT.md`에 기록한다. push·병합은 하지 않는다.
