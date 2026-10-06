#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -m)" == arm64 ]] || { echo 'Apple Silicon 맥 필요' >&2; exit 1; }
[[ -x .venv-dist/bin/pyinstaller ]] || { echo '.venv-dist의 PyInstaller 없음; 새 패키지 설치 필요' >&2; exit 1; }
mkdir -p dist-build/pyinstaller-config dist-build/tmp desktop/src-tauri/resources
export PYINSTALLER_CONFIG_DIR="$ROOT/dist-build/pyinstaller-config"
export TMPDIR="$ROOT/dist-build/tmp"
.venv-dist/bin/pyinstaller --noconfirm --distpath dist-build/engine --workpath dist-build/pyinstaller scripts/vnote-engine.spec
DEST="$ROOT/desktop/src-tauri/resources/vnote-engine"
rm -rf "$DEST"
ditto dist-build/engine/vnote-engine "$DEST"
echo "엔진: $DEST"
