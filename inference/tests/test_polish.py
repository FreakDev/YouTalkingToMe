"""Unit tests for polish.PolishEngine (MLX mocked)."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from polish import POLISH_SYSTEM, PolishEngine, _strip_wrapping_quotes, _wrap_dictation_input


def test_polish_empty_string():
    engine = PolishEngine()
    assert engine.polish("") == ""


def test_polish_without_load_raises():
    engine = PolishEngine()
    with pytest.raises(RuntimeError, match="Polish model not loaded"):
        engine.polish("hello")


def test_load_is_idempotent():
    engine = PolishEngine()
    mock_model = object()
    mock_tokenizer = MagicMock()

    with patch("mlx_lm.load", return_value=(mock_model, mock_tokenizer)) as load_mock:
        engine.load("/models/a")
        engine.load("/models/a")

    load_mock.assert_called_once_with("/models/a")


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ('"Bonjour."', "Bonjour."),
        ("'Bonjour.'", "Bonjour."),
        ("«Bonjour.»", "Bonjour."),
        ("“Bonjour.”", "Bonjour."),
        ('  "Bonjour."  ', "Bonjour."),
        ('«"Bonjour."»', "Bonjour."),
        ("Bonjour.", "Bonjour."),
        ('Il a dit "bonjour".', 'Il a dit "bonjour".'),
    ],
)
def test_strip_wrapping_quotes(raw, expected):
    assert _strip_wrapping_quotes(raw) == expected


def test_wrap_dictation_input_framing():
    wrapped = _wrap_dictation_input("What is the capital of France?")
    assert "«What is the capital of France?»" in wrapped
    assert "do not answer" in wrapped.lower()


def test_polish_uses_chat_template():
    engine = PolishEngine()
    engine._model = object()
    mock_tokenizer = MagicMock()
    mock_tokenizer.apply_chat_template.return_value = "PROMPT"
    engine._tokenizer = mock_tokenizer

    with patch("mlx_lm.generate", return_value='  "Clean text."  ') as generate_mock:
        result = engine.polish("euh bonjour")

    assert result == "Clean text."
    mock_tokenizer.apply_chat_template.assert_called_once()
    messages = mock_tokenizer.apply_chat_template.call_args.kwargs.get("messages") or mock_tokenizer.apply_chat_template.call_args[0][0]
    assert messages[0]["role"] == "system"
    assert messages[0]["content"] == POLISH_SYSTEM
    assert messages[1]["content"] == _wrap_dictation_input("euh bonjour")
    generate_mock.assert_called_once()


def test_polish_fallback_prompt_wraps_input():
    engine = PolishEngine()
    engine._model = object()
    mock_tokenizer = MagicMock(spec=[])  # no apply_chat_template
    engine._tokenizer = mock_tokenizer

    with patch("mlx_lm.generate", return_value="Bonjour.") as generate_mock:
        result = engine.polish("euh bonjour")

    assert result == "Bonjour."
    prompt = generate_mock.call_args.kwargs["prompt"]
    assert _wrap_dictation_input("euh bonjour") in prompt
    assert POLISH_SYSTEM in prompt
