#!/bin/bash
# scripts/health_check.sh
# Validates claude-crew system health.
# Usage: bash scripts/health_check.sh
# Exit code: 0 = all checks pass, 1 = failures found

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0; WARN=0

check() {
  local desc="$1" result="$2"
  if [ "$result" = "pass" ]; then
    ((PASS++))
  elif [ "$result" = "warn" ]; then
    echo "WARN: $desc"
    ((WARN++))
  else
    echo "FAIL: $desc"
    ((FAIL++))
  fi
}

echo "=== claude-crew Health Check ==="

# Check 1: config.yaml exists and has version field
if [[ -f "$PROJECT_ROOT/config.yaml" ]] && grep -q "^version:" "$PROJECT_ROOT/config.yaml"; then
  echo "[1/10] config.yaml exists and has version ... PASS"
  check "config.yaml" "pass"
else
  echo "[1/10] config.yaml exists and has version ... FAIL"
  check "config.yaml missing or no version field" "fail"
fi

# Check 2: All templates referenced in CLAUDE.md exist
TEMPLATE_CHECK="pass"
if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
  # Extract template paths from CLAUDE.md
  TEMPLATES=$(grep -oP 'templates/[a-z_]+\.md' "$PROJECT_ROOT/CLAUDE.md" | sort -u)
  MISSING_TEMPLATES=""

  for template in $TEMPLATES; do
    if [[ ! -f "$PROJECT_ROOT/$template" ]]; then
      TEMPLATE_CHECK="fail"
      MISSING_TEMPLATES="$MISSING_TEMPLATES $template"
    fi
  done

  if [[ "$TEMPLATE_CHECK" = "pass" ]]; then
    echo "[2/10] All templates exist ... PASS"
    check "templates" "pass"
  else
    echo "[2/10] All templates exist ... FAIL"
    check "Missing templates:$MISSING_TEMPLATES" "fail"
  fi
else
  echo "[2/10] All templates exist ... FAIL"
  check "CLAUDE.md not found" "fail"
fi

# Check 3: settings.json is valid JSON
if [[ -f "$PROJECT_ROOT/.claude/settings.json" ]]; then
  if jq . "$PROJECT_ROOT/.claude/settings.json" >/dev/null 2>&1; then
    echo "[3/10] settings.json is valid JSON ... PASS"
    check "settings.json" "pass"
  else
    echo "[3/10] settings.json is valid JSON ... FAIL"
    check "settings.json is invalid JSON" "fail"
  fi
else
  echo "[3/10] settings.json is valid JSON ... FAIL"
  check "settings.json not found" "fail"
fi

# Check 4: permission-fallback.sh is executable
if [[ -x "$PROJECT_ROOT/.claude/hooks/permission-fallback.sh" ]]; then
  echo "[4/10] permission-fallback.sh is executable ... PASS"
  check "permission-fallback.sh" "pass"
else
  echo "[4/10] permission-fallback.sh is executable ... FAIL"
  check "permission-fallback.sh not executable or missing" "fail"
fi

# Check 5: jq is installed
if command -v jq >/dev/null 2>&1; then
  echo "[5/10] jq is installed ... PASS"
  check "jq" "pass"
else
  echo "[5/10] jq is installed ... FAIL"
  check "jq command not found" "fail"
fi

# Check 6: All scripts/ files are executable
SCRIPT_CHECK="pass"
NON_EXEC=""

if [[ -d "$PROJECT_ROOT/scripts" ]]; then
  # Check .sh files
  for script in "$PROJECT_ROOT/scripts"/*.sh; do
    # Skip if glob didn't match
    [[ -e "$script" ]] || continue

    if [[ ! -x "$script" ]]; then
      SCRIPT_CHECK="fail"
      NON_EXEC="$NON_EXEC $(basename "$script")"
    fi
  done

  # Check .py files
  for script in "$PROJECT_ROOT/scripts"/*.py; do
    # Skip if glob didn't match
    [[ -e "$script" ]] || continue

    if [[ ! -x "$script" ]]; then
      SCRIPT_CHECK="fail"
      NON_EXEC="$NON_EXEC $(basename "$script")"
    fi
  done

  if [[ "$SCRIPT_CHECK" = "pass" ]]; then
    echo "[6/10] All scripts/ files are executable ... PASS"
    check "scripts executability" "pass"
  else
    echo "[6/10] All scripts/ files are executable ... FAIL"
    check "Non-executable scripts:$NON_EXEC" "fail"
  fi
else
  echo "[6/10] All scripts/ files are executable ... FAIL"
  check "scripts/ directory not found" "fail"
fi

# Check 7: Hook test suite passes
if [[ -f "$PROJECT_ROOT/.claude/hooks/test-permission-fallback.sh" ]]; then
  if bash "$PROJECT_ROOT/.claude/hooks/test-permission-fallback.sh" >/dev/null 2>&1; then
    echo "[7/10] Hook test suite passes ... PASS"
    check "hook tests" "pass"
  else
    echo "[7/10] Hook test suite passes ... FAIL"
    check "test-permission-fallback.sh failed" "fail"
  fi
else
  echo "[7/10] Hook test suite passes ... FAIL"
  check "test-permission-fallback.sh not found" "fail"
fi

# Check 8: CLAUDE.md exists
if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
  echo "[8/10] CLAUDE.md exists ... PASS"
  check "CLAUDE.md" "pass"
else
  echo "[8/10] CLAUDE.md exists ... FAIL"
  check "CLAUDE.md not found" "fail"
fi

# Check 9: docs/parent_guide.md exists
if [[ -f "$PROJECT_ROOT/docs/parent_guide.md" ]]; then
  echo "[9/10] docs/parent_guide.md exists ... PASS"
  check "parent_guide.md" "pass"
else
  echo "[9/10] docs/parent_guide.md exists ... FAIL"
  check "docs/parent_guide.md not found" "fail"
fi

# Check 10: No stale `Bash(./scripts/*)` references
STALE_CHECK="pass"
STALE_FILES=""

# Search in docs/ excluding CHANGELOG.md
if [[ -d "$PROJECT_ROOT/docs" ]]; then
  STALE_REFS=$(grep -r "Bash(./scripts/" "$PROJECT_ROOT/docs/" --exclude="CHANGELOG.md" 2>/dev/null || true)

  if [[ -n "$STALE_REFS" ]]; then
    STALE_CHECK="fail"
    # Extract filenames with stale refs
    STALE_FILES=$(echo "$STALE_REFS" | cut -d: -f1 | sort -u | xargs -n1 basename 2>/dev/null | tr '\n' ' ')
  fi
fi

if [[ "$STALE_CHECK" = "pass" ]]; then
  echo "[10/10] No stale Bash(./scripts/*) references ... PASS"
  check "stale references" "pass"
else
  echo "[10/10] No stale Bash(./scripts/*) references ... FAIL"
  check "Stale references in:$STALE_FILES" "fail"
fi

# Summary
echo "=== RESULTS ==="
echo "Passed: $PASS, Warnings: $WARN, Failed: $FAIL"

if [[ $FAIL -gt 0 ]]; then
  echo "System has issues — see above."
  exit 1
else
  echo "System is healthy."
  exit 0
fi
