"""플랫폼 공통 설정, 대본 처리와 진행 보고."""
import bisect
import datetime
import json
import os
import re
import sys
import threading
import unicodedata
from pathlib import Path
from platformdirs import user_data_dir, user_documents_dir

HERE = Path(__file__).resolve().parent.parent
VENV = HERE / ".venv"
FLUID = HERE / "vendor/FluidAudio/.build/release/fluidaudiocli"
ASR_MODEL = "moona3k/mlx-qwen3-asr-1.7b-8bit"
LIVE_MODEL = "moona3k/mlx-qwen3-asr-0.6b-4bit"
PROFILES = Path(user_data_dir("VoiceNote", appauthor=False)) / "profiles.json"
CONFIG = PROFILES.with_name("config.json")
DEFAULT_OUT = Path(user_documents_dir()) / "VoiceNote/transcripts"
PROVENANCE = "provenance: VoiceNote 자동 전사(Qwen3-ASR + FluidAudio 화자 분리). 오인식 교정 없음. 화자N 라벨은 자동 추정."
MAX_GAP = 2.0      # 같은 화자라도 이만큼(초) 쉬면 줄을 나눈다
MAX_LEN = 60.0     # 한 줄이 이만큼(초) 넘으면 문장 끝에서 나눈다
LEAK_MIN = 4       # 힌트 용어가 원래 순서대로 이만큼 연속되면 누출로 본다


def load_config():
    """설정은 읽기만 한다. vault가 없으면 위키를 끈다."""
    cfg = {"vault": "", "semester": ""}
    if CONFIG.exists():
        try:
            data = json.loads(CONFIG.read_text())
            for key in cfg:
                if isinstance(data.get(key), str):
                    cfg[key] = data[key]
        except (ValueError, AttributeError):
            pass
    return cfg


def resolve_wiki_dir(wiki_dir, vault=None):
    vault = load_config()["vault"] if vault is None else vault
    if not vault or not wiki_dir:
        return None
    return wiki_dir if os.path.isabs(wiki_dir) else str(Path(vault) / wiki_dir)


def _wiki(course):
    cfg = load_config()
    return {"course": course, "wiki_dir": f"{cfg['semester']}/{course}/transcript" if cfg['vault'] else None}

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

MAX_TERMS = 80

def load_profiles():
    if not PROFILES.exists():
        return {k: dict(v) for k, v in DEFAULT_PROFILES.items()}
    # macOS 경로·인자로 들어온 한글은 NFD(자모 분리)일 수 있어 이름을 NFC로 맞춘다
    return {unicodedata.normalize("NFC", k): v for k, v in json.loads(PROFILES.read_text()).items()}

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

def wav_duration(wav):
    import soundfile as sf
    return sf.info(str(wav)).duration

def unique_path(path):
    p, n = path, 2
    while p.exists():
        p = path.with_name(f"{path.stem} ({n}){path.suffix}")
        n += 1
    return p

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


def normalize_wav(wav):
    """확장 WAV 헤더를 일반 PCM16으로 다시 쓴다."""
    import soundfile as sf
    data, sr = sf.read(str(wav), dtype="int16")
    sf.write(str(wav), data, sr, subtype="PCM_16", format="WAV")


def engine_name(model):
    return f"{model.rsplit('/', 1)[-1].removeprefix('mlx-')} + fluidaudio-offline"


def write_markdown(src, dur, pname, profile, lines, nspk, out, model):
    mtime = datetime.datetime.fromtimestamp(src.stat().st_mtime)
    d = int(dur)
    head = ["---", f"date: {mtime:%Y-%m-%d %H:%M}", f"duration: {d // 60}:{d % 60:02d}",
            f"profile: {pname or '-'}", f"speakers: {nspk}", f"source: {src}", f"engine: {engine_name(model)}"]
    if profile.get("course"):
        head += [f"course: {profile['course']}", PROVENANCE]
    head += ["---", ""]
    body = []
    for ln in lines:
        body += [f"[{fmt(ln['t'])}] 화자{ln['spk']}: {ln['body']}", ""]
    out_dir = Path(out).expanduser() if out else DEFAULT_OUT
    out_dir.mkdir(parents=True, exist_ok=True)
    dst = unique_path(out_dir / f"{mtime:%Y-%m-%d %H%M} {src.stem}.md")
    dst.write_text("\n".join(head + body))
    return dst
