#!/usr/bin/env python3
"""비교용: Whisper large-v3-turbo(mlx-whisper)로 받아쓰기. MacWhisper(Whisper 계열) 품질 대용.

사용: .venv/bin/python bench_whisper.py audio/xxx.wav [--language ko]
결과: out/whisper/xxx.json, xxx.txt
"""
import argparse
import json
import time
from pathlib import Path

import mlx_whisper
import soundfile as sf

HERE = Path(__file__).parent

ap = argparse.ArgumentParser()
ap.add_argument("audio")
ap.add_argument("--language", default=None)
ap.add_argument("--model", default="mlx-community/whisper-large-v3-turbo")
args = ap.parse_args()

audio, sr = sf.read(args.audio, dtype="float32")
assert sr == 16000, "16kHz WAV 필요"
t0 = time.time()
r = mlx_whisper.transcribe(audio, path_or_hf_repo=args.model, language=args.language,
                           condition_on_previous_text=False, word_timestamps=True)
elapsed = time.time() - t0

out = HERE / "out/whisper"
out.mkdir(parents=True, exist_ok=True)
stem = Path(args.audio).stem
(out / f"{stem}.json").write_text(json.dumps(r, ensure_ascii=False, indent=1))
(out / f"{stem}.txt").write_text(
    "\n".join(f"[{int(s['start'] // 60)}:{int(s['start'] % 60):02d}] {s['text'].strip()}" for s in r["segments"]))
print(f"{stem}: {len(audio) / sr / 60:.1f}분 녹음, {elapsed:.0f}초 걸림 (실시간의 {len(audio) / sr / elapsed:.0f}배)")
