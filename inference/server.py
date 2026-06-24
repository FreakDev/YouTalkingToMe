"""JSON-line IPC server for You Talking To Me inference."""

from __future__ import annotations

import json
import sys
import traceback
from pathlib import Path

from huggingface_hub import snapshot_download
from polish import PolishEngine
from stt import transcribe

MODELS_CONFIG = Path(__file__).parent / "models.json"


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def load_tiers() -> dict:
    with MODELS_CONFIG.open() as f:
        data = json.load(f)
    return data["tiers"]


def download_model(repo: str, cache_dir: str) -> str:
    return snapshot_download(repo_id=repo, cache_dir=cache_dir)


class InferenceServer:
    def __init__(self) -> None:
        self.tiers = load_tiers()
        self.cache_dir = str(Path.home() / "Library" / "Application Support" / "YouTalkingToMe" / "models")
        self.current_tier = "fast"
        self.polish_engine = PolishEngine()
        self.stt_model_path: str | None = None

    def handle(self, message: dict) -> None:
        command = message.get("command")
        try:
            if command == "ping":
                emit({"type": "result", "command": "ping", "ok": True})
            elif command == "load_models":
                self._load_models(message.get("tier", "fast"))
            elif command == "transcribe":
                audio_path = message.get("audio_path", "")
                text = transcribe(audio_path, self._stt_model())
                emit({"type": "result", "command": "transcribe", "text": text})
            elif command == "polish":
                raw = message.get("text", "")
                polished = self.polish_engine.polish(raw)
                emit({"type": "result", "command": "polish", "text": polished})
            elif command == "transcribe_and_polish":
                audio_path = message.get("audio_path", "")
                raw = transcribe(audio_path, self._stt_model())
                polished = self.polish_engine.polish(raw)
                emit(
                    {
                        "type": "result",
                        "command": "transcribe_and_polish",
                        "raw_text": raw,
                        "text": polished,
                    }
                )
            else:
                emit({"type": "error", "message": f"Unknown command: {command}"})
        except Exception as exc:  # noqa: BLE001
            emit({"type": "error", "message": str(exc), "trace": traceback.format_exc()})

    def _stt_repo(self) -> str:
        tier = self.tiers.get(self.current_tier, self.tiers["fast"])
        return tier["stt"]

    def _polish_repo(self) -> str:
        tier = self.tiers.get(self.current_tier, self.tiers["fast"])
        return tier["polish"]

    def _stt_model(self) -> str:
        if self.stt_model_path:
            return self.stt_model_path
        return self._stt_repo()

    def _load_models(self, tier: str) -> None:
        if tier not in self.tiers:
            raise ValueError(f"Unknown tier: {tier}")

        self.current_tier = tier
        stt_repo = self._stt_repo()
        polish_repo = self._polish_repo()

        emit({"type": "progress", "stage": "download_stt", "model": stt_repo, "percent": 0})
        stt_path = download_model(stt_repo, self.cache_dir)
        emit({"type": "progress", "stage": "download_stt", "model": stt_repo, "percent": 1})

        emit({"type": "progress", "stage": "download_polish", "model": polish_repo, "percent": 0})
        polish_path = download_model(polish_repo, self.cache_dir)
        emit({"type": "progress", "stage": "download_polish", "model": polish_repo, "percent": 1})

        self.stt_model_path = stt_path
        self.polish_engine.load(polish_path)

        emit(
            {
                "type": "result",
                "command": "load_models",
                "tier": tier,
                "stt_path": stt_path,
                "polish_path": polish_path,
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
