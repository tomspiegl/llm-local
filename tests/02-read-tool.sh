#!/usr/bin/env bash
# Read-tool test: model must open a file to answer.
set -e

pi --provider gemma4-local \
   --model "mlx-community/gemma-4-26b-a4b-it-4bit" \
   --tools read --no-session --print \
   "Read /Users/tom/Develop/gemma-4/setup.sh and state the value of the MODEL variable. Answer in one line."
