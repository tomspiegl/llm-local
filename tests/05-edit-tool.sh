#!/usr/bin/env bash
# Edit-tool test: model must modify a scratch file and we verify the result.
set -e

SCRATCH="$(mktemp -t pi-edit-XXXXX.txt)"
trap 'rm -f "$SCRATCH"' EXIT

printf 'the quick brown fox\n' > "$SCRATCH"

pi --provider gemma4-local \
   --model "mlx-community/gemma-4-26b-a4b-it-4bit" \
   --tools read,edit --no-session --print \
   "Edit $SCRATCH: replace the word 'brown' with 'purple'. Confirm when done."

echo "---"
echo "File contents after edit:"
cat "$SCRATCH"

grep -q 'purple fox' "$SCRATCH" && echo "PASS" || { echo "FAIL"; exit 1; }
