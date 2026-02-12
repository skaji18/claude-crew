#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== claude-crew Setup ===" && echo

# Bash 4+
[[ ${BASH_VERSINFO[0]:-0} -ge 4 ]] || { echo "✗ Bash 4+ required"; exit 1; }
echo "✓ Bash ${BASH_VERSINFO[0]}"

# Check jq, git
command -v jq >/dev/null 2>&1 || { echo "✗ jq not found"; exit 1; }
echo "✓ jq installed"
command -v git >/dev/null 2>&1 || { echo "✗ git not found"; exit 1; }
echo "✓ git installed"

# Check Memory MCP connection (optional feature)
if command -v claude >/dev/null 2>&1; then
  if claude mcp list 2>/dev/null | grep -q "memory:.*✓ Connected"; then
    echo "✓ Memory MCP connected"
  else
    echo "⚠ Memory MCP not connected (optional feature)"
  fi
else
  echo "⚠ Memory MCP check skipped (claude command not found — optional feature)"
fi

echo
bash "$PROJECT_ROOT/scripts/validate_config.sh" || { echo "✗ Config validation failed"; exit 1; }
echo
bash "$PROJECT_ROOT/scripts/health_check.sh" || { echo "✗ Health check failed"; exit 1; }

echo && echo "✅ claude-crew setup complete!" && echo
echo "Quick Start:"
echo "1. Open Claude Code in this directory"
echo "2. Give Claude a task (e.g., \"Research the best testing frameworks for Python\")"
echo "3. Claude will decompose, execute, aggregate, and report automatically"
echo && echo "For more info: docs/parent_guide.md"
