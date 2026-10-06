"""모델을 로드하지 않는 배포판 다운로드/캐시 점검."""
import json
import os
import subprocess
import sys
import tempfile
import wave
from pathlib import Path
from engine.core import ASR_MODEL, LIVE_MODEL, FLUID, CONFIG

ALIGNER = "Qwen/Qwen3-ForcedAligner-0.6B"


def cache_root():
    if os.environ.get("HF_HOME"):
        return Path(os.environ["HF_HOME"]) / "hub"
    if os.environ.get("VNOTE_DATA_DIR"):
        return Path(os.environ["VNOTE_DATA_DIR"]) / "models/hub"
    raise RuntimeError("모델 관리는 VNOTE_DATA_DIR 또는 HF_HOME이 필요합니다")


def fluid_root():
    # FluidAudio의 DownloadUtils 기본 Application Support 캐시.
    return Path.home() / "Library/Application Support/FluidAudio/Models"


def folder_status(path):
    files = [p for p in path.rglob("*") if p.is_file() and not p.name.endswith((".incomplete", ".lock"))] if path.exists() else []
    return bool(files), sum(p.stat().st_size for p in files)


def model_status(model):
    path = cache_root() / ("models--" + model.replace("/", "--"))
    snapshots = path / "snapshots"
    # 스냅샷 필수 config와 가중치 및 깨진 symlink 확인.
    complete = any((s / "config.json").is_file() and
                   any(p.suffix in (".safetensors", ".bin") for p in s.rglob("*") if p.is_file()) and
                   all(p.exists() for p in s.rglob("*") if p.is_symlink())
                   for s in snapshots.iterdir()) if snapshots.exists() else False
    _, size = folder_status(path / "blobs")
    return {"id": model, "downloaded": complete, "size_bytes": size}


def status():
    ready, size = folder_status(fluid_root())
    return {"stage": "models", "status": "status", "models": [model_status(m) for m in (ASR_MODEL, LIVE_MODEL, ALIGNER)] +
            [{"id": "FluidAudio", "downloaded": ready, "size_bytes": size}]}


def save_model(model):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    data = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    data["asr_model"] = model
    with tempfile.NamedTemporaryFile(mode="w", dir=CONFIG.parent, delete=False) as f:
        json.dump(data, f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
        tmp = Path(f.name)
    tmp.replace(CONFIG)


def warm_fluid(emit):
    binary = Path(os.environ.get("VNOTE_FLUID_BIN", str(FLUID)))
    if not binary.is_file():
        raise RuntimeError("fluidaudiocli가 없습니다")
    root = CONFIG.parent / "model-download-tmp"
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=root) as tmp:
        wav = Path(tmp) / "silence.wav"
        with wave.open(str(wav), "wb") as f:
            f.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
            f.writeframes(bytes(16000 * 2 * 3))
        emit("download", model="FluidAudio", progress=0)
        result = subprocess.run([str(binary), "process", str(wav), "--mode", "offline", "--output", str(Path(tmp) / "out.json")],
                                stdout=sys.stderr, stderr=sys.stderr, timeout=900)
        if result.returncode:
            raise RuntimeError(f"FluidAudio 모델 준비 실패: {result.returncode}")
        emit("download", model="FluidAudio", progress=1)


def run_models(args):
    wire = sys.stdout
    def emit(kind, **kw):
        obj = {"stage": "models", "status": kind, **kw}
        print(json.dumps(obj, ensure_ascii=False) if args.json else str(obj), file=wire, flush=True)
    try:
        if args.model_action == "status":
            obj = status()
            print(json.dumps(obj, ensure_ascii=False) if args.json else str(obj), file=wire, flush=True)
            return 0
        from huggingface_hub import snapshot_download
        from tqdm.auto import tqdm
        class Progress(tqdm):
            def update(self, n=1):
                result = super().update(n)
                emit("download", model=current[0], downloaded=self.n, total=self.total,
                     progress=min(1, self.n / self.total) if self.total else 0)
                return result
        chosen = ASR_MODEL if args.set == "full" else LIVE_MODEL
        current = [""]
        for model in dict.fromkeys([chosen, LIVE_MODEL, ALIGNER]):
            current[0] = model
            emit("download", model=model, progress=0)
            snapshot_download(model, cache_dir=cache_root(), tqdm_class=Progress)
            emit("download", model=model, progress=1)
        warm_fluid(emit)
        save_model(chosen)
        emit("done", model_set=args.set, asr_model=chosen)
        return 0
    except Exception as e:
        emit("error", message=str(e))
        return 1
