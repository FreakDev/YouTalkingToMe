"""JSON-line IPC server for You Talking To Me STT inference."""

from __future__ import annotations

import json
import os
import sys
import traceback
from pathlib import Path

from huggingface_hub import snapshot_download
from stt import transcribe

MODELS_CONFIG = Path(__file__).parent / "models.json"


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def default_cache_dir() -> str:
    return os.environ.get(
        "YTTM_MODELS_CACHE_DIR",
        str(Path.home() / "Library" / "Application Support" / "YouTalkingToMe" / "models"),
    )


def load_tiers() -> dict:
    with MODELS_CONFIG.open() as f:
        data = json.load(f)
    return data["tiers"]


def download_model(repo: str, cache_dir: str) -> str:
    return snapshot_download(repo_id=repo, cache_dir=cache_dir)


class InferenceServer:
    def __init__(self, cache_dir: str | None = None) -> None:
        self.tiers = load_tiers()
        self.cache_dir = cache_dir or default_cache_dir()
        self.current_tier = "fast"
        self.stt_model_path: str | None = None

    def handle(self, message: dict) -> None:
        command = message.get("command")
        request_id = message.get("request_id")

        def emit_response(payload: dict) -> None:
            if request_id:
                payload["request_id"] = request_id
            emit(payload)

        try:
            if command == "ping":
                emit_response({"type": "result", "command": "ping", "ok": True})
            elif command == "load_models":
                self._load_models(message.get("tier", "fast"), emit_response)
            elif command == "transcribe":
                audio_path = message.get("audio_path", "")
                text = transcribe(audio_path, self._stt_model())
                emit_response({"type": "result", "command": "transcribe", "text": text})
            else:
                emit_response({"type": "error", "message": f"Unknown command: {command}"})
        except Exception as exc:  # noqa: BLE001
            emit_response({"type": "error", "message": str(exc), "trace": traceback.format_exc()})

    def _stt_repo(self) -> str:
        tier = self.tiers.get(self.current_tier, self.tiers["fast"])
        return tier["stt"]

    def _stt_model(self) -> str:
        if self.stt_model_path:
            return self.stt_model_path
        return self._stt_repo()

    def _load_models(self, tier: str, emit_response) -> None:
        if tier not in self.tiers:
            raise ValueError(f"Unknown tier: {tier}")

        self.current_tier = tier
        stt_repo = self._stt_repo()

        emit({"type": "progress", "stage": "download_stt", "model": stt_repo, "percent": 0})
        stt_path = download_model(stt_repo, self.cache_dir)
        emit({"type": "progress", "stage": "download_stt", "model": stt_repo, "percent": 1})

        self.stt_model_path = stt_path

        emit_response(
            {
                "type": "result",
                "command": "load_models",
                "tier": tier,
                "stt_path": stt_path,
            }
        )


def main() -> None:
    server = InferenceServer()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            emit({"type": "error", "message": "Invalid JSON"})
            continue
        server.handle(message)


if __name__ == "__main__":
    main()
