"""모델을 로드하지 않는 배포판 다운로드/캐시 점검."""
import json
import os
import subprocess
import sys
import tempfile
import threading
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
    root = os.environ.get("VNOTE_DATA_DIR")
    if not root:
        raise RuntimeError("FluidAudio 점검에는 VNOTE_DATA_DIR이 필요합니다")
    return Path(root).expanduser() / "models/fluid-home/Library/Application Support/FluidAudio/Models"


def folder_status(path):
    files = [p for p in path.rglob("*") if p.is_file() and not p.name.endswith((".incomplete", ".lock"))] if path.exists() else []
    return bool(files), sum(p.stat().st_size for p in files)


def snapshot_complete(snapshot):
    tokenizer = (snapshot / "tokenizer.json").is_file() or all(
        (snapshot / name).is_file() for name in ("vocab.json", "merges.txt"))
    if not (snapshot / "config.json").is_file() or not tokenizer:
        return False
    files = list(snapshot.rglob("*"))
    if any(p.is_symlink() and not p.exists() for p in files):
        return False
    weights = [p for p in files if p.suffix in (".safetensors", ".bin") and p.is_file()]
    if not weights or any(p.stat().st_size == 0 for p in weights):
        return False
    for index in snapshot.glob("*.index.json"):
        try:
            shards = set(json.loads(index.read_text())["weight_map"].values())
            if not shards or not all((snapshot / name).is_file() for name in shards):
                return False
        except (ValueError, KeyError, TypeError):
            return False
    return True


def model_status(model):
    path = cache_root() / ("models--" + model.replace("/", "--"))
    snapshots = path / "snapshots"
    complete = any(snapshot_complete(s) for s in snapshots.iterdir()) if snapshots.exists() else False
    _, size = folder_status(path / "blobs")
    return {"id": model, "downloaded": complete, "size_bytes": size}


def fluid_complete():
    root = fluid_root()
    required = ("Segmentation.mlmodelc", "Embedding.mlmodelc", "FBank.mlmodelc", "PldaRho.mlmodelc", "plda-parameters.json")
    # ModelHub는 저장소 하위 폴더를 붙일 수 있다. 같은 폴더의 전체 필수 파일을 확인한다.
    return any(all((p.parent / name).exists() for name in required) for p in root.rglob("plda-parameters.json")) if root.exists() else False


def status():
    _, size = folder_status(fluid_root())
    return {"stage": "models", "status": "status", "models": [model_status(m) for m in (ASR_MODEL, LIVE_MODEL, ALIGNER)] +
            [{"id": "FluidAudio", "downloaded": fluid_complete(), "size_bytes": size}]}


def save_model(model):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    data = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    data["asr_model"] = model
    with tempfile.NamedTemporaryFile(mode="w", dir=CONFIG.parent, delete=False) as f:
        json.dump(data, f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
        tmp = Path(f.name)
    try:
        tmp.replace(CONFIG)
        fd = os.open(CONFIG.parent, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        tmp.unlink(missing_ok=True)


def fluid_env():
    root = os.environ.get("VNOTE_DATA_DIR")
    if not root:
        return None
    home = Path(root).expanduser() / "models/fluid-home"
    home.mkdir(parents=True, exist_ok=True)
    return {**os.environ, "CFFIXED_USER_HOME": str(home.resolve())}


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
                                stdout=sys.stderr, stderr=subprocess.PIPE, text=True, timeout=900, env=fluid_env())
        if not fluid_complete():
            lines = (result.stderr or "").strip().splitlines()
            detail = lines[-1] if lines else "필수 모델 파일 없음"
            raise RuntimeError(f"FluidAudio 모델 준비 실패: {result.returncode}: {detail}")
        emit("download", model="FluidAudio", progress=1)


def run_models(args):
    wire = sys.stdout
    lock = threading.Lock()
    def emit(kind, **kw):
        obj = {"stage": "models", "status": kind, **kw}
        with lock:
            print(json.dumps(obj, ensure_ascii=False) if args.json else str(obj), file=wire, flush=True)
    try:
        if args.model_action == "status":
            obj = status()
            print(json.dumps(obj, ensure_ascii=False) if args.json else str(obj), file=wire, flush=True)
            return 0
        from huggingface_hub import snapshot_download
        from huggingface_hub.utils import tqdm
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
