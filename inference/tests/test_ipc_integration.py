"""Subprocess IPC integration tests for server.py."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


INFERENCE_DIR = Path(__file__).resolve().parent.parent
SERVER = INFERENCE_DIR / "server.py"


def _run_server_commands(commands: list[dict], timeout: float = 10.0) -> list[dict]:
    python = INFERENCE_DIR / ".venv" / "bin" / "python"
    executable = str(python if python.exists() else sys.executable)

    proc = subprocess.Popen(
        [executable, str(SERVER)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        cwd=str(INFERENCE_DIR),
    )

    assert proc.stdin is not None
    assert proc.stdout is not None

    for command in commands:
        proc.stdin.write(json.dumps(command) + "\n")
        proc.stdin.flush()

    proc.stdin.close()

    lines: list[dict] = []
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        lines.append(json.loads(line))

    proc.wait(timeout=timeout)
    return lines


def test_ipc_ping():
    lines = _run_server_commands([{"command": "ping"}])
    assert lines == [{"type": "result", "command": "ping", "ok": True}]


def test_ipc_invalid_json():
    python = INFERENCE_DIR / ".venv" / "bin" / "python"
    executable = str(python if python.exists() else sys.executable)

    proc = subprocess.Popen(
        [executable, str(SERVER)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        cwd=str(INFERENCE_DIR),
    )

    assert proc.stdin is not None
    assert proc.stdout is not None

    proc.stdin.write("not json\n")
    proc.stdin.flush()
    proc.stdin.close()

    line = proc.stdout.readline().strip()
    proc.wait(timeout=5)

    payload = json.loads(line)
    assert payload["type"] == "error"
    assert payload["message"] == "Invalid JSON"


def test_ipc_one_result_per_command():
    lines = _run_server_commands([{"command": "ping"}, {"command": "ping"}])
    results = [line for line in lines if line.get("type") == "result"]
    assert len(results) == 2
    assert all(line.get("command") == "ping" for line in results)
