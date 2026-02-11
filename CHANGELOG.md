# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).
This project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.8.0] - 2026-02-11

### Changed
- **CLAUDE.md split** (INT-001) — moved detailed processing flows, execution log specs, and parent session rules to `docs/parent_guide.md`; CLAUDE.md reduced from 539 lines to ~70 lines for sub-agent context optimization
- **Phase 2 validation consolidation** (INT-002) — replaced 4 individual Bash calls (tail, wc, grep×2) per task with single `scripts/validate_result.sh` call; 75% reduction in tool invocations
- **Approval flow consolidation** (EXT-002) — merged Phase 3 Memory MCP approval and Phase 4 proposals into single post-Phase 4 batch review; reduced human interaction from 4 rounds to 1
- **Template common rules extraction** (INT-004) — created `templates/worker_common.md` with shared Output Format, Memory MCP candidate rules, and common Rules; eliminated ~188 lines of duplication across 5 worker templates

### Added
- **`scripts/validate_result.sh`** (INT-002) — unified result validation script outputting JSON with complete_marker, line_count, section checks, and pass/fail status
- **`docs/parent_guide.md`** (INT-001) — detailed parent session guide (processing flow, execution log, checkpoint restart, phase skip rules)
- **`templates/worker_common.md`** (INT-004) — shared rules and output format for all worker personas
- **Phase 2 progress messages** (EXT-001) — Wave start/completion messages displayed to user during execution

## [0.7.5] - 2026-02-11

### Fixed
- **decomposer.md Memory MCP naming contradiction** (INT-003) — removed `claude-crew:{type}:{identifier}` naming convention that conflicted with CLAUDE.md instant-reject filter; unified to `{domain}:{category}:{identifier}`

### Changed
- **worker_default.md deprecation** (INT-005) — added DEPRECATED warning banner; marked as deprecated in CLAUDE.md template reference table

## [0.7.4] - 2026-02-10

### Changed
- **Permission system: 3-tier control** — introduced `ask` tier in `.claude/settings.json` for deny > ask > allow evaluation order
  - `git *` in allow — single pattern covers all git subcommands including `-C`, `--no-pager` flag combinations
  - `git*push*` in ask — git push (including force push) requires user confirmation instead of hard deny
  - Git destructive ops (`reset --hard`, `clean -f`, `checkout .`, `restore .`) moved from deny to ask — recoverable via reflog, user decides
  - `curl POST/PUT/PATCH` moved from deny to ask — enables API testing with user confirmation
  - `curl DELETE` remains in deny — irreversible external data loss
  - `* | sh`, `* | bash` generalized from curl/wget-specific patterns — covers all pipe-to-shell regardless of download tool
  - Removed redundant patterns (`git add *`, `git commit *` covered by `git *`)
  - Removed false-positive-prone `*git*` prefix in deny, changed to `git*` prefix (prevents `grep "git push" log` from being blocked)
- **CLAUDE.md permission policy table** — updated to reflect 3-tier control with ask tier documentation

## [0.7.3] - 2026-02-10

### Added
- **`/refine-iteratively` Claude Skill** (`.claude/skills/refine-iteratively/`) — user-invocable iterative quality refinement workflow; executes any task through multiple rounds of validation and improvement until acceptance criteria are met
  - `SKILL.md` — skill definition (invocation, arguments, workflow, validation rules, examples)
  - `refine_defaults.yaml` — default configuration (thresholds, validation rules, round settings)
  - `scripts/extract_metadata.py` — YAML frontmatter extraction from result files
  - `scripts/validate_round.py` — round quality/completeness threshold validation
  - `scripts/generate_feedback.py` — structured improvement feedback generation
  - `scripts/consolidate_report.py` — multi-round final report consolidation
- **Skill scripts permission** in `.claude/settings.json` — added `Bash(python3 .claude/skills/*/scripts/*)` to allow list

## [0.7.2] - 2026-02-08

### Fixed
- **CLAUDE.md Memory MCP self-contradiction** (A-1) — "親はメモリに触れない" conflicted with Phase 3 Step 4 parent calling `mcp__memory__create_entities`; changed to delegate Memory MCP writes to sub-agents
- **CLAUDE.md Phase skip vs Phase 4 incompatibility** (A-2) — Phase 3 skip produced no `report_summary.md`, breaking Phase 4 mode determination; added parent-generated minimal `report_summary.md` when Phase 3 is skipped
- **CLAUDE.md checkpoint restart missing `retrying` status** (A-3) — added `retrying` to the list of statuses that trigger Wave re-execution
- **CLAUDE.md `partial` status undefined** (A-4) — added `partial` to execution_log.yaml Status definitions
- **CLAUDE.md Phase 4 Memory MCP candidates unprocessed** (A-5) — added processing step for retrospector Memory MCP candidates (symmetric with Phase 3 Step 4)
- **CLAUDE.md version metadata list incomplete** (A-6) — added `report_summary.md` to バージョン管理 target list
- **CLAUDE.md `plan_retry.md` missing from directory structure** (A-7) — added to ディレクトリ構造
- **CLAUDE.md execution_log.yaml example incomplete** (A-8) — added aggregator and retrospector entries
- **CLAUDE.md Persona list missing `writer`** (A-9) — added `writer` to パス受け渡し許可 Persona example
- **README.md Work Directory section missing files** (A-10) — added `report_summary.md` and `retrospective.md` to the second directory tree
- **README.md / README_ja.md pipeline descriptions omit Phase 4** (B-1) — updated Features, Constraints text, and sequence diagrams to include retrospect phase
- **CLAUDE.md policy table vs settings.json mismatch** (B-2) — expanded 操作別ポリシー table to reflect actual allow/deny lists (added Bash utilities, git write, curl deny detail)
- **CLAUDE.md config.yaml format example version stale** (B-3) — updated from `"0.7.0"` to `"0.7.2"`
- **decomposer.md Wave/Phase terminology collision** (B-4) — changed Execution Order from "Phase 1/Phase 2" to "Wave 1/Wave 2" to avoid confusion with macro-level Phase 2
- **README.md / README_ja.md template table ordering** (B-5) — aligned row order to match CLAUDE.md (researcher → writer → coder → reviewer)
- **decomposer.md missing completion marker** (C-1) — added `<!-- COMPLETE -->` instruction to decomposer.md
- **worker_writer.md missing ⚠️ emoji** (C-2) — added `⚠️` to Output Format mandatory notice
- **retrospector.md Memory MCP heading inconsistency** (C-3) — changed `## Memory MCP Candidates` to `## Memory MCP追加候補` to match worker templates

## [0.7.1] - 2026-02-08

### Fixed
- **CLAUDE.md version metadata format** — fixed blockquote format (`> Generated by...`) to match actual YAML frontmatter format used in templates (unified in v0.5.0 but CLAUDE.md was not updated)
- **CLAUDE.md Phase 3 self-contradiction** — step 3 said "don't read report.md" but step 4 required reading its Memory MCP section; clarified as an explicit exception with updated path-passing principle
- **CLAUDE.md config.yaml required format** — updated example version from `"0.5.0"` to `"0.7.0"` and added missing `retrospect` section
- **CLAUDE.md architecture diagram** — added Phase 4 (retrospector) to the diagram, matching the 4-phase flow described in the document
- **CLAUDE.md phase count** — changed "3フェーズ" to "4フェーズ" in processing flow introduction
- **CLAUDE.md template reference table** — added missing `multi_analysis.md` entry
- **decomposer.md Recommended Persona** — removed banned `worker_default` and added missing `worker_writer` in task_N.md template example
- **settings.json allow list** — added `Bash(tail *)` and `Bash(grep *)` required by Phase 2 validation (completion marker check and structural quality validation)
- **README.md / README_ja.md** — added Phase 4 (Retrospect) to How It Works, added `retrospector.md` and `multi_analysis.md` to templates, added `report_summary.md` and `retrospective.md` to directory structures

### Added
- **CLAUDE.md path-passing principle** — added `report.md` Memory MCP section as explicitly allowed metadata read

## [0.7.0] - 2026-02-08

### Added
- **Completion marker** (`<!-- COMPLETE -->`) in all worker/aggregator/retrospector templates — enables parent to detect partial file writes (1.1)
- **Structural quality validation** in CLAUDE.md Phase 2 — line count check (≥20), Sources section check (researcher), code block check (coder) without reading file content (1.2)
- **worker_writer template** (`templates/worker_writer.md`) — specialized persona for documentation and content creation tasks (2.1)
- **Report summary** (`report_summary.md`, ≤50 lines) — aggregator generates a compact summary for the parent session, keeping detailed report in report.md (3.1b)
- **retrospector template** (`templates/retrospector.md`) — Phase 4 post-mortem and success analysis agent
- **multi_analysis template** (`templates/multi_analysis.md`) — N-viewpoint parallel analysis framework referenced by decomposer
- **Phase 4 (Retrospect)** — post-mortem analysis phase in CLAUDE.md with full/light mode, scoring system, and proposal filtering
- **config.yaml retrospect section** — Phase 4 configuration (enabled, filter_threshold, model, proposal limits)
- **Decomposer self-check items 9-10** — Persona selection validation and Model cost-optimality check (expanded from 8 to 10 items)

### Changed
- **Template externalization** — parent passes TEMPLATE_PATH instead of reading template content into prompt; sub-agents read their own templates (3.1a)
- **Execution log YAML migration** — `execution_log.md` (Markdown table) replaced by `execution_log.yaml` (structured YAML) with real-time update protocol (4.2)
- **Decomposer persona selection** — added `worker_writer` to keyword table, output type table, decision flowchart, and self-check; moved writing-related keywords from researcher to writer (2.1)
- **Phase 2 validation flow** — completion marker check (Step 4b.1) added before metadata check; structural quality check (Step 4d) added after metadata validation (1.1, 1.2)

## [0.6.0] - 2026-02-07

### Changed
- Consolidate "path passthrough" principle references to single canonical definition in CLAUDE.md (C-03, ~9 lines reduced)
- Consolidate retry mechanism references to single canonical definition in CLAUDE.md (C-04, ~4 lines reduced)
- Standardize parallel count expression to "Up to 10" in README.md (R-04)
- Translate config.yaml comments from Japanese to English
- Translate MCP search query placeholders from Japanese to English in all worker templates
- Translate YAML inline comments from Japanese to English in all templates
- Fix MCP search query inconsistency in worker_reviewer.md

### Added
- README_ja.md: Complete Japanese translation of README.md
- Cross-language links between README.md and README_ja.md

## [0.5.0] - 2026-02-07

### Fixed
- Fix wildcard position in settings.json deny pattern for `rm -rf` (H01)
- Remove `Bash(cat *)` from settings.json allow list (M03)
- Unify version metadata into YAML frontmatter in aggregator.md and decomposer.md (H02)

### Added
- Add `curl -X PUT/DELETE/PATCH` to settings.json deny list (A9)
- Add TASKS_DIR parameter documentation to Phase 1 in CLAUDE.md (H06)
- Add timeout processing flow to Phase 2 in CLAUDE.md (H07)
- Add execution_log.md, config.yaml, CHANGELOG.md, scripts/ to README.md directory structure (H04, H05)
- Add config.yaml to README.md file purpose table (H10)
- Make config.yaml mandatory with error message on missing (H03)

### Changed
- Standardize "subagent" to "sub-agent" across all templates (M07)

## [0.4.0] - 2026-02-07

### Added
- **Input validation guidance** in all templates — defined behavior for missing, empty, or malformed input files (S1: issue H7)
- **Language policy** in README.md — documented that CLAUDE.md is in Japanese (agent instructions) and README.md is in English (user-facing) (S3: issue M5)
- **Checkpoint restart mechanism** — resume interrupted executions from execution_log.md status, skipping already-completed tasks (M1: issue C1)
- **Worker timeout control** via `config.yaml: worker_max_turns` — maps to Task tool's `max_turns` parameter for sub-agent turn limits (M2: issue C2)
- **Feedback loop for re-decomposition** — when partial/failure results exceed 50%, trigger one-time re-decomposition via decomposer (M3: issue M7)

### Changed
- **config.yaml** version: 0.3.0 → 0.4.0

### Not Implemented (by design)
- Decomposer plan.md Status format unification to YAML front matter (S2: issue M9) — current `**Status**: success` format functions well in practice; change deferred

## [0.3.0] - 2026-02-07

### Added
- **YAML front matter metadata** in all worker templates — structured header with `status`, `quality`, `completeness`, `errors`, `task_id` fields for machine-readable result inspection
- **Mandatory RESULT_PATH writing** with file existence verification step in all worker templates
- **Self-check checklist** in decomposer.md — 8-item validation (circular deps, integration task prohibition, Output column, RESULT_PATH pattern, Status line, independence, model fit, task count) with PASS/CORRECTED reporting
- **Quality Review system** in aggregator.md — cross-checks results for consistency, evidence, and task compliance; assigns GREEN/YELLOW/RED quality level
- **Memory MCP integration** — workers search for related knowledge before task execution (`mcp__memory__search_nodes`); workers report knowledge candidates in result files; aggregator collects and groups candidates for human review
- **Structured metadata header protocol** — parent session reads only first 20 lines of result files (metadata only), preserving the path-passing principle while enabling observability
- **Execution log format** (`execution_log.md`) — standardized table with timestamps, duration, status tracking per sub-agent
- **Result file retry and validation** — parent verifies result existence after each Wave, retries up to `max_retries` times with status-aware checking (success/partial/failure)

### Changed
- **CLAUDE.md** major restructuring — added metadata header support, execution log standards, Memory MCP protocol, result validation procedures
- **.claude/settings.json** — updated permission rules
- **scripts/new_cmd.sh** — improved reliability

## [0.2.0] - 2026-02-06

### Added
- **Wave-based execution** for dependent tasks — tasks grouped by dependency depth (Wave 1: no deps, Wave 2: depends on Wave 1, etc.), replacing implicit sequential execution
- **Model selection guidelines** in decomposer.md — per-task model recommendation (haiku for simple, sonnet for standard, opus for complex) with cost-awareness
- **Phase skip decision table** in CLAUDE.md — criteria for when to skip decompose/aggregate phases based on subtask count and dependency presence
- **Path passing principle boundaries** — explicit documentation of what metadata the parent may read vs. what content it must not read
- **Output column** required in plan.md Tasks table — each task must specify its result file path

### Changed
- **decomposer.md** — prohibited integration/summary task generation (aggregator handles synthesis); enforced `result_N.md` naming pattern for all RESULT_PATHs
- **aggregator.md** — added execution verification steps for result file completeness
- **CLAUDE.md** — added artifact vs result file distinction (workers write both when task produces deliverables); documented config.yaml reference protocol
- **config.yaml** — externalized configuration values (default_model, max_parallel, max_retries, background_threshold)

### Fixed
- Dependency task success rate improved from 33% to 100% after Wave-based execution and template hardening

## [0.1.0] - 2026-02-05

### Added
- **Core 2-layer flat architecture** — parent session coordinates up to 10 parallel sub-agents via Task tool; no sub-agent nesting
- **3-phase pipeline** — Decompose → Execute → Aggregate, with file-based communication throughout
- **6 prompt templates** — decomposer.md, worker_default.md, worker_researcher.md, worker_coder.md, worker_reviewer.md, aggregator.md
- **CLAUDE.md** — framework instructions for Claude Code, defining the multi-agent coordinator behavior
- **README.md** — user documentation with architecture diagrams, Quick Start, and directory structure guide
- **config.yaml** — basic configuration (default_model, max_parallel)
- **scripts/new_cmd.sh** — atomic cmd directory creation with mkdir retry (up to 5 attempts with random backoff)
- **.claude/settings.json** — permission control with allow/deny lists for safe sub-agent operation
- **work/ directory** — self-contained working directory; each request creates `cmd_NNN/` with request.md, plan.md, tasks/, results/, report.md
- **File-based communication** — sub-agents read/write files; parent passes paths only, keeping context window lean
- **Persona switching** — workers adopt specialized roles (researcher, coder, reviewer, default)
- **Model flexibility** — assign haiku/sonnet/opus per sub-agent for cost optimization
