"""백엔드 교체 시 유지할 데이터와 호출 계약."""
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


@dataclass
class WordTimestamp:
    text: str
    start: float
    end: float


@dataclass
class Transcript:
    text: str
    segments: list[WordTimestamp]


@dataclass
class SpeakerSegment:
    speaker: int | str
    start: float
    end: float


@dataclass
class LiveState:
    chunk_id: int
    committed_text: str
    window_text: str
    buffer_samples: int
    audio_samples: int


class LiveSession(ABC):
    @abstractmethod
    def init(self) -> LiveState: ...

    @abstractmethod
    def feed(self, pcm) -> LiveState: ...

    @abstractmethod
    def finish(self) -> LiveState: ...


class Backend(ABC):
    def validate(self):
        """모델 실행 전 필요한 바이너리 등을 확인한다."""

    @abstractmethod
    def convert(self, src: Path, wav: Path): ...

    @abstractmethod
    def transcribe(self, wav: Path, language: str | None, terms: list[str],
                   on_progress: Callable[[dict], None]) -> Transcript: ...

    @abstractmethod
    def diarize(self, wav: Path, speakers: int | None) -> list[SpeakerSegment]: ...

    @abstractmethod
    def live_session(self, model: str, terms: list[str], language: str | None,
                     chunk_sec: float) -> LiveSession: ...
