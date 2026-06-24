"""Shared pytest fixtures for inference tests."""

from __future__ import annotations

import sys
import wave
from pathlib import Path

import numpy as np
import pytest

INFERENCE_DIR = Path(__file__).resolve().parent.parent
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"


@pytest.fixture
def inference_dir() -> Path:
    return INFERENCE_DIR


@pytest.fixture
def emit_capture(monkeypatch):
    """Capture server.emit payloads in a list."""
    outputs: list[dict] = []

    def _capture(payload: dict) -> None:
        outputs.append(payload)

    import server as server_module

    monkeypatch.setattr(server_module, "emit", _capture)
    return outputs


@pytest.fixture
def inference_server(emit_capture, monkeypatch):
    import server as server_module

    server = server_module.InferenceServer()
    return server, emit_capture


def write_wav(
    path: Path,
    *,
    sample_rate: int = 16000,
    channels: int = 1,
    sample_width: int = 2,
    frames: np.ndarray | None = None,
    num_frames: int = 1600,
) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)

    if frames is None:
        if sample_width == 2:
            frames = np.zeros(num_frames, dtype=np.int16)
        elif sample_width == 4:
            frames = np.zeros(num_frames, dtype=np.float32)
        else:
            raise ValueError(f"Unsupported sample_width: {sample_width}")

    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(sample_width)
        wf.setframerate(sample_rate)
        if sample_width == 2:
            if frames.dtype != np.int16:
                frames = frames.astype(np.int16)
            wf.writeframes(frames.tobytes())
        elif sample_width == 4:
            if frames.dtype != np.float32:
                frames = frames.astype(np.float32)
            wf.writeframes(frames.tobytes())
        else:
            wf.writeframes(frames.tobytes())

    return path


@pytest.fixture
def wav_mono_16k(tmp_path: Path) -> Path:
    t = np.linspace(0, 0.1, int(16000 * 0.1), endpoint=False)
    tone = (np.sin(2 * np.pi * 440 * t) * 16000).astype(np.int16)
    return write_wav(tmp_path / "mono_16k.wav", sample_rate=16000, frames=tone)


@pytest.fixture
def wav_stereo_16k(tmp_path: Path) -> Path:
    t = np.linspace(0, 0.1, int(16000 * 0.1), endpoint=False)
    left = (np.sin(2 * np.pi * 440 * t) * 16000).astype(np.int16)
    right = (np.sin(2 * np.pi * 880 * t) * 16000).astype(np.int16)
    interleaved = np.column_stack([left, right]).reshape(-1)
    path = tmp_path / "stereo_16k.wav"
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(16000)
        wf.writeframes(interleaved.tobytes())
    return path


@pytest.fixture
def wav_44k_mono(tmp_path: Path) -> Path:
    num_frames = 4410
    frames = np.zeros(num_frames, dtype=np.int16)
    return write_wav(tmp_path / "mono_44k.wav", sample_rate=44100, frames=frames)


@pytest.fixture
def wav_float32_mono(tmp_path: Path) -> Path:
    frames = np.zeros(800, dtype=np.float32)
    return write_wav(
        tmp_path / "float32.wav",
        sample_rate=16000,
        sample_width=4,
        frames=frames,
    )


@pytest.fixture
def wav_invalid_width(tmp_path: Path) -> Path:
    path = tmp_path / "bad.wav"
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(3)
        wf.setframerate(16000)
        wf.writeframes(b"\x00" * 48)
    return path


def models_cache_dir() -> Path:
    return Path.home() / "Library" / "Application Support" / "YouTalkingToMe" / "models"


def models_cached() -> bool:
    cache = models_cache_dir()
    return cache.exists() and any(cache.iterdir())


requires_models = pytest.mark.skipif(not models_cached(), reason="ML models not cached locally")


def pytest_addoption(parser):
    parser.addoption(
        "--smoke",
        action="store_true",
        default=False,
        help="Run ML smoke tests (require cached models)",
    )


def pytest_configure(config):
    config.addinivalue_line("markers", "smoke: ML smoke tests (require cached models)")


def pytest_collection_modifyitems(config, items):
    if config.getoption("--smoke"):
        return
    skip_smoke = pytest.mark.skip(reason="pass --smoke to run ML smoke tests")
    for item in items:
        if "smoke" in item.nodeid:
            item.add_marker(skip_smoke)
