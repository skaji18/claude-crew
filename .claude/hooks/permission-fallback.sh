#!/bin/bash
# .claude/hooks/permission-fallback.sh
#
# PermissionRequest fallback:
# settings.json の glob でカバーしきれないスクリプト実行を自動承認する。
#
# 前提: このスクリプトに到達する = settings.json の deny を通過済み
# 目的: scripts/ および .claude/hooks/ 配下スクリプト実行を allow する
#   - python3/bash/sh 経由の実行
#   - 直接実行（shebang ベース: ./scripts/foo.sh）
#
# 設計原則: 「入力を正規化してから判定」
#   1. 制御文字を拒否 (sanitize)
#   2. tool_name を検証
#   3. 危険なシェル構文を拒否 (compound commands, redirections, etc.)
#   4. コマンドをパースして interpreter / options / script_path に分離
#   5. オプションを正規化して危険フラグを拒否
#   6. パスを正規化して scripts/ or .claude/hooks/ 配下かを判定

set -euo pipefail

# --- Fail closed: jq required ---
if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: permission-fallback.sh disabled (jq not found). Install jq to enable automatic script approval." >&2
  exit 0
fi

# --- Read input ---
INPUT=$(cat)

# --- Helper: allow decision ---
allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n'
  exit 0
}

# --- Helper: reject (with optional debug) ---
reject() {
  local reason="${1:-unknown}"
  [[ "${PERMISSION_DEBUG:-0}" == "1" ]] && echo "REJECT[$reason]" >&2
  exit 0
}

# Guard S0: Reject null bytes in raw input (before jq processing).
# Bash command substitution strips null bytes, so [[:cntrl:]] check would miss them.
# Null bytes in JSON (\u0000) get converted by jq to real 0x00, then bash strips them,
# causing adjacent strings to concatenate and potentially bypass path checks.
if printf '%s' "$INPUT" | grep -qP '\x00' 2>/dev/null; then
  reject "S0:null_byte"
fi
# Also reject JSON-encoded null (\u0000) in the raw JSON string before jq processes it.
if printf '%s' "$INPUT" | grep -q '\\u0000' 2>/dev/null; then
  reject "S0:json_null"
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && reject "S0:empty_command"

# =======================================================
# Configuration: Interpreter allowlist and flag rules
# =======================================================
# Adding a new interpreter: add an entry below and restart.
# Format: Each interpreter has safe_flags and dangerous_flags.
#
# INTERPRETERS: space-separated list of allowed interpreters
# SAFE_FLAGS_<interp>: single-char flags that are safe to pass through
# DANGEROUS_FLAGS_<interp>: flags that indicate code injection (reject)
# DANGEROUS_LONG_FLAGS_<interp>: long-form flags to reject

INTERPRETERS="python3 bash sh"

# python3: safe single-char flags (buffering, optimization, verbosity)
SAFE_FLAGS_python3="u B s S v b q O I E P R"
# python3: dangerous flags (inline code execution)
DANGEROUS_FLAGS_python3="c e m"
DANGEROUS_LONG_FLAGS_python3="--command --eval"

# bash: no safe flags auto-approved
SAFE_FLAGS_bash=""
# bash: dangerous flags
DANGEROUS_FLAGS_bash="c i"
DANGEROUS_LONG_FLAGS_bash="--init-file --rcfile"

# sh: same as bash
SAFE_FLAGS_sh=""
DANGEROUS_FLAGS_sh="c i"
DANGEROUS_LONG_FLAGS_sh="--init-file --rcfile"

# =======================================================
# Phase 1: Sanitize — reject malformed input
# =======================================================

# Guard S1: Control characters (newline, CR, null, tabs, etc.)
# These can break regex guards and enable injection.
# [[:cntrl:]] matches all control characters (0x00-0x1F, 0x7F).
if [[ "$COMMAND" =~ [[:cntrl:]] ]]; then
  reject "S1:control_chars"
fi

# Guard S2: tool_name must be "Bash"
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL_NAME" != "Bash" ]] && reject "S2:tool_name"

# =======================================================
# Phase 2: Reject dangerous shell syntax (pre-parse)
# =======================================================

# Guard P1: Shell operators — compound commands, pipes, backgrounding
[[ "$COMMAND" =~ [\;\|\&\`] ]] && reject "P1:shell_operators"

# Guard P2: Redirections and process substitution
[[ "$COMMAND" =~ [\>\<] ]] && reject "P2:redirections"

# Guard P3: Command substitution $( ... )
[[ "$COMMAND" =~ \$\( ]] && reject "P3:cmd_substitution"

# Guard P4: Variable/arithmetic expansion ($VAR, ${VAR}, $[arith])
[[ "$COMMAND" =~ \$[A-Za-z_{[:digit:]\[] ]] && reject "P4:var_expansion"

# Guard P5: Environment variable assignment prefix (VAR=value cmd)
[[ "$COMMAND" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && reject "P5:env_assignment"

# Guard P6: Tilde expansion (~ at start of a word creates semantic gap:
# hook sees literal ~, but shell expands to $HOME)
[[ "$COMMAND" =~ (^|\ )~ ]] && reject "P6:tilde_expansion"

# Guard P7: Glob/brace expansion characters (hook checks literal path,
# but shell expands globs before execution)
[[ "$COMMAND" =~ [\*\?\[\{] ]] && reject "P7:glob_chars"

# =======================================================
# Phase 3: Parse command into structured components
# =======================================================

# Split command into words
read -ra WORDS <<< "$COMMAND"
[[ ${#WORDS[@]} -lt 1 ]] && reject "P3:empty_words"

INTERPRETER="${WORDS[0]}"
SCRIPT_PATH=""

# Only allow known interpreters — or treat as direct execution
IS_KNOWN_INTERPRETER=false
for interp in $INTERPRETERS; do
  [[ "$INTERPRETER" == "$interp" ]] && IS_KNOWN_INTERPRETER=true && break
done
if ! $IS_KNOWN_INTERPRETER; then
  # Direct execution (shebang-based): first word is the script path itself.
  # No interpreter options to parse — skip Phase 4, go to Phase 5.
  SCRIPT_PATH="$INTERPRETER"
fi

# =======================================================
# Phase 4: Normalize options — classify each word
# =======================================================

# Walk through words after the interpreter.
# Categorize as: safe-flag, dangerous-flag, or positional-arg (script path).
#
# Strategy for flags attached to values (e.g., -c"code", -mmodule):
#   If a word starts with a known dangerous flag prefix, reject.

# Phase 4 only applies when a known interpreter is used.
# For direct execution (shebang), SCRIPT_PATH was already set in Phase 3.
if [[ -z "$SCRIPT_PATH" ]]; then
  # Get flag lists for current interpreter
  SAFE_VAR="SAFE_FLAGS_${INTERPRETER}"
  DANGER_VAR="DANGEROUS_FLAGS_${INTERPRETER}"
  DANGER_LONG_VAR="DANGEROUS_LONG_FLAGS_${INTERPRETER}"

  SAFE_FLAGS="${!SAFE_VAR:-}"
  DANGER_FLAGS="${!DANGER_VAR:-}"
  DANGER_LONG_FLAGS="${!DANGER_LONG_VAR:-}"

  IDX=1

  while [[ $IDX -lt ${#WORDS[@]} ]]; do
    WORD="${WORDS[$IDX]}"

    if [[ "$WORD" == -* ]]; then
      # --- Option word ---

      # Check for dangerous long flags (exact match)
      for long_flag in $DANGER_LONG_FLAGS; do
        if [[ "$WORD" == "$long_flag" ]]; then
          reject "P4:dangerous_flag"
        fi
      done

      # Check for dangerous single-char flags (exact or prefix match)
      for flag_char in $DANGER_FLAGS; do
        # Exact match: -c, -e, -m, -i
        if [[ "$WORD" == "-$flag_char" ]]; then
          reject "P4:dangerous_flag"
        fi
        # Prefix match: -c"code", -ccode, -mmodule, -e"code"
        if [[ "$WORD" == "-${flag_char}"* ]]; then
          reject "P4:dangerous_flag"
        fi
      done

      # Check for safe single-char flags (exactly 2 chars: dash + letter)
      if [[ ${#WORD} -eq 2 ]]; then
        FLAG_CHAR="${WORD:1:1}"
        IS_SAFE=false
        for safe_char in $SAFE_FLAGS; do
          if [[ "$FLAG_CHAR" == "$safe_char" ]]; then
            IS_SAFE=true
            break
          fi
        done
        if $IS_SAFE; then
          # Known safe flag — skip
          ((IDX++))
          continue
        fi
      fi

      # Unknown flag — fail closed (show dialog)
      reject "P4:unknown_flag"
    else
      # --- Positional argument = script path ---
      SCRIPT_PATH="$WORD"
      break
    fi

    ((IDX++))
  done
fi

# No script path found
[[ -z "$SCRIPT_PATH" ]] && reject "P4:no_script_path"

# =======================================================
# Phase 5: Normalize path — resolve to absolute, then check
# =======================================================

# Determine project directory.
# CLAUDE_PROJECT_DIR is set by Claude Code when invoking hooks.
# Fallback: script's own location (two levels up from .claude/hooks/).
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -n "${CLAUDE_PROJECT_DIR:-}" && "$CLAUDE_PROJECT_DIR" != "$PROJECT_DIR" ]]; then
  echo "WARNING: CLAUDE_PROJECT_DIR mismatch (expected=$PROJECT_DIR, got=$CLAUDE_PROJECT_DIR). Using computed." >&2
fi

# Normalize the script path to absolute using realpath -m (--canonicalize-missing).
# This resolves .., ., symlinks, and produces a clean absolute path
# even if the file doesn't exist.
if [[ "$SCRIPT_PATH" == /* ]]; then
  # Already absolute
  ABS_PATH=$(realpath -m "$SCRIPT_PATH" 2>/dev/null) || reject "P5:realpath_failed"
else
  # Relative to project directory
  ABS_PATH=$(realpath -m "$PROJECT_DIR/$SCRIPT_PATH" 2>/dev/null) || reject "P5:realpath_failed"
fi

# Safety check: ABS_PATH must be non-empty
[[ -z "$ABS_PATH" ]] && reject "P5:empty_abs_path"

# =======================================================
# Phase 6: Judge — is the normalized path under scripts/ or .claude/hooks/?
# =======================================================

# The normalized absolute path must:
# 1. Start with PROJECT_DIR/ (stay within the project)
# 2. Have a /scripts/ component in the path OR be under .claude/hooks/

# Check 1: Must be under PROJECT_DIR
[[ "$ABS_PATH" == "$PROJECT_DIR/"* ]] || reject "P6:outside_project"

# Get the relative path within the project
REL_PATH="${ABS_PATH#"$PROJECT_DIR"/}"

# Check 2a: Relative path must start with "scripts/" or contain "/scripts/"
# This correctly handles:
#   scripts/foo.py                          -> allow
#   .claude/skills/refine-iteratively/scripts/extract_metadata.py -> allow
#   evil_scripts/payload.py                 -> reject (no /scripts/ boundary)
if [[ "$REL_PATH" == scripts/* ]] || [[ "$REL_PATH" == */scripts/* ]]; then
  allow
fi

# Check 2b: Relative path under .claude/hooks/
# This allows:
#   .claude/hooks/test-permission-fallback.sh -> allow
#   .claude/hooks/permission-fallback.sh      -> allow
#   .claude/hooks_evil/script.sh              -> reject (no /hooks/ boundary)
if [[ "$REL_PATH" == .claude/hooks/* ]]; then
  allow
fi

# Default: show permission dialog
reject "P6:not_in_allowed_dir"
