# You Talking To Me — Glossary

## DictationSession

A complete push-to-talk cycle: user holds the hotkey, speaks, releases the hotkey, and receives polished text injected into the active application.

## Polish

The LLM transformation step that turns a raw speech transcript into clean, formatted text. Removes filler words, applies self-corrections, and adds punctuation. Distinct from transcription (STT).

## Injection

Inserting polished text into the focused text field of the active application via the system pasteboard and simulated paste command.

## Tier

A named preset pairing an STT model and a polish model. The two tiers are **fast** (default) and **quality**.

## InferenceServer

The bundled Python MLX helper process that performs local speech-to-text (Whisper). Communicates with the Swift app via JSON lines on stdin/stdout.

## MLPolishService

Swift-side MLX service that downloads and runs the Gemma 4 polish model via `mlx-swift-lm`. Transforms raw transcripts into clean dictation text.
