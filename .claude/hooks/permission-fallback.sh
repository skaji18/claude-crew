#!/bin/bash
# .claude/hooks/permission-fallback.sh
#
# PermissionRequest fallback:
# settings.json の glob でカバーしきれないコマンド実行を自動承認する。
#
# 前提: このスクリプトに到達する = settings.json の deny を通過済み
# 目的:
#   1. scripts/ および .claude/hooks/ 配下スクリプト実行を allow する
#      - python3/bash/sh 経由の実行
#      - 直接実行（shebang ベース: ./scripts/foo.sh）
#   2. プロジェクト内ファイル操作の一般コマンドを allow する (Phase 7)
#
# 設計原則: 「入力を正規化してから判定」
#   1. 制御文字を拒否 (sanitize)
#   2. tool_name を検証
#   3. 危険なシェル構文を拒否 (compound commands, redirections, etc.)
#   4. コマンドをパースして interpreter / options / script_path に分離
#   5. オプションを正規化して危険フラグを拒否
#   6. パスを正規化して scripts/ or .claude/hooks/ 配下かを判定
#   7. 一般コマンド: ALWAYS_ASK チェック + パス封じ込め検証

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

# bash: -n is safe (syntax check only, no execution)
SAFE_FLAGS_bash="n"
# bash: dangerous flags
DANGEROUS_FLAGS_bash="c i"
DANGEROUS_LONG_FLAGS_bash="--init-file --rcfile"

# sh: same as bash (minus -n for now)
SAFE_FLAGS_sh=""
DANGEROUS_FLAGS_sh="c i"
DANGEROUS_LONG_FLAGS_sh="--init-file --rcfile"

# =======================================================
# Configuration: Phase 7 — General command auto-approval
# =======================================================
# ALWAYS_ASK: Commands that always show a permission dialog,
# regardless of their arguments. These are commands whose
# effects cannot be assessed by examining path arguments alone.
#
# Organized by reason. Edit to add/remove commands.
# Lookup is via bash associative array (O(1) per command).

# Network: primary data exfiltration / remote access vectors
# Omitted (user-manageable): sftp ncat netcat ping dig nslookup host
#   traceroute tracepath telnet ftp xdg-open open — diagnostics/rare/URL-caught
ALWAYS_ASK_NETWORK="curl wget ssh scp rsync nc"

# Privilege: actual privilege escalation
# Omitted (user-manageable): doas pkexec chown chgrp — rare or path-contained
ALWAYS_ASK_PRIVILEGE="sudo su"

# Execution: wrap/run other commands (inner command invisible to Phase 7)
# busybox: wraps any command (busybox wget, busybox sh)
# screen/tmux: can silently run commands in background (screen -d -m curl ...)
# script: can wrap commands via -c flag (script -c "curl ..." /dev/null)
# Omitted (user-manageable): watch crontab at gdb lldb strace ltrace dd
ALWAYS_ASK_EXECUTION="eval exec xargs env nohup timeout busybox screen tmux script"

# Package: download/install software (network + system modification)
# Omitted (user-manageable): yum dnf pacman brew snap gem yarn pnpm — platform-specific
ALWAYS_ASK_PACKAGE="pip pip3 npm apt apt-get"

# Interpreters not in INTERPRETERS list (Phase 4 only handles python3/bash/sh;
# these other interpreters would bypass Phase 4 and need always-ask treatment)
# Omitted (user-manageable): lua — rare in agent workflows
ALWAYS_ASK_INTERPRETERS="node perl ruby php"

# Additional allowed directories for path containment checks.
# Space-separated absolute paths. Empty by default.
# Example: ALLOWED_DIRS_EXTRA="/tmp/claude-work /data/shared"
ALLOWED_DIRS_EXTRA=""

# Source user overrides if present (AFTER defaults above)
_HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$_HOOK_DIR/permission-config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$_HOOK_DIR/permission-config.sh"
fi

# Build associative array for O(1) lookup
declare -A _ALWAYS_ASK_SET
for _cmd in $ALWAYS_ASK_NETWORK $ALWAYS_ASK_PRIVILEGE $ALWAYS_ASK_EXECUTION $ALWAYS_ASK_PACKAGE $ALWAYS_ASK_INTERPRETERS; do
  _ALWAYS_ASK_SET["$_cmd"]=1
done

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
# Phase 1.5: Strip safe trailing suffixes (pre-Phase 2)
# =======================================================
# Safe suffixes are stripped BEFORE operator guards so that
# P1/P2 never see the safe operators. The core command
# then passes through P1-P6 normally.

# --- Regex patterns stored in variables (avoids quoting hell in [[ =~ ]]) ---
# IMPORTANT: When used as [[ "$X" =~ $RE_VAR ]], do NOT quote $RE_VAR.
RE_OR_TRUE='^(.+) \|\| true$'
RE_2_REDIR1='^(.+) 2>&1$'
RE_2_REDIR_NULL='^(.+) 2>/dev/null$'

# For echo with double-quoted literals: reject $, backtick, (, ), backslash
# Character class for safe content inside double quotes
SAFE_DQ='[^$`()\\"]'
RE_OR_ECHO_DQ="^(.+) \\|\\| echo \"(${SAFE_DQ}*)\"$"
RE_AND_ECHO_DQ="^(.+) && echo \"(${SAFE_DQ}*)\"$"

# For echo with single-quoted literals: reject only single quotes
SQ="'"
RE_OR_ECHO_SQ="^(.+) \\|\\| echo ${SQ}([^${SQ}]*)${SQ}$"
RE_AND_ECHO_SQ="^(.+) && echo ${SQ}([^${SQ}]*)${SQ}$"

ORIGINAL_COMMAND="$COMMAND"
SAFE_SUFFIX=""

# Iteratively strip safe suffixes from the end of COMMAND.
# Loop because suffixes can combine: "2>&1 || true"
# Process order: strip logical operators first, then stderr redirects
# (so "2>&1 || true" strips "|| true" first, then "2>&1")

SUFFIX_CHANGED=true
while $SUFFIX_CHANGED; do
  SUFFIX_CHANGED=false

  # Strip: || true
  if [[ "$COMMAND" =~ $RE_OR_TRUE ]]; then
    COMMAND="${BASH_REMATCH[1]}"
    SAFE_SUFFIX=" || true${SAFE_SUFFIX}"
    SUFFIX_CHANGED=true
    continue
  fi

  # Strip: || echo "literal" (double-quoted, no expansion chars)
  if [[ "$COMMAND" =~ $RE_OR_ECHO_DQ ]]; then
    COMMAND="${BASH_REMATCH[1]}"
    SAFE_SUFFIX=" || echo \"${BASH_REMATCH[2]}\"${SAFE_SUFFIX}"
    SUFFIX_CHANGED=true
    continue
  fi

  # Strip: || echo 'literal' (single-quoted)
  if [[ "$COMMAND" =~ $RE_OR_ECHO_SQ ]]; then
    COMMAND="${BASH_REMATCH[1]}"
    SAFE_SUFFIX=" || echo '${BASH_REMATCH[2]}'${SAFE_SUFFIX}"
    SUFFIX_CHANGED=true
    continue
  fi

  # Strip: && echo "literal" (double-quoted, no expansion chars)
  if [[ "$COMMAND" =~ $RE_AND_ECHO_DQ ]]; then
    COMMAND="${BASH_REMATCH[1]}"
    SAFE_SUFFIX=" && echo \"${BASH_REMATCH[2]}\"${SAFE_SUFFIX}"
    SUFFIX_CHANGED=true
    continue
  fi

  # Strip: && echo 'literal' (single-quoted)
  if [[ "$COMMAND" =~ $RE_AND_ECHO_SQ ]]; then
    COMMAND="${BASH_REMATCH[1]}"
    SAFE_SUFFIX=" && echo '${BASH_REMATCH[2]}'${SAFE_SUFFIX}"
    SUFFIX_CHANGED=true
    continue
  fi

  # Strip: 2>&1
  if [[ "$COMMAND" =~ $RE_2_REDIR1 ]]; then
    COMMAND="${BASH_REMATCH[1]}"
    SAFE_SUFFIX=" 2>&1${SAFE_SUFFIX}"
    SUFFIX_CHANGED=true
    continue
  fi

  # Strip: 2>/dev/null
  if [[ "$COMMAND" =~ $RE_2_REDIR_NULL ]]; then
    COMMAND="${BASH_REMATCH[1]}"
    SAFE_SUFFIX=" 2>/dev/null${SAFE_SUFFIX}"
    SUFFIX_CHANGED=true
    continue
  fi
done

# Debug: log what was stripped
if [[ -n "$SAFE_SUFFIX" && "${PERMISSION_DEBUG:-0}" == "1" ]]; then
  echo "SUFFIX_STRIPPED[$SAFE_SUFFIX]" >&2
fi

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

# No script path found — for known interpreters, this means no script was specified.
# For non-interpreter commands, SCRIPT_PATH was set in Phase 3.
# Known interpreters without a script path: reject (e.g., bare "python3" or "bash")
if [[ -z "$SCRIPT_PATH" ]]; then
  if $IS_KNOWN_INTERPRETER; then
    reject "P4:no_script_path"
  fi
  # Non-interpreter: SCRIPT_PATH should have been set in Phase 3.
  # If we reach here, something went wrong. Fail closed.
  reject "P4:no_script_path"
fi

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
if [[ "$ABS_PATH" == "$PROJECT_DIR/"* ]]; then
  # Get the relative path within the project
  REL_PATH="${ABS_PATH#"$PROJECT_DIR"/}"

  # Check 2a: Relative path must start with "scripts/" or contain "/scripts/"
  if [[ "$REL_PATH" == scripts/* ]] || [[ "$REL_PATH" == */scripts/* ]]; then
    allow
  fi

  # Check 2b: Relative path under .claude/hooks/
  if [[ "$REL_PATH" == .claude/hooks/* ]]; then
    allow
  fi
fi

# Phase 6 did not approve. Route based on command type:
# - Known interpreter with unapproved script path: REJECT (don't fall through)
#   Rationale: python3/bash/sh running an arbitrary script should NOT be
#   auto-approved just because the command isn't in ALWAYS_ASK.
# - Non-interpreter command: fall through to Phase 7 for general approval.
if $IS_KNOWN_INTERPRETER; then
  reject "P6:not_in_allowed_dir"
fi

# =======================================================
# Phase 7: General command auto-approval
# =======================================================
# Reached when: command's first word is NOT a known interpreter.
# Preconditions:
#   - Phase 1-2 passed (structurally safe, no shell metacharacters)
#   - WORDS[] is populated from Phase 3
#   - IS_KNOWN_INTERPRETER is false
#
# Decision logic:
#   7A: Extract command name (basename, strip path prefix)
#   7B: Check ALWAYS_ASK list → reject if present
#   7C: Collect path-like arguments from WORDS[1..n]
#   7D: Check path containment → allow if all in-project, reject otherwise

# --- Step 7A: Extract command name ---
CMD_NAME=$(basename "${WORDS[0]}")
[[ "${PERMISSION_DEBUG:-0}" == "1" ]] && echo "P7A:cmd=$CMD_NAME" >&2

# --- Step 7B: Check ALWAYS_ASK list ---
if [[ -n "${_ALWAYS_ASK_SET[$CMD_NAME]+x}" ]]; then
  reject "P7B:always_ask:$CMD_NAME"
fi

# --- Step 7C: Collect path-like arguments ---
# Walk WORDS[1..n], skipping flags (words starting with -)
# After --, treat all remaining words as positional arguments.
# Path-like: starts with / or ./ or ../ or contains /
declare -a P7_PATH_ARGS=()
P7_PAST_DD=false
P7_IDX=1

while [[ $P7_IDX -lt ${#WORDS[@]} ]]; do
  P7_WORD="${WORDS[$P7_IDX]}"

  # End-of-options marker
  if [[ "$P7_WORD" == "--" ]] && ! $P7_PAST_DD; then
    P7_PAST_DD=true
    ((P7_IDX++))
    continue
  fi

  # Skip flags (unless past --)
  if [[ "$P7_WORD" == -* ]] && ! $P7_PAST_DD; then
    ((P7_IDX++))
    continue
  fi

  # Strip surrounding quotes from word before path analysis.
  # read -ra does NOT process shell quotes, so "/etc/passwd" becomes
  # the literal characters " / e t c ... " which tricks realpath into
  # resolving inside the project. Strip them to see the real path.
  P7_WORD_STRIPPED="$P7_WORD"
  if [[ "${P7_WORD_STRIPPED:0:1}" == '"' && "${P7_WORD_STRIPPED: -1}" == '"' && ${#P7_WORD_STRIPPED} -ge 2 ]]; then
    P7_WORD_STRIPPED="${P7_WORD_STRIPPED:1:${#P7_WORD_STRIPPED}-2}"
  elif [[ "${P7_WORD_STRIPPED:0:1}" == "'" && "${P7_WORD_STRIPPED: -1}" == "'" && ${#P7_WORD_STRIPPED} -ge 2 ]]; then
    P7_WORD_STRIPPED="${P7_WORD_STRIPPED:1:${#P7_WORD_STRIPPED}-2}"
  fi

  # Detect URLs (contains ://) — network addresses, not filesystem paths.
  # Reject regardless of ALWAYS_ASK to close URL-masquerading attacks.
  if [[ "$P7_WORD_STRIPPED" == *"://"* ]]; then
    reject "P7C:url_detected:$P7_WORD_STRIPPED"
  fi

  # Positional argument — check if path-like
  # Rule 1: starts with / → absolute path
  # Rule 2: starts with ./ or ../ → explicit relative
  # Rule 3: contains / anywhere → implicit relative path (e.g., work/results/file.md)
  if [[ "$P7_WORD_STRIPPED" == /* ]] || [[ "$P7_WORD_STRIPPED" == ./* ]] || [[ "$P7_WORD_STRIPPED" == ../* ]] || [[ "$P7_WORD_STRIPPED" == */* ]]; then
    P7_PATH_ARGS+=("$P7_WORD_STRIPPED")
  fi
  # else: non-path positional arg (e.g., "hello", "5", "pattern", ".version")
  # — ignored for containment purposes. Bare filenames (config.yaml) are
  #   implicitly project-local when cwd is the project dir.

  ((P7_IDX++))
done

[[ "${PERMISSION_DEBUG:-0}" == "1" ]] && echo "P7C:paths=${P7_PATH_ARGS[*]:-none}" >&2

# --- Step 7D: Check path containment ---
if [[ ${#P7_PATH_ARGS[@]} -eq 0 ]]; then
  # No path-like arguments — command operates on non-path args or no args.
  # Dangerous no-path commands were caught in 7B (ALWAYS_ASK).
  # Examples that reach here: echo hello, date, sleep 5, wc -l, basename foo
  [[ "${PERMISSION_DEBUG:-0}" == "1" ]] && echo "P7D:allow:no_paths" >&2
  allow
fi

# Check each path argument for project containment
for p7_path in "${P7_PATH_ARGS[@]}"; do
  # Resolve to absolute
  if [[ "$p7_path" == /* ]]; then
    P7_ABS=$(realpath -m "$p7_path" 2>/dev/null) || reject "P7D:realpath_failed"
  else
    P7_ABS=$(realpath -m "$PROJECT_DIR/$p7_path" 2>/dev/null) || reject "P7D:realpath_failed"
  fi

  [[ -z "$P7_ABS" ]] && reject "P7D:empty_abs"

  # Check containment against project directory
  P7_CONTAINED=false
  if [[ "$P7_ABS" == "$PROJECT_DIR" ]] || [[ "$P7_ABS" == "$PROJECT_DIR/"* ]]; then
    P7_CONTAINED=true
  fi

  # Check containment against extra allowed directories
  if ! $P7_CONTAINED && [[ -n "$ALLOWED_DIRS_EXTRA" ]]; then
    for p7_extra_dir in $ALLOWED_DIRS_EXTRA; do
      [[ -z "$p7_extra_dir" ]] && continue
      P7_RESOLVED_EXTRA=$(realpath -m "$p7_extra_dir" 2>/dev/null) || continue
      if [[ "$P7_ABS" == "$P7_RESOLVED_EXTRA" ]] || [[ "$P7_ABS" == "$P7_RESOLVED_EXTRA/"* ]]; then
        P7_CONTAINED=true
        break
      fi
    done
  fi

  if ! $P7_CONTAINED; then
    [[ "${PERMISSION_DEBUG:-0}" == "1" ]] && echo "P7D:reject:outside=$P7_ABS" >&2
    reject "P7D:outside_project:$P7_ABS"
  fi
done

# All path arguments are contained within the project (or allowed dirs)
[[ "${PERMISSION_DEBUG:-0}" == "1" ]] && echo "P7D:allow:all_contained" >&2
allow
