#!/usr/bin/env bash
# Multi-step agentic test: list files, read each, synthesize.
set -e

pi --provider gemma4-local \
   --model "mlx-community/gemma-4-26b-a4b-it-4bit" \
   --tools read,bash --no-session --print \
   "In /Users/tom/Develop/gemma-4: use bash to list top-level .sh files, then read each one, then summarize each script in exactly one line formatted as 'filename: purpose'."
