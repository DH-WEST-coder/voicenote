#!/usr/bin/env python3
"""받아쓰기(out/asr/xxx.json) + 화자 구간(out/diar/xxx.json) → out/transcript/xxx.md

사용: .venv/bin/python merge.py xxx [asr폴더]
합치기 로직은 voicenote.py로 옮겼다. 이 파일은 옛 벤치마크 재현용 얇은 래퍼.
"""
import json
import sys
from pathlib import Path

from voicenote import build_lines, fmt

HERE = Path(__file__).parent


def main(stem):
    asr = json.loads((HERE / (sys.argv[2] if len(sys.argv) > 2 else "out/asr") / f"{stem}.json").read_text())
    diar_path = HERE / f"out/diar/{stem}.json"
    segs = json.loads(diar_path.read_text()) if diar_path.exists() else []
    lines, n = build_lines(asr, segs)
    out = [f"# {stem}", "", f"> 자동 받아쓰기(Qwen3-ASR) + 화자 분리(pyannote seg-3.0 + WeSpeaker). 화자 {n}명 추정.", ""]
    for ln in lines:
        label = f"화자{ln['spk']}: " if segs else ""
        out += [f"[{fmt(ln['t'])}] {label}{ln['body']}", ""]
    dst = HERE / f"out/transcript/{stem}.md"
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text("\n".join(out))
    print(f"{dst}: {len(lines)}줄, 화자 {n}명")


if __name__ == "__main__":
    main(sys.argv[1])
