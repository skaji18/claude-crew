#!/bin/bash
# .claude/hooks/permission-fallback.sh
#
# PermissionRequest fallback:
# settings.json の glob でカバーしきれないスクリプト実行を自動承認する。
#
# 前提: このスクリプトに到達する = settings.json の deny を通過済み
# 目的: scripts/ 配下スクリプト実行を allow する
#   - python3/bash/sh 経由の実行
#   - 直接実行（shebang ベース: ./scripts/foo.sh）
#
# 設計原則: 「入力を正規化してから判定」
#   1. 制御文字を拒否 (sanitize)
#   2. tool_name を検証
#   3. 危険なシェル構文を拒否 (compound commands, redirections, etc.)
#   4. コマンドをパースして interpreter / options / script_path に分離
#   5. オプションを正規化して危険フラグを拒否
#   6. パスを正規化して scripts/ 配下かを判定

set -euo pipefail

# --- Fail closed: jq required ---
command -v jq >/dev/null 2>&1 || exit 0

# --- Read input ---
INPUT=$(cat)

# Guard S0: Reject null bytes in raw input (before jq processing).
# Bash command substitution strips null bytes, so [[:cntrl:]] check would miss them.
# Null bytes in JSON (\u0000) get converted by jq to real 0x00, then bash strips them,
# causing adjacent strings to concatenate and potentially bypass path checks.
if printf '%s' "$INPUT" | grep -qP '\x00' 2>/dev/null; then
  exit 0
fi
# Also reject JSON-encoded null (\u0000) in the raw JSON string before jq processes it.
if printf '%s' "$INPUT" | grep -q '\\u0000' 2>/dev/null; then
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# --- Helper: allow decision ---
allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n'
  exit 0
}

# =======================================================
# Phase 1: Sanitize — reject malformed input
# =======================================================

# Guard S1: Control characters (newline, CR, null, tabs, etc.)
# These can break regex guards and enable injection.
# [[:cntrl:]] matches all control characters (0x00-0x1F, 0x7F).
if [[ "$COMMAND" =~ [[:cntrl:]] ]]; then
  exit 0
fi

# Guard S2: tool_name must be "Bash"
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL_NAME" != "Bash" ]] && exit 0

# =======================================================
# Phase 2: Reject dangerous shell syntax (pre-parse)
# =======================================================

# Guard P1: Shell operators — compound commands, pipes, backgrounding
[[ "$COMMAND" =~ [\;\|\&\`] ]] && exit 0

# Guard P2: Redirections and process substitution
[[ "$COMMAND" =~ [\>\<] ]] && exit 0

# Guard P3: Command substitution $( ... )
[[ "$COMMAND" =~ \$\( ]] && exit 0

# Guard P4: Variable/arithmetic expansion ($VAR, ${VAR}, $[arith])
[[ "$COMMAND" =~ \$[A-Za-z_{[:digit:]\[] ]] && exit 0

# Guard P5: Environment variable assignment prefix (VAR=value cmd)
[[ "$COMMAND" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && exit 0

# Guard P6: Tilde expansion (~ at start of a word creates semantic gap:
# hook sees literal ~, but shell expands to $HOME)
[[ "$COMMAND" =~ (^|\ )~ ]] && exit 0

# Guard P7: Glob/brace expansion characters (hook checks literal path,
# but shell expands globs before execution)
[[ "$COMMAND" =~ [\*\?\[\{] ]] && exit 0

# =======================================================
# Phase 3: Parse command into structured components
# =======================================================

# Split command into words
read -ra WORDS <<< "$COMMAND"
[[ ${#WORDS[@]} -lt 1 ]] && exit 0

INTERPRETER="${WORDS[0]}"
SCRIPT_PATH=""

# Only allow known interpreters — or treat as direct execution
case "$INTERPRETER" in
  python3|bash|sh) ;;
  *)
    # Direct execution (shebang-based): first word is the script path itself.
    # No interpreter options to parse — skip Phase 4, go to Phase 5.
    SCRIPT_PATH="$INTERPRETER"
    ;;
esac

# =======================================================
# Phase 4: Normalize options — classify each word
# =======================================================

# Walk through words after the interpreter.
# Categorize as: safe-flag, dangerous-flag, or positional-arg (script path).
#
# Dangerous flags (must reject):
#   python3: -c, -e, -m, --command, --eval (with or without space before value)
#   bash/sh: -c, --init-file, --rcfile, -i
#
# Safe single-char flags (allow and skip):
#   python3: -u, -B, -s, -S, -v, -b, -q, -O, -I, -E, -P, -R, -W*, -X*
#   bash/sh: (none that we auto-allow; safest to be conservative)
#
# Strategy for flags attached to values (e.g., -c"code", -mmodule):
#   If a word starts with a known dangerous flag prefix, reject.

# Phase 4 only applies when a known interpreter is used.
# For direct execution (shebang), SCRIPT_PATH was already set in Phase 3.
if [[ -z "$SCRIPT_PATH" ]]; then
  IDX=1

  while [[ $IDX -lt ${#WORDS[@]} ]]; do
    WORD="${WORDS[$IDX]}"

    if [[ "$WORD" == -* ]]; then
      # --- Option word ---

      # Dangerous flags: exact match or prefix match (handles -c"code", -mmod)
      case "$WORD" in
        # Exact matches for flags that take a following argument
        -c|--command|-e|--eval|-m)
          exit 0
          ;;
        # Prefix matches: -c"code", -ccode, -mmodule, -e"code"
        -c*|-e*|-m*)
          # Distinguish from safe single-char flags like -B, -u
          # -c, -e, -m followed by more chars = dangerous (value attached)
          # But single-char flags like -B are exactly 2 chars and not -c/-e/-m
          exit 0
          ;;
        # Bash-specific dangerous flags
        --init-file|--rcfile|-i)
          [[ "$INTERPRETER" == "bash" || "$INTERPRETER" == "sh" ]] && exit 0
          ;;
      esac

      # Safe single-char flags for python3 (exactly 2 chars: dash + letter)
      if [[ "$INTERPRETER" == "python3" && ${#WORD} -eq 2 ]]; then
        case "$WORD" in
          -u|-B|-s|-S|-v|-b|-q|-O|-I|-E|-P|-R)
            # Known safe python3 flags — skip
            ((IDX++))
            continue
            ;;
        esac
      fi

      # Unknown flag — fail closed (show dialog)
      exit 0
    else
      # --- Positional argument = script path ---
      SCRIPT_PATH="$WORD"
      break
    fi

    ((IDX++))
  done
fi

# No script path found
[[ -z "$SCRIPT_PATH" ]] && exit 0

# =======================================================
# Phase 5: Normalize path — resolve to absolute, then check
# =======================================================

# Determine project directory.
# CLAUDE_PROJECT_DIR is set by Claude Code when invoking hooks.
# Fallback: script's own location (two levels up from .claude/hooks/).
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  PROJECT_DIR="$CLAUDE_PROJECT_DIR"
else
  PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
fi

# Normalize the script path to absolute using realpath -m (--canonicalize-missing).
# This resolves .., ., symlinks, and produces a clean absolute path
# even if the file doesn't exist.
if [[ "$SCRIPT_PATH" == /* ]]; then
  # Already absolute
  ABS_PATH=$(realpath -m "$SCRIPT_PATH" 2>/dev/null) || exit 0
else
  # Relative to project directory
  ABS_PATH=$(realpath -m "$PROJECT_DIR/$SCRIPT_PATH" 2>/dev/null) || exit 0
fi

# Safety check: ABS_PATH must be non-empty
[[ -z "$ABS_PATH" ]] && exit 0

# =======================================================
# Phase 6: Judge — is the normalized path under scripts/?
# =======================================================

# The normalized absolute path must:
# 1. Start with PROJECT_DIR/ (stay within the project)
# 2. Have a /scripts/ component in the path (the script lives under a scripts/ dir)

# Check 1: Must be under PROJECT_DIR
[[ "$ABS_PATH" == "$PROJECT_DIR/"* ]] || exit 0

# Get the relative path within the project
REL_PATH="${ABS_PATH#"$PROJECT_DIR"/}"

# Check 2: Relative path must start with "scripts/" or contain "/scripts/"
# This correctly handles:
#   scripts/foo.py                          -> allow
#   .claude/skills/refine-iteratively/scripts/extract_metadata.py -> allow
#   evil_scripts/payload.py                 -> reject (no /scripts/ boundary)
if [[ "$REL_PATH" == scripts/* ]] || [[ "$REL_PATH" == */scripts/* ]]; then
  allow
fi

# Default: show permission dialog
exit 0
