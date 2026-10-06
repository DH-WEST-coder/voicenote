#!/bin/bash
# 실제 모델 다운로드·Metal 실행. Opus가 일반 맥에서 실행한다.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# == 2 ]] || { echo '사용: scripts/opus_verify.sh 한국어.wav 영어.wav' >&2; exit 2; }
[[ -f "$1" && -f "$2" ]] || { echo '시험 오디오 파일이 없습니다' >&2; exit 2; }
APP="$ROOT/desktop/src-tauri/target/aarch64-apple-darwin/release/bundle/macos/VNote.app"
ENGINE="$APP/Contents/Resources/vnote-engine/vnote-engine"
export VNOTE_DATA_DIR="$ROOT/out/dist-test/opus-packaged"
export HF_HOME="$VNOTE_DATA_DIR/models"
export VNOTE_FLUID_BIN="$APP/Contents/MacOS/fluidaudiocli"
export TMPDIR="$VNOTE_DATA_DIR/tmp"
mkdir -p "$TMPDIR" "$HF_HOME"
codesign --verify --deep --strict --verbose=2 "$APP"
"$ENGINE" models download --set full --json | tee "$VNOTE_DATA_DIR/download.jsonl"
"$ENGINE" models status --json | tee "$VNOTE_DATA_DIR/status.json"
"$ROOT/.venv-dist/bin/python" - <<'PY'
import json
import os
from pathlib import Path
root = Path(os.environ['VNOTE_DATA_DIR'])
assert all(m['downloaded'] for m in json.loads((root/'status.json').read_text())['models'])
assert json.loads((root/'config.json').read_text())['asr_model'] == 'moona3k/mlx-qwen3-asr-1.7b-8bit'
PY
"$ENGINE" transcribe "$1" --language Korean --json-progress --out "$VNOTE_DATA_DIR/korean" | tee "$VNOTE_DATA_DIR/korean.jsonl"
"$ENGINE" transcribe "$2" --language English --json-progress --out "$VNOTE_DATA_DIR/english" | tee "$VNOTE_DATA_DIR/english.jsonl"
"$ENGINE" live --input-file "$1" --duration 30 --language Korean | tee "$VNOTE_DATA_DIR/live.jsonl"
echo "Opus 결과: $VNOTE_DATA_DIR"
