"""0단계 실측 전 Windows 자리 표시."""
from engine.backends.base import Backend


class WindowsBackend(Backend):
    def validate(self):
        raise NotImplementedError("윈도우 엔진은 0단계 실측 후 구현")

    def convert(self, src, wav):
        raise NotImplementedError("윈도우 엔진은 0단계 실측 후 구현")

    def transcribe(self, wav, language, terms, on_progress):
        raise NotImplementedError("윈도우 엔진은 0단계 실측 후 구현")

    def diarize(self, wav, speakers):
        raise NotImplementedError("윈도우 엔진은 0단계 실측 후 구현")

    def live_session(self, model, terms, language, chunk_sec):
        raise NotImplementedError("윈도우 엔진은 0단계 실측 후 구현")
