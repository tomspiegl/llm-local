#!/usr/bin/env bash
# Health check: no tools, single chat roundtrip.
set -e

pi --provider gemma4-local \
   --model "mlx-community/gemma-4-26b-a4b-it-4bit" \
   --no-tools --no-session --print \
   "Reply with exactly the word: READY"
