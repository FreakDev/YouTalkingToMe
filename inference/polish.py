"""Polish raw transcripts with a local MLX LLM."""

from __future__ import annotations

POLISH_SYSTEM = (
    "You receive a raw voice dictation transcript. "
    "Clean the text: remove filler words (euh, bah, um, uh), "
    "apply self-corrections (e.g. 'Tuesday, wait no Friday' -> 'Friday'), "
    "add punctuation and capitalization. "
    "Output in the same language as the input. "
    "Do not add new content. Return only the final text."
)


class PolishEngine:
    def __init__(self) -> None:
        self._model = None
        self._tokenizer = None
        self._model_path: str | None = None

    def load(self, model_path: str) -> None:
        if self._model_path == model_path and self._model is not None:
            return
        from mlx_lm import load

        self._model, self._tokenizer = load(model_path)
        self._model_path = model_path

    def polish(self, raw_text: str) -> str:
        if not raw_text.strip():
            return ""
        if self._model is None or self._tokenizer is None:
            raise RuntimeError("Polish model not loaded")

        from mlx_lm import generate

        if hasattr(self._tokenizer, "apply_chat_template"):
            messages = [
                {"role": "system", "content": POLISH_SYSTEM},
                {"role": "user", "content": raw_text},
            ]
            prompt = self._tokenizer.apply_chat_template(
                messages,
                tokenize=False,
                add_generation_prompt=True,
            )
        else:
            prompt = f"System: {POLISH_SYSTEM}\nUser: {raw_text}\nAssistant:"

        response = generate(
            self._model,
            self._tokenizer,
            prompt=prompt,
            max_tokens=512,
            verbose=False,
        )
        return response.strip()
