import pytest

from engine.backends.mac import MacBackend


@pytest.mark.parametrize(
    ("message", "expected"),
    [("Failed to process audio file (offline mode): noSpeechDetected", "empty"),
     ("Failed to process audio file (offline mode): modelFailure", "error")],
)
def test_fluid_diarize_failure_modes_use_fake_binary(work_dir, monkeypatch, message, expected):
    binary = work_dir / "fluidaudiocli"
    binary.write_text(f"#!/bin/sh\necho '{message}' >&2\nexit 1\n")
    binary.chmod(0o755)
    wav = work_dir / "audio.wav"
    wav.touch()
    monkeypatch.setattr("engine.models.fluid_env", lambda: {})

    backend = MacBackend("model", binary)
    if expected == "empty":
        assert backend.diarize(wav, None) == []
    else:
        with pytest.raises(RuntimeError, match="화자 분리 실패"):
            backend.diarize(wav, None)
