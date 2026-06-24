"""Runtime import audit tests."""

from __future__ import annotations

import importlib
import sys
import types

import pytest

FORBIDDEN_AT_IMPORT = {"pytest", "pip", "_pytest"}


def test_core_modules_import_without_forbidden():
    before = set(sys.modules.keys())
    for module_name in ("stt", "polish", "server"):
        sys.modules.pop(module_name, None)

    for module_name in ("stt", "polish", "server"):
        importlib.import_module(module_name)

    newly_loaded = set(sys.modules.keys()) - before
    loaded_forbidden = FORBIDDEN_AT_IMPORT.intersection(newly_loaded)
    assert not loaded_forbidden, f"Forbidden modules loaded: {loaded_forbidden}"


def test_transcribe_does_not_import_torch(monkeypatch, wav_mono_16k):
    import stt as stt_module

    fake_whisper = types.SimpleNamespace(
        transcribe=lambda audio, path_or_hf_repo, verbose=False: {"text": "hello"}
    )
    monkeypatch.setitem(sys.modules, "mlx_whisper", fake_whisper)
    sys.modules.pop("torch", None)

    result = stt_module.transcribe(str(wav_mono_16k), "mlx-community/whisper-small-mlx")
    assert result == "hello"
    assert "torch" not in sys.modules
