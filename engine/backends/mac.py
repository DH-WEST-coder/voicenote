"""MLX Qwen3-ASR, aligner, FluidAudio와 macOS 오디오 변환."""
import json
import subprocess
import tempfile
from pathlib import Path
from engine.core import normalize_wav
from engine.backends.base import Backend, LiveSession, LiveState, SpeakerSegment, Transcript, WordTimestamp


class MacLiveSession(LiveSession):
    def __init__(self, model, terms, language, chunk_sec):
        self.model, self.terms = model, terms
        self.language, self.chunk_sec = language, chunk_sec

    def snapshot(self):
        s = self.state
        return LiveState(s.chunk_id, s.committed_text, s.window_text, len(s.buffer), len(s.audio_accum))

    def init(self):
        import mlx.core as mx
        from mlx_qwen3_asr.load_models import _ModelHolder
        from mlx_qwen3_asr.streaming import init_streaming
        self.model_obj, _ = _ModelHolder.get(self.model, dtype=mx.float16)
        self.state = init_streaming(model=self.model, context=" ".join(self.terms),
                                    chunk_size_sec=self.chunk_sec, language=self.language, sample_rate=16000)
        return self.snapshot()

    def feed(self, pcm):
        from mlx_qwen3_asr.streaming import feed_audio
        feed_audio(pcm, self.state, self.model_obj)
        return self.snapshot()

    def finish(self):
        from mlx_qwen3_asr.streaming import finish_streaming
        finish_streaming(self.state, self.model_obj)
        return self.snapshot()


class MacBackend(Backend):
    def __init__(self, asr_model, diarizer_bin):
        self.asr_model = asr_model
        self.diarizer_bin = Path(diarizer_bin).expanduser()

    def validate(self):
        if not self.diarizer_bin.exists():
            raise RuntimeError(f"fluidaudiocli가 없습니다: {self.diarizer_bin}")

    def convert(self, src, wav):
        r = subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(src), str(wav)],
                           capture_output=True, text=True)
        if r.returncode != 0 or not Path(wav).exists():
            raise RuntimeError(f"오디오 변환 실패: {r.stderr.strip()}")
        normalize_wav(wav)

    def transcribe(self, wav, language, terms, on_progress):
        from mlx_qwen3_asr import transcribe
        res = transcribe(str(wav), model=self.asr_model, context=" ".join(terms),
                         language=language, return_timestamps=True, on_progress=on_progress)
        return Transcript(res.text, [WordTimestamp(w["text"], w["start"], w["end"])
                                     for w in res.segments or []])

    def diarize(self, wav, speakers):
        with tempfile.TemporaryDirectory(prefix="voicenote-diar-", dir=Path(wav).parent) as tmp:
            out_json, log_path = Path(tmp) / "diar.json", Path(tmp) / "diar.log"
            cmd = [str(self.diarizer_bin), "process", str(wav), "--mode", "offline", "--output", str(out_json)]
            if speakers:
                cmd += ["--num-speakers", str(speakers)]
            with log_path.open("w") as log:
                from engine.models import fluid_env
                p = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, env=fluid_env())
            if p.returncode != 0 or not out_json.exists():
                tail = log_path.read_text()[-500:]
                raise RuntimeError(f"화자 분리 실패(코드 {p.returncode}): {tail}")
            raw = json.loads(out_json.read_text())
            return [SpeakerSegment(s["speakerId"], s["startTimeSeconds"], s["endTimeSeconds"])
                    for s in raw["segments"]]

    def live_session(self, model, terms, language, chunk_sec):
        return MacLiveSession(model, terms, language, chunk_sec)
