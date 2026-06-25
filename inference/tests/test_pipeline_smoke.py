"""ML smoke test for full transcribe_and_polish pipeline."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest

from conftest import models_cached
from server import InferenceServer, download_model


@pytest.mark.skipif(not models_cached(), reason="ML models not cached locally")
def test_transcribe_and_polish_returns_polished_text(monkeypatch, tmp_path):
    """Regression: bundled transformers pruning must not leave polish returning empty text."""
    import server as server_module

    outputs: list[dict] = []

    def capture(payload: dict) -> None:
        outputs.append(payload)

    monkeypatch.setattr(server_module, "emit", capture)

    cache = str(Path.home() / "Library/Application Support/YouTalkingToMe/models")
    polish_path = download_model("mlx-community/gemma-4-e2b-it-4bit", cache)

    server = server_module.InferenceServer()
    server.polish_engine.load(polish_path)

    raw_transcript = "euh bonjour le mardi euh"
    with patch("server.transcribe", return_value=raw_transcript):
        server.handle({"command": "transcribe_and_polish", "audio_path": "/tmp/unused.wav"})

    result_messages = [msg for msg in outputs if msg.get("type") == "result"]
    assert len(result_messages) == 1
    payload = result_messages[0]
    assert payload["command"] == "transcribe_and_polish"
    assert payload["raw_text"] == raw_transcript
    assert isinstance(payload.get("text"), str)
    assert payload["text"].strip(), "Polish must return non-empty text for non-empty transcript"
