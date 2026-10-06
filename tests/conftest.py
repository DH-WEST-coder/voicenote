"""시험 출력과 임시 파일은 worktree 안에만 둔다."""
import tempfile
from pathlib import Path
import pytest
from unittest.mock import patch

# core의 개인용 기본 프로필 초기화가 실제 사용자 설정을 열지 않도록
# collection 이전에 OS 표준 경로 함수만 시험 폴더로 바꿔 import한다.
_TEST_ROOT = Path(__file__).resolve().parents[1] / "out/dist-test/config-fixture"
with patch("platformdirs.user_data_dir", return_value=str(_TEST_ROOT)), \
     patch("platformdirs.user_documents_dir", return_value=str(_TEST_ROOT)):
    import engine.core  # noqa: F401


@pytest.fixture
def work_dir():
    root = Path(__file__).resolve().parents[1] / "out/dist-test/tmp"
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=root) as folder:
        yield Path(folder)
