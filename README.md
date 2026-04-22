# llm-local

Run local LLMs on Apple Silicon with an OpenAI-compatible HTTP API, plus a small live monitor for system and server metrics.

Two models are wired up out of the box:

| Key            | Model                                                   | Port   | Use                          |
| -------------- | ------------------------------------------------------- | ------ | ---------------------------- |
| `gemma`        | `mlx-community/gemma-4-26b-a4b-it-4bit`                 | 11435  | General / multimodal default |
| `qwen3-coder`  | `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit-dwq-v2`| 9099   | Code, native tool calling    |

Each server speaks the OpenAI API at `http://127.0.0.1:<port>/v1`, so any OpenAI-compatible client works.

## Requirements

- Apple Silicon Mac (arm64) — MLX does not run on Intel.
- [`uv`](https://docs.astral.sh/uv/) — `brew install uv`
- [`just`](https://github.com/casey/just) — `brew install just`
- Enough RAM/unified memory for the chosen model (~20 GB free recommended for the 4-bit builds above).

## Setup

```sh
./setup.sh
```

This creates `.venv` with Python 3.13, installs `mlx-vlm` (pulls in `mlx` and `mlx-lm`) plus `huggingface_hub`, and pre-downloads both model weights.

## Usage

All commands go through `just`.

```sh
just              # list recipes
just start        # interactive picker, then start a server in the background
just start qwen3-coder
just status       # show which ports are up
just logs gemma   # tail server log
just stop all     # stop all servers
```

Start the monitor UI at `http://127.0.0.1:8766/`:

```sh
just monitor
```

Bring up a server + the monitor together, or take everything down:

```sh
just up
just down
```

### Talking to the server

```sh
curl http://127.0.0.1:11435/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mlx-community/gemma-4-26b-a4b-it-4bit",
    "messages": [{"role": "user", "content": "Say hi in one word."}]
  }'
```

Point any OpenAI-compatible tool at the base URL `http://127.0.0.1:<port>/v1` with any non-empty API key.

## Layout

```
setup.sh         Install venv + models
serve.sh         Start mlx_lm.server for one model (MODEL/PORT env)
stop.sh          Kill whatever holds a given PORT
justfile         start / stop / restart / logs / status / up / down / monitor
monitor.py       Tiny HTTP server exposing /stats + monitor.html
monitor.html     Live dashboard (CPU, memory, GPU, per-endpoint health)
tests/           Shell smoke tests against a running server
.pi/extensions/  pi-coding-agent extension (llm-debug logger)
```

## Logs

Server and monitor logs are written to `.logs/` (e.g. `serve-gemma.log`, `serve-qwen3-coder.log`, `monitor.log`). Tail them with `just logs <key>` or `just monitor-logs`.

## Troubleshooting

- **"Already running on port …"** — a previous server still holds the port. `just stop <key>` or `just stop all`.
- **First request hangs** — weights are still downloading. `just start` pre-fetches them, but the first run can take a while on slow links.
- **`uv not found`** — `brew install uv` then rerun `./setup.sh`.
