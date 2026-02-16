# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).
This project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- **Secretary Pattern deprecated** — Disabled by default (`secretary.enabled: false`) based on 8-round investigation (cmd_119-126, cmd_113); deprecation notices added to config.yaml, parent_guide.md, secretary.md, CLAUDE.md; path-passing rationale updated from capacity conservation to attention quality preservation; dormant fields preserved for measurement-triggered reactivation
- **parent_guide.md flow control restructure** — Promoted Secretary Delegation pattern from Phase 2 subsection to top-level `### 共通パターン` section; extracted LP operational details (260+ lines) to dedicated `## LP System Operations` section; unified heading levels across Phases; added Secretary to overview.md architecture diagram and CLAUDE.md Template Reference

### Added
- **Secretary Pattern v2** — Parent reduced to single-gate router (`secretary.enabled == true` delegates all phases); secretary gains Autonomous Assessment (self-determines skip/execute per operation); 3-value response protocol (success/skip/failure); `config.yaml` simplified from 12→6 lines (removed `delegate_phases`, `min_tasks_for_delegation`); `docs/parent_guide.md` compressed from 3 individual delegation sections (~175 lines) to unified pattern (~58 lines, 67% reduction)

### Added
- **`/next-round` skill** (`.claude/skills/next-round/SKILL.md`) — Inter-round navigation: reads completed report.md, detects continuation signals via LLM judgment, presents strategy options (review/mutation/deepen/synthesize + creative freeform), generates next-round request.md with natural Layer 1 keyword embedding; zero scripts, zero config (cmd_101, cmd_103)
- **Aggregator Open Questions / Unexplored Dimensions** — Two new output sections in `templates/aggregator.md` with category-tagged bullet format (`[Category] Description`); enables signal detection for `/next-round`; gap identification via 5 LLM-based heuristics (cmd_101, cmd_103)

### Removed
- **`/refine-iteratively` skill** — Deleted `.claude/skills/refine-iteratively/` (7 files, 1,830 lines); replaced by `/next-round` + aggregator enhancement (cmd_101, cmd_103)

### Added
- **Mutation mechanism plan** — `docs/mutation_plan.md` documenting 4-layer hybrid architecture (Layer 0–2B), implementation roadmap (6 phases, 10-11 weeks), decision framework, known risks, and design references from cmd_079–088 (10-round iterative design)
- **Worker self-validation checklists** — Added completion checklists to `worker_common.md` (6-item common checklist), `worker_coder.md` (4-item implementation checklist), `worker_researcher.md` (3-item research quality checklist); lightweight alternative to full SDD, derived from cmd_091 18-task exploration verdict (cmd_098)
- **Decomposer inline success criteria** — Added `## Inline Success Criteria Guidelines` to `decomposer.md` (+82 lines); instructs decomposers to include EARS-format acceptance criteria for coder tasks and research question lists for researcher tasks; covers simple/complex/research task types with templates and examples (cmd_098)
- **SDD exploration reference doc** — Created `docs/sdd_exploration.md` documenting cmd_091 findings: R1 design (760-line SDD rejected), R2 validation (verdict C: adopt alternatives), 4 SDD reconsideration conditions, reusable insights (EARS notation, END placement, complexity scoring) (cmd_098)

### Changed
- **Permission hook migrated to plugin** — Replaced inline `.claude/hooks/permission-fallback` with `permission-guard` plugin dependency (`skaji18-plugins` marketplace); `.claude/settings.json` now uses `enabledPlugins` instead of `hooks` section; project config moved to `.claude/permission-config.yaml` (Layer 2); deleted 4 inline hook files and test script; updated all references across scripts (setup.sh, health_check.sh, error_codes.sh, merge_config.py) and docs (parent_guide.md, README.md, README_ja.md, roadmap.md) (cmd_093, cmd_095)
- **Permission hook dual-mode support** — `permission-fallback` now supports both Plugin mode (`$CLAUDE_PLUGIN_ROOT`) and inline mode (`__file__` relative); `_detect_project_dir()` with 3-priority detection chain (`CLAUDE_PROJECT_DIR` → `__file__` → `cwd`); `load_config()` upgraded to 4-layer merge (Hardcoded → Plugin/Inline base → Project `.claude/permission-config.yaml` → Local overlay); all security floors and frozen keys preserved (cmd_092)
- **Roadmap v6→v7.3 redesign** — Migrated from phase-based (Phase 1-3) to state-based structure (Shipped/Backlog/Conditional); recognized 10 completed items as Shipped; reduced backlog from 25 to 19 items (58.5-63.5h); added Roadmap Maintenance process, Skills Catalog, Breaking Changes sections; effort estimates calibrated via 5-round iterative review with feasibility verification (cmd_090)
- **Background execution removed** — Deprecated `run_in_background: true` across all docs (`CLAUDE.md`, `parent_guide.md`, `README.md`, `README_ja.md`) and removed `background_threshold` from `config.yaml`; foreground parallel is now the only execution mode; added polling prohibition rule (cmd_089)

### Removed
- **Inline permission hook files** — Removed `.claude/hooks/permission-fallback`, `.claude/hooks/permission-config.yaml`, `.claude/hooks/test-permission-fallback.sh`, `.claude/hooks/test-hooks-support.sh`, `scripts/test_permission_hook.sh` (replaced by `permission-guard` plugin)

### Added
- **Layer 0 Self-Challenge mutation** — Always-on adversarial self-review injected via `phase_instructions.execute`; all workers must list failure scenarios, complex tasks require assumption reversal, alternative paradigm, pre-mortem, and evidence audit; anti-sycophancy validation enforced (cmd_079–088, 10-round mutation design)
- **doc_impact workflow integration** — LLM-driven documentation impact detection across 3 templates: decomposer Self-Check item (plan-time doc impact awareness), worker_common `doc_impact` output field (worker-reported impacts), aggregator Step 8 (doc_impact aggregation into report); zero-maintenance design with no hardcoded rules or file registries (cmd_078)
- **LP system independence** — LP signal detection now works independently of crew phases: `docs/lp_rules.md` (40-line normative rules source of truth), `templates/lp_flush.md` (lightweight LP processing when Phase 4 skipped), `.claude/skills/lp-check/SKILL.md` (standalone `/lp-check` skill for non-crew sessions); inline rule duplication eliminated from retrospector/worker_common/parent_guide via references (cmd_077)
- **`/commit` Claude Skill** (`.claude/skills/commit/SKILL.md`) — Analyzes git diff, generates Conventional Commits message and Keep a Changelog entry, then commits in one step; supports `--dry-run` and `--no-changelog` options (cmd_075)
- **Pre-Action Gate** (`docs/parent_guide.md`) — Mandatory 3-question gate (exception check, input source validation, Edit/Write prohibition) before file operations to prevent crew workflow bypass (cmd_075)
- **Plan mode workflow warning** (`CLAUDE.md`, `docs/parent_guide.md`) — Clarifies that plan mode output is not a workflow exception; added to "よくある間違い" section with root cause documentation (cmd_075)

## [1.0] - 2026-02-14

### Added
- **LICENSE file (MIT)** — MIT License with "AS IS" warranty disclaimer for legal compliance and liability protection (cmd_072)
- **README disclaimer** — Added prominent "as is" disclaimer section before Quick Start; clarifies no active support is provided (cmd_072)
- **Error code system (E001-E399)** — `scripts/error_codes.sh` with 150 standardized error codes across 4 categories (Configuration E001-E099, Execution E100-E199, Validation E200-E299, System E300-E399); includes 7 helper functions (error, fatal, warn, check_or_error, get_error_message, list_category_errors, list_all_errors) with inline troubleshooting guidance (cmd_072)
- **Error code integration** — Integrated 30 error codes into 4 existing scripts (new_cmd.sh, validate_result.sh, merge_config.py, validate_config.sh) with standardized `[E###] message → action` format; backward compatible (cmd_072)
- **config.yaml validation script** — `scripts/validate_config.py` validates required fields, types, ranges, and enums using Python 3 stdlib only (custom YAML parser, no PyYAML dependency); 12 test cases (cmd_072)
- **execution_log.yaml validation script** — `scripts/validate_exec_log.py` detects 5 anomaly types (invalid status, orphaned tasks, excessive duration, retry violations, duplicate IDs) with severity levels; integrates with config.yaml thresholds (cmd_072)
- **Roadmap v6** — Restructured roadmap removing public-facing tasks, focusing on self-use quality; 40→25 items, ~40% effort reduction (cmd_072)

### Changed
- **Version bump** — 1.0-rc2 → 1.0

## [1.0-rc2] - 2026-02-14

### Added

#### Learned Preferences (LP) System
- **LP Signal Detection** — Retrospector detects 4 signal types (course correction, afterthought supplement, rejection/revert, repeated specification) with N>=3 aggregation rule and weighted signal accumulation; signals trigger LP proposal generation (cmd_056)
- **LP Search Integration** — Workers search for applicable learned preferences in Memory MCP during task execution via `mcp__memory__search_nodes(query="lp:")`; LP rules applied silently to guide decision-making on translation cost reduction (cmd_056)
- **LP Approval Flow** — Unified approval workflow combining Memory MCP candidates and LP proposals in post-Phase 4 batch review; includes onboarding for first LP, natural language presentation, and batch limit of 3 LP candidates per session (cmd_056)
- **LP Five Principles** — (1) Silent application, (2) Default not mandatory, (3) Absolute quality immutable, (4) Change tolerance, (5) No recording without approval (cmd_056)
- **LP Quality Guardrails** — Dual-quality framework: absolute quality (correctness, completeness, security, safety, test coverage) is immutable; relative quality (style, design choices, report format, confirmation frequency) is LP-adjustable (cmd_056)
- **LP Privacy Safeguards** — 8 forbidden categories (personality, emotional, schedule, productivity, health, political, relationships, financial); aggregate profile review at milestones (10, 20, 30); one-command reset via `lp_system.reset_all: true` (cmd_056)
- **LP Validation Script** — `scripts/validate_lp.py` validates LP entity naming convention, observation format, privacy keywords, quality guardrails, and observation length (100-500 chars) (cmd_056)
- **LP User Guide** — `docs/learned_preferences.md` comprehensive guide covering signal types, 6 clusters, 5 principles, quality scoring, approval workflow, privacy safeguards, FAQ, and lifecycle example (cmd_056)
- **CLAUDE.md LP Section** — Added LP System overview, 5 principles, quality guardrails, 6 clusters, privacy protections, and integration points (cmd_056)

#### Decomposer Enhancements
- **Phase Instructions documentation** — Added comprehensive Phase Instructions section to decomposer with configuration structure, 5 concrete usage examples (progressive constraint relaxation, wave parallelization override, feedback integration, model restrictions, custom output format), and best practices (cmd_057)
- **Large Scope Handling (15+ tasks)** — Added splitting strategies for commands exceeding 15 tasks: sequential cmd split (dependency chains), parallel cmd split (independent workstreams), and decision guidelines table (cmd_057)
- **Consistency Maintenance for Large Commands** — Added canonical values pattern, consistency checkpoints, and explicit input dependencies for commands with 5+ waves or 10+ cross-file shared values; based on cmd_056 retrospective findings (cmd_057)

#### Infrastructure
- **Phase 1.5 safe suffix stripping** — Automatic handling of safe suffix removal during path normalization to prevent false positives in permission fallback checks (cmd_047)
- **Phase 7 general command auto-approval** — Extended auto-approval mechanism for common commands with path containment validation to streamline permission fallback processing (cmd_048)
- **Memory MCP connection check in setup.sh** — Added verification of Memory MCP service connectivity during initialization to ensure knowledge graph functionality is available (cmd_049)
- **Config override system** — JSON-to-YAML migration for local config overrides with deep-merge support (cmd_057)
- **CLAUDE.md diet** — Reduced CLAUDE.md size and improved document consistency (cmd_057)

### Changed
- **Wave derivation clarification** — Parent session now derives Wave assignments exclusively from `Depends On` column; `## Execution Order` section treated as reference only (cmd_055)
- **Decomposer file conflict rules** — File conflicts must be declared as explicit `Depends On` dependencies; implicit Wave-based conflict avoidance is prohibited (cmd_055)
- **Task granularity optimization** — Added systematic merge/don't-merge criteria and judgment flowchart for decomposer to reduce over-decomposition (cmd_055)
- **Decomposer Self-Check expansion** — Added 5 checklist items: Execution Order consistency, Wave separation justification, file conflict detection, granularity optimization, over-decomposition check (cmd_055)

### Fixed
- **macOS/bash 3.2 compatibility** — Resolved compatibility issues with permission-fallback.sh on macOS systems running bash 3.2 to ensure cross-platform operation (cmd_050)

## [1.0-rc] - 2026-02-11

### Added (v1.0-rc Features)

#### Self-Awareness (W1, W3, W5)
- **F15**: Pre-flight plan validation (Phase 1.5) — Optional reviewer validates decomposer's plan against original request before execution begins; gated by `plan_validation` config field
- **F16**: Capability self-assessment (W3) — Decomposer warns when task exceeds reliable scope (>10 files, >1000 LOC, >5 cross-file dependencies); prevents scope creep failures
- **F17**: Aggregator conflict detection (W5) — Detects contradictions between worker results and classifies as COSMETIC (wording) vs FUNDAMENTAL (opposing approaches); resolves with evidence-based reasoning or escalates unresolvable conflicts

#### Learnability (W2, W4)
- **F21**: Failure forensics (W2) — Anti-pattern Memory MCP entities extracted from failed tasks with mitigations; rejection memory prevents repeated proposal submissions in rejected categories
- **F22**: Workflow pattern mining (W4) — `analyze_patterns.sh` script parses execution logs to identify success rates, durations, and task sequences; patterns.md consumed by decomposer for informed planning

#### Extensibility
- **F14**: Custom personas — Decomposer auto-discovers user-defined personas in `personas/*.md` directory with optional persona templates

#### Observability
- **F19**: Plan visualization — `visualize_plan.sh` generates Mermaid flowchart diagrams from plan.md showing task dependencies and Wave groupings
- **F24**: ETA in Wave progress — Wave messages include estimated time remaining based on historical stats.sh data with fallback persona estimates

#### Quality Assurance
- **F23**: Phase instructions config — `phase_instructions:` block in config.yaml allows custom per-phase instructions without modifying templates
- **F26**: Documentation audit — All 24 features systematically verified for documentation coverage; code-docs alignment confirmed; 3 gaps identified and fixed
- **F27**: Validation pass — CHANGELOG updated, version consistency verified, implementation completeness confirmed

### Changed
- `templates/decomposer.md`: Added Custom Persona Discovery section (F14), Scope Assessment section (F16), Anti-Pattern Awareness section (F21), Historical Patterns section (F22)
- `templates/aggregator.md`: Added Conflict Detection & Resolution step (F17) with COSMETIC vs FUNDAMENTAL classification
- `templates/retrospector.md`: Added Failure Signature Extraction section (F21), Rejection Memory Check section; updated Memory MCP search to include antipattern entities
- `docs/parent_guide.md`: Added Phase 1.5 Pre-Flight Plan Validation section (F15), Rejection Memory Storage subsection in Phase 4 (F21), Wave Progress Messages with ETA calculation (F24), phase_instructions injection notes
- `config.yaml`: Added `plan_validation: true` field (F15), `phase_instructions:` block with 4 phase fields (F23)
- `CLAUDE.md`: Updated architecture diagram to include Phase 1.5 (F15)
- `README.md`: Added Scripts section documenting all 9 utility scripts (F26)

### Added (New Files)
- `personas/.gitkeep` — Directory marker for user-defined persona templates (F14)
- `scripts/visualize_plan.sh` — Mermaid diagram generator for plan.md (F19)
- `scripts/analyze_patterns.sh` — Workflow pattern mining from execution logs (F22)

### Dependencies
- Builds on v0.9.0 Foundation & Measurement features (F01-F13)

## [0.9.0] - 2026-02-11

### Added
- **F01: `scripts/smoke_test.sh`** — End-to-end smoke test exercising project infrastructure (config validation, health check, directory structure)
- **F02: `scripts/validate_config.sh`** — Config validation script checking all required fields, types, and value ranges
- **F05: `scripts/setup.sh`** — Prerequisites check (bash 4+, jq) + health_check.sh + quick-start output
- **F06: `scripts/stats.sh`** — Execution log parser: duration, persona/model success rates, time trends
- **F07: Shared notes mechanism** — Workers can share cross-task findings via `WORK_DIR/shared_notes.md` (worker_common.md)
- **F08: Partial result forwarding** — Aggregator receives partial results with explicit `task_N: failed` markers (parent_guide.md + aggregator.md)
- **F09: Cascade failure detection** — Parent skips Wave N dependents when Wave N-1 dependency failed (parent_guide.md)
- **F10: Plan-result reconciliation** — `validate_result.sh --reconcile` checks all planned outputs exist and match
- **F11: Failure summary output** — Structured failure message at Phase 2 completion (parent_guide.md)
- **F12: Context hygiene hardening** — Parent records only pass/fail, terse progress messages (parent_guide.md)
- **F13: Execution time config** — `max_cmd_duration_sec` field in config.yaml; parent warns if exceeded

### Changed
- **permission-fallback.sh rewrite** — replaced regex-based guards with 6-phase structured validation pipeline (sanitize → pre-parse → parse → normalize options → normalize path → judge); adds defenses against null byte injection, path traversal, tilde/glob expansion, no-space flag bypass, and tool_name spoofing
- **permission-fallback.sh direct execution support** — shebang ベースの直接実行（`./scripts/foo.sh`）を自動承認対象に追加; Phase 3 で未知インタプリタをスクリプトパスとして扱い Phase 5-6 のパス検証に委譲
- **permission-fallback.sh `.claude/hooks/` support** — Phase 6 に `.claude/hooks/` 配下のスクリプト自動承認を追加; substring attack 耐性を維持
- **permission-fallback.sh data-driven config** — インタプリタ許可リスト・安全/危険フラグをファイル先頭の設定ブロックに抽出; 新インタプリタ追加が設定変更のみで可能に
- **permission-fallback.sh debug mode** — `PERMISSION_DEBUG=1` で拒否理由をstderrに出力する `reject()` 関数を追加; 全拒否ポイントに構造化理由コード付与（S0〜P7, Phase 5-6）
- **permission-fallback.sh defense-in-depth** — jq未インストール時のstderr警告追加; `CLAUDE_PROJECT_DIR` 環境変数をスクリプト自身の位置と交差検証
- **settings.json permission consolidation** — `Bash(./scripts/*)` と `Bash(bash .claude/hooks/test-permission-fallback.sh)` を削除; スクリプト実行承認を permission-fallback.sh hook に一元化
- **permission-fallback tests expanded** — 95→117件に拡張; null byte, 空コマンド, 長パス, `.claude/hooks/` 境界, init_refine_dir.sh, settings.json削除カバレッジを追加
- **CLAUDE.md workflow enforcement** — crew ワークフロー必須化（親セッションの Edit/Write 禁止）、Phase 1 必須化、例外条件6件、よくある間違いセクション追加、config.yaml YAML ブロックをクロスリファレンスに置換
- **parent_guide.md hardening** — Phase 1 を全ケースで必須に変更; パーミッション判定フローチャート追加; `Bash(./scripts/*)` 古い参照を修正; 例外条件を CLAUDE.md と同期

### Added
- **`scripts/health_check.sh`** — 10項目のシステム健全性チェック（config, templates, settings.json, hook実行権限, jq, スクリプト実行権限, hookテスト, CLAUDE.md, parent_guide.md, 古い参照検出）
- **`.claude/hooks/test-hooks-support.sh`** — `.claude/hooks/` サポート専用テストスクリプト

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
- **Skill scripts permission** in `.claude/settings.json` — added `Bash(./scripts/*)` to allow list for script execution

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
