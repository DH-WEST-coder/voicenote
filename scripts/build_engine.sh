#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -m)" == arm64 ]] || { echo 'Apple Silicon 맥 필요' >&2; exit 1; }
[[ -x .venv-dist/bin/pyinstaller ]] || { echo '.venv-dist의 PyInstaller 없음; 새 패키지 설치 필요' >&2; exit 1; }
for package in mlx-0.32.3.dist-info mlx_metal-0.32.3.dist-info; do
  wheel="$(find .venv-dist/lib -path "*/site-packages/$package/WHEEL" -print -quit)"
  if [[ -z "$wheel" ]] || ! grep -Eq '^Tag: .*macosx_14_0_arm64$' "$wheel"; then
    cat >&2 <<EOF
오류: .venv-dist의 $package WHEEL이 macosx_14_0_arm64가 아닙니다.
호환 휠을 네트워크가 되는 별도 환경에서 준비한 뒤 수동 설치하세요:
  pip download --platform macosx_14_0_arm64 --only-binary=:all: mlx==0.32.3 mlx-metal==0.32.3
  uv pip install --python .venv-dist/bin/python --reinstall --no-deps ./mlx-0.32.3-*.whl ./mlx_metal-0.32.3-*.whl
EOF
    exit 1
  fi
done
mkdir -p dist-build/pyinstaller-config dist-build/tmp desktop/src-tauri/resources
export PYINSTALLER_CONFIG_DIR="$ROOT/dist-build/pyinstaller-config"
export TMPDIR="$ROOT/dist-build/tmp"
.venv-dist/bin/pyinstaller --noconfirm --distpath dist-build/engine --workpath dist-build/pyinstaller scripts/vnote-engine.spec
DEST="$ROOT/desktop/src-tauri/resources/vnote-engine"
rm -rf "$DEST"
ditto dist-build/engine/vnote-engine "$DEST"
echo "엔진: $DEST"
