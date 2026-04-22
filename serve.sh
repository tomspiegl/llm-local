#!/usr/bin/env bash
# Start the MLX OpenAI-compatible server for Gemma 4 26B-A4B.
set -euo pipefail

MODEL="${MODEL:-mlx-community/gemma-4-26b-a4b-it-4bit}"
PORT="${PORT:-11435}"
HOST="${HOST:-127.0.0.1}"

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/dev/null
source .venv/bin/activate

echo ">> Serving $MODEL at http://$HOST:$PORT/v1"
exec python -m mlx_lm.server \
  --model "$MODEL" \
  --host "$HOST" \
  --port "$PORT"
