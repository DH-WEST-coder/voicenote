# 배포판 3단계: 맥 패키징 (Codex 작업 지시서)

2단계에서 만든 `desktop/` 앱을 **엔진까지 들어 있는 서명 없는 `.dmg`**로 만든다. 사용자는 dmg를 받아 앱을 Applications에 끌어 넣고, 첫 실행 때 한 번 "그래도 열기"를 누르면 끝이어야 한다.

작업 위치와 금지 사항은 IMPL_DIST_2.md와 같다(voice-dist 밖 쓰기 금지, 개인용 데이터 접근 금지, 네트워크 없을 수 있음, Metal 실행 확인은 Opus가 함).

## 이미 확인한 것 (Opus 실측, 2026-10-06)
아래 명령으로 묶은 엔진(onedir, 319MB)이 Metal에서 일괄 처리와 실시간 모두 기준과 같은 결과를 냈다.
```
.venv-dist/bin/pyinstaller --noconfirm --onedir --name vnote-engine \
  --collect-all mlx --collect-all mlx_qwen3_asr --collect-data soundfile \
  --copy-metadata mlx-qwen3-asr voicenote.py
```
2단계에서 엔진에 추가된 모듈(`engine/models.py`의 huggingface_hub 등)도 묶이도록 필요한 `--collect`/`--hidden-import`를 더한다.

## 할 일
1. **`scripts/build_engine.sh`**
   - `.venv-dist`로 위 PyInstaller를 돌리고, 결과를 `desktop/src-tauri/resources/vnote-engine/`에 넣는다(onedir, gitignore).
   - 빌드 폴더는 `dist-build/` 아래에 둔다.
   - PyInstaller spec 파일(`scripts/vnote-engine.spec`)로 고정해서 다시 만들 수 있게 한다.
2. **fluidaudiocli 넣기**
   - `vendor/FluidAudio/.build/release/fluidaudiocli`를 `desktop/src-tauri/binaries/fluidaudiocli-aarch64-apple-darwin`으로 복사한다. 스크립트 `scripts/build_sidecars.sh`가 하게 하고, gitignore한다.
   - `externalBin`에 추가한다.
3. **앱이 번들 엔진을 쓰게**
   - `VNOTE_ENGINE_CMD`가 없으면 `<resource_dir>/vnote-engine/vnote-engine`을 실행한다.
   - `VNOTE_FLUID_BIN`은 번들 fluidaudiocli 사이드카 경로로 넘긴다.
   - `HF_HOME`/`VNOTE_DATA_DIR`은 2단계 규칙대로 넘긴다.
   - `tauri.conf.json`의 `bundle.resources`에 엔진 폴더를 넣는다.
4. **서명과 dmg**
   - `bundle.macOS.signingIdentity = "-"`(ad-hoc), `minimumSystemVersion`은 mlx가 요구하는 버전(확인해서 적기).
   - 앱 안의 모든 실행 파일과 dylib(엔진 폴더 포함)이 ad-hoc 서명되어 `codesign --verify --deep --strict`를 통과해야 한다. 필요하면 번들 후 서명 스크립트를 넣는다.
   - `Info.plist`에 `NSMicrophoneUsageDescription`(한국어)을 넣는다.
   - 대상은 `aarch64-apple-darwin`만이다.
   - 전체 빌드 스크립트 `scripts/build_mac.sh`: 엔진 → 사이드카 → `npm run tauri build -- --bundles app,dmg` → 서명 확인. 결과 dmg 경로를 출력한다.
5. **버전**: 0.1.0. `package.json`, `Cargo.toml`, `tauri.conf.json`을 맞추고, 앱의 업데이트 확인이 이 값을 쓴다.
6. **배포 저장소용 문서** `release/` (아직 올리지 않음. 나중에 공개 저장소 `vnote-releases`에 그대로 복사할 내용)
   - `release/README.md`(한국어, 아무것도 모르는 사용자 기준)
     - VNote가 뭔지 세 줄
     - 요구 사항: Apple Silicon 맥, macOS 버전, 메모리 권장, 디스크(모델 포함 대략 크기)
     - 설치: dmg 열기 → Applications로 끌기 → 처음 열 때 막히면 시스템 설정 → 개인정보 보호 및 보안 → "그래도 열기". 스크린샷 자리는 `images/`에 파일명만 정해 둔다.
     - 업데이트 후 마이크 권한을 다시 물을 수 있다는 안내
     - ChatGPT 연결 방법(로그인, 구독 한도에서 차감됨, 연결 해제)
     - 개인정보: 무엇이 로컬에 남고 무엇이 OpenAI로 가는지
     - 녹음 동의 안내
     - 라이선스 목록
     - 문제 해결: 엔진 오류, 모델 다시 받기, 로그 폴더 위치
   - `release/LICENSES.md`: 포함된 구성 요소별 라이선스 전문 또는 링크. pyannote community-1은 CC-BY-4.0 출처 표기를 넣는다.

## 확인 (실제로 돌리고 보고)
- `scripts/build_mac.sh` 성공, dmg 생성
- `codesign --verify --deep --strict --verbose=2 <app>` 통과
- 번들 안의 엔진으로 모델 없는 명령(`--help`, `models status --json`)이 실행되는지 확인
- Metal이 필요한 실행 확인은 Opus가 한다. 확인할 명령을 보고서에 적어 둔다.

## 마무리
- 커밋은 한국어 메시지로 한다(push·병합 금지).
- 보고: 만든 파일, 실제로 돌린 명령과 결과, dmg 크기, 남은 문제.
