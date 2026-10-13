#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -m)" == arm64 ]] || { echo 'aarch64-apple-darwin만 지원' >&2; exit 1; }
mkdir -p dist-build/tmp
export TMPDIR="$ROOT/dist-build/tmp"
export CARGO_NET_OFFLINE=true
export MACOSX_DEPLOYMENT_TARGET=14.0
scripts/build_engine.sh
scripts/build_sidecars.sh
cd desktop
if ! npm run tauri build -- --target aarch64-apple-darwin --bundles app,dmg -- --offline; then
  echo 'Tauri app,dmg가 실패했습니다. app 빌드를 재검증한 뒤 hdiutil로 DMG를 생성합니다.' >&2
  npm run tauri build -- --target aarch64-apple-darwin --bundles app -- --offline
fi
cd "$ROOT"
BUNDLE="$ROOT/desktop/src-tauri/target/aarch64-apple-darwin/release/bundle"
APP="$BUNDLE/macos/VNote.app"
scripts/sign_app.sh "$APP"
scripts/check_app_minos.py "$APP" 14.0
SMOKE="$(mktemp -d "$ROOT/dist-build/tmp/bundle-smoke.XXXXXX")"
mkdir -p "$SMOKE/models" "$SMOKE/tmp"
ENGINE="$APP/Contents/Resources/vnote-engine/vnote-engine"
VNOTE_DATA_DIR="$SMOKE" HF_HOME="$SMOKE/models" TMPDIR="$SMOKE/tmp" "$ENGINE" --help > "$ROOT/dist-build/bundle-help.log"
VNOTE_DATA_DIR="$SMOKE" HF_HOME="$SMOKE/models" TMPDIR="$SMOKE/tmp" "$ENGINE" selftest-imports --json > "$ROOT/dist-build/bundle-selftest-imports.json"
VNOTE_DATA_DIR="$SMOKE" HF_HOME="$SMOKE/models" TMPDIR="$SMOKE/tmp" "$ENGINE" models status --json > "$ROOT/dist-build/bundle-status.json"
rm -rf "$SMOKE"
# Tauri가 만든 DMG 이후의 추가 서명을 배포 이미지에도 반영한다.
STAGE="$ROOT/dist-build/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/VNote.app"
ln -s /Applications "$STAGE/Applications"
DMG="$BUNDLE/dmg/VNote_0.1.2_aarch64.dmg"
rm -f "$DMG"
if ! hdiutil create -volname VNote -srcfolder "$STAGE" -format UDZO -ov "$DMG"; then
  # 디스크 장치를 붙일 수 없는 빌드 환경에서도 HFS 이미지는 파일로 생성 가능.
  echo 'hdiutil create 실패. HFS hybrid 파일을 UDZO로 변환합니다.' >&2
  HYBRID="$ROOT/dist-build/VNote-hybrid.dmg"
  rm -f "$HYBRID" "$DMG"
  hdiutil makehybrid -hfs -hfs-volume-name VNote -o "$HYBRID" "$STAGE"
  hdiutil convert "$HYBRID" -format UDZO -o "$DMG"
fi
hdiutil verify "$DMG"
# ตรวจ 링크는 서명된 앱을 담은 최종 DMG 안에서 수행한다.
MOUNT="$ROOT/dist-build/tmp/dmg-link-check"
mkdir -p "$MOUNT"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG"
detach_dmg() { hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; }
trap detach_dmg EXIT
scripts/engine_symlinks.py check "$ROOT/dist-build/engine/vnote-engine" "$MOUNT/VNote.app/Contents/Resources/vnote-engine"
detach_dmg
trap - EXIT
codesign --verify --deep --strict --verbose=2 "$APP"
echo "DMG: $DMG"
stat -f '크기: %z bytes' "$DMG"
