---
name: refine-iteratively
description: "Execute any task through multiple rounds of execution and validation, improving quality progressively until acceptance criteria are met."
user-invocable: true
---

# Claude Skill: refine-iteratively

## Overview

Execute any task through multiple rounds of execution and validation, improving quality progressively until acceptance criteria are met or maximum rounds are reached. This skill implements the iterative refinement pattern proven effective in multi-agent systems and applies it universally to code, documentation, data analysis, testing, and design tasks.

## Invocation

```bash
/refine-iteratively [task_description] [options]
```

## Arguments

- `task_description` (required, string): What to accomplish
  - Example: "Implement secure authentication module"
  - Example: "Analyze Q4 sales trends for regional breakdown"

- `--max-rounds=N` (optional, integer, default: 4)
  - Maximum number of refinement rounds (1-10)

- `--quality-threshold=LEVEL` (optional, enum, default: GREEN)
  - Minimum acceptable quality: RED, YELLOW, or GREEN

- `--completeness-threshold=N` (optional, integer 0-100, default: 90)
  - Minimum acceptable completeness percentage

- `--output-dir=PATH` (optional, string, default: ./refine_output/)
  - Directory for storing results and logs

- `--config=FILE` (optional, string)
  - Path to custom validation configuration (YAML)

- `--task-file=PATH` (optional, string)
  - Read task from file instead of command line (for complex tasks)
  - Format: Plain text or markdown file containing task description
  - Example: `task.md` containing detailed requirements, acceptance criteria, and context

## Examples

### Example 1: Basic Security Code Review
```bash
/refine-iteratively "Review authentication.py for OWASP Top 10 vulnerabilities"
```
Executes security audit with defaults (max 4 rounds, GREEN quality required, 90% completeness).

### Example 2: Documentation with Custom Thresholds
```bash
/refine-iteratively "Generate OpenAPI specification for user service" \
  --quality-threshold=YELLOW \
  --completeness-threshold=80 \
  --max-rounds=4
```
Accepts YELLOW quality and 80% completeness (faster iteration for documentation).

### Example 3: Complex Analysis with Custom Config
```bash
/refine-iteratively \
  --task-file=customer_analysis_task.md \
  --config=analysis_standards.yaml \
  --output-dir=./analysis_results/
```
Reads task from file, applies custom validation rules, outputs to specified directory.

## How It Works

### Workflow Overview

1. **Initialize**: Create output directory, load configuration, set up logging
2. **Execute Round N**:
   - Execute task using full Claude capabilities
   - Write result with YAML metadata (status, quality, completeness, errors, warnings)
   - Record execution time and resource usage
3. **Validate Round N**:
   - Check YAML metadata against thresholds
   - Verify structural quality (line count, required sections)
   - Compare quality/completeness against targets
4. **Decision Gate**:
   - **Pass**: Mark as complete, generate final report
   - **Fail + Rounds Remaining**: Generate improvement feedback, proceed to Round N+1
   - **Fail + No Rounds**: Mark as partial success, generate report with warnings
5. **Final Report**: Consolidate all rounds, show quality progression, return best result

### Implementation for Claude Code

When user invokes `/refine-iteratively [task] [options]`:

1. **Parse arguments and initialize**:
   - Extract task description (required)
   - Parse optional arguments (--max-rounds, --quality-threshold, --completeness-threshold, --output-dir, --config, --task-file)
   - Load configuration (merge user config with `.claude/skills/refine-iteratively/refine_defaults.yaml`)
   - Create output directory with timestamp: `{output-dir}/refine_{timestamp}/`
   - Copy task description to `task.md` in output directory
   - Initialize `execution_log.yaml` with task metadata

2. **Execute rounds (loop from 1 to max_rounds)**:
   - For round N:
     a. **Execute task**: Use all available tools (Read, Edit, Write, Bash, Grep, Glob, WebSearch, etc.) to complete the task
     b. **Write result**: Create `result_N.md` with YAML frontmatter containing required fields (status, quality, completeness, errors, warnings)
     c. **Extract metadata**: Call `python3 .claude/skills/refine-iteratively/scripts/extract_metadata.py --file result_N.md` to get metadata JSON
     d. **Validate result**: Call `python3 .claude/skills/refine-iteratively/scripts/validate_round.py --metadata-json metadata.json --quality-threshold X --completeness-threshold Y`
     e. **Check validation**:
        - If validation **passed**: Break loop (success)
        - If validation **failed** and rounds remain:
          - Call `python3 .claude/skills/refine-iteratively/scripts/generate_feedback.py --result-file result_N.md --metadata-json metadata.json --output feedback_N.md --round-number N+1`
          - Update execution_log.yaml with round N metadata
          - Proceed to round N+1 with feedback
        - If validation **failed** and no rounds remain:
          - Mark as partial success, update execution_log.yaml
          - Break loop

3. **Generate final report**:
   - Call `python3 .claude/skills/refine-iteratively/scripts/consolidate_report.py --results-dir {output-dir}/refine_{timestamp}/ --output refinement_report.md`
   - Update execution_log.yaml with final status and timestamp
   - Present refinement_report.md to user

4. **Return results**:
   - Report final status, quality, and completeness to user
   - Provide path to output directory for user review

### Result Format (result_N.md)

Each round must produce a result file with this structure:

```markdown
---
status: success | partial | failure
quality: GREEN | YELLOW | RED
completeness: 0-100
errors: []
warnings: []
task_name: "Task description"
round: 1
duration_sec: 120
---

# Result: [Task Name]

[Task-specific content and results]

<!-- COMPLETE -->
```

**Required YAML fields:**
- `status`: Execution outcome (success/partial/failure)
- `quality`: Self-assessed quality level (GREEN/YELLOW/RED)
- `completeness`: Estimated percentage complete (0-100)
- `errors`: List of errors encountered (empty list if none)

**Optional YAML fields:**
- `warnings`: List of non-fatal issues
- `task_name`: Echoed from input for audit trail
- `round`: Round number (auto-populated by skill)
- `duration_sec`: Execution time in seconds

### Validation Rules (Built-In)

**All tasks:**
- Minimum 20 lines of output (prevents trivial results)
- Completion marker present: `<!-- COMPLETE -->`
- Required YAML metadata fields must be present and valid

**Code-related tasks** (auto-detected via keywords: "code", "implement", "fix"):
- Must contain code blocks (``` fences)
- Recommendation: Include test cases

**Research-related tasks** (auto-detected via keywords: "research", "analyze", "survey"):
- Must contain `## Sources` section
- Recommendation: Include methodology section

**Review-related tasks** (auto-detected via keywords: "review", "audit", "check"):
- Must contain `## Findings` section
- Recommendation: Include severity ratings

**Custom validation**: Override via `refine_config.yaml`

### Configuration (refine_defaults.yaml)

```yaml
# Default configuration for /refine-iteratively skill

version: "1.0"

# Core settings
max_rounds: 4
quality_threshold: GREEN  # Minimum quality level required
completeness_threshold: 90  # Minimum completeness percentage required

# Validation rules
validation:
  min_lines: 20
  require_completion_marker: true
  auto_detect_task_type: true
  required_sections:
    code:
      - "```"
    research:
      - "## Sources"
    review:
      - "## Findings"

# Round execution
round_settings:
  timeout_per_round_sec: 300
  model: opus  # claude-opus-4.6 (can be overridden)
  max_turns: 30

# Output
output:
  timestamp_format: "%Y-%m-%d_%H:%M:%S"
  include_execution_log: true
  generate_json_output: false  # Can be enabled for CI/CD pipelines
```

### Execution Log (execution_log.yaml)

Created automatically by the skill; shows round-by-round progress:

```yaml
task: "Implement authentication module"
invocation_time: "2026-02-09 10:00:00"
completed_time: null
total_duration_sec: null
final_status: null
final_quality: null
final_completeness: null

rounds:
  - id: 1
    started: "2026-02-09 10:00:00"
    finished: "2026-02-09 10:03:00"
    duration_sec: 180
    status: partial
    quality: YELLOW
    completeness: 75
    validation_passed: false
    validation_issues:
      - "Missing input validation (caught by structural check)"
      - "Password hashing incomplete (from error field)"
    error_count: 2
    warning_count: 1

  - id: 2
    started: "2026-02-09 10:04:00"
    finished: "2026-02-09 10:08:00"
    duration_sec: 240
    status: success
    quality: GREEN
    completeness: 95
    validation_passed: true
    validation_issues: []
    error_count: 0
    warning_count: 0

config_used:
  max_rounds: 4
  quality_threshold: GREEN
  completeness_threshold: 90
  custom_config: false
```

### Helper Scripts

**extract_metadata.py**: Parses YAML front matter from result files
- Input: filepath to result_N.md
- Output: dict with status, quality, completeness, errors, warnings
- Handles: Missing fields, malformed YAML, encoding issues

**validate_round.py**: Checks result against thresholds and structural rules
- Input: metadata dict, config dict, filepath
- Output: tuple (passed: bool, issues: list[str])
- Checks: Quality threshold, completeness threshold, status, line count, required sections, completion marker

**generate_feedback.py**: Creates structured improvement plan for next round
- Input: metadata dict, validation issues list
- Output: markdown text for feedback_N.md
- Generates: Identified issues, gaps, recommended improvements

**consolidate_report.py**: Creates final refinement_report.md
- Input: execution_log.yaml, all result_N.md files
- Output: markdown report
- Includes: Summary, round-by-round progression table, quality delta, recommendations

## File Output Structure

```
{output-dir}/refine_{timestamp}/
├── task.md                    # Original task description (copied from input)
├── execution_log.yaml         # Round-by-round metadata
├── config_used.yaml           # Configuration actually used (defaults merged with user config)
├── result_1.md                # First round output
├── feedback_1.md              # Validation feedback (if round failed)
├── result_2.md                # Second round output (if needed)
├── feedback_2.md              # (if needed)
├── result_N.md                # Final round output
└── refinement_report.md       # Consolidated final report

# If --output-format=json is enabled:
├── execution_log.json
├── refinement_report.json
└── result_N.json
```

## Integration Examples

### Use Case 1: Security Code Review (Non-claude-crew Project)

```bash
# In a Django project:
/refine-iteratively "Audit settings.py and middleware.py for security configuration issues" \
  --quality-threshold=GREEN \
  --completeness-threshold=95 \
  --output-dir=./security_audit/
```

**Expected Flow:**
- Round 1: Identify 5 configuration issues (YELLOW quality, 70% complete)
- Round 2: Verify fixes, document compliance (GREEN quality, 95% complete)
- Output: `refinement_report.md` shows progression, lists issues found and addressed

### Use Case 2: API Documentation (Non-claude-crew Project)

```bash
# In a FastAPI project:
/refine-iteratively "Generate comprehensive OpenAPI documentation for payment service" \
  --quality-threshold=YELLOW \
  --completeness-threshold=80 \
  --max-rounds=4 \
  --config=doc_standards.yaml
```

**Custom Config (doc_standards.yaml):**
```yaml
validation:
  required_sections:
    - "## Endpoints"
    - "## Data Models"
    - "## Error Codes"
    - "## Rate Limiting"
  min_lines: 150
```

**Expected Flow:**
- Round 1: Draft basic endpoints (YELLOW, 60% complete)
- Round 2: Add data models and error codes (YELLOW, 80% complete)
- Output: Accepted at YELLOW (meets threshold), documentation ready for publication

### Use Case 3: Data Analysis (Non-claude-crew Project)

```bash
# In a data science project:
/refine-iteratively "Analyze customer churn patterns and identify top 5 drivers" \
  --quality-threshold=YELLOW \
  --completeness-threshold=85 \
  --config=analysis_config.yaml
```

**Expected Flow:**
- Round 1: Initial analysis without statistical significance (RED quality)
- Round 2: Add statistical tests (YELLOW quality, 85% complete)
- Output: Accepted at YELLOW, analysis ready for stakeholder presentation

## Quality Criteria

### Acceptance Decision

A result is accepted when **ALL** of the following are true:

```
status == "success" AND
quality >= quality_threshold AND
completeness >= completeness_threshold AND
line_count >= 20 AND
completion_marker_present == true
```

### Quality Level Definitions

- **GREEN**: High quality, complete, all validation checks passed, ready for production/delivery
- **YELLOW**: Acceptable quality, minor issues or gaps, suitable for most uses but may need final review
- **RED**: Low quality, significant issues, not acceptable for delivery without major revision

### Completeness Percentage

- 0-50%: Incomplete work, major sections missing
- 51-79%: Substantial progress, some gaps remain
- 80-99%: Nearly complete, minor sections or edge cases missing
- 100%: Fully complete, all expected sections and edge cases addressed

## Comparison to claude-crew Feedback Loop

The skill extracts and generalizes claude-crew's Phase 2 feedback loop for universal use:

| Dimension | claude-crew Phase 2 | /refine-iteratively Skill |
|-----------|---------------------|---------------------------|
| Invocation | Automatic (parent session) | User-invocable (`/refine-iteratively`) |
| Scope | Internal task retries | Any external task or project |
| Personas | Fixed (worker_coder, etc.) | Flexible (Claude chooses or specified) |
| Max rounds | 2 (config: max_retries) | Configurable (1-10, default 4) |
| Feedback | Metadata validation only | Explicit improvement plan |
| Output location | work/cmd_NNN/results/ | User-specified output directory |
| Generalizability | claude-crew only | Universal (code, docs, data, design) |

## Troubleshooting

### Common Issues

**Issue: "Validation failed: quality below threshold"**
- Solution: Check feedback_N.md for specific improvement suggestions
- Increase `--max-rounds` to allow more refinement iterations
- Lower `--quality-threshold` if acceptable for your use case

**Issue: "Max rounds reached without passing validation"**
- Solution: Review execution_log.yaml to identify recurring issues
- Adjust validation config if requirements are too strict
- Check if task is too complex for current round budget

**Issue: "Missing required section"**
- Solution: Modify task description to explicitly request missing sections
- Override validation config with `--config` to adjust required sections

**Issue: "Completion marker missing"**
- Solution: Internal error - file write interrupted or incomplete
- Check result_N.md for partial content
- Re-run skill (will restart from last successful round if execution_log exists)

### Performance Tips

- **Documentation tasks**: Use `--quality-threshold=YELLOW --completeness-threshold=80` for faster turnaround
- **Security audits**: Use `--quality-threshold=GREEN --completeness-threshold=95` for thorough coverage
- **Exploratory analysis**: Start with `--max-rounds=2` to get quick insights, then increase if needed

### Debugging

Enable verbose logging by setting environment variable:
```bash
export REFINE_DEBUG=1
/refine-iteratively "task description"
```

Check execution_log.yaml for round-by-round diagnostics:
- Validation issues per round
- Time spent per round
- Error counts and warnings
