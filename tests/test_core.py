import json
import os
import subprocess
import sys
from pathlib import Path
import pytest
from engine import core
from engine.cli import get_backend


def asr(text, intervals):
    return {"text": text, "segments": [{"text": word, "start": start, "end": end}
            for word, (start, end) in zip(text.split(), intervals)]}


def test_speaker_numbers_follow_first_appearance():
    data = asr("one two three", [(0, 1), (1, 2), (3, 4)])
    lines, count = core.build_lines(data, [dict(speaker=9, start=0, end=2),
                                         dict(speaker=3, start=3, end=4)])
    assert lines == [dict(spk=1, t=0, body="one two"), dict(spk=2, t=3, body="three")]
    assert count == 2


@pytest.mark.parametrize("gap,count", [(core.MAX_GAP, 1), (core.MAX_GAP + .01, 2)])
def test_gap_boundary(gap, count):
    lines, _ = core.build_lines(asr("one two", [(0, 1), (1 + gap, 2 + gap)]), [])
    assert len(lines) == count


@pytest.mark.parametrize("text,start,count", [("one. two", 60, 1),
    ("one. two", 60.01, 2), ("one two", 60.01, 1)])
def test_length_requires_sentence_end(text, start, count):
    lines, _ = core.build_lines(asr(text, [(0, start), (start, start + 1)]), [])
    assert len(lines) == count


def test_speaker_nearest_and_overlap():
    segs = [dict(speaker=8, start=1, end=3), dict(speaker=2, start=4, end=8)]
    assert core.speaker_at(segs, [1, 4], 2, 6) == 2
    assert core.speaker_at(segs, [1, 4], 9, 10) == 2


@pytest.mark.parametrize("text,expected", [("A B C", []), ("A B C D", [(0, 7)]),
    ("A B C D E", [(0, 9)]), ("A B unrelated C D", []), ("D C B A", [])])
def test_leak_min_and_order(text, expected):
    assert core.find_leaks(text, ["A", "B", "C", "D", "E"]) == expected


def test_multiword_terms_count_distinct_terms():
    assert core.find_leaks("free wheeling diode PWM", ["free wheeling diode", "PWM"]) == []
    text = "intro A B C D outro"
    leaks = core.find_leaks(text, ["A", "B", "C", "D"])
    lines, _ = core.build_lines(asr(text, [(i, i + .5) for i in range(6)]), [], leaks)
    assert lines == [dict(spk=1, t=0, body="intro"), dict(spk=1, t=5, body="outro")]


@pytest.mark.parametrize("data", [None, {}, {"vault": ""}, {"vault": 3}, "invalid"])
def test_no_vault_disables_wiki_without_writes(work_dir, monkeypatch, data):
    path = work_dir / "config.json"
    if data is not None:
        path.write_text(data if data == "invalid" else json.dumps(data))
    before = path.read_bytes() if path.exists() else None
    monkeypatch.setattr(core, "CONFIG", path)
    assert core.load_config()["vault"] == ""
    assert core.resolve_wiki_dir("relative") is None
    assert core.resolve_wiki_dir(str(work_dir / "absolute")) is None
    assert (path.read_bytes() if path.exists() else None) == before


def test_config_resolves_relative_and_absolute(work_dir, monkeypatch):
    path = work_dir / "config.json"
    path.write_text(json.dumps({"vault": str(work_dir), "semester": "semester"}))
    monkeypatch.setattr(core, "CONFIG", path)
    assert core.resolve_wiki_dir("course/transcript") == str(work_dir / "course/transcript")
    assert core.resolve_wiki_dir("/absolute") == "/absolute"
    assert core.resolve_wiki_dir("relative", "") is None
    assert core.load_config()["semester"] == "semester"


def test_missing_profiles_are_read_only(work_dir, monkeypatch):
    monkeypatch.setattr(core, "PROFILES", work_dir / "missing/profiles.json")
    assert "전력전자" in core.load_profiles()
    assert not core.PROFILES.parent.exists()


def test_environment_paths_and_show_config(work_dir):
    env = dict(os.environ, HOME=str(work_dir), XDG_DATA_HOME=str(work_dir / "data"),
               PYTHONDONTWRITEBYTECODE="1")
    result = subprocess.run([sys.executable, "voicenote.py", "show-config"], env=env,
                            capture_output=True, text=True)
    assert result.returncode == 0
    assert "vault: vault 없음" in result.stdout
    assert "wiki_dir=None" in result.stdout
    assert not list(work_dir.rglob("config.json"))
    assert not list(work_dir.rglob("profiles.json"))


def test_windows_backend_override(monkeypatch):
    monkeypatch.setenv("VNOTE_BACKEND", "win")
    backend = get_backend()
    for call in [lambda: backend.transcribe(None, None, [], None),
                 lambda: backend.diarize(None, None),
                 lambda: backend.live_session("model", [], None, 2),
                 lambda: backend.convert(None, None), backend.validate]:
        with pytest.raises(NotImplementedError, match="윈도우 엔진은 0단계 실측 후 구현"):
            call()


def test_platform_backend_and_binary_override(monkeypatch):
    monkeypatch.delenv("VNOTE_BACKEND", raising=False)
    monkeypatch.setattr(sys, "platform", "win32")
    assert get_backend().__class__.__name__ == "WindowsBackend"
    monkeypatch.setenv("VNOTE_BACKEND", "mac")
    monkeypatch.setenv("VNOTE_FLUID_BIN", "/custom/fluid")
    assert get_backend().diarizer_bin == Path("/custom/fluid")
    assert get_backend(diarizer_bin="/argument/fluid").diarizer_bin == Path("/argument/fluid")


def test_markdown_default_model_and_unique_name(work_dir):
    src = work_dir / "clip.wav"
    src.touch()
    args = (src, 61.9, None, {}, [dict(spk=1, t=0, body="hello")], 1, work_dir)
    dst = core.write_markdown(*args, core.ASR_MODEL)
    assert "engine: qwen3-asr-1.7b-8bit + fluidaudio-offline\n" in dst.read_text()
    assert "duration: 1:01\nprofile: -\nspeakers: 1\n" in dst.read_text()
    assert dst.read_text().endswith("---\n\n[0:00] 화자1: hello\n")
    second = core.write_markdown(*args, "custom/mlx-qwen3-asr-0.6b-4bit")
    assert second.stem.endswith(" (2)")
    assert "engine: qwen3-asr-0.6b-4bit + fluidaudio-offline" in second.read_text()
