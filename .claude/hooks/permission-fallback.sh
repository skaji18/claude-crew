#!/bin/bash
# .claude/hooks/permission-fallback.sh
#
# PermissionRequest フォールバック:
# settings.json の glob でカバーしきれないスクリプト実行を自動承認する。
#
# 前提: このスクリプトに到達する = settings.json の deny を通過済み
# 目的: python3/bash/sh 経由のスクリプト実行（パス形式不問）を allow する

set -euo pipefail

# jq dependency check — fail closed (show dialog) if unavailable
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

allow() {
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
EOF
  exit 0
}

# Guard 1: Compound commands (shell operators + logical operators)
[[ "$COMMAND" =~ [\;\|\&\`\>\<] ]] && exit 0
[[ "$COMMAND" =~ \$\( ]]            && exit 0
[[ "$COMMAND" =~ \|\| ]]            && exit 0
[[ "$COMMAND" =~ \&\& ]]            && exit 0

# Guard 2: Inline code execution (all common interpreters + flag variants)
[[ "$COMMAND" =~ ^(python3?|bash|sh)\ +(--?c(ommand)?|--?e(val)?|--?m)\  ]] && exit 0

# Guard 3: Redirection and process substitution
[[ "$COMMAND" =~ \<\< ]] && exit 0
[[ "$COMMAND" =~ \<\( ]] && exit 0
[[ "$COMMAND" =~ \>\( ]] && exit 0

# Guard 4: Environment variable assignment prefix
[[ "$COMMAND" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && exit 0

# Allow: Interpreter + scripts/ path (python3, bash, sh)
[[ "$COMMAND" =~ ^(python3|bash|sh)\ +.*scripts/ ]] && allow

# Default: Show permission dialog
exit 0
