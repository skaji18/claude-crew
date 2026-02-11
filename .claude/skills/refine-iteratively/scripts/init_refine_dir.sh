#!/bin/bash
# Initialize refine-iteratively output directory with timestamped subdirectory
# Usage: bash init_refine_dir.sh [output_dir]
# Arguments:
#   output_dir: Base output directory (default: ./refine_output/)
# Output: Prints the created directory path to stdout on success
# Exit codes:
#   0 = success
#   1 = failure (with error message to stderr)

set -euo pipefail

# Parse arguments
OUTPUT_BASE="${1:-./refine_output}"

# Generate timestamp in format YYYY-MM-DD_HH:MM:SS
TIMESTAMP=$(date +"%Y-%m-%d_%H:%M:%S")
REFINE_DIR="${OUTPUT_BASE}/refine_${TIMESTAMP}"

# Ensure base directory exists
if ! mkdir -p "$OUTPUT_BASE" 2>/dev/null; then
  echo "ERROR: failed to create base directory: $OUTPUT_BASE" >&2
  exit 1
fi

# Create timestamped refine directory
if ! mkdir -p "$REFINE_DIR" 2>/dev/null; then
  echo "ERROR: failed to create refine directory: $REFINE_DIR" >&2
  exit 1
fi

# Create subdirectory structure
# These directories are used by refine-iteratively workflow:
#   - results/: stores result_N.md files
#   - feedback/: stores feedback_N.md files
#   - logs/: stores execution_log.yaml and other metadata
if ! mkdir -p "$REFINE_DIR/results" "$REFINE_DIR/feedback" "$REFINE_DIR/logs" 2>/dev/null; then
  echo "ERROR: failed to create subdirectories in: $REFINE_DIR" >&2
  exit 1
fi

# Success: output the created directory path (used by calling code)
echo "$REFINE_DIR"
exit 0
