"""Speech-to-text via mlx-whisper."""

from __future__ import annotations

import wave
from math import gcd

import numpy as np
from scipy.signal import resample_poly

SAMPLE_RATE = 16000


def load_wav(path: str, target_sr: int = SAMPLE_RATE) -> np.ndarray:
    """Load a WAV file as mono float32 at 16 kHz (Whisper input format)."""
    with wave.open(path, "rb") as wf:
        channels = wf.getnchannels()
        sample_width = wf.getsampwidth()
        sample_rate = wf.getframerate()
        raw = wf.readframes(wf.getnframes())

    if sample_width == 2:
        audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    elif sample_width == 4:
        audio = np.frombuffer(raw, dtype=np.float32)
    else:
        raise ValueError(f"Unsupported WAV sample width: {sample_width} bytes")

    if channels > 1:
        audio = audio.reshape(-1, channels).mean(axis=1)

    if sample_rate != target_sr:
        factor = gcd(sample_rate, target_sr)
        audio = resample_poly(audio, target_sr // factor, sample_rate // factor).astype(np.float32)

    return audio


def transcribe(audio_path: str, model_repo: str) -> str:
    import mlx_whisper

    audio = load_wav(audio_path)
    result = mlx_whisper.transcribe(
        audio,
        path_or_hf_repo=model_repo,
        verbose=False,
    )
    text = result.get("text", "").strip()
    return text
