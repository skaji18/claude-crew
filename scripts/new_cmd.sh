#!/bin/bash
# Create a new cmd_NNN directory with atomic mkdir retry
# Merges config.yaml with local overrides if present
# Usage: bash scripts/new_cmd.sh
# Output: prints "cmd_NNN" on success, exits 1 on failure

set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

for i in $(seq 1 5); do
  LAST=$(ls work/ 2>/dev/null | sed -n 's/^cmd_\([0-9]*\)$/\1/p' | sort -n | tail -1)
  NEXT=$(printf "%03d" $(( 10#${LAST:-0} + 1 )))
  if mkdir "work/cmd_${NEXT}" 2>/dev/null; then
    mkdir -p "work/cmd_${NEXT}/tasks" "work/cmd_${NEXT}/results"

    # --- Config merge step ---
    MERGE_EXIT=0
    python3 scripts/merge_config.py "work/cmd_${NEXT}" >/dev/null || MERGE_EXIT=$?
    if [[ $MERGE_EXIT -eq 1 ]]; then
      echo "ERROR: config merge failed for cmd_${NEXT}" >&2
      rm -rf "work/cmd_${NEXT}"
      exit 1
    fi
    # Exit code 2 = warnings only, proceed normally (warnings already on stderr)

    echo "cmd_${NEXT}"
    exit 0
  fi
  sleep 0.$((RANDOM % 500))
done

echo "ERROR: failed to create cmd dir after 5 retries" >&2
exit 1
