#!/bin/bash
# scripts/validate_config.sh
# Validates config.yaml structure and field values.
# Usage: bash scripts/validate_config.sh
# Exit code: 0 = all fields valid, 1 = failures found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source error code system
source "${SCRIPT_DIR}/error_codes.sh" 2>/dev/null || {
  echo "ERROR: failed to load error_codes.sh" >&2
  exit 1
}

# Determine config path: use work_dir merged config if provided, else base
if [[ -n "${1:-}" ]] && [[ -f "$1/config.yaml" ]]; then
  CONFIG_PATH="$1/config.yaml"
elif [[ -n "${1:-}" ]] && [[ -f "$PROJECT_ROOT/$1/config.yaml" ]]; then
  CONFIG_PATH="$PROJECT_ROOT/$1/config.yaml"
else
  CONFIG_PATH="$PROJECT_ROOT/config.yaml"
fi

PASS=0; FAIL=0

check() {
  local desc="$1" result="$2"
  if [ "$result" = "pass" ]; then
    ((PASS++)) || true
    echo "PASS: $desc"
  else
    echo "FAIL: $desc"
    ((FAIL++))
  fi
}

echo "=== config.yaml Validation ==="

# Check 0: config.yaml exists
if [[ ! -f "$CONFIG_PATH" ]]; then
  fatal E001 "$CONFIG_PATH"
fi

# Check 1: version (quoted string, semver-like)
VERSION=$(grep "^version:" "$CONFIG_PATH" | sed 's/^version:[[:space:]]*//' | tr -d '"' || echo "")
if [[ -n "$VERSION" ]] && [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.]+)?$ ]]; then
  check "version is valid: $VERSION" "pass"
else
  ERR_MSG=$(get_error_message E011)
  check "[E011] $ERR_MSG (got: $VERSION)" "fail"
fi

# Check 2: default_model (haiku, sonnet, or opus)
DEFAULT_MODEL=$(grep "^default_model:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$DEFAULT_MODEL" =~ ^(haiku|sonnet|opus)$ ]]; then
  check "default_model is valid: $DEFAULT_MODEL" "pass"
else
  ERR_MSG=$(get_error_message E004)
  check "[E004] $ERR_MSG (got: $DEFAULT_MODEL)" "fail"
fi

# Check 3: max_parallel (integer, 1-20)
MAX_PARALLEL=$(grep "^max_parallel:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$MAX_PARALLEL" =~ ^[0-9]+$ ]] && [[ $MAX_PARALLEL -ge 1 ]] && [[ $MAX_PARALLEL -le 20 ]]; then
  check "max_parallel is valid: $MAX_PARALLEL" "pass"
else
  ERR_MSG=$(get_error_message E005)
  check "[E005] $ERR_MSG (got: $MAX_PARALLEL)" "fail"
fi

# Check 4: max_retries (integer, 0-10)
MAX_RETRIES=$(grep "^max_retries:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$MAX_RETRIES" =~ ^[0-9]+$ ]] && [[ $MAX_RETRIES -ge 0 ]] && [[ $MAX_RETRIES -le 10 ]]; then
  check "max_retries is valid: $MAX_RETRIES" "pass"
else
  ERR_MSG=$(get_error_message E006)
  check "[E006] $ERR_MSG (got: $MAX_RETRIES)" "fail"
fi

# Check 5: background_threshold (integer, 1-20)
BG_THRESHOLD=$(grep "^background_threshold:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$BG_THRESHOLD" =~ ^[0-9]+$ ]] && [[ $BG_THRESHOLD -ge 1 ]] && [[ $BG_THRESHOLD -le 20 ]]; then
  check "background_threshold is valid: $BG_THRESHOLD" "pass"
else
  ERR_MSG=$(get_error_message E008)
  check "[E008] $ERR_MSG (got: $BG_THRESHOLD)" "fail"
fi

# Check 6: worker_max_turns (integer, 5-100)
WORKER_MAX_TURNS=$(grep "^worker_max_turns:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$WORKER_MAX_TURNS" =~ ^[0-9]+$ ]] && [[ $WORKER_MAX_TURNS -ge 5 ]] && [[ $WORKER_MAX_TURNS -le 100 ]]; then
  check "worker_max_turns is valid: $WORKER_MAX_TURNS" "pass"
else
  ERR_MSG=$(get_error_message E007)
  check "[E007] $ERR_MSG (got: $WORKER_MAX_TURNS)" "fail"
fi

# Check 7: retrospect.enabled (true or false)
RETRO_ENABLED=$(grep "^[[:space:]]*enabled:" "$CONFIG_PATH" | head -1 | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$RETRO_ENABLED" =~ ^(true|false)$ ]]; then
  check "retrospect.enabled is valid: $RETRO_ENABLED" "pass"
else
  ERR_MSG=$(get_error_message E009)
  check "[E009] $ERR_MSG (got: $RETRO_ENABLED)" "fail"
fi

# Check 8: retrospect.filter_threshold (number)
FILTER_THRESHOLD=$(grep "^[[:space:]]*filter_threshold:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$FILTER_THRESHOLD" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  check "retrospect.filter_threshold is valid: $FILTER_THRESHOLD" "pass"
else
  ERR_MSG=$(get_error_message E012)
  check "[E012] $ERR_MSG (got: $FILTER_THRESHOLD)" "fail"
fi

# Check 9: retrospect.model (haiku, sonnet, or opus)
RETRO_MODEL=$(grep "^[[:space:]]*model:" "$CONFIG_PATH" | head -1 | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$RETRO_MODEL" =~ ^(haiku|sonnet|opus)$ ]]; then
  check "retrospect.model is valid: $RETRO_MODEL" "pass"
else
  ERR_MSG=$(get_error_message E010)
  check "[E010] $ERR_MSG (got: $RETRO_MODEL)" "fail"
fi

# Check 10: max_cmd_duration_sec (optional, integer > 0 if present)
MAX_CMD_DUR=$(grep "^max_cmd_duration_sec:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ -z "$MAX_CMD_DUR" ]]; then
  echo "INFO: max_cmd_duration_sec not set (optional)"
elif [[ "$MAX_CMD_DUR" =~ ^[0-9]+$ ]] && [[ $MAX_CMD_DUR -gt 0 ]]; then
  check "max_cmd_duration_sec is valid: $MAX_CMD_DUR" "pass"
else
  ERR_MSG=$(get_error_message E013)
  check "[E013] $ERR_MSG (got: $MAX_CMD_DUR)" "fail"
fi

# Check 11: local/config.yaml override validation (if exists and merge script available)
if [[ -f "$PROJECT_ROOT/local/config.yaml" ]]; then
  if python3 -c "import yaml" 2>/dev/null; then
    TMPDIR=$(mktemp -d)
    MERGE_WARNINGS=$(python3 "$PROJECT_ROOT/scripts/merge_config.py" \
      "$TMPDIR" 2>&1 >/dev/null) || true
    rm -rf "$TMPDIR"
    if [[ -n "$MERGE_WARNINGS" ]]; then
      check "local/config.yaml override validation" "fail"
      echo "  $MERGE_WARNINGS"
    else
      check "local/config.yaml override has valid keys" "pass"
    fi
  else
    echo "INFO: local/config.yaml found but PyYAML not installed (skipping override validation)"
  fi
fi

# Summary
echo "=== RESULTS ==="
echo "Passed: $PASS, Failed: $FAIL"

if [[ $FAIL -gt 0 ]]; then
  echo "config.yaml has issues — see above."
  exit 1
else
  echo "config.yaml is valid."
  exit 0
fi
