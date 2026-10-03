#!/bin/bash
# 새 맥에서 VoiceNote 엔진 환경을 만든다. 필요: Apple Silicon, uv, Swift(Command Line Tools).
set -e
cd "$(dirname "$0")"
FLUID_COMMIT=0b1f462   # 벤치마크에 쓴 FluidAudio 버전

uv venv -p 3.12 .venv
uv pip install -p .venv -r requirements.txt

if [ ! -d vendor/FluidAudio ]; then
  git clone https://github.com/FluidInference/FluidAudio.git vendor/FluidAudio
  git -C vendor/FluidAudio checkout "$FLUID_COMMIT"
fi
(cd vendor/FluidAudio && swift build -c release --product fluidaudiocli)

# diarize.py(sherpa-onnx 비교용) 모델 — 엔진에는 필요 없음
if [ "$1" = "--bench" ] && [ ! -d models ]; then
  mkdir -p models && cd models
  curl -sSL https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2 | tar xj
  curl -sSL -O https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx
  cd ..
fi

(cd app && ./build.sh)
echo "완료: open app/build/VoiceNote.app"
