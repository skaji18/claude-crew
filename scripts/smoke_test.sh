#!/bin/bash
# scripts/smoke_test.sh
# End-to-end smoke test for claude-crew infrastructure.
# Usage: bash scripts/smoke_test.sh
# Exit code: 0 = all checks pass, 1 = failures found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0

check() {
  local desc="$1" result="$2"
  if [ "$result" = "pass" ]; then
    ((PASS++)) || true
  else
    echo "FAIL: $desc"
    ((FAIL++)) || true
  fi
}

echo "=== claude-crew Smoke Test ==="

# Check 1: Prerequisites - config.yaml exists
if [[ -f "$PROJECT_ROOT/config.yaml" ]]; then
  echo "[1/8] config.yaml exists ... PASS"
  check "config.yaml exists" "pass"
else
  echo "[1/8] config.yaml exists ... FAIL"
  check "config.yaml missing" "fail"
fi

# Check 2: Prerequisites - templates/ directory exists
if [[ -d "$PROJECT_ROOT/templates" ]]; then
  echo "[2/8] templates/ directory exists ... PASS"
  check "templates/ exists" "pass"
else
  echo "[2/8] templates/ directory exists ... FAIL"
  check "templates/ missing" "fail"
fi

# Check 3: Prerequisites - scripts/ directory exists
if [[ -d "$PROJECT_ROOT/scripts" ]]; then
  echo "[3/8] scripts/ directory exists ... PASS"
  check "scripts/ exists" "pass"
else
  echo "[3/8] scripts/ directory exists ... FAIL"
  check "scripts/ missing" "fail"
fi

# Check 4: Create temporary cmd directory
TEMP_CMD=""
if [[ -x "$PROJECT_ROOT/scripts/new_cmd.sh" ]]; then
  TEMP_CMD=$(bash "$PROJECT_ROOT/scripts/new_cmd.sh" 2>/dev/null || echo "")
  if [[ -n "$TEMP_CMD" ]]; then
    echo "[4/8] Create temporary cmd directory ... PASS"
    check "new_cmd.sh creates directory" "pass"
  else
    echo "[4/8] Create temporary cmd directory ... FAIL"
    check "new_cmd.sh failed to create directory" "fail"
  fi
else
  echo "[4/8] Create temporary cmd directory ... FAIL"
  check "new_cmd.sh not found or not executable" "fail"
fi

# Check 5: Verify directory structure (tasks/, results/ subdirs)
if [[ -n "$TEMP_CMD" ]]; then
  if [[ -d "$PROJECT_ROOT/work/$TEMP_CMD/tasks" ]] && [[ -d "$PROJECT_ROOT/work/$TEMP_CMD/results" ]]; then
    echo "[5/8] Verify directory structure (tasks/, results/) ... PASS"
    check "directory structure" "pass"
  else
    echo "[5/8] Verify directory structure (tasks/, results/) ... FAIL"
    check "tasks/ or results/ subdirectories missing" "fail"
  fi
else
  echo "[5/8] Verify directory structure (tasks/, results/) ... SKIP"
fi

# Check 6: Create minimal request.md and verify it exists
if [[ -n "$TEMP_CMD" ]]; then
  REQUEST_FILE="$PROJECT_ROOT/work/$TEMP_CMD/request.md"
  cat > "$REQUEST_FILE" <<'EOF'
# Smoke Test Request

This is a minimal request file for smoke testing.
EOF
  if [[ -f "$REQUEST_FILE" ]]; then
    echo "[6/8] Create minimal request.md ... PASS"
    check "request.md creation" "pass"
  else
    echo "[6/8] Create minimal request.md ... FAIL"
    check "request.md creation failed" "fail"
  fi
else
  echo "[6/8] Create minimal request.md ... SKIP"
fi

# Check 7: Run validate_config.sh
if [[ -x "$PROJECT_ROOT/scripts/validate_config.sh" ]]; then
  if bash "$PROJECT_ROOT/scripts/validate_config.sh" >/dev/null 2>&1; then
    echo "[7/8] validate_config.sh passes ... PASS"
    check "validate_config.sh" "pass"
  else
    echo "[7/8] validate_config.sh passes ... FAIL"
    check "validate_config.sh failed" "fail"
  fi
else
  echo "[7/8] validate_config.sh passes ... FAIL"
  check "validate_config.sh not found or not executable" "fail"
fi

# Check 8: Run health_check.sh
if [[ -x "$PROJECT_ROOT/scripts/health_check.sh" ]]; then
  if bash "$PROJECT_ROOT/scripts/health_check.sh" >/dev/null 2>&1; then
    echo "[8/8] health_check.sh passes ... PASS"
    check "health_check.sh" "pass"
  else
    echo "[8/8] health_check.sh passes ... FAIL"
    check "health_check.sh failed" "fail"
  fi
else
  echo "[8/8] health_check.sh passes ... FAIL"
  check "health_check.sh not found or not executable" "fail"
fi

# Cleanup: Remove temporary cmd directory
if [[ -n "$TEMP_CMD" ]] && [[ -d "$PROJECT_ROOT/work/$TEMP_CMD" ]]; then
  rm -rf "$PROJECT_ROOT/work/$TEMP_CMD"
  echo "Cleanup: Removed $TEMP_CMD"
fi

# Summary
echo "=== RESULTS ==="
echo "Passed: $PASS, Failed: $FAIL"

if [[ $FAIL -gt 0 ]]; then
  echo "Smoke test failed — see above."
  exit 1
else
  echo "Smoke test passed."
  exit 0
fi
