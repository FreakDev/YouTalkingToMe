"""ML smoke test for full transcribe_and_polish pipeline."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from conftest import write_wav
from server import InferenceServer, download_model

pytestmark = pytest.mark.smoke


def _models_cached() -> bool:
    cache = Path.home() / "Library" / "Application Support" / "YouTalkingToMe" / "models"
    return cache.exists() and any(cache.iterdir())


@pytest.mark.skipif(not _models_cached(), reason="ML models not cached locally")
def test_pipeline_smoke(emit_capture, tmp_path):
    cache = str(Path.home() / "Library" / "Application Support" / "YouTalkingToMe" / "models")
    stt_path = download_model("mlx-community/whisper-small-mlx", cache)
    polish_path = download_model("mlx-community/Qwen2.5-1.5B-Instruct-4bit", cache)

    t = np.linspace(0, 1.0, int(16000 * 1.0), endpoint=False)
    tone = (np.sin(2 * np.pi * 220 * t) * 12000).astype(np.int16)
    wav_path = write_wav(tmp_path / "pipeline.wav", sample_rate=16000, frames=tone)

    server = InferenceServer()
    server.stt_model_path = stt_path
    server.polish_engine.load(polish_path)

    server.handle({"command": "transcribe_and_polish", "audio_path": str(wav_path)})

    result_messages = [msg for msg in emit_capture if msg.get("type") == "result"]
    assert len(result_messages) == 1
    payload = result_messages[0]
    assert payload["command"] == "transcribe_and_polish"
    assert isinstance(payload.get("raw_text"), str)
    assert isinstance(payload.get("text"), str)
