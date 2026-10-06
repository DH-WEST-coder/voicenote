# 배포판 A/B 검증 보고 (2026-10-06)

작업 폴더: `/Users/DH_WEST/LocalAI_Project/voice-dist`, 브랜치 `dist/1-engine`, 시작 커밋 `c85976a`.

## A — Opus 검토 수정

- `engine/models.py`: 스냅샷 완료 기준을 `config.json` + (`tokenizer.json` 또는 `vocab.json`·`merges.txt`) + 0바이트가 아닌 가중치로 수정. 기존 shard index·끊어진 symlink 검사 유지.
- FluidAudio: 필수 모델이 모두 있으면 종료 코드 1의 `noSpeechDetected`도 성공. 필수 파일이 없으면 종료 코드와 stderr 마지막 줄을 오류에 포함. 상태 조회와 준비 완료 판정에 같은 함수를 사용.
- 다운로드 전체 성공 후 `asr_model` 원자적 저장. 실제 가짜 실행 파일이 종료 코드 1을 반환하는 full/lite 성공과 종료 코드 0/1의 파일 누락 실패를 회귀 테스트. 실패 때 이전 설정 유지.
- 실제 ASR 두 개·aligner 파일 목록 테스트, 0바이트 가중치·tokenizer 부분 누락 검사 추가.
- `cargo fmt` 적용. TSX 긴 JSX 줄바꿈·들여쓰기 정리. 기존 TypeScript 컴파일러로 생성 JS AST의 동일성을 확인했고 프런트 빌드 출력 JS 해시도 동일.

실행 결과:

| 명령 | 결과 |
|---|---|
| `.venv-dist/bin/python -m pytest -q tests` | 42 passed |
| `cargo fmt --manifest-path desktop/src-tauri/Cargo.toml` | 성공 |
| `cargo test --offline` (`desktop/src-tauri`) | 18 passed |
| `npm run build` (`desktop`) | 성공 |
| `git diff --check` | 성공 |

## B — 맥 패키징 구현

- `scripts/build_engine.sh`, `scripts/vnote-engine.spec`: 준비된 `.venv-dist`로 PyInstaller arm64 onedir 생성. `dist-build/`에 작업·캐시·임시 파일을 두고 `desktop/src-tauri/resources/vnote-engine/`에 복사. 결과 엔진 약 319MiB.
- spec은 MLX·mlx-qwen3-asr·huggingface_hub 모듈을 **파일 목록에서 정적으로 수집**. `collect_all`은 이 환경에서 MLX 모듈을 import하며 Metal 초기화 및 nanobind 중복 등록으로 실패했다. 정적 수집은 같은 모듈·데이터·dylib를 import 없이 수집한다. SoundFile의 네이티브 라이브러리는 PyInstaller hook으로 포함.
- `scripts/build_sidecars.sh`: 기존 FluidAudio 바이너리와 SwiftPM 데이터 번들 복사. 기존 Codex 사이드카 포함. 생성 리소스·바이너리는 gitignore.
- `engine.rs`: `VNOTE_ENGINE_CMD`가 있으면 사용, 없으면 `<resource_dir>/vnote-engine/vnote-engine`. FluidAudio는 번들 `Contents/MacOS/fluidaudiocli`. `VNOTE_DATA_DIR`, `HF_HOME`, `TMPDIR` 전달 유지.
- Tauri `bundle.resources`, `externalBin`, ad-hoc signingIdentity `-`, macOS 최소 14.0 설정. 마이크 한국어 설명은 기존 `Info.plist`에서 번들에 들어간 것 확인.
- `scripts/sign_app.sh`: PyInstaller 원본 엔진의 symlink를 앱 리소스에 복원한 뒤 모든 Mach-O·프레임워크·SwiftPM 리소스 번들을 안쪽부터 ad-hoc 서명. `--options 0`으로 PyInstaller hardened runtime의 Python dylib Team ID 로딩 충돌 해결.
- `scripts/build_mac.sh`: 엔진 → 사이드카 → Tauri app → symlink 복원·서명 → 모델 없는 번들 smoke test → Mach-O minos 검사 → 서명한 앱으로 DMG 생성·검증. DMG를 읽기 전용 마운트해 앱 엔진 symlink도 원본과 비교한다. Tauri DMG 보조 스크립트 실패 때 app 빌드를 별도로 재검증. 기본 `hdiutil create`가 장치 오류로 실패하면 **HFS hybrid 파일 생성 후 UDZO 변환**으로 완료한다.
- `package.json`, `Cargo.toml`, `tauri.conf.json` 모두 기존 0.1.0 일치 확인. 업데이트 확인은 `app.package_info().version` 사용.
- `release/README.md`, `release/LICENSES.md`, `release/licenses/`, `release/images/README.md`: 사용자 설치·모델·연결·개인정보·문제 해결, 모델 출처/변환 표시, pyannote CC-BY-4.0, Python/npm/Cargo 및 FluidAudio 내장 구성 요소 고지. `scripts/generate_licenses.py`는 로컬 metadata에서 재생성.
- `scripts/opus_verify.sh`: 실제 모델·Metal 확인 명령. 여기서는 실행하지 않음.

최소 OS 근거: 준비된 `.venv-dist`의 MLX·mlx-metal 0.32.3 WHEEL 태그가 `macosx_14_0_arm64`이며, 빌드 스크립트가 앱 안 모든 Mach-O의 `LC_BUILD_VERSION minos`를 14.0 이하로 검사한다. 최소 지원 OS는 **macOS 14.0 (Sonoma)**이다. 빌드 스크립트는 호환 휠을 자동 설치하지 않으며 태그가 다르면 수동 설치 방법을 안내하고 실패한다.

## 실제 패키징 결과

- `scripts/build_mac.sh`: **종료 코드 0**, 전체 성공(`dist-build/build-mac-final.log`). 내부 Tauri app/dmg·hdiutil create 실패는 파일 기반 fallback으로 해결.
- 최종 DMG: **259,725,352 bytes (약 247.69MiB)**. `hdiutil verify`의 CRC32 검증 **VALID**.
- DMG SHA-256: `e0e39ce2790839bf5c1791e5880414ccb85fa07cefa39d53613fa1efb6bc5424`.
- 앱 파일 합계: 약 598.7MiB. 엔진 약 319MiB. 모델 가중치 미포함.

- 앱: `desktop/src-tauri/target/aarch64-apple-darwin/release/bundle/macos/VNote.app`
- DMG: `desktop/src-tauri/target/aarch64-apple-darwin/release/bundle/dmg/VNote_0.1.0_aarch64.dmg`
- `codesign --verify --deep --strict --verbose=2 <app>`: 통과. 별도 전수 검사에서 Mach-O 192개 모두 ad-hoc, 개별 `codesign --verify --strict` 통과.
- 실제 번들 엔진 `--help`, `models status --json`: 종료 코드 0. 빈 시험 캐시에서 모델 네 개 모두 `downloaded:false`, 0 bytes인 정상 결과. 개인용 데이터는 사용하지 않음.
- B 코드 변경 후 `cargo test --offline`: 18 passed. pytest 재실행: 42 passed. 프런트 빌드 성공.
- 로그: `dist-build/build-mac-final.log`, `dist-build/sign-app-final.log`, `dist-build/python-tests.log`, `dist-build/rust-tests.log`, `dist-build/bundle-help.log`, `dist-build/bundle-status.json`, `dist-build/macho-audit.json`.

초기 실패와 해결:

1. PyInstaller `collect_all` MLX import 실패: 정적 모듈 수집으로 해결.
2. PyInstaller `codesign_identity='-'`의 hardened runtime 때문에 Python dylib 로딩 실패: PyInstaller 자동 ad-hoc와 후처리 `--options 0`으로 해결.
3. 실행 파일 옆의 unsigned SwiftPM 데이터 번들을 codesign이 코드로 오인: `Contents/Resources` 최상위에 배치·리소스 번들 서명으로 해결.
4. Tauri `bundle_dmg.sh` 실패, `hdiutil create`의 `장치가 구성되지 않았음`: app 재검증 및 `makehybrid -hfs` → `convert -format UDZO`로 해결.
5. `diskutil image`는 DiskManagement framework 접근 불가, `hdiutil imageinfo`도 장치 오류. 생성·변환·checksum 검증에는 성공하는 파일 기반 경로를 사용.

## Git 커밋 — 환경 제한으로 미완료

A와 B 각각 `git add`·한국어 메시지 `git commit`을 직접 실행했으나 모두 다음 오류로 실패했다.

```text
fatal: Unable to create '/Users/DH_WEST/LocalAI_Project/voice/.git/worktrees/voice-dist/index.lock': Operation not permitted
```

설정상 허용된 `.git` 경로에 짧은 시험 파일을 직접 생성하는 것도 같은 권한 오류였다. 커밋 없음. 시작 HEAD와 브랜치는 유지. push·병합 없음. A만 분리한 patch는 `dist-build/A-opus-fixes.patch`에 보존했다.

Git 쓰기가 가능한 환경에서 현재 작업 트리 그대로 두고 실행:

```sh
cd /Users/DH_WEST/LocalAI_Project/voice-dist
git diff --cached --quiet
git apply --cached dist-build/A-opus-fixes.patch
git commit -m 'fix: 모델 다운로드 완료 판정과 코드 가독성 수정'
git add README.md desktop scripts release DIST_3_REPORT.md
git commit -m 'build: 맥 엔진 번들과 서명·DMG 배포 추가'
```

## Opus 확인 명령

실제 시험용 한국어 3분·영어 2분 오디오 경로를 전달한다. 캐시·출력은 worktree의 `out/dist-test/opus-packaged`에만 생성한다. 기존 개인용 `VoiceNote` 및 `../voice/` 작업 파일은 사용하지 않는다.

```sh
cd /Users/DH_WEST/LocalAI_Project/voice-dist
scripts/build_mac.sh
scripts/opus_verify.sh '/시험/한국어3분.wav' '/시험/영어2분.wav'
```

## 2026-10-06 후속 수정 및 재검증

- `scripts/engine_symlinks.py`: PyInstaller 원본의 모든 symlink를 번들 앱에 복원하고, 최종 DMG 마운트본에서 상대 경로·symlink 상태를 검사한다.
- `scripts/build_engine.sh`: MLX·mlx-metal WHEEL 태그가 `macosx_14_0_arm64`인지 확인한다. 다르면 수동 wheel 준비·설치 명령을 안내하고 종료한다. 자동 설치/네트워크 사용은 없다.
- `scripts/check_app_minos.py`: 앱 내 Mach-O의 `LC_BUILD_VERSION minos`가 14.0 이하인지 검사한다.
- `scripts/build_mac.sh`, `scripts/sign_app.sh`, `scripts/opus_verify.sh`: symlink 복원 후 서명, DMG 생성 뒤 읽기 전용 attach 및 검증, Opus 검증도 DMG 안 앱에서 진행하도록 변경.
- `tauri.conf.json`, 배포/개발 README의 최소 지원을 macOS 14.0 (Sonoma)으로 수정.

실행 결과:

| 명령 | 결과 |
|---|---|
| `scripts/build_mac.sh` | 부분 실패: 앱 빌드·ad-hoc 서명·모델 없는 smoke test·189개 Mach-O minos 검사·DMG 생성·CRC 검증 통과. 마지막 `hdiutil attach -readonly -nobrowse`에서 `장치가 구성되지 않았음`으로 종료 코드 1. DMG 내부 symlink 검사는 이 환경에서 실행 불가. |
| `scripts/engine_symlinks.py check dist-build/engine/vnote-engine <앱>/Contents/Resources/vnote-engine` | 통과, 원본 symlink 2개 일치. |
| `.venv-dist/bin/python -m pytest -q tests` | 42 passed. |
| `cargo test --offline` (`desktop/src-tauri`) | 18 passed. |
| DMG `hdiutil verify` | CRC32 유효. 크기 225,764,846 bytes. |

DMG: `desktop/src-tauri/target/aarch64-apple-darwin/release/bundle/dmg/VNote_0.1.0_aarch64.dmg`. 이 실행 환경에서 이미지 attach가 막혀 DMG 안 링크 검사와 `opus_verify.sh`의 Metal·실제 모델 검증은 완료하지 못했다. Opus가 attach 가능한 맥에서 재검증해야 한다.

`opus_verify.sh`가 실행하는 명령: 번들 모델 full 다운로드·status, config의 선택 모델·모든 다운로드 완료 확인, 한국어·영어 일괄 처리와 화자 분리, 한국어 앞 30초 live. 생성 대본·JSONL을 이전 Opus 기준과 비교한다. 경량 세트도 확인하려면 같은 격리 환경에서 `models download --set lite --json` 후 config 모델이 0.6B인지 확인한다.

실제 마이크·GUI·ChatGPT 로그인·온라인 업데이트·DMG 마운트/설치·첫 실행 차단 해제는 여기서 검증하지 않았다. 이 환경에서는 디스크 장치 접근 자체가 불가하므로 DMG 설치 확인은 일반 맥에서 필요하다. 정식 GUI는 새 배포판 `VNote` 앱 데이터를 생성하므로 본 작업 범위 안에서 실행하지 않았다. Apple Developer ID·공증 없음(ad-hoc).

## 격리 누락 기록

원본 CLI의 `live --help`, `transcribe --help` 옵션 조회 두 번에서 `VNOTE_DATA_DIR`를 누락했다. `engine.core`의 기본 프로필 초기화는 `load_config()`를 호출하므로 개인용 설정의 존재 여부 조회 및 파일이 있으면 읽기가 실행될 수 있다. 개인 파일 존재/내용을 추가로 확인하지 않았다. 이 두 명령은 파일 쓰기를 하지 않는다. 이후 smoke test·패키징 확인·Opus 명령은 전부 worktree 시험 폴더로 격리했다. 개인용 파일에 대한 쓰기·변경은 하지 않았다.
