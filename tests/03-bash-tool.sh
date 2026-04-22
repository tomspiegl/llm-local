#!/usr/bin/env bash
# Bash-tool test: model must run a shell command.
set -e

pi --provider gemma4-local \
   --model "mlx-community/gemma-4-26b-a4b-it-4bit" \
   --tools bash --no-session --print \
   "Use bash to count the number of .sh files directly under /Users/tom/Develop/gemma-4 (not recursive). Answer with just the number."
