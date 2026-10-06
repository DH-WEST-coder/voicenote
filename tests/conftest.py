"""시험 출력과 임시 파일은 worktree 안에만 둔다."""
import tempfile
from pathlib import Path
import pytest


@pytest.fixture
def work_dir():
    root = Path(__file__).resolve().parents[1] / "out/dist-test/tmp"
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=root) as folder:
        yield Path(folder)
