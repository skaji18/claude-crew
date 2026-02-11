#!/bin/bash
# scripts/validate_config.sh
# Validates config.yaml structure and field values.
# Usage: bash scripts/validate_config.sh
# Exit code: 0 = all fields valid, 1 = failures found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$PROJECT_ROOT/config.yaml"
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
  echo "FATAL: config.yaml not found at $CONFIG_PATH"
  exit 1
fi

# Check 1: version (quoted string, semver-like)
VERSION=$(grep "^version:" "$CONFIG_PATH" | sed 's/^version:[[:space:]]*//' | tr -d '"' || echo "")
if [[ -n "$VERSION" ]] && [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  check "version is valid semver: $VERSION" "pass"
else
  check "version missing or invalid (expected quoted semver like \"0.9.0\")" "fail"
fi

# Check 2: default_model (haiku, sonnet, or opus)
DEFAULT_MODEL=$(grep "^default_model:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$DEFAULT_MODEL" =~ ^(haiku|sonnet|opus)$ ]]; then
  check "default_model is valid: $DEFAULT_MODEL" "pass"
else
  check "default_model missing or invalid (expected haiku|sonnet|opus, got: $DEFAULT_MODEL)" "fail"
fi

# Check 3: max_parallel (integer, 1-20)
MAX_PARALLEL=$(grep "^max_parallel:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$MAX_PARALLEL" =~ ^[0-9]+$ ]] && [[ $MAX_PARALLEL -ge 1 ]] && [[ $MAX_PARALLEL -le 20 ]]; then
  check "max_parallel is valid: $MAX_PARALLEL" "pass"
else
  check "max_parallel missing or out of range (expected 1-20, got: $MAX_PARALLEL)" "fail"
fi

# Check 4: max_retries (integer, 0-10)
MAX_RETRIES=$(grep "^max_retries:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$MAX_RETRIES" =~ ^[0-9]+$ ]] && [[ $MAX_RETRIES -ge 0 ]] && [[ $MAX_RETRIES -le 10 ]]; then
  check "max_retries is valid: $MAX_RETRIES" "pass"
else
  check "max_retries missing or out of range (expected 0-10, got: $MAX_RETRIES)" "fail"
fi

# Check 5: background_threshold (integer, 1-20)
BG_THRESHOLD=$(grep "^background_threshold:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$BG_THRESHOLD" =~ ^[0-9]+$ ]] && [[ $BG_THRESHOLD -ge 1 ]] && [[ $BG_THRESHOLD -le 20 ]]; then
  check "background_threshold is valid: $BG_THRESHOLD" "pass"
else
  check "background_threshold missing or out of range (expected 1-20, got: $BG_THRESHOLD)" "fail"
fi

# Check 6: worker_max_turns (integer, 5-100)
WORKER_MAX_TURNS=$(grep "^worker_max_turns:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$WORKER_MAX_TURNS" =~ ^[0-9]+$ ]] && [[ $WORKER_MAX_TURNS -ge 5 ]] && [[ $WORKER_MAX_TURNS -le 100 ]]; then
  check "worker_max_turns is valid: $WORKER_MAX_TURNS" "pass"
else
  check "worker_max_turns missing or out of range (expected 5-100, got: $WORKER_MAX_TURNS)" "fail"
fi

# Check 7: retrospect.enabled (true or false)
RETRO_ENABLED=$(grep "^[[:space:]]*enabled:" "$CONFIG_PATH" | head -1 | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$RETRO_ENABLED" =~ ^(true|false)$ ]]; then
  check "retrospect.enabled is valid: $RETRO_ENABLED" "pass"
else
  check "retrospect.enabled missing or invalid (expected true|false, got: $RETRO_ENABLED)" "fail"
fi

# Check 8: retrospect.filter_threshold (number)
FILTER_THRESHOLD=$(grep "^[[:space:]]*filter_threshold:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$FILTER_THRESHOLD" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  check "retrospect.filter_threshold is valid: $FILTER_THRESHOLD" "pass"
else
  check "retrospect.filter_threshold missing or invalid (expected number, got: $FILTER_THRESHOLD)" "fail"
fi

# Check 9: retrospect.model (haiku, sonnet, or opus)
RETRO_MODEL=$(grep "^[[:space:]]*model:" "$CONFIG_PATH" | head -1 | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ "$RETRO_MODEL" =~ ^(haiku|sonnet|opus)$ ]]; then
  check "retrospect.model is valid: $RETRO_MODEL" "pass"
else
  check "retrospect.model missing or invalid (expected haiku|sonnet|opus, got: $RETRO_MODEL)" "fail"
fi

# Check 10: max_cmd_duration_sec (optional, integer > 0 if present)
MAX_CMD_DUR=$(grep "^max_cmd_duration_sec:" "$CONFIG_PATH" | awk '{print $2}' | tr -d '[:space:]' || echo "")
if [[ -z "$MAX_CMD_DUR" ]]; then
  echo "INFO: max_cmd_duration_sec not set (optional)"
elif [[ "$MAX_CMD_DUR" =~ ^[0-9]+$ ]] && [[ $MAX_CMD_DUR -gt 0 ]]; then
  check "max_cmd_duration_sec is valid: $MAX_CMD_DUR" "pass"
else
  check "max_cmd_duration_sec invalid (expected positive integer, got: $MAX_CMD_DUR)" "fail"
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
