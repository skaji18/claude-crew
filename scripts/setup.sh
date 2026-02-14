#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ERRORS=0
AUTO_YES=false

# Parse flags
for arg in "$@"; do
  case "$arg" in
    -y|--yes) AUTO_YES=true ;;
  esac
done

echo "=== claude-crew Setup ===" && echo

# --- Helper: detect package manager ---
detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v brew >/dev/null 2>&1; then
    echo "brew"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  else
    echo ""
  fi
}

# --- Helper: install a package ---
install_pkg() {
  local pkg="$1"
  local mgr
  mgr="$(detect_pkg_manager)"

  if [[ -z "$mgr" ]]; then
    echo "  No supported package manager found. Please install '$pkg' manually."
    return 1
  fi

  echo "  Installing '$pkg' via $mgr ..."
  case "$mgr" in
    apt)    sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg" ;;
    brew)   brew install "$pkg" ;;
    dnf)    sudo dnf install -y -q "$pkg" ;;
    yum)    sudo yum install -y -q "$pkg" ;;
    pacman) sudo pacman -S --noconfirm "$pkg" ;;
  esac
}

# --- Helper: prompt yes/no ---
confirm() {
  local msg="$1"
  # --yes flag or non-interactive (piped stdin) → default yes
  if [[ "$AUTO_YES" == true ]] || [[ ! -t 0 ]]; then
    return 0
  fi
  read -rp "$msg [Y/n] " answer
  [[ -z "$answer" || "$answer" =~ ^[Yy] ]]
}

# =========================================================
# 1. Bash version
# =========================================================
if [[ ${BASH_VERSINFO[0]:-0} -ge 4 ]]; then
  echo "✓ Bash ${BASH_VERSINFO[0]}"
else
  echo "⚠ Bash ${BASH_VERSINFO[0]:-unknown} — some utility scripts (stats.sh, analyze_patterns.sh) require Bash 4+"
fi

# =========================================================
# 2. python3  (check only — too fundamental to auto-install)
# =========================================================
if command -v python3 >/dev/null 2>&1; then
  echo "✓ python3 $(python3 --version 2>&1 | awk '{print $2}')"
else
  echo "✗ python3 not found — please install Python 3"
  ((ERRORS++)) || true
fi

# =========================================================
# 3. git  (check only — too fundamental to auto-install)
# =========================================================
if command -v git >/dev/null 2>&1; then
  echo "✓ git installed"
else
  echo "✗ git not found — please install git"
  ((ERRORS++)) || true
fi

# =========================================================
# 4. jq  (auto-install if missing)
# =========================================================
if command -v jq >/dev/null 2>&1; then
  echo "✓ jq installed"
else
  echo "✗ jq not found"
  if confirm "  Install jq?"; then
    if install_pkg jq; then
      echo "  ✓ jq installed successfully"
    else
      echo "  ✗ jq installation failed"
      ((ERRORS++)) || true
    fi
  else
    echo "  Skipped. Please install jq manually."
    ((ERRORS++)) || true
  fi
fi

# =========================================================
# 5. Script permissions  (auto-fix)
# =========================================================
FIXED=0
for f in "$PROJECT_ROOT"/scripts/*.sh "$PROJECT_ROOT"/scripts/*.py \
         "$PROJECT_ROOT"/.claude/hooks/*.sh "$PROJECT_ROOT"/.claude/hooks/*.py \
         "$PROJECT_ROOT"/.claude/hooks/permission-fallback \
         "$PROJECT_ROOT"/.claude/skills/*/scripts/*.sh "$PROJECT_ROOT"/.claude/skills/*/scripts/*.py; do
  [[ -e "$f" ]] || continue
  if [[ ! -x "$f" ]]; then
    chmod +x "$f"
    ((FIXED++)) || true
  fi
done

if [[ $FIXED -gt 0 ]]; then
  echo "✓ Fixed executable permission on $FIXED script(s)"
else
  echo "✓ All scripts already executable"
fi

# =========================================================
# 6. Memory MCP  (check only — optional)
# =========================================================
if command -v claude >/dev/null 2>&1; then
  if claude mcp list 2>/dev/null | grep -q "memory:.*✓ Connected"; then
    echo "✓ Memory MCP connected"
  else
    echo "⚠ Memory MCP not connected (optional)"
  fi
else
  echo "⚠ claude CLI not found — Memory MCP check skipped (optional)"
fi

# =========================================================
# 7. Validation
# =========================================================
if [[ $ERRORS -gt 0 ]]; then
  echo
  echo "✗ $ERRORS prerequisite(s) missing. Fix the above and re-run."
  exit 1
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
