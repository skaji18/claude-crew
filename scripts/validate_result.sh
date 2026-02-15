#!/bin/bash
# Validate a result file for completeness and quality
# Usage: bash scripts/validate_result.sh <result_path> <persona>
#        bash scripts/validate_result.sh --reconcile <plan_path> <results_dir>
# Output: JSON to stdout

set -euo pipefail

# Source error code system
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/error_codes.sh" 2>/dev/null || {
  echo "ERROR: failed to load error_codes.sh" >&2
  exit 1
}

# Reconcile mode: check planned vs actual results
reconcile_plan() {
  local PLAN_PATH="$1"
  local RESULTS_DIR="$2"

  # Parse plan.md for task numbers (extract from Tasks table)
  local PLANNED_TASKS=$(grep -E '^\| [0-9]+ \|' "$PLAN_PATH" | awk -F'|' '{print $2}' | tr -d ' ' || echo "")
  local TOTAL_PLANNED=$(echo "$PLANNED_TASKS" | wc -w)
  local MISSING=()
  local RESULTS_STATUS="{}"
  local OVERALL_STATUS="success"

  # Check each planned task
  for task_num in $PLANNED_TASKS; do
    local RESULT_FILE="$RESULTS_DIR/result_${task_num}.md"
    if [[ ! -f "$RESULT_FILE" ]]; then
      MISSING+=("$task_num")
      OVERALL_STATUS="partial"
    else
      # Extract status from YAML frontmatter
      local STATUS=$(grep -E '^status:' "$RESULT_FILE" | head -1 | awk '{print $2}' || echo "unknown")
      RESULTS_STATUS=$(echo "$RESULTS_STATUS" | jq --arg k "$task_num" --arg v "$STATUS" '. + {($k): $v}')
      if [[ "$STATUS" != "success" ]]; then
        OVERALL_STATUS="partial"
      fi
    fi
  done

  # Build missing array JSON
  local MISSING_JSON="["
  local FIRST=true
  for m in "${MISSING[@]+"${MISSING[@]}"}"; do
    [[ "$FIRST" == true ]] && FIRST=false || MISSING_JSON+=", "
    MISSING_JSON+="$m"
  done
  MISSING_JSON+="]"

  local TOTAL_FOUND=$((TOTAL_PLANNED - ${#MISSING[@]}))

  # Output JSON
  cat <<EOF
{
  "total_planned": $TOTAL_PLANNED,
  "total_found": $TOTAL_FOUND,
  "missing": $MISSING_JSON,
  "results": $RESULTS_STATUS,
  "status": "$OVERALL_STATUS"
}
EOF

  [[ "$OVERALL_STATUS" == "success" ]] && exit 0 || exit 1
}

# Usage check
if [[ $# -eq 3 && "$1" == "--reconcile" ]]; then
  reconcile_plan "$2" "$3"
  exit $?
elif [[ $# -ne 2 ]]; then
  echo "Usage: $0 <result_path> <persona>" >&2
  echo "       $0 --reconcile <plan_path> <results_dir>" >&2
  echo "  persona: researcher | writer | coder | reviewer | default" >&2
  exit 1
fi

RESULT_PATH="$1"
PERSONA="$2"

# Initialize validation results
COMPLETE_MARKER=false
LINE_COUNT=0
HAS_SOURCES=false
HAS_CODE_BLOCKS=false
STATUS="pass"
ISSUES=()

# Check file exists
if [[ ! -f "$RESULT_PATH" ]]; then
  ERR_MSG=$(get_error_message E128)
  echo "{\"complete_marker\": false, \"line_count\": 0, \"has_sources\": false, \"has_code_blocks\": false, \"status\": \"fail\", \"issues\": [\"[E128] $ERR_MSG\"]}"
  exit 0
fi

# 1. Check complete marker (last line)
LAST_LINE=$(tail -1 "$RESULT_PATH" 2>/dev/null || echo "")
if [[ "$LAST_LINE" == "<!-- COMPLETE -->" ]]; then
  COMPLETE_MARKER=true
else
  ERR_MSG=$(get_error_message E134)
  ISSUES+=("[E134] $ERR_MSG")
  STATUS="fail"
fi

# 2. Check line count
LINE_COUNT=$(wc -l < "$RESULT_PATH" 2>/dev/null || echo "0")
if [[ $LINE_COUNT -lt 20 ]]; then
  ERR_MSG=$(get_error_message E135)
  ISSUES+=("[E135] $ERR_MSG (found: $LINE_COUNT)")
  STATUS="fail"
fi

# 3. Check Sources section (researcher only)
if [[ "$PERSONA" == "researcher" ]]; then
  SOURCES_COUNT=$(grep -c '## Sources' "$RESULT_PATH" 2>/dev/null || true)
  if [[ ${SOURCES_COUNT:-0} -gt 0 ]]; then
    HAS_SOURCES=true
  else
    ERR_MSG=$(get_error_message E136)
    ISSUES+=("warning: [E136] $ERR_MSG")
    # Note: warnings do not change status to fail
  fi
fi

# 4. Check code blocks (coder only)
if [[ "$PERSONA" == "coder" ]]; then
  CODE_BLOCK_COUNT=$(grep -c '```' "$RESULT_PATH" 2>/dev/null || true)
  if [[ ${CODE_BLOCK_COUNT:-0} -gt 0 ]]; then
    HAS_CODE_BLOCKS=true
  else
    ERR_MSG=$(get_error_message E137)
    ISSUES+=("warning: [E137] $ERR_MSG")
    # Note: warnings do not change status to fail
  fi
fi

# Extract YAML frontmatter metadata
RESULT_STATUS="unknown"
RESULT_QUALITY="unknown"
RESULT_COMPLETENESS="unknown"

# Read first 20 lines for YAML frontmatter
FRONTMATTER=$(head -20 "$RESULT_PATH" 2>/dev/null || echo "")

# Extract status field
if [[ -n "$FRONTMATTER" ]]; then
  RESULT_STATUS=$(echo "$FRONTMATTER" | grep -E '^status:' | head -1 | awk '{print $2}' || echo "unknown")
  # If empty, set to unknown
  [[ -z "$RESULT_STATUS" ]] && RESULT_STATUS="unknown"
fi

# Extract quality field
if [[ -n "$FRONTMATTER" ]]; then
  RESULT_QUALITY=$(echo "$FRONTMATTER" | grep -E '^quality:' | head -1 | awk '{print $2}' || echo "unknown")
  # If empty, set to unknown
  [[ -z "$RESULT_QUALITY" ]] && RESULT_QUALITY="unknown"
fi

# Extract completeness field
if [[ -n "$FRONTMATTER" ]]; then
  RESULT_COMPLETENESS=$(echo "$FRONTMATTER" | grep -E '^completeness:' | head -1 | awk '{print $2}' || echo "unknown")
  # If empty, set to unknown
  [[ -z "$RESULT_COMPLETENESS" ]] && RESULT_COMPLETENESS="unknown"
fi

# Build JSON output
# Escape issues array for JSON
ISSUES_JSON="["
FIRST=true
for issue in "${ISSUES[@]+"${ISSUES[@]}"}"; do
  if [[ "$FIRST" == true ]]; then
    FIRST=false
  else
    ISSUES_JSON+=", "
  fi
  # Escape double quotes and backslashes in issue text
  ESCAPED_ISSUE=$(echo "$issue" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
  ISSUES_JSON+="\"$ESCAPED_ISSUE\""
done
ISSUES_JSON+="]"

# Output JSON
cat <<EOF
{
  "complete_marker": $COMPLETE_MARKER,
  "line_count": $LINE_COUNT,
  "has_sources": $HAS_SOURCES,
  "has_code_blocks": $HAS_CODE_BLOCKS,
  "status": "$STATUS",
  "issues": $ISSUES_JSON,
  "result_status": "$RESULT_STATUS",
  "result_quality": "$RESULT_QUALITY",
  "result_completeness": "$RESULT_COMPLETENESS"
}
EOF
