"""ML smoke tests for polish engine."""

from __future__ import annotations

from pathlib import Path

import pytest

from polish import PolishEngine
from server import download_model


def _models_cached() -> bool:
    cache = Path.home() / "Library" / "Application Support" / "YouTalkingToMe" / "models"
    return cache.exists() and any(cache.iterdir())


pytestmark = [
    pytest.mark.smoke,
    pytest.mark.skipif(not _models_cached(), reason="ML models not cached locally"),
]


@pytest.mark.smoke
def test_polish_smoke():
    cache_dir = str(Path.home() / "Library" / "Application Support" / "YouTalkingToMe" / "models")
    polish_path = download_model("mlx-community/Qwen2.5-1.5B-Instruct-4bit", cache_dir)

    engine = PolishEngine()
    engine.load(polish_path)

    result = engine.polish("euh bonjour le mardi euh")
    assert isinstance(result, str)
    assert len(result.strip()) > 0
