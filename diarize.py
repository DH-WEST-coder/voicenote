#!/usr/bin/env python3
"""녹음 파일의 화자 구간을 찾는다(sherpa-onnx, 토큰 필요 없음).

사용: .venv/bin/python diarize.py audio/xxx.wav [--speakers N] [--threshold 0.5]
결과: out/diar/xxx.json  ([{"start": 초, "end": 초, "speaker": 번호}, ...])

모델(models/): pyannote segmentation-3.0 ONNX + WeSpeaker ResNet34-LM
(pyannote 3.1 공식 파이프라인과 같은 조합). GitHub 릴리스에서 받으며 약관 동의가 없다.
"""
import argparse
import json
import time
from pathlib import Path

import sherpa_onnx
import soundfile as sf

HERE = Path(__file__).parent
SEG_MODEL = HERE / "models/sherpa-onnx-pyannote-segmentation-3-0/model.onnx"
EMB_MODEL = HERE / "models/wespeaker_en_voxceleb_resnet34_LM.onnx"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("--speakers", type=int, default=-1, help="화자 수를 알면 지정, 모르면 -1")
    ap.add_argument("--threshold", type=float, default=0.5, help="작을수록 화자를 더 많이 나눔")
    ap.add_argument("--threads", type=int, default=4)
    args = ap.parse_args()

    config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
        segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
            pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(model=str(SEG_MODEL)),
            num_threads=args.threads,
        ),
        embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=str(EMB_MODEL), num_threads=args.threads),
        clustering=sherpa_onnx.FastClusteringConfig(num_clusters=args.speakers, threshold=args.threshold),
        min_duration_on=0.3,
        min_duration_off=0.5,
    )
    if not config.validate():
        raise SystemExit("모델 파일 확인 필요: models/")
    sd = sherpa_onnx.OfflineSpeakerDiarization(config)

    audio, sr = sf.read(args.audio, dtype="float32", always_2d=True)
    audio = audio[:, 0]
    if sr != sd.sample_rate:
        raise SystemExit(f"{sd.sample_rate}Hz WAV가 필요함 (afconvert -f WAVE -d LEI16@16000 -c 1)")

    t0 = time.time()
    result = sd.process(audio).sort_by_start_time()
    segs = [{"start": round(r.start, 3), "end": round(r.end, 3), "speaker": r.speaker} for r in result]
    elapsed = time.time() - t0

    out = HERE / "out/diar" / (Path(args.audio).stem + ".json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(segs, ensure_ascii=False, indent=1))

    talk = {}
    for s in segs:
        talk[s["speaker"]] = talk.get(s["speaker"], 0) + s["end"] - s["start"]
    print(f"{out.name}: {len(audio) / sr / 60:.1f}분 녹음, {elapsed:.0f}초 걸림, 구간 {len(segs)}개")
    for spk, sec in sorted(talk.items(), key=lambda x: -x[1]):
        print(f"  화자{spk + 1}: {sec / 60:.1f}분")


if __name__ == "__main__":
    main()
