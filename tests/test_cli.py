import argparse
import io
import json
import os
import subprocess
import sys
from pathlib import Path
from engine import cli
from engine.backends.base import LiveState, SpeakerSegment, Transcript, WordTimestamp


class FakeBackend:
    def validate(self):
        pass

    def convert(self, src, wav):
        Path(wav).touch()

    def transcribe(self, wav, language, terms, on_progress):
        assert language == "English"
        assert terms == ["PWM", "ripple"]
        for progress in [0, .001, .5, 1]:
            on_progress({"progress": progress})
        return Transcript("hello world", [WordTimestamp("hello", 0, 1), WordTimestamp("world", 1, 2)])

    def diarize(self, wav, speakers):
        assert speakers == 2
        return [SpeakerSegment(7, 0, 2)]

    def live_session(self, model, terms, language, chunk_sec):
        return FakeSession()


class FakeSession:
    def init(self):
        return LiveState(0, "", "", 0, 0)

    def feed(self, pcm):
        assert len(pcm) == 16000
        return LiveState(1, "", "hello", 0, len(pcm))

    def finish(self):
        return LiveState(1, "hello", "", 0, 0)


def test_batch_protocol_and_arguments(work_dir, monkeypatch):
    source, terms = work_dir / "clip.wav", work_dir / "terms.txt"
    source.touch()
    terms.write_text("PWM\npwm\nripple\n")
    args = argparse.Namespace(audio=str(source), profile=None, terms_file=str(terms), language="English",
        course="Course", asr_model="custom/model", diarizer_bin="/custom/bin", speakers=2, out=str(work_dir))
    received = {}

    def select(**kwargs):
        received.update(kwargs)
        return FakeBackend()

    monkeypatch.setattr(cli, "get_backend", select)
    monkeypatch.setattr(cli, "wav_duration", lambda wav: 2)
    events = []
    rep = argparse.Namespace(emit=lambda stage, **kwargs: events.append(dict(stage=stage, **kwargs)))
    dst = cli.transcribe_file(args, rep)
    assert received == dict(asr_model="custom/model", diarizer_bin="/custom/bin")
    assert [e['progress'] for e in events if e.get('status') == 'progress'] == [0, .5, 1]
    # 병렬 화자 분리의 완료 위치는 스케줄러에 따라 바뀔 수 있다.
    assert [e.get('status') for e in events if e['stage'] == 'asr'] == ['start', 'progress', 'progress', 'progress', 'done']
    assert events[-1] == dict(stage='merge', status='done', lines=1, speakers=1)
    assert "course: Course\nprovenance:" in dst.read_text()
    assert "engine: model + fluidaudio-offline" in dst.read_text()


def test_diarize_failure_skips_and_keeps_empty_asr(work_dir, monkeypatch):
    source = work_dir / "clip.wav"
    source.touch()

    class FailedDiarBackend(FakeBackend):
        def transcribe(self, wav, language, terms, on_progress):
            return Transcript("", [])

        def diarize(self, wav, speakers):
            raise RuntimeError("fluidaudiocli diagnostic")

    monkeypatch.setattr(cli, "get_backend", lambda **kwargs: FailedDiarBackend())
    monkeypatch.setattr(cli, "wav_duration", lambda wav: 14)
    events = []
    rep = argparse.Namespace(emit=lambda stage, **kwargs: events.append(dict(stage=stage, **kwargs)))
    args = argparse.Namespace(audio=str(source), profile=None, terms_file=None, language=None, course=None,
        asr_model="custom/model", diarizer_bin="/custom/bin", speakers=None, out=str(work_dir))
    dst = cli.transcribe_file(args, rep)

    assert len([e for e in events if e == {"stage": "diarize", "status": "skipped", "reason": "화자 분리 실패"}]) == 1
    assert events[-1]["stage"] == "merge" and events[-1]["speakers"] == 0
    assert "본문이 없습니다." in dst.read_text()


def test_live_protocol_commit_tail_and_incomplete_pcm(monkeypatch):
    import numpy as np
    output = io.StringIO()
    monkeypatch.setattr(sys, "stdout", output)
    monkeypatch.setattr(sys, "stdin", argparse.Namespace(buffer=io.BytesIO(np.zeros(16000, dtype='<f4').tobytes() + b'x')))
    monkeypatch.setattr(cli, "get_backend", lambda: FakeBackend())
    args = argparse.Namespace(profile=None, terms_file=None, language=None, model="fake", chunk_sec=2,
                              input_file=None, duration=None, realtime=False)
    assert cli.run_live(args) == 0
    events = [json.loads(line) for line in output.getvalue().splitlines()]
    assert [e['type'] for e in events] == ['loading', 'ready', 'partial', 'commit', 'stats', 'done']
    assert events[3] == dict(type='commit', start=0.0, end=1.0, text='hello')
    assert events[4]['final'] is True


def test_live_backend_error_is_json(monkeypatch):
    output = io.StringIO()
    monkeypatch.setattr(sys, "stdout", output)
    monkeypatch.setenv("VNOTE_BACKEND", "win")
    args = argparse.Namespace(profile=None, terms_file=None, language=None, model="fake", chunk_sec=2)
    assert cli.run_live(args) == 1
    events = [json.loads(line) for line in output.getvalue().splitlines()]
    assert [e['type'] for e in events] == ['loading', 'error']
    assert events[-1]['message'] == "윈도우 엔진은 0단계 실측 후 구현"


def test_selftest_imports_command():
    root = Path(__file__).resolve().parents[1]
    completed = subprocess.run(
        [sys.executable, str(root / "voicenote.py"), "selftest-imports", "--json"],
        cwd=root,
        env={**os.environ, "VNOTE_BACKEND": "win"},
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert len(completed.stdout.splitlines()) == 1
    report = json.loads(completed.stdout)
    assert report["status"] == "ok"
    assert all(check["ok"] for check in report["checks"].values())
    assert all(item["tokens"] for item in report["checks"]["tokenizers"]["languages"].values())
