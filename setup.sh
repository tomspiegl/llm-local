#!/usr/bin/env bash
# Install MLX models for local agentic coding on Apple Silicon:
#   - Gemma 4 26B-A4B (MoE, 3.8B active) — multimodal default
#   - Qwen3-Coder-30B-A3B-Instruct-4bit-dwq-v2 — code-specialized, native tool calling
set -euo pipefail

MODELS=(
  "mlx-community/gemma-4-26b-a4b-it-4bit"
  "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit-dwq-v2"
)

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Error: MLX requires Apple Silicon (arm64). Got: $(uname -m)" >&2
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "Error: uv not found. Install with: brew install uv" >&2
  exit 1
fi

if [[ ! -d .venv ]]; then
  echo ">> Creating .venv with Python 3.13"
  uv venv --python 3.13 .venv
fi

# shellcheck source=/dev/null
source .venv/bin/activate

echo ">> Installing mlx-vlm (pulls in mlx + mlx-lm) and huggingface_hub"
uv pip install -U mlx-vlm huggingface_hub

for model in "${MODELS[@]}"; do
  echo ">> Downloading $model"
  hf download "$model"
done

echo
echo "Ready. Start a server with:  just start"
echo "Reactivate the env later with:  source .venv/bin/activate"
