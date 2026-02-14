#!/bin/bash
# scripts/error_codes.sh
# Centralized error code definitions for claude-crew
# Usage: source scripts/error_codes.sh && error E001 [context]
# Range: E001-E399 organized by category

# ============================================================================
# CATEGORY 1: Configuration Errors (E001-E099)
# ============================================================================

declare -A ERROR_MESSAGES=(
  # Config file errors (E001-E019)
  ["E001"]="config.yaml not found → Run: bash scripts/setup.sh"
  ["E002"]="config.yaml parse error - invalid YAML → Check YAML syntax with a YAML validator or PyYAML"
  ["E003"]="config.yaml missing required field → Run: bash scripts/validate_config.sh to identify missing fields"
  ["E004"]="default_model invalid - expected haiku, sonnet, or opus → Edit config.yaml and set default_model appropriately"
  ["E005"]="max_parallel out of range - expected 1-20 → Edit config.yaml and set max_parallel to a value between 1 and 20"
  ["E006"]="max_retries out of range - expected 0-10 → Edit config.yaml and set max_retries to a value between 0 and 10"
  ["E007"]="worker_max_turns out of range - expected 5-100 → Edit config.yaml and set worker_max_turns to a value between 5 and 100"
  ["E008"]="background_threshold out of range - expected 1-20 → Edit config.yaml and set background_threshold to a value between 1 and 20"
  ["E009"]="retrospect.enabled invalid - expected true or false → Edit config.yaml and set retrospect.enabled to true or false"
  ["E010"]="retrospect.model invalid - expected haiku, sonnet, or opus → Edit config.yaml and set retrospect.model appropriately"
  ["E011"]="version field missing or invalid - expected semver → Edit config.yaml and set version to format like \"1.0.0\" or \"1.0-rc\""
  ["E012"]="retrospect.filter_threshold invalid - expected number → Edit config.yaml and set retrospect.filter_threshold to a numeric value"
  ["E013"]="max_cmd_duration_sec invalid - expected positive integer → Edit config.yaml and set max_cmd_duration_sec to a positive integer or remove it"

  # Config merge errors (E020-E039)
  ["E020"]="local/config.yaml parse error - invalid YAML → Check YAML syntax in local/config.yaml"
  ["E021"]="local/config.yaml has unknown keys → Review warnings from merge_config.py for typos or invalid keys"
  ["E022"]="local/config.yaml must be YAML mapping - not list or scalar → Edit local/config.yaml to use key-value format"
  ["E023"]="PyYAML not installed, local config ignored → Install with: pip3 install pyyaml"
  ["E024"]="config merge failed → Check stderr output from merge_config.py for details"
  ["E025"]="permission-config.yaml parse error → Check YAML syntax in .claude/hooks/permission-config.yaml"
  ["E026"]="local permission-config.yaml parse error → Check YAML syntax in local/hooks/permission-config.yaml"
  ["E027"]="permission-config.yaml must be YAML mapping → Edit permission-config.yaml to use key-value format"
  ["E028"]="frozen key override blocked - interpreters cannot be overridden → Remove 'interpreters' key from local/hooks/permission-config.yaml"

  # Template errors (E040-E059)
  ["E040"]="template file not found → Check that template path exists in templates/ directory"
  ["E041"]="CLAUDE.md not found → Run: bash scripts/setup.sh or restore CLAUDE.md from git"
  ["E042"]="parent_guide.md not found → Run: bash scripts/setup.sh or restore docs/parent_guide.md from git"
  ["E043"]="worker template missing → Check templates/ directory for required worker template files"
  ["E044"]="decomposer template missing → Check that templates/decomposer.md exists"
  ["E045"]="aggregator template missing → Check that templates/aggregator.md exists"
  ["E046"]="retrospector template missing → Check that templates/retrospector.md exists"

  # Work directory errors (E060-E079)
  ["E060"]="work directory not found → Work directory should be created automatically, check file system permissions"
  ["E061"]="cmd directory creation failed after retries → Check file system permissions on work/ directory"
  ["E062"]="cmd directory already exists - race condition → This is handled automatically by retry logic"
  ["E063"]="tasks subdirectory creation failed → Check file system permissions on work/cmd_NNN/ directory"
  ["E064"]="results subdirectory creation failed → Check file system permissions on work/cmd_NNN/ directory"

  # Settings errors (E080-E099)
  ["E080"]="settings.json not found → Run: bash scripts/setup.sh or restore .claude/settings.json from git"
  ["E081"]="settings.json invalid JSON → Check JSON syntax with: jq . .claude/settings.json"
  ["E082"]="permission-fallback hook not executable → Run: chmod +x .claude/hooks/permission-fallback"
  ["E083"]="permission-fallback hook not found → Run: bash scripts/setup.sh or restore from git"
)

declare -A CONFIG_ERRORS=(
  ["E001"]="Configuration errors (E001-E099)"
  ["E100"]="Execution errors (E100-E199)"
  ["E200"]="Validation errors (E200-E299)"
  ["E300"]="System errors (E300-E399)"
)

# ============================================================================
# CATEGORY 2: Execution Errors (E100-E199)
# ============================================================================

ERROR_MESSAGES+=(
  # Task execution errors (E100-E119)
  ["E100"]="task file not found → Check that task file exists at specified path"
  ["E101"]="task file is empty → Task file must contain task description"
  ["E102"]="task file missing required fields → Check task file has all required YAML frontmatter fields"
  ["E103"]="input file referenced in task not found → Check that all input files referenced in task exist"
  ["E104"]="input file is corrupt or unreadable → Verify file permissions and content"
  ["E105"]="subagent invocation failed → Check subagent spawn logs for error details"
  ["E106"]="subagent timeout → Increase worker timeout or simplify task scope"
  ["E107"]="subagent returned non-zero exit code → Check subagent logs for failure reason"
  ["E108"]="background task failed → Check background task output file for error details"
  ["E109"]="too many parallel tasks → Reduce max_parallel in config.yaml or wait for tasks to complete"

  # Phase errors (E120-E139)
  ["E120"]="decomposer (Phase 1) failed → Check decomposer output for errors"
  ["E121"]="worker (Phase 2) failed → Check worker result files for status: failure"
  ["E122"]="aggregator (Phase 3) failed → Check aggregator output for errors"
  ["E123"]="retrospector (Phase 4) failed → Check retrospector output for errors"
  ["E124"]="plan.md generation failed → Check decomposer logs for errors"
  ["E125"]="task file generation failed → Check decomposer logs for task creation errors"
  ["E126"]="aggregation input missing → Ensure all worker results exist before aggregation"
  ["E127"]="phase transition error → Check execution log for phase state"

  # Result errors (E140-E159)
  ["E128"]="result file not found → Worker must create result file at RESULT_PATH"
  ["E129"]="result file is empty → Worker must write YAML frontmatter and content to result file"
  ["E130"]="result file missing YAML frontmatter → Add --- delimited YAML block at start of result file"
  ["E131"]="result file missing status field → Add status field: success, partial, or failure to YAML frontmatter"
  ["E132"]="result file missing quality field → Add quality field: GREEN, YELLOW, or RED to YAML frontmatter"
  ["E133"]="result file missing completeness field → Add completeness field: 0-100 to YAML frontmatter"
  ["E134"]="result file missing complete marker → Add comment <!-- COMPLETE --> as last line of result file"
  ["E135"]="result line count too low → Result file must be at least 20 lines"
  ["E136"]="researcher result missing Sources section → Add ## Sources section with citations"
  ["E137"]="coder result missing code blocks → Add code examples in triple-backtick blocks"

  # Retry and recovery errors (E160-E179)
  ["E160"]="max retries exceeded → Task failed after max_retries attempts, check task logs"
  ["E161"]="retry failed with same error → Root cause not resolved, manual intervention needed"
  ["E162"]="recovery action failed → Check recovery action logs for errors"

  # Worker-specific errors (E180-E199)
  ["E180"]="researcher: source validation failed → Check that all sources are accessible and cited"
  ["E181"]="writer: document validation failed → Check document structure and required sections"
  ["E182"]="coder: test execution failed → Run tests manually and fix failures"
  ["E183"]="coder: linter or formatter failed → Fix linting errors or adjust linter config"
  ["E184"]="reviewer: review criteria not met → Address review feedback and retry"
  ["E185"]="custom persona: template parse error → Check custom persona template syntax"
)

# ============================================================================
# CATEGORY 3: Validation Errors (E200-E299)
# ============================================================================

ERROR_MESSAGES+=(
  # Metadata validation (E200-E219)
  ["E200"]="YAML frontmatter missing → Add --- delimited YAML block at file start"
  ["E201"]="YAML frontmatter parse error → Check YAML syntax in frontmatter block"
  ["E202"]="required metadata field missing → Check that all required fields are present"
  ["E203"]="metadata field type mismatch → Check field types match expected schema"
  ["E204"]="generated_by field missing → Add generated_by field to YAML frontmatter"
  ["E205"]="date field missing or invalid → Add date field in ISO 8601 format YYYY-MM-DD"
  ["E206"]="cmd_id field missing → Add cmd_id field to YAML frontmatter"
  ["E207"]="task_id field missing → Add task_id field to YAML frontmatter"

  # Result validation (E220-E239)
  ["E220"]="status field invalid - expected success, partial, or failure → Set status to one of: success, partial, or failure"
  ["E221"]="quality field invalid - expected GREEN, YELLOW, or RED → Set quality to one of: GREEN, YELLOW, or RED"
  ["E222"]="completeness out of range - expected 0-100 → Set completeness to integer between 0 and 100"
  ["E223"]="errors field missing → Add errors: [] field (empty array if no errors)"
  ["E224"]="errors field must be array → Change errors field to YAML array format"
  ["E225"]="complete marker not found → Add <!-- COMPLETE --> as last line of file"
  ["E226"]="result reconciliation failed → Some planned tasks missing result files"
  ["E227"]="planned vs actual mismatch → Check that all tasks in plan have corresponding results"

  # Content validation (E240-E259)
  ["E240"]="file content is empty → File must contain substantive content"
  ["E241"]="line count below threshold → File must meet minimum line count requirement"
  ["E242"]="required section missing → Add required section to document"
  ["E243"]="markdown syntax error → Fix markdown formatting issues"
  ["E244"]="code block syntax error → Fix code block delimiters using triple backticks"
  ["E245"]="link validation failed → Check that all links are valid and accessible"
  ["E246"]="image validation failed → Check that all image paths are valid"

  # Schema validation (E260-E279)
  ["E260"]="plan.md schema validation failed → Check plan.md follows expected schema"
  ["E261"]="task.md schema validation failed → Check task.md follows expected schema"
  ["E262"]="result.md schema validation failed → Check result.md follows expected schema"
  ["E263"]="config.yaml schema validation failed → Check config.yaml follows expected schema"

  # Data validation (E280-E299)
  ["E280"]="JSON parse error → Check JSON syntax"
  ["E281"]="YAML parse error → Check YAML syntax"
  ["E282"]="CSV parse error → Check CSV format and delimiters"
  ["E283"]="data type mismatch → Check that data types match expected schema"
  ["E284"]="value out of bounds → Check that numeric values are within expected range"
  ["E285"]="enum value invalid → Check that value is one of allowed enum values"
  ["E286"]="required field null → Field must have non-null value"
)

# ============================================================================
# CATEGORY 4: System Errors (E300-E399)
# ============================================================================

ERROR_MESSAGES+=(
  # File I/O errors (E300-E319)
  ["E300"]="file not found → Check file path is correct and file exists"
  ["E301"]="file permission denied → Check file permissions with: ls -l <file>"
  ["E302"]="file write failed → Check disk space and permissions"
  ["E303"]="file read failed → Check file exists and is readable"
  ["E304"]="directory creation failed → Check parent directory exists and is writable"
  ["E305"]="directory not found → Check directory path is correct"
  ["E306"]="file already exists - conflict → Remove or rename existing file"
  ["E307"]="file is read-only → Remove read-only flag with: chmod +w <file>"
  ["E308"]="disk space full → Free up disk space and retry"
  ["E309"]="file lock timeout → Wait for lock to be released or remove stale lock file"

  # Git errors (E320-E339)
  ["E320"]="not a git repository → Initialize with: git init"
  ["E321"]="git command failed → Check git status and error message"
  ["E322"]="git merge conflict → Resolve conflicts manually"
  ["E323"]="git push failed → Check remote access and branch status"
  ["E324"]="git pull failed → Check remote access and local changes"
  ["E325"]="git branch not found → Check branch name with: git branch -a"
  ["E326"]="git uncommitted changes → Commit or stash changes before operation"
  ["E327"]="git remote not configured → Add remote with: git remote add origin <url>"

  # MCP errors (E340-E359)
  ["E340"]="MCP connection failed → Check MCP server is running"
  ["E341"]="Memory MCP not connected → Run: claude mcp connect memory"
  ["E342"]="MCP query failed → Check query syntax and MCP server logs"
  ["E343"]="MCP write failed → Check MCP server permissions"
  ["E344"]="MCP timeout → Increase timeout or check network connectivity"
  ["E345"]="MCP authentication failed → Check MCP credentials"
  ["E346"]="MCP node not found → Verify node exists with search query"
  ["E347"]="MCP relation creation failed → Check that both entities exist"

  # External dependency errors (E360-E379)
  ["E360"]="jq not found → Install with: bash scripts/setup.sh or manually install jq"
  ["E361"]="python3 not found → Install Python 3"
  ["E362"]="bash version too old - need 4+ → Upgrade bash or use alternative shell"
  ["E363"]="claude CLI not found → Install Claude CLI"
  ["E364"]="required command not found → Install missing command"
  ["E365"]="library import failed → Install required Python library"
  ["E366"]="API connection failed → Check network and API endpoint"

  # System resource errors (E380-E399)
  ["E380"]="out of memory → Free up memory or increase available RAM"
  ["E381"]="process limit reached → Reduce max_parallel or kill stale processes"
  ["E382"]="timeout exceeded → Increase timeout or optimize operation"
  ["E383"]="network connection failed → Check network connectivity"
  ["E384"]="permission denied → Check user permissions"
  ["E385"]="operation not permitted → Check file/directory permissions or run with appropriate privileges"
  ["E386"]="resource busy → Wait for resource to be available or kill blocking process"
  ["E387"]="system call interrupted → Retry operation"
)

# ============================================================================
# Helper Functions
# ============================================================================

# Print error message with code and context
# Usage: error E001 [additional_context]
error() {
  local code="$1"
  local context="${2:-}"

  if [[ -z "${ERROR_MESSAGES[$code]:-}" ]]; then
    echo "ERROR: Unknown error code: $code" >&2
    return 1
  fi

  local message="${ERROR_MESSAGES[$code]}"

  if [[ -n "$context" ]]; then
    echo "[$code] $message (Context: $context)" >&2
  else
    echo "[$code] $message" >&2
  fi

  return 1
}

# Print error message and exit
# Usage: fatal E001 [additional_context]
fatal() {
  error "$@"
  exit 1
}

# Warn with error code but don't exit
# Usage: warn E023
warn() {
  local code="$1"
  local context="${2:-}"

  if [[ -z "${ERROR_MESSAGES[$code]:-}" ]]; then
    echo "WARNING: Unknown error code: $code" >&2
    return 0
  fi

  local message="${ERROR_MESSAGES[$code]}"

  if [[ -n "$context" ]]; then
    echo "WARNING [$code] $message (Context: $context)" >&2
  else
    echo "WARNING [$code] $message" >&2
  fi

  return 0
}

# Check condition and error if false
# Usage: check_or_error <condition> E001 [context]
# Example: check_or_error "-f config.yaml" E001
check_or_error() {
  local condition="$1"
  local code="$2"
  local context="${3:-}"

  if ! eval "$condition" 2>/dev/null; then
    error "$code" "$context"
    return 1
  fi
  return 0
}

# Check condition and fatal if false
# Usage: check_or_fatal <condition> E001 [context]
check_or_fatal() {
  local condition="$1"
  local code="$2"
  local context="${3:-}"

  if ! eval "$condition" 2>/dev/null; then
    fatal "$code" "$context"
  fi
}

# Get just the error message without formatting
# Usage: get_error_message E001
get_error_message() {
  local code="$1"
  echo "${ERROR_MESSAGES[$code]:-Unknown error code: $code}"
}

# List all error codes in a category
# Usage: list_category_errors 1  (for E001-E099)
list_category_errors() {
  local category="$1"
  local start end

  case "$category" in
    1) start=1; end=99; echo "Configuration Errors (E001-E099):" ;;
    2) start=100; end=199; echo "Execution Errors (E100-E199):" ;;
    3) start=200; end=299; echo "Validation Errors (E200-E299):" ;;
    4) start=300; end=399; echo "System Errors (E300-E399):" ;;
    *) echo "Invalid category (expected 1-4)" >&2; return 1 ;;
  esac

  for i in $(seq "$start" "$end"); do
    local code=$(printf "E%03d" "$i")
    if [[ -n "${ERROR_MESSAGES[$code]:-}" ]]; then
      echo "  $code: ${ERROR_MESSAGES[$code]}"
    fi
  done
}

# List all defined error codes
# Usage: list_all_errors
list_all_errors() {
  echo "=== claude-crew Error Codes ==="
  echo
  for category in 1 2 3 4; do
    list_category_errors "$category"
    echo
  done
}

# Export functions for use in other scripts
export -f error fatal warn check_or_error check_or_fatal get_error_message list_category_errors list_all_errors
