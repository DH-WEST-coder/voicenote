#!/bin/bash
set -euo pipefail
[[ $# == 1 && -d "$1/Contents" ]] || { echo '사용: sign_app.sh VNote.app' >&2; exit 1; }
APP="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Tauri는 리소스 복사 중 symlink를 일반 파일로 풀 수 있다. MLX는
# libmlx.dylib 옆의 metallib을 찾으므로 PyInstaller 원본 링크를 복원한다.
"$ROOT/scripts/engine_symlinks.py" restore "$ROOT/dist-build/engine/vnote-engine" "$APP/Contents/Resources/vnote-engine"
# SwiftPM 데이터 번들은 Contents/Resources 최상위에 배치한다.
# MacOS의 데이터 전용 번들은 codesign이 코드로 오인한다.
while IFS= read -r -d '' bundle; do
  /usr/bin/codesign --force --sign - --options 0 "$bundle"
done < <(find "$APP/Contents/Resources" -depth -type d -name '*.bundle' -print0)
# 확장자와 실행 비트만으로는 Python 확장 모듈·프레임워크를 놓친다.
while IFS= read -r -d '' file; do
  if /usr/bin/file -b "$file" | /usr/bin/grep -q 'Mach-O'; then
    /usr/bin/codesign --force --sign - --options 0 "$file"
  fi
done < <(find "$APP/Contents" -type f -print0)
while IFS= read -r -d '' framework; do
  /usr/bin/codesign --force --sign - --options 0 "$framework"
done < <(find "$APP/Contents" -depth -type d -name '*.framework' -print0)
/usr/bin/codesign --force --sign - --options 0 "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
