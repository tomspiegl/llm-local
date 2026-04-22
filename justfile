set shell := ["bash", "-cu"]

# Gemma port matches pi's gemma4-local; Qwen port matches pi's qwen-local (~/.pi/agent/models.json).
GEMMA_PORT    := "11435"
QWEN_PORT     := "9099"
HOST          := env_var_or_default("HOST", "127.0.0.1")
MONITOR_PORT  := "8766"
LOG_DIR       := ".logs"

# list recipes
default:
    @just --list

# start MLX server in background (interactive model picker, or `just start <name>`)
start model="":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p {{LOG_DIR}}

    KEYS=(gemma qwen3-coder)
    IDS=(
      "mlx-community/gemma-4-26b-a4b-it-4bit"
      "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit-dwq-v2"
    )
    PORTS=({{GEMMA_PORT}} {{QWEN_PORT}})

    key="{{model}}"
    if [[ -z "$key" ]]; then
      echo "Available models:"
      for i in "${!KEYS[@]}"; do
        printf "  %d) %-18s :%s  %s\n" "$((i+1))" "${KEYS[$i]}" "${PORTS[$i]}" "${IDS[$i]}"
      done
      read -rp "Select [1-${#KEYS[@]}] or name (default 1): " choice
      choice="${choice:-1}"
      if [[ "$choice" =~ ^[0-9]+$ ]]; then
        idx=$((choice - 1))
        if (( idx < 0 || idx >= ${#KEYS[@]} )); then
          echo "Invalid selection: $choice"; exit 1
        fi
        key="${KEYS[$idx]}"
      else
        key="$choice"
      fi
    fi

    model_id=""
    port=""
    for i in "${!KEYS[@]}"; do
      if [[ "${KEYS[$i]}" == "$key" ]]; then
        model_id="${IDS[$i]}"
        port="${PORTS[$i]}"
        break
      fi
    done
    if [[ -z "$model_id" ]]; then
      echo "Unknown model: $key"
      echo "Valid: ${KEYS[*]}"
      exit 1
    fi

    if lsof -ti :"$port" >/dev/null 2>&1; then
      echo "Already running on port $port (pid $(lsof -ti :$port))"
      exit 0
    fi

    # Pre-fetch weights in the foreground so the port only opens once the model is
    # actually serveable. Otherwise mlx_lm.server accepts connections while still
    # downloading, and clients (pi, etc.) hang on their first request.
    echo ">> Ensuring weights cached: $model_id"
    # shellcheck source=/dev/null
    source .venv/bin/activate
    hf download "$model_id"

    logfile="{{LOG_DIR}}/serve-$key.log"
    echo ">> Starting $key ($model_id) on :$port"
    MODEL="$model_id" PORT="$port" nohup ./serve.sh > "$logfile" 2>&1 &
    echo "Server starting -> http://{{HOST}}:$port/v1  (logs: $logfile)"

# stop MLX server (defaults to gemma; pass `qwen` to stop the qwen endpoint)
stop target="gemma":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{target}}" in
      gemma) port={{GEMMA_PORT}} ;;
      qwen|qwen3-coder) port={{QWEN_PORT}} ;;
      all)
        PORT={{GEMMA_PORT}} ./stop.sh || true
        PORT={{QWEN_PORT}}  ./stop.sh || true
        exit 0 ;;
      *) echo "Unknown stop target: {{target}} (use gemma|qwen|all)"; exit 1 ;;
    esac
    PORT="$port" ./stop.sh

# restart MLX server (optional model name)
restart model="":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{model}}" in
      ""|gemma)       target=gemma ;;
      qwen3-coder)    target=qwen ;;
      *)              target=gemma ;;
    esac
    just stop "$target" || true
    sleep 1
    just start "{{model}}"

# tail MLX server log (e.g. `just logs gemma` or `just logs qwen3-coder`)
logs target="gemma":
    @tail -f {{LOG_DIR}}/serve-{{target}}.log

# start monitor in background (logs -> .logs/monitor.log)
monitor:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p {{LOG_DIR}}
    if lsof -ti :{{MONITOR_PORT}} >/dev/null 2>&1; then
      echo "Monitor already running on port {{MONITOR_PORT}} (pid $(lsof -ti :{{MONITOR_PORT}}))"
      exit 0
    fi
    nohup python3 monitor.py > {{LOG_DIR}}/monitor.log 2>&1 &
    echo "Monitor starting -> http://127.0.0.1:{{MONITOR_PORT}}/  (logs: {{LOG_DIR}}/monitor.log)"

# stop monitor
monitor-stop:
    #!/usr/bin/env bash
    set -euo pipefail
    pid="$(lsof -ti :{{MONITOR_PORT}} 2>/dev/null || true)"
    if [[ -z "$pid" ]]; then
      echo "No monitor running on port {{MONITOR_PORT}}"
      exit 0
    fi
    echo ">> Stopping monitor (pid $pid, port {{MONITOR_PORT}})"
    kill "$pid"

# tail monitor log
monitor-logs:
    @tail -f {{LOG_DIR}}/monitor.log

# show status of servers + monitor
status:
    #!/usr/bin/env bash
    check() {
      local name="$1" port="$2"
      local pid
      pid="$(lsof -ti :"$port" 2>/dev/null || true)"
      if [[ -n "$pid" ]]; then
        printf "%-12s port %-6s  up   (pid %s)\n" "$name" "$port" "$pid"
      else
        printf "%-12s port %-6s  down\n" "$name" "$port"
      fi
    }
    check "Gemma"   {{GEMMA_PORT}}
    check "Qwen"    {{QWEN_PORT}}
    check "Monitor" {{MONITOR_PORT}}

# start both server (prompts for model) and monitor
up: start monitor

# stop everything (both servers + monitor)
down:
    @just stop all || true
    @just monitor-stop || true
