"""Unit tests for stt.load_wav."""

from __future__ import annotations

import wave

import numpy as np
import pytest

from stt import SAMPLE_RATE, load_wav


def test_load_wav_mono_16k(wav_mono_16k):
    audio = load_wav(str(wav_mono_16k))
    assert audio.dtype == np.float32
    assert audio.ndim == 1
    assert len(audio) > 0
    assert audio.min() >= -1.0
    assert audio.max() <= 1.0


def test_load_wav_stereo_to_mono(wav_stereo_16k):
    audio = load_wav(str(wav_stereo_16k))
    assert audio.ndim == 1
    expected_frames = 1600
    assert abs(len(audio) - expected_frames) <= 2


def test_load_wav_resample_44k_to_16k(wav_44k_mono):
    audio = load_wav(str(wav_44k_mono))
    expected = int(round(4410 * SAMPLE_RATE / 44100))
    assert abs(len(audio) - expected) <= 2


def test_load_wav_float32(wav_float32_mono):
    audio = load_wav(str(wav_float32_mono))
    assert audio.dtype == np.float32
    assert len(audio) == 800


def test_load_wav_invalid_sample_width(wav_invalid_width):
    with pytest.raises(ValueError, match="Unsupported WAV sample width"):
        load_wav(str(wav_invalid_width))


def test_load_wav_missing_file(tmp_path):
    missing = tmp_path / "missing.wav"
    with pytest.raises(FileNotFoundError):
        load_wav(str(missing))
