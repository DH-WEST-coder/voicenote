"""호환 CLI와 일괄/실시간 처리 순서."""
import argparse
import contextlib
import datetime
import importlib
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import threading
import time
import types
import unicodedata
from dataclasses import asdict
from pathlib import Path
from engine.core import (ASR_MODEL, LIVE_MODEL, FLUID, VENV, CONFIG, MAX_TERMS,
                         Reporter, default_asr_model, load_config, load_profiles, resolve_wiki_dir,
                         build_lines, find_leaks, wav_duration, write_markdown,
                         collapse_repeats, _strip_spans)


def get_backend(*, asr_model=ASR_MODEL, diarizer_bin=None):
    name = os.environ.get("VNOTE_BACKEND")
    if name is None:
        name = {"darwin": "mac", "win32": "win"}.get(sys.platform)
    if name == "mac":
        from engine.backends.mac import MacBackend
        return MacBackend(asr_model, diarizer_bin or os.environ.get("VNOTE_FLUID_BIN", str(FLUID)))
    if name == "win":
        from engine.backends.win import WindowsBackend
        return WindowsBackend()
    raise RuntimeError(f"지원하지 않는 백엔드: {name or sys.platform}")


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
    if args.course:
        profile["course"] = args.course   # 앱의 프로젝트 과목(대본 frontmatter용)
    backend = get_backend(asr_model=args.asr_model, diarizer_bin=args.diarizer_bin)
    backend.validate()

    tmp = Path(tempfile.mkdtemp(prefix="voicenote-"))
    try:
        wav = tmp / "audio.wav"
        rep.emit("convert", status="start")
        backend.convert(src, wav)
        dur = wav_duration(wav)
        rep.emit("convert", status="done")

        # 화자 분리는 스레드에서 외부 프로세스로, ASR은 이 스레드에서 동시에
        diar = {}

        def diar_job():
            try:
                rep.emit("diarize", status="start")
                diar["segs"] = [asdict(s) for s in backend.diarize(wav, args.speakers)]
                rep.emit("diarize", status="done")
            except Exception as e:
                # 화자 분리는 보조 단계다. 실패해도 ASR 대본을 화자1로 만든다.
                print(f"[diarize] skipped: {e}", file=sys.stderr, flush=True)
                diar["segs"] = []
                rep.emit("diarize", status="skipped", reason="화자 분리 실패")

        th = threading.Thread(target=diar_job)
        th.start()
        try:
            rep.emit("asr", status="start")
            last = [-1]

            def on_progress(ev):
                p = int(ev.get("progress", 0) * 100)
                if "progress" in ev and p != last[0]:
                    last[0] = p
                    rep.emit("asr", status="progress", progress=p / 100)

            result = backend.transcribe(wav, profile.get("language"), profile.get("terms") or [], on_progress)
            asr = {"text": result.text, "segments": [asdict(w) for w in result.segments]}
            rep.emit("asr", status="done")
        finally:
            th.join()
        rep.emit("merge", status="start")
        leaks = find_leaks(asr["text"], profile.get("terms") or [])
        lines, nspk = build_lines(asr, diar["segs"], leaks)
        if leaks:
            rep.emit("merge", status="leak_removed", count=len(leaks))

        dst = write_markdown(src, dur, pname, profile, lines, nspk, args.out, args.asr_model)
        rep.emit("merge", status="done", lines=len(lines), speakers=nspk)
        return dst
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

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
        backend = get_backend()
        session = backend.live_session(args.model, terms, language, args.chunk_sec)
        state = session.init()
        sr = 16000
        emit(type="ready", model=args.model)

        def audio_source():
            """16kHz 모노 float32 조각들을 돌려준다(최대 chunk_sec 길이)."""
            step = max(1600, int(args.chunk_sec * sr / 2))
            if args.input_file:
                tmp = Path(tempfile.mkdtemp(prefix="voicenote-live-"))
                try:
                    wav = tmp / "a.wav"
                    backend.convert(Path(args.input_file).expanduser(), wav)
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
            state = session.feed(pcm)
            if state.chunk_id != before:
                proc_ms += (time.monotonic() - t) * 1000
                proc_n += state.chunk_id - before
                if state.committed_text != committed_seen:
                    new = state.committed_text
                    new = new[len(committed_seen):] if new.startswith(committed_seen) else new
                    committed_seen = state.committed_text
                    processed = fed / sr - state.buffer_samples / sr
                    new_ws = max(ws, processed - state.audio_samples / sr)
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

        state = session.finish()
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


def selftest_imports():
    """Build-time import smoke test; deliberately loads no model or MLX device."""
    result = {"stage": "selftest-imports", "checks": {}}
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        try:
            # mlx.core selects the Metal device during import on macOS. The
            # aligner text processor only needs its type annotations at import
            # time, so load its real source with a tiny mlx.core placeholder.
            # This keeps the smoke test safe on headless build hosts.
            package_spec = importlib.util.find_spec("mlx_qwen3_asr")
            if package_spec is None or not package_spec.submodule_search_locations:
                raise ImportError("mlx_qwen3_asr package not found")
            package = types.ModuleType("mlx_qwen3_asr")
            package.__path__ = list(package_spec.submodule_search_locations)
            package.__package__ = "mlx_qwen3_asr"
            sys.modules.setdefault("mlx_qwen3_asr", package)
            mlx_stub = types.ModuleType("mlx")
            core_stub = types.ModuleType("mlx.core")
            core_stub.float16 = object()
            mlx_stub.core = core_stub
            sys.modules.setdefault("mlx", mlx_stub)
            sys.modules.setdefault("mlx.core", core_stub)
            from mlx_qwen3_asr.forced_aligner import ForcedAlignTextProcessor
            tokenizers = {}
            for language, text in (
                ("Korean", "안녕하세요 세계입니다"),
                ("Japanese", "こんにちは世界です"),
                ("English", "hello world"),
            ):
                try:
                    tokens = ForcedAlignTextProcessor.tokenize_text(text, language)
                    tokenizers[language] = {"ok": bool(tokens), "tokens": tokens}
                except Exception as e:
                    cause = e.__cause__
                    detail = f"{type(e).__name__}: {e}"
                    if cause:
                        detail += f" (caused by {type(cause).__name__}: {cause})"
                    tokenizers[language] = {"ok": False, "error": detail}
            result["checks"]["tokenizers"] = {
                "ok": all(item["ok"] for item in tokenizers.values()), "languages": tokenizers,
            }
        except Exception as e:
            result["checks"]["tokenizers"] = {"ok": False, "error": f"{type(e).__name__}: {e}"}

        for name, module in (
            ("soundfile", "soundfile"),
            ("huggingface_hub", "huggingface_hub"),
            ("engine.models", "engine.models"),
        ):
            try:
                __import__(module)
                result["checks"][name] = {"ok": True}
            except Exception as e:
                result["checks"][name] = {"ok": False, "error": f"{type(e).__name__}: {e}"}

    ok = all(check.get("ok", False) for check in result["checks"].values())
    result["status"] = "ok" if ok else "error"
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0 if ok else 1

def main():
    ap = argparse.ArgumentParser(prog="voicenote.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("selftest-imports", help=argparse.SUPPRESS).add_argument(
        "--json", action="store_true", required=True
    )
    t = sub.add_parser("transcribe")
    t.add_argument("audio")
    t.add_argument("--profile")
    t.add_argument("--speakers", type=int)
    t.add_argument("--out")
    t.add_argument("--json-progress", action="store_true")
    t.add_argument("--terms-file", help="용어 힌트 파일(한 줄에 하나). 프로필 용어에 더한다")
    t.add_argument("--language", help="Korean | English | auto (프로필 언어를 덮어씀)")
    t.add_argument("--course", help="과목 이름(대본 frontmatter의 course). 앱 프로젝트에서 넘긴다")
    t.add_argument("--asr-model", default=default_asr_model())
    t.add_argument("--diarizer-bin", default=os.environ.get("VNOTE_FLUID_BIN", str(FLUID)))
    lv = sub.add_parser("live", help="실시간 받아쓰기: stdin 16kHz 모노 float32 PCM → JSON 줄")
    from engine.core import default_live_model
    lv.add_argument("--model", default=default_live_model())
    lv.add_argument("--chunk-sec", type=float, default=2.0)
    lv.add_argument("--terms-file")
    lv.add_argument("--language")
    lv.add_argument("--profile")
    lv.add_argument("--input-file", help="시험용: stdin 대신 이 오디오를 넣는다")
    lv.add_argument("--realtime", action="store_true", help="--input-file을 실제 시간 속도로 넣는다")
    lv.add_argument("--duration", type=float, help="--input-file의 앞 N초만 쓴다(시험용)")
    sc = sub.add_parser("show-config", help="vault/semester와 프로필별 해석된 wiki_dir 출력")
    models = sub.add_parser("models", help="배포판 모델 관리")
    ms = models.add_subparsers(dest="model_action", required=True)
    status = ms.add_parser("status")
    status.add_argument("--json", action="store_true")
    download = ms.add_parser("download")
    group = download.add_mutually_exclusive_group(required=True)
    group.add_argument("--set", choices=["full", "lite"])
    group.add_argument("--models", help="받을 모델 ID를 쉼표로 구분")
    download.add_argument("--asr-model", help="저장할 일괄 모델 ID")
    download.add_argument("--live-model", help="저장할 실시간 모델 ID")
    download.add_argument("--json", action="store_true")
    args = ap.parse_args()
    if args.cmd == "selftest-imports":
        return selftest_imports()
    if args.cmd == "models":
        from engine.models import run_models
        return run_models(args)

    if args.cmd == "show-config":
        cfg = load_config()
        print(f"config: {CONFIG}\nvault: {cfg['vault'] or 'vault 없음'}\nsemester: {cfg['semester']}")
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
