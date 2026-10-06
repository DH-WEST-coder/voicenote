#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/vendor/FluidAudio/.build/release"
DEST="$ROOT/desktop/src-tauri/binaries"
[[ -x "$SOURCE/fluidaudiocli" ]] || { echo '빌드된 fluidaudiocli 없음; 오프라인 빌드가 먼저 필요' >&2; exit 1; }
mkdir -p "$DEST" "$ROOT/desktop/src-tauri/resources/fluid-resources"
cp "$SOURCE/fluidaudiocli" "$DEST/fluidaudiocli-aarch64-apple-darwin"
chmod +x "$DEST/fluidaudiocli-aarch64-apple-darwin"
# SwiftPM Bundle.module가 CLI 옆에서 찾는 데이터 번들도 보존.
for bundle in "$SOURCE"/*.bundle; do
  [[ -d "$bundle" ]] || continue
  ditto "$bundle" "$ROOT/desktop/src-tauri/resources/fluid-resources/$(basename "$bundle")"
done
[[ -x "$DEST/codex-aarch64-apple-darwin" ]] || { echo '기존 Codex 사이드카 없음' >&2; exit 1; }
echo "사이드카: $DEST"
