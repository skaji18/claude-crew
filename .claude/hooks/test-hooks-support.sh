#!/bin/bash
# .claude/hooks/test-hooks-support.sh
#
# Test script to verify that .claude/hooks/ scripts are allowed by permission-fallback.sh
# Usage: bash .claude/hooks/test-hooks-support.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$SCRIPT_DIR/permission-fallback.sh"
PASS=0; FAIL=0

test_case() {
  local cmd="$1" expected="$2" desc="$3"
  local input="{\"tool_input\":{\"command\":\"$cmd\"},\"tool_name\":\"Bash\",\"hook_event_name\":\"PermissionRequest\"}"
  local output
  output=$(echo "$input" | bash "$HOOK" 2>/dev/null)

  if [ "$expected" = "allow" ]; then
    if echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null 2>&1; then
      ((PASS++))
      echo "PASS [$desc]"
    else
      echo "FAIL [$desc]: expected allow, got: $output"
      ((FAIL++))
    fi
  elif [ "$expected" = "dialog" ]; then
    if [ -z "$output" ]; then
      ((PASS++))
      echo "PASS [$desc]"
    else
      echo "FAIL [$desc]: expected dialog (empty), got: $output"
      ((FAIL++))
    fi
  fi
}

echo "=== .claude/hooks/ Support Tests ==="
test_case "bash .claude/hooks/test-permission-fallback.sh" allow "bash + .claude/hooks/ script"
test_case ".claude/hooks/test-permission-fallback.sh" allow "direct + .claude/hooks/ script"
test_case "python3 .claude/hooks/some-script.py" allow "python3 + .claude/hooks/ script"
test_case "sh .claude/hooks/another.sh" allow "sh + .claude/hooks/ script"
test_case "bash .claude/hooks/subfolder/nested.sh" allow "bash + nested .claude/hooks/ script"

echo ""
echo "=== .claude/hooks/ Security Tests ==="
test_case "bash .claude/hooks_evil/script.sh" dialog "reject: .claude/hooks_evil/ substring"
test_case "bash .claude/hooksdir/script.sh" dialog "reject: .claude/hooksdir/ substring"
test_case "bash /tmp/.claude/hooks/evil.sh" dialog "reject: /tmp/.claude/hooks/ outside project"

echo ""
echo "=== Existing scripts/ Support (Regression) ==="
test_case "python3 scripts/foo.py" allow "python3 + scripts/ (unchanged)"
test_case "./scripts/foo.sh" allow "direct + scripts/ (unchanged)"
test_case "bash scripts/run.sh" allow "bash + scripts/ (unchanged)"

echo ""
echo "=== RESULTS ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
[ $FAIL -eq 0 ] && echo "All tests passed!" || exit 1
