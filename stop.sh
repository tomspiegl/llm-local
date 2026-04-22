#!/usr/bin/env bash
# Stop the MLX OpenAI-compatible server (whatever process holds the port).
set -euo pipefail

PORT="${PORT:-11435}"
pid="$(lsof -ti ":$PORT" 2>/dev/null || true)"

if [[ -z "$pid" ]]; then
  echo "No server running on port $PORT"
  exit 0
fi

echo ">> Stopping MLX server (pid $pid, port $PORT)"
kill "$pid"
