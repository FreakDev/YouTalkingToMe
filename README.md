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
- **Run the built app:** no dev tools required
- **Build from source:** Xcode Command Line Tools (`xcode-select --install`) + Python 3.11+ for `./scripts/bundle-python.sh`
- **Xcode.app:** optional for building; **required** to run Swift unit tests (`swift test`)

## Tests

```bash
# Fast suite: Python unit + IPC + Swift unit tests (< 30s)
chmod +x scripts/test.sh
./scripts/test.sh

# Include ML smoke tests (requires models cached in ~/Library/Application Support/YouTalkingToMe/models)
./scripts/test.sh --smoke

# Include bundle checks (run ./scripts/build-app.sh first)
./scripts/test.sh --bundle

# Everything
./scripts/test.sh --all
```

Dev Python test deps (installed automatically by `test.sh` if missing):

```bash
inference/.venv/bin/pip install -r inference/requirements-dev.txt
```

Bundle size budget is tracked in `inference/tests/bundle_budget.json` (baseline ~490 Mo). Do not set `transformers_models_keep` — AutoTokenizer scans all model modules and pruning breaks polish.

