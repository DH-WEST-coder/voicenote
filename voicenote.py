#!/usr/bin/env python3
"""VoiceNote 엔진: 오디오 → 화자 라벨 Markdown 대본.

사용: .venv/bin/python voicenote.py transcribe <오디오> [--profile 이름] [--speakers N] [--out 폴더] [--json-progress]
      .venv/bin/python voicenote.py show-config

순서: 변환(afconvert) → 받아쓰기(Qwen3-ASR) ‖ 화자 분리(FluidAudio) → 합치기 → 힌트 누출 제거 → .md
"""
import argparse
import bisect
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
VENV = HERE / ".venv"
FLUID = HERE / "vendor/FluidAudio/.build/release/fluidaudiocli"
ASR_MODEL = "moona3k/mlx-qwen3-asr-1.7b-8bit"
ENGINE = "qwen3-asr-1.7b-8bit + fluidaudio-offline"
PROFILES = Path.home() / "Library/Application Support/VoiceNote/profiles.json"
DEFAULT_OUT = Path.home() / "Documents/VoiceNote/transcripts"

PROVENANCE = "provenance: VoiceNote 자동 전사(Qwen3-ASR + FluidAudio 화자 분리). 오인식 교정 없음. 화자N 라벨은 자동 추정."
MAX_GAP = 2.0      # 같은 화자라도 이만큼(초) 쉬면 줄을 나눈다
MAX_LEN = 60.0     # 한 줄이 이만큼(초) 넘으면 문장 끝에서 나눈다
LEAK_MIN = 4       # 힌트 용어가 원래 순서대로 이만큼 연속되면 누출로 본다

CONFIG = Path.home() / "Library/Application Support/VoiceNote/config.json"
# config.json이 없을 때 처음 한 번 쓰는 기본값(코드 안의 유일한 vault 경로). 앱과 같은 파일을 공유한다.
DEFAULT_VAULT = ("/Users/DH_WEST/Library/CloudStorage/GoogleDrive-hello430234@gmail.com/내 드라이브/04_LLMwiki/"
                 "LLM WIKI for study")
DEFAULT_SEMESTER = "raw/05_UNIST/07_3학년 가을학기"


def load_config():
    """{"vault": 절대경로, "semester": vault 기준 상대경로}. 없으면 기본값으로 만든다."""
    cfg = {"vault": DEFAULT_VAULT, "semester": DEFAULT_SEMESTER}
    if CONFIG.exists():
        try:
            data = json.loads(CONFIG.read_text())
            if isinstance(data.get("vault"), str) and data["vault"]:
                cfg["vault"] = data["vault"]
            if isinstance(data.get("semester"), str):
                cfg["semester"] = data["semester"]
        except (ValueError, AttributeError):
            pass
    else:
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        CONFIG.write_text(json.dumps(cfg, ensure_ascii=False, indent=2))
    return cfg


def resolve_wiki_dir(wiki_dir, vault=None):
    """프로필 wiki_dir 해석: 상대경로는 vault 기준, 절대경로는 그대로."""
    if not wiki_dir:
        return wiki_dir
    return wiki_dir if os.path.isabs(wiki_dir) else str(Path(vault or load_config()["vault"]) / wiki_dir)


def _wiki(course):
    return {"course": course, "wiki_dir": f"{load_config()['semester']}/{course}/transcript"}


_PE_TERMS = [
    "전력전자", "PWM", "듀티", "듀티비", "캐리어", "삼각파", "스위칭", "주파수", "인덕터", "리플", "RL", "부하",
    "역기전력", "전향", "보상", "PI 제어기", "적분기", "안티 와인드업", "연속 제어", "이산 제어", "샘플링",
    "피크", "밸리", "Simulink", "PLECS", "서브시스템", "트리거", "레그", "암", "단락", "데드타임"]

# course/wiki_dir는 선택 항목. wiki_dir은 vault 기준 상대경로(절대경로도 허용)로, 위키 raw의 과목 transcript 폴더(앱이 새 파일만 추가한다).
DEFAULT_PROFILES = {
    "전력전자": {"language": "Korean", "terms": _PE_TERMS, **_wiki("전력전자")},
    "Power Electronics (EN)": {"language": "English", "terms": [
        "freewheeling diode", "rectifier", "Fourier series", "harmonics", "ripple"], **_wiki("전력전자")},
    "물리전자": {"language": "Korean", "terms": [], **_wiki("물리전자")},
    "인턴십 PESL": {"language": "Korean", "terms": list(_PE_TERMS), **_wiki("인턴십")},
}


# ---------- 합치기 (merge.py에서 옮김) ----------

def locate_tokens(text, words):
    """각 단어 토큰의 원문 시작 위치. 못 찾으면 직전 위치를 쓴다."""
    pos, out = 0, []
    for w in words:
        t = w["text"].strip()
        i = text.find(t, pos) if t else -1
        if i == -1 or i - pos > 40:   # 너무 멀리 뛰면 정렬 실패로 보고 제자리
            out.append(pos)
        else:
            out.append(i)
            pos = i + len(t)
    return out


def speaker_at(segs, starts, t0, t1):
    """[t0, t1]과 가장 많이 겹치는 화자. 겹침이 없으면 가장 가까운 구간의 화자."""
    best, best_ov = None, 0.0
    i = max(0, bisect.bisect_right(starts, t0) - 3)
    while i < len(segs) and segs[i]["start"] <= t1 + 0.01:
        s = segs[i]
        ov = min(t1, s["end"]) - max(t0, s["start"])
        if ov > best_ov or (best is None and ov >= 0):
            best, best_ov = s["speaker"], ov
        i += 1
    if best is not None:
        return best
    j = bisect.bisect_right(starts, t0)
    cand = [segs[k] for k in (j - 1, j) if 0 <= k < len(segs)]
    return min(cand, key=lambda s: min(abs(s["start"] - t0), abs(s["end"] - t0)))["speaker"] if cand else 0


def fmt(t):
    t = int(t)
    return f"{t // 3600}:{t % 3600 // 60:02d}:{t % 60:02d}" if t >= 3600 else f"{t // 60}:{t % 60:02d}"


def build_lines(asr, segs, leaks=()):
    """→ (줄 목록[{spk,t,body}], 화자 수). leaks는 지울 (시작, 끝) 원문 위치 목록."""
    segs = sorted(segs, key=lambda s: s["start"])
    starts = [s["start"] for s in segs]
    text, words = asr["text"], [w for w in asr["segments"] if w["text"].strip()]
    idx = locate_tokens(text, words)

    def leaked(i):
        return any(a <= i < b for a, b in leaks)

    keep = [k for k in range(len(words)) if not leaked(idx[k])]
    words, idx = [words[k] for k in keep], [idx[k] for k in keep]

    # 화자 번호를 처음 말한 순서대로 1, 2, 3...
    order, spk = {}, []
    for w in words:
        s = speaker_at(segs, starts, w["start"], max(w["end"], w["start"] + 0.05)) if segs else 0
        spk.append(order.setdefault(s, len(order) + 1))

    lines, cur = [], None
    for k, w in enumerate(words):
        new = cur is None or spk[k] != cur["spk"] or w["start"] - words[k - 1]["end"] > MAX_GAP \
            or (w["start"] - cur["t"] > MAX_LEN and text[idx[k] - 2:idx[k]].strip()[-1:] in ".?!")
        if new:
            if cur:
                cur["end_i"] = idx[k]
                lines.append(cur)
            cur = {"spk": spk[k], "t": w["start"], "start_i": idx[k]}
    if cur:
        cur["end_i"] = len(text)
        lines.append(cur)

    out = []
    for ln in lines:
        a, b = ln["start_i"], ln["end_i"]
        cuts = sorted((max(x, a), min(y, b)) for x, y in leaks if x < b and y > a)
        body, p = "", a
        for x, y in cuts:
            body += text[p:x]
            p = max(p, y)
        body = (body + text[p:b]).strip()
        if body:
            out.append({"spk": ln["spk"], "t": ln["t"], "body": body})
    return out, len(order)


# ---------- 힌트 누출 제거 ----------

def _norm(tok):
    return tok.strip(".,?!\"'()[]·…").casefold()


def find_leaks(text, terms):
    """프로필 용어가 원래 순서대로 연속 LEAK_MIN개 이상(서로 다른 용어) 나오는 원문 구간들."""
    flat = []   # (토큰, 용어 번호)
    for n, term in enumerate(terms):
        flat += [(_norm(t), n) for t in term.split()]
    toks = [(m.start(), m.end(), _norm(m.group())) for m in re.finditer(r"\S+", text)]
    spans, i = [], 0
    while i < len(toks):
        prev, j, seen = -1, i, set()
        while j < len(toks):
            nxt = next((k for k in range(prev + 1, len(flat)) if flat[k][0] == toks[j][2]), None)
            if nxt is None:
                break
            prev = nxt
            seen.add(flat[nxt][1])
            j += 1
        if len(seen) >= LEAK_MIN:
            spans.append((toks[i][0], toks[j - 1][1]))
            i = j
        else:
            i += 1
    return spans


# 용어 힌트 상한: 너무 길면 느려지고 대본에 힌트가 새어 나온다
MAX_TERMS = 80

# ---------- 프로필 ----------

def load_profiles():
    if not PROFILES.exists():
        PROFILES.parent.mkdir(parents=True, exist_ok=True)
        PROFILES.write_text(json.dumps(DEFAULT_PROFILES, ensure_ascii=False, indent=2))
    # macOS 경로·인자로 들어온 한글은 NFD(자모 분리)일 수 있어 이름을 NFC로 맞춘다
    return {unicodedata.normalize("NFC", k): v for k, v in json.loads(PROFILES.read_text()).items()}


# ---------- 진행 보고 ----------

class Reporter:
    def __init__(self, as_json):
        self.as_json, self.out, self.lock = as_json, sys.stdout, threading.Lock()
        sys.stdout = sys.stderr   # 라이브러리가 stdout에 찍는 잡음이 JSON 줄을 오염시키지 않게

    def emit(self, stage, **kw):
        with self.lock:
            if self.as_json:
                print(json.dumps({"stage": stage, **kw}, ensure_ascii=False), file=self.out, flush=True)
            else:
                print(f"[{stage}] " + " ".join(f"{k}={v}" for k, v in kw.items()), file=sys.stderr, flush=True)


# ---------- 단계 ----------

def convert(src, wav):
    r = subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(src), str(wav)],
                       capture_output=True, text=True)
    if r.returncode != 0 or not Path(wav).exists():
        raise RuntimeError(f"오디오 변환 실패: {r.stderr.strip()}")
    # afconvert는 m4a 등에서 WAVE_FORMAT_EXTENSIBLE 헤더를 쓰는데, mlx-qwen3-asr의 내장 리더가
    # 이를 못 읽고 ffmpeg로 넘어간다(ffmpeg 없음). 일반 PCM16 WAV로 다시 쓴다.
    import soundfile as sf
    data, sr = sf.read(str(wav), dtype="int16")
    sf.write(str(wav), data, sr, subtype="PCM_16", format="WAV")


def run_asr(wav, profile, rep):
    from mlx_qwen3_asr import transcribe   # 무거우니 필요할 때만
    last = [-1]

    def on_progress(ev):
        p = int(ev.get("progress", 0) * 100)
        if "progress" in ev and p != last[0]:
            last[0] = p
            rep.emit("asr", status="progress", progress=p / 100)

    terms = profile.get("terms") or []
    res = transcribe(str(wav), model=ASR_MODEL, context=" ".join(terms),
                     language=profile.get("language"), return_timestamps=True, on_progress=on_progress)
    return {"text": res.text, "segments": res.segments or []}


def run_diar(wav, out_json, speakers, log_path):
    cmd = [str(FLUID), "process", str(wav), "--mode", "offline", "--output", str(out_json)]
    if speakers:
        cmd += ["--num-speakers", str(speakers)]
    with open(log_path, "w") as log:
        p = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
    if p.returncode != 0 or not Path(out_json).exists():
        tail = Path(log_path).read_text()[-500:]
        raise RuntimeError(f"화자 분리 실패(코드 {p.returncode}): {tail}")
    raw = json.loads(Path(out_json).read_text())
    return [{"speaker": s["speakerId"], "start": s["startTimeSeconds"], "end": s["endTimeSeconds"]}
            for s in raw["segments"]]


def wav_duration(wav):
    import soundfile as sf
    return sf.info(str(wav)).duration


def unique_path(path):
    p, n = path, 2
    while p.exists():
        p = path.with_name(f"{path.stem} ({n}){path.suffix}")
        n += 1
    return p


def transcribe_file(args, rep):
    src = Path(args.audio).expanduser().resolve()
    if not src.is_file():
        raise RuntimeError(f"파일이 없습니다: {src}")
    profile, pname = {}, None
    if args.profile:
        args.profile = unicodedata.normalize("NFC", args.profile)
        profiles = load_profiles()
        if args.profile not in profiles:
            raise RuntimeError(f"프로필 '{args.profile}' 없음. 있는 프로필: {', '.join(profiles)}")
        profile, pname = dict(profiles[args.profile]), args.profile
        if profile.get("wiki_dir"):
            profile["wiki_dir"] = resolve_wiki_dir(profile["wiki_dir"])
        rep.emit("config", vault=load_config()["vault"], wiki_dir=profile.get("wiki_dir", "-"))
    else:
        load_profiles()   # 기본 프로필 파일 만들어 두기
    # 노트별 용어(앱이 강의자료에서 뽑은 것)와 언어: 프로필 값에 더하거나 덮어쓴다
    if args.terms_file:
        extra = [t.strip() for t in Path(args.terms_file).read_text().splitlines() if t.strip()]
        seen, merged = set(), []
        for t in (profile.get("terms") or []) + extra:
            if t.lower() not in seen:
                seen.add(t.lower()); merged.append(t)
        profile["terms"] = merged[:MAX_TERMS]
    if args.language:
        profile["language"] = None if args.language == "auto" else args.language
    if not FLUID.exists():
        raise RuntimeError(f"fluidaudiocli가 없습니다: {FLUID}")

    tmp = Path(tempfile.mkdtemp(prefix="voicenote-"))
    try:
        wav = tmp / "audio.wav"
        rep.emit("convert", status="start")
        convert(src, wav)
        dur = wav_duration(wav)
        rep.emit("convert", status="done")

        # 화자 분리는 스레드에서 외부 프로세스로, ASR은 이 스레드에서 동시에
        diar = {}

        def diar_job():
            try:
                rep.emit("diarize", status="start")
                diar["segs"] = run_diar(wav, tmp / "diar.json", args.speakers, tmp / "diar.log")
                rep.emit("diarize", status="done")
            except Exception as e:
                diar["err"] = e

        th = threading.Thread(target=diar_job)
        th.start()
        try:
            rep.emit("asr", status="start")
            asr = run_asr(wav, profile, rep)
            rep.emit("asr", status="done")
        finally:
            th.join()
        if "err" in diar:
            raise diar["err"]

        rep.emit("merge", status="start")
        leaks = find_leaks(asr["text"], profile.get("terms") or [])
        lines, nspk = build_lines(asr, diar["segs"], leaks)
        if leaks:
            rep.emit("merge", status="leak_removed", count=len(leaks))

        mtime = datetime.datetime.fromtimestamp(src.stat().st_mtime)
        d = int(dur)
        head = ["---", f"date: {mtime:%Y-%m-%d %H:%M}", f"duration: {d // 60}:{d % 60:02d}",
                f"profile: {pname or '-'}", f"speakers: {nspk}", f"source: {src}", f"engine: {ENGINE}"]
        if profile.get("course"):
            head += [f"course: {profile['course']}", PROVENANCE]
        head += ["---", ""]
        body = []
        for ln in lines:
            body += [f"[{fmt(ln['t'])}] 화자{ln['spk']}: {ln['body']}", ""]
        out_dir = Path(args.out).expanduser() if args.out else DEFAULT_OUT
        out_dir.mkdir(parents=True, exist_ok=True)
        dst = unique_path(out_dir / f"{mtime:%Y-%m-%d %H%M} {src.stem}.md")
        dst.write_text("\n".join(head + body))
        rep.emit("merge", status="done", lines=len(lines), speakers=nspk)
        return dst
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------- 실시간 받아쓰기 (live) ----------

LIVE_MODEL = "moona3k/mlx-qwen3-asr-0.6b-4bit"


def _strip_spans(text, spans):
    out, p = "", 0
    for a, b in sorted(spans):
        out += text[p:a]
        p = max(p, b)
    return (out + text[p:]).strip()


def collapse_repeats(text, min_rep=3, max_n=12):
    """작은 모델이 같은 구절을 계속 되풀이하는 루프를 한 번으로 줄인다(연속 min_rep회 이상 반복만)."""
    toks = text.split()
    out, i = [], 0
    while i < len(toks):
        hit = False
        for n in range(1, max_n + 1):
            if i + n * min_rep > len(toks):
                break
            seq = toks[i:i + n]
            r = 1
            while toks[i + r * n:i + (r + 1) * n] == seq:
                r += 1
            if r >= min_rep:
                out += seq; i += r * n; hit = True
                break
        if not hit:
            out.append(toks[i]); i += 1
    return " ".join(out)


def run_live(args):
    """stdin(16kHz 모노 float32 LE) 또는 --input-file → JSON 줄(ready/loading/commit/partial/stats/done/error)."""
    import numpy as np
    out = sys.stdout
    sys.stdout = sys.stderr   # 라이브러리 잡음이 JSON 줄을 오염시키지 않게
    lock = threading.Lock()

    def emit(**kw):
        with lock:
            print(json.dumps(kw), file=out, flush=True)

    try:
        profile = {}
        if args.profile:
            name = unicodedata.normalize("NFC", args.profile)
            profile = dict(load_profiles().get(name, {}))
        terms = list(profile.get("terms") or [])
        if args.terms_file and Path(args.terms_file).exists():
            extra = [t.strip() for t in Path(args.terms_file).read_text().splitlines() if t.strip()]
            seen, merged = set(), []
            for t in terms + extra:
                if t.lower() not in seen:
                    seen.add(t.lower()); merged.append(t)
            terms = merged
        terms = terms[:MAX_TERMS]
        language = profile.get("language")
        if args.language:
            language = None if args.language == "auto" else args.language

        emit(type="loading", model=args.model)
        import mlx.core as mx
        from mlx_qwen3_asr.load_models import _ModelHolder
        from mlx_qwen3_asr.streaming import init_streaming, feed_audio, finish_streaming
        model_obj, _ = _ModelHolder.get(args.model, dtype=mx.float16)
        sr = 16000
        state = init_streaming(model=args.model, context=" ".join(terms), chunk_size_sec=args.chunk_sec,
                               language=language, sample_rate=sr)
        emit(type="ready", model=args.model)

        def audio_source():
            """16kHz 모노 float32 조각들을 돌려준다(최대 chunk_sec 길이)."""
            step = max(1600, int(args.chunk_sec * sr / 2))
            if args.input_file:
                tmp = Path(tempfile.mkdtemp(prefix="voicenote-live-"))
                try:
                    wav = tmp / "a.wav"
                    convert(Path(args.input_file).expanduser(), wav)
                    import soundfile as sf
                    data, _sr = sf.read(str(wav), dtype="float32")
                finally:
                    shutil.rmtree(tmp, ignore_errors=True)
                if args.duration:
                    data = data[:int(args.duration * sr)]
                t0 = time.monotonic()
                for i in range(0, len(data), step):
                    if args.realtime:
                        wait = (i / sr) - (time.monotonic() - t0)
                        if wait > 0:
                            time.sleep(wait)
                    yield data[i:i + step]
            else:
                stdin, nbytes, rest = sys.stdin.buffer, step * 4, b""
                while True:
                    b = stdin.read(nbytes)
                    if not b:
                        break
                    b = rest + b
                    n = len(b) // 4 * 4
                    rest = b[n:]
                    if n:
                        yield np.frombuffer(b[:n], dtype="<f4").astype(np.float32)

        fed, ws = 0, 0.0           # 넣은 표본 수, 현재 창의 시작 시각(초)
        committed_seen = ""
        last_partial = None
        proc_ms, proc_n, next_stats = 0.0, 0, 30.0

        def emit_commit(text, start, end):
            text = collapse_repeats(text)
            leaks = find_leaks(text, terms) if terms else []
            text = _strip_spans(text, leaks) if leaks else text.strip()
            if text:
                emit(type="commit", start=round(start, 2), end=round(end, 2), text=text)

        for pcm in audio_source():
            fed += len(pcm)
            before = state.chunk_id
            t = time.monotonic()
            feed_audio(pcm, state, model_obj)
            if state.chunk_id != before:
                proc_ms += (time.monotonic() - t) * 1000
                proc_n += state.chunk_id - before
                if state.committed_text != committed_seen:
                    new = state.committed_text
                    new = new[len(committed_seen):] if new.startswith(committed_seen) else new
                    committed_seen = state.committed_text
                    processed = fed / sr - len(state.buffer) / sr
                    new_ws = max(ws, processed - len(state.audio_accum) / sr)
                    emit_commit(new, ws, new_ws)
                    ws, last_partial = new_ws, None
                wt = state.window_text.strip()
                if wt != last_partial:
                    last_partial = wt
                    shown = wt = collapse_repeats(wt)
                    if terms and wt:
                        lk = find_leaks(wt, terms)
                        shown = _strip_spans(wt, lk) if lk else wt
                    emit(type="partial", start=round(ws, 2), text=shown)
            if fed / sr >= next_stats:
                next_stats += 30.0
                emit(type="stats", audio_sec=round(fed / sr, 1),
                     proc_ms_avg=round(proc_ms / max(1, proc_n), 1), chunks=proc_n)

        finish_streaming(state, model_obj)
        tail = state.window_text.strip()
        if state.committed_text != committed_seen:   # 마지막 finish에서 창이 확정된 경우
            new = state.committed_text
            new = new[len(committed_seen):] if new.startswith(committed_seen) else new
            emit_commit(new, ws, fed / sr)
            tail = ""
        if tail:
            emit_commit(tail, ws, fed / sr)
        emit(type="stats", audio_sec=round(fed / sr, 1), proc_ms_avg=round(proc_ms / max(1, proc_n), 1),
             chunks=proc_n, final=True)
        emit(type="done")
        return 0
    except BaseException as e:
        emit(type="error", message=str(e) or type(e).__name__)
        return 1


def main():
    ap = argparse.ArgumentParser(prog="voicenote.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("transcribe")
    t.add_argument("audio")
    t.add_argument("--profile")
    t.add_argument("--speakers", type=int)
    t.add_argument("--out")
    t.add_argument("--json-progress", action="store_true")
    t.add_argument("--terms-file", help="용어 힌트 파일(한 줄에 하나). 프로필 용어에 더한다")
    t.add_argument("--language", help="Korean | English | auto (프로필 언어를 덮어씀)")
    lv = sub.add_parser("live", help="실시간 받아쓰기: stdin 16kHz 모노 float32 PCM → JSON 줄")
    lv.add_argument("--model", default=LIVE_MODEL)
    lv.add_argument("--chunk-sec", type=float, default=2.0)
    lv.add_argument("--terms-file")
    lv.add_argument("--language")
    lv.add_argument("--profile")
    lv.add_argument("--input-file", help="시험용: stdin 대신 이 오디오를 넣는다")
    lv.add_argument("--realtime", action="store_true", help="--input-file을 실제 시간 속도로 넣는다")
    lv.add_argument("--duration", type=float, help="--input-file의 앞 N초만 쓴다(시험용)")
    sc = sub.add_parser("show-config", help="vault/semester와 프로필별 해석된 wiki_dir 출력")
    args = ap.parse_args()
    if args.cmd == "show-config":
        cfg = load_config()
        print(f"config: {CONFIG}\nvault: {cfg['vault']}\nsemester: {cfg['semester']}")
        for n, p in load_profiles().items():
            print(f"profile {n}: wiki_dir={resolve_wiki_dir(p.get('wiki_dir'), cfg['vault'])}")
        return 0

    # .venv 파이썬이 아니면 그걸로 다시 실행
    venv_py = VENV / "bin/python"
    if Path(sys.prefix).resolve() != VENV.resolve() and venv_py.exists():
        os.execv(str(venv_py), [str(venv_py), *sys.argv])

    if args.cmd == "live":
        return run_live(args)

    rep = Reporter(args.json_progress)
    try:
        dst = transcribe_file(args, rep)
    except BaseException as e:
        rep.emit("error", message=str(e) or type(e).__name__)
        return 1
    rep.emit("done", output=str(dst))
    if not args.json_progress:
        print(dst, file=rep.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
