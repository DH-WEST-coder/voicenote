#!/usr/bin/env python3
"""가짜 엔진: 진행 JSON 줄을 sleep과 함께 내보내고 예제 대본을 복사한다. (앱 개발/테스트 전용)"""
import argparse, json, os, sys, time, datetime

SAMPLE = "/Users/DH_WEST/LocalAI_Project/voice/out/transcript/2026-10-02.md"

def emit(**kw):
    print(json.dumps(kw, ensure_ascii=False), flush=True)

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("transcribe")
    t.add_argument("audio"); t.add_argument("--profile", default="")
    t.add_argument("--speakers"); t.add_argument("--out", default=".")
    t.add_argument("--json-progress", action="store_true")
    a = ap.parse_args()
    if not os.path.exists(a.audio):
        emit(stage="error", message="파일 없음: " + a.audio); sys.exit(2)
    delay = float(os.environ.get("FAKE_DELAY", "0.6"))
    for st in ("convert", "asr", "diarize", "merge"):
        emit(stage=st, status="start"); time.sleep(delay)
        emit(stage=st, status="done")
    if "FAIL" in os.path.basename(a.audio):
        emit(stage="error", message="가짜 실패 (파일명에 FAIL)"); sys.exit(1)
    os.makedirs(a.out, exist_ok=True)
    now = datetime.datetime.now().strftime("%Y-%m-%d %H%M")
    title = os.path.splitext(os.path.basename(a.audio))[0]
    out = os.path.join(a.out, f"{now} {title}.md")
    body = open(SAMPLE, encoding="utf-8").read()
    body = "\n".join(l for l in body.split("\n") if not l.startswith("# ") and not l.startswith("> "))
    fm = f"---\ndate: {now[:10]} {now[11:13]}:{now[13:]}\nduration: 66:05\nprofile: {a.profile}\nspeakers: 4\nsource: {a.audio}\nengine: fake\n---\n"
    open(out, "w", encoding="utf-8").write(fm + body.lstrip("\n"))
    emit(stage="done", output=out)

main()
