"""ML smoke tests for speech-to-text."""

from __future__ import annotations

from pathlib import Path

import pytest

from stt import transcribe


def _models_cached() -> bool:
    cache = Path.home() / "Library" / "Application Support" / "YouTalkingToMe" / "models"
    return cache.exists() and any(cache.iterdir())


pytestmark = [
    pytest.mark.smoke,
    pytest.mark.skipif(not _models_cached(), reason="ML models not cached locally"),
]


@pytest.mark.smoke
def test_transcribe_smoke(wav_mono_16k):
    result = transcribe(str(wav_mono_16k), "mlx-community/whisper-small-mlx")
    assert isinstance(result, str)
