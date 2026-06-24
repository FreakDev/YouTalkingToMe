# You Talking To Me

macOS push-to-talk voice dictation app — local MLX inference (speech-to-text + LLM polish).

## Setup

```bash
# 1. Python inference environment
chmod +x scripts/bundle-python.sh
./scripts/bundle-python.sh

# 2. Build app bundle (no full Xcode required)
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/YouTalkingToMe.app

# Alternative: open in Xcode (requires Xcode.app from App Store)
# open YouTalkingToMe.xcodeproj
```

## Usage

1. Launch You Talking To Me (menubar mic icon).
2. Complete onboarding: grant Microphone, Accessibility, and Input Monitoring permissions.
3. Download models on first launch (fast or quality tier).
4. Hold **Option + Space**, speak, release — polished text is pasted into the active app.

## Architecture

- **Swift app** — hotkey, audio capture, overlay, text injection, settings.
- **Python MLX helper** (`inference/`) — local STT + `mlx-lm` polish via JSON stdin/stdout IPC.

## Requirements

- macOS 14+, Apple Silicon (M1+)
- Python 3.11+
- Xcode 15+
