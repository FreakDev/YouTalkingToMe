"""Unit tests for inference server command handling."""

from __future__ import annotations

import pytest


def test_ping(inference_server):
    server, outputs = inference_server
    server.handle({"command": "ping"})
    assert outputs == [{"type": "result", "command": "ping", "ok": True}]


def test_unknown_command(inference_server):
    server, outputs = inference_server
    server.handle({"command": "foo"})
    assert len(outputs) == 1
    assert outputs[0]["type"] == "error"
    assert "Unknown command" in outputs[0]["message"]


def test_load_models_unknown_tier(inference_server):
    server, outputs = inference_server
    server.handle({"command": "load_models", "tier": "nonexistent"})
    assert len(outputs) == 1
    assert outputs[0]["type"] == "error"
    assert "Unknown tier" in outputs[0]["message"]


def test_load_models_progress_and_result(inference_server, monkeypatch):
    server, outputs = inference_server

    monkeypatch.setattr(
        "server.download_model",
        lambda repo, cache_dir: f"/fake/{repo.split('/')[-1]}",
    )

    server.handle({"command": "load_models", "tier": "fast"})

    assert outputs[0]["type"] == "progress"
    assert outputs[0]["stage"] == "download_stt"
    assert outputs[1]["type"] == "progress"
    assert outputs[1]["stage"] == "download_stt"
    assert outputs[1]["percent"] == 1
    assert outputs[-1]["type"] == "result"
    assert outputs[-1]["command"] == "load_models"
    assert outputs[-1]["tier"] == "fast"
    assert "polish_path" not in outputs[-1]


def test_transcribe_without_models(inference_server, monkeypatch, wav_mono_16k):
    server, outputs = inference_server

    def _fail_transcribe(audio_path, model_repo):
        raise RuntimeError(f"model not loaded: {model_repo}")

    monkeypatch.setattr("server.transcribe", _fail_transcribe)

    server.handle({"command": "transcribe", "audio_path": str(wav_mono_16k)})

    assert len(outputs) == 1
    assert outputs[0]["type"] == "error"
    assert "model not loaded" in outputs[0]["message"]


def test_transcribe_success(inference_server, monkeypatch, wav_mono_16k):
    server, outputs = inference_server

    monkeypatch.setattr("server.transcribe", lambda audio_path, model_repo: "bonjour")

    server.handle({"command": "transcribe", "audio_path": str(wav_mono_16k)})

    assert outputs[-1] == {
        "type": "result",
        "command": "transcribe",
        "text": "bonjour",
    }
