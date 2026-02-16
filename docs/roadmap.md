# claude-crew Roadmap (v7.3)

**Status**: Final (2026-02-15)
**Scope**: 19 backlog items + 4 conditional triggers + 3 shipped skills
**Philosophy**: State-based roadmap reflecting actual implementation progress

> **v6→v7 Changes**: Migrated from phase-based planning to shipped/backlog model. Removed 6 completed items (Error system, LP system, Wave ETA calculation, Background execution deprecation, Config validation, Execution log validation). Reprioritized decomposer optimization (A→B) based on low utilization evidence. Added Skills catalog and Breaking Changes section.

> **v7.0→v7.1 Changes** (Round 2): Added Roadmap Maintenance section (staleness prevention). Validated LP entity count (measured: 3, not estimated 8-12). Clarified Wave metrics scope (renamed #20 to "Wave metrics dashboard"). Added Conditional trigger automation mechanisms. Elevated Multi-round docs (#10) and numbering extension (#22) to S-tier. Added effort tracking integration. Strengthened dependency chains. Removed Alternative Paradigm discussion (state-based confirmed).

> **v7.1→v7.2 Changes** (Round 3): Converted Roadmap Maintenance from documentation to implementation (new item #25). Revised item #24 effort estimate (0h → 2h, config-only → A-tier). Clarified archive destination (CHANGELOG.md). Added execution_log schema enhancement (new item #26) as prerequisite for Conditional trigger #27. Merged Config/Permission docs (#6+#7 → #6). Removed low-ROI item #23 (new_cmd.sh UI improvements). Renumbered items for consistency. Net backlog: 51.5h across 18 items.

> **v7.2→v7.3 Changes** (Round 4): Applied feasibility verification adjustments. Revised effort estimates for 6 items (#7, #8, #12, #13, #22, #23): total +7-12h increase. Changed item #22 implementation from bash to Python (maintenance-free compliance). Added completion criteria details for items #12 (test harness interface), #24 (Conditional trigger enforcement). Clarified item #19 JSON schema convention. Reverted item #6 merge (split back to #6 Config + #7 Permission hooks) based on quality/time-saving concerns. Adjusted schedule to 12-13 weeks (realistic velocity). Net backlog: 58.5-63.5h across 19 items.

---

## Shipped (v1.0-rc State)

These items were completed during Rounds 1-10 (cmd_081→089) and are now operational:

| Item | Status | Evidence |
|------|--------|----------|
| **Error code system (E001-E399)** | DONE | `scripts/error_codes.sh` (351 lines), config validation chain |
| **LP system (6 clusters, validation)** | DONE | `docs/learned_preferences.md`, `scripts/validate_lp.py`, `lp_rules.md` |
| **Wave parallelism ETA calculation** | DONE | `docs/parent_guide.md` lines 143-150, algorithm complete, integrated into parent workflow |
| **Config validation** | DONE | `scripts/error_codes.sh` E001-E099 range, integrated into `new_cmd.sh` |
| **Execution log validation** | DONE | `scripts/validate_exec_log.py`, E100-E199 error range |
| **Background execution deprecation** | DONE | Removed in cmd_089 (2026-02-15). Foreground-only execution now mandatory. |
| **Persona system (custom roles)** | DONE | `templates/worker_*.md`, `personas/` directory, custom persona support |
| **Permission hooks** | DONE | Migrated to `permission-guard` plugin (`/plugin install permission-guard@skaji18-plugins`). Project config: `.claude/permission-config.yaml`. Local overlay: `local/hooks/permission-config.yaml`. |
| **Config merge (local overrides)** | DONE | `scripts/merge_config.py`, `local/config.yaml` support |
| **Health check diagnostics** | DONE | `scripts/health_check.sh` |

**Completion criteria**: All items have production-grade implementations with documentation and integration into core workflows.

**Archive note**: As more items complete, this section will be versioned ("Shipped in v1.0", "Shipped in v1.1") to prevent roadmap bloat. Items older than 3 months will move to **CHANGELOG.md** (archive destination).

---

## Skills Catalog

User-invocable skills (commands prefixed with `/`):

| # | Skill | Command | Purpose | Status | Documentation |
|---|-------|---------|---------|--------|---------------|
| S1 | LP Monitor | `/lp-check` | Inspect LP entity count, trigger pruning review | Shipping | `.claude/skills/lp-check/` |
| S2 | Commit Automation | `/commit` | Conventional commits with approval flow | Shipping | `.claude/skills/commit/` |

**Completion criteria**: All skills functional with help text and error handling.

---

## Backlog

Items not yet started, grouped by domain. Total effort: **58.5-63.5h** (realistic range with overhead).

### Foundation (3 items, 10h)

| # | Item | Priority | Effort | Notes | Completion Criteria |
|---|------|----------|--------|-------|---------------------|
| 1 | LICENSE file (MIT) | S | 0.5h | "AS IS" disclaimer for legal protection. **BLOCKS** #2. | LICENSE exists at repo root with MIT text |
| 2 | README minimal update | A | 1h | Setup steps + disclaimer (not marketing). **BLOCKED BY** #1. | README has installation section + "use at own risk" note |
| 3 | Memory MCP connection fallback | A | 1.5h | Graceful degradation when MCP unavailable | Worker templates handle MCP failure without crash, tested via `killall mcp-server` integration test |
| 4 | Worker timeout detection & recovery | A | 3.5h | Task tool timeout + parent-side retry logic | Parent detects hung workers, logs timeout errors (E2XX range), tested via artificial 5-min hang |
| 5 | LP privacy audit tool | A | 2h | Validate no PII/secrets in LP observations. **BLOCKS** Conditional #25-26. | Script scans learned_preferences.md for common PII patterns (emails, API keys), exits 0 if clean |

### Workflow (5 items, 17h-19.5h)

| # | Item | Priority | Effort | Notes | Completion Criteria |
|---|------|----------|--------|-------|---------------------|
| 6 | Config merge documentation | B | 1.5h | **REVERTED from v7.2 merge**. Document local/config.yaml override behavior + examples. | `docs/config.md` section explaining merge precedence, 2+ examples of override patterns |
| 7 | Permission hooks guide | B | 2.5h | **REVERTED from v7.2 merge**. Document `permission-guard` plugin usage + `.claude/permission-config.yaml` configuration + real-world examples. | `docs/permission_hooks.md` with 3+ complete use cases (file blocking, approval flows, etc.) |
| 8 | Error message inline troubleshooting | S | 4-5h | **REVISED from 3h** (feasibility: error analysis + fix drafting + testing 10 scenarios). Embed fix suggestions in error output. | Error messages include "Try: [action]" hints for top 10 errors (E001-E010) |
| 9 | Hierarchical aggregation (40+ tasks) | A | 8-9h | **REVISED from 7h** (feasibility: performance debugging for 40+ task aggregation). Support decomposition into 40+ subtasks. | Aggregator handles 40+ result files without OOM or timeout, tested with synthetic 50-task cmd |
| 10 | Multi-round framework documentation | S | 2h | Document Rounds 1-N convergence pattern. **BLOCKING** for Round 11+ meta-design work. Elevated from A to S (review feedback #7). | `docs/multi_round.md` explaining when to use, how to structure, termination criteria |
| 11 | scope_warning split recommendations | B | 2.5h | Decomposer suggests task split when scope exceeds threshold | **Reprioritized A→B** (low decomposer utilization). Decomposer logs split recommendation when task desc > 500 words |
| 12 | Long-running task split rules | B | 1.5h | Auto-suggest splits for tasks > 2h estimate | **Reprioritized A→B**. Decomposer emits warning when single task effort > 2h |

**Rationale for #6+#7 split reversion**: v7.2 merged these items claiming 0.5h overhead savings. Feasibility analysis disproved this: documentation is linear in content length (750 words + 1250 words = 2000 words ≈ 4-5h, not 3.5h). Merged item risks uneven allocation (Config rushed, Permission hooks shallow). Separate items allow prioritization (Config A-tier blocking, Permission hooks B-tier deferred) and ensure quality per topic.

**Reprioritization rationale (items 11-12)**: cmd_081→089 show decomposer bypass via Phase 1 exception path for meta-design work. Decomposer optimization has lower ROI until utilization increases. **Note**: If decomposer usage rises ≥70% over 4 weeks, re-elevate to A-tier (see Conditional Triggers).

### Quality (5 items, 25.5-31h)

| # | Item | Priority | Effort | Notes | Completion Criteria |
|---|------|----------|--------|-------|---------------------|
| 13 | Integration test (minimal) | S | 8-10h | **REVISED from 7h** (feasibility: test infrastructure setup + debugging historically exceeds estimates). End-to-end test for basic crew workflow. **BLOCKS** #14. **UPDATED**: Test harness exposes standardized exit codes (0=pass, 1=fail) and optional JSON summary for CI consumption. | Test runs cmd with 3 tasks, validates all result files created, passes CI, provides CI-compatible interface |
| 14 | CI/CD setup | A | 3-4h | **REVISED from 2.5h** (feasibility: first-time CI setup includes debugging permissions/environment issues). Automated test run on commit. **BLOCKED BY** #13. | GitHub Actions runs integration test on push to main, badge in README |
| 15 | Custom persona guide | A | 4h | Examples + documentation for custom personas | `docs/custom_personas.md` with 2+ complete examples |
| 16 | Integration test (Rounds 2-7) | A | 6h | Verify multi-round convergence patterns | Test validates Round 1→7 with mutation tracking, validates convergence criteria |
| 17 | Edge case tests | B | 2h | Test failure paths, empty inputs, malformed configs | Test suite covers 10+ edge cases with expected error codes |
| 18 | Test coverage report | B | 3h | Measure test coverage for scripts/ | Coverage tool generates HTML report, baseline: 60% for core scripts |

**Item #13 update**: Added completion criteria requiring standardized test harness interface (exit codes, JSON summary) to prevent #14 rework (dependency clarification from feasibility analysis).

### Tooling (3 items, 4h)

| # | Item | Priority | Effort | Notes | Completion Criteria |
|---|------|----------|--------|-------|---------------------|
| 19 | Model selection integration | B | 4h | Integrate `/model-selection-guide` skill into workflow | Parent suggests model based on task type (already has skill, needs integration) |
| ~~20~~ | ~~Wave metrics dashboard~~ | - | - | **DROPPED**: stats.sh and analyze_patterns.sh removed (cmd_128 analysis showed insufficient analytical value). Wave ETA calculation also removed. | - |
| 21 | execution_log analysis tool | B | 1.5h | Summarize cmd history trends | `scripts/analyze_exec_log.sh` outputs: avg tasks/cmd, success rate, top personas |
| 22 | numbering format extension (cmd_999+) | S | 0.5h | Support cmd_1000+ in scripts. **Elevated from A to S** (review feedback #6): trivial blocker, not high-value A-slot work. | `new_cmd.sh` handles 4+ digit cmd numbers without padding errors, tested with cmd_1000 mock |

**Item #20 dropped**: stats.sh, analyze_patterns.sh, patterns.md, and Wave ETA calculation removed based on cmd_128 deep analysis (selection bias in model comparisons, coder CV=97-113% makes ETA unreliable).

### Maintenance (3 items, 7.5-10h)

| # | Item | Priority | Effort | Notes | Completion Criteria |
|---|------|----------|--------|-------|---------------------|
| 23 | Roadmap Maintenance automation | S | 4-5h | **REVISED from 2h** (feasibility: multi-component integration scope). **IMPLEMENTATION CHANGED**: Python-based staleness detection (maintenance-free compliance) instead of bash YAML parsing. Scope: (1) health_check.sh staleness detection (YAML parsing, date comparison = 1-1.5h), (2) retrospector template modification (item completion logging = 1-1.5h), (3) integration test (mock stale scenario = 0.5-1h). **BLOCKS** long-term roadmap sustainability. | `scripts/health_check.sh` warns when roadmap last-modified > 5 cmds ago (Python-based YAML parsing). Retrospector template logs roadmap item completions to execution_log.yaml. Tested via mock stale scenario. |
| 24 | Execution_log effort tracking | A | 2.5-3h | **REVISED from 2h** (feasibility: backward compatibility for 60+ existing logs adds complexity). Enhance execution_log.yaml schema to track actual vs. planned effort. Includes validation updates + backward compatibility for cmd_030-089 logs. | `execution_log.yaml` includes `effort_hours` field (optional), retrospector logs actual vs. planned hours, validation allows optional field |
| 25 | Execution_log schema enhancement (plan_status) | A | 1.5h | Add `plan_status` field to execution_log.yaml (success/failure). Required for Conditional trigger #27. **UPDATED**: Completion criteria include parent_guide.md update with Conditional Trigger pre-activation checklist. | `execution_log.yaml` includes `plan_status` field (optional), retrospector logs plan success/failure, validation updated, `scripts/audit_failures.sh` counts failures, `docs/parent_guide.md` updated with pre-activation checklist |

**Item #23 critical update**: Revised from 2h to 4-5h based on realistic scope breakdown. Changed implementation from bash YAML parsing (brittle, violates maintenance-free principle) to Python-based detection (matches existing validate_*.py pattern, uses PyYAML for schema-aware parsing). This prevents silent failures when execution_log.yaml format evolves.

**Item #25 update**: Added parent_guide.md update to completion criteria, ensuring Conditional trigger activation has enforcement mechanism (dependency clarification from feasibility analysis).

**Rationale for new items**:
- **#23 (Roadmap Maintenance automation)**: v7.1 documented the process but didn't implement it. Round 3 review flagged this as HIGH-likelihood staleness risk. Elevating to S-tier implementation ensures process is enforced, not aspirational. Round 4 feasibility analysis confirmed scope underestimate and maintenance-free violation; revised accordingly.
- **#24 (effort tracking revised)**: v7.1 marked as "0h config-only" but review identified validation + migration complexity. Revised to 2.5-3h A-tier with explicit scope (validation updates, backward compatibility). Round 4 added 0.5-1h buffer for edge cases.
- **#25 (schema enhancement)**: Conditional trigger #27 depends on `plan_status` field that doesn't exist yet. Adding explicit prerequisite prevents activation of trigger with missing infrastructure.

---

## Conditional Triggers

Items activated when specific conditions are met:

| # | Item | Trigger Condition | Priority | Effort | Automation Mechanism | Completion Criteria |
|---|------|-------------------|----------|--------|----------------------|---------------------|
| 26 | LP settling timing optimization | LP entity count ≥ 20 | C | 1.5h | **Monitor**: `/lp-check` skill outputs entity count; parent health_check.sh warns when count ≥ 18 (approaching threshold). **Trigger**: Manual activation when count reaches 20. | Retrospector adjusts LP merge window based on entity count |
| 27 | LP confidence scoring | LP entity count ≥ 20 | C | 1.5h | Same monitoring as #26. **BLOCKED BY** #5 (LP privacy audit must pass before activating LP enhancements). | LP observations include confidence scores (0.0-1.0) |
| 28 | Phase 1.5 re-enablement | Plan failure ≥3 times in one quarter | C | 0h (config only) | **Monitor**: Retrospector logs plan failures to execution_log.yaml (field: `plan_status`). **BLOCKED BY** #25 (schema enhancement must complete first). **Audit**: Quarterly script `scripts/audit_failures.sh` counts failures. **Trigger**: Auto-opens issue when count ≥ 3. **Enforcement**: parent_guide.md pre-activation checklist (added in #25 completion). | `config.yaml: phases.decomposer.optional: false` |
| 29 | Decomposer optimization re-elevation | Decomposer usage ≥70% over 4 weeks | C | 0h (priority change) | **Monitor**: `scripts/analyze_exec_log.sh --decomposer-usage` outputs percentage. **Trigger**: When usage ≥ 70%, re-prioritize items #11-12 from B → A. | Items #11-12 moved to A-tier, scheduled for next planning cycle |

**Current LP entity count**: **3 entities** (measured 2026-02-15 via Memory MCP `mcp__memory__read_graph`). Last measurement: 2026-02-15.

**Dependency update**: Conditional trigger #28 now explicitly **BLOCKED BY** item #25 (execution_log schema enhancement). This prevents activation of plan failure monitoring before `plan_status` field exists. Item #25 completion includes parent_guide.md update with pre-activation enforcement checklist.

---

## Roadmap Maintenance

**Purpose**: Prevent staleness. v6 became outdated within weeks; v7.3 implements operational process to keep roadmap current.

**Implementation status**: v7.1 documented the process. v7.2 added item #23 (Roadmap Maintenance automation, S-tier) to convert documentation into operational tooling. v7.3 revised item #23 to 4-5h (realistic scope) and changed implementation to Python (maintenance-free compliance).

### Refresh Cadence

**Every 5 cmds** (approximately every 2-3 weeks at current velocity):
1. Review Backlog → Shipped promotions (did any items complete?)
2. Validate LP entity count (approaching thresholds for Conditional triggers?)
3. Check for breaking changes (update Breaking Changes section if needed)
4. Audit priority assignments (does evidence still support current priorities?)

### Ownership

**Parent session (via item #23 implementation)**:
- `scripts/health_check.sh` checks roadmap last-modified date vs. execution_log.yaml latest cmd (Python-based YAML parsing)
- If gap > 5 cmds, emit warning: "Roadmap may be stale. Run roadmap refresh."

**Retrospector (Phase 4, via item #23 implementation)**:
- Log which roadmap items (if any) were addressed in current cmd
- Recommend Backlog → Shipped promotion if applicable
- Flag priority drift if evidence contradicts roadmap priorities

### Trigger Conditions

**Immediate refresh required when**:
1. Breaking change deployed (update Breaking Changes section)
2. LP entity count crosses threshold (activate Conditional items #26-27)
3. Decomposer usage pattern shifts (trigger Conditional #29)
4. Plan failure count ≥ 3 in quarter (trigger Conditional #28)

### Archival Process

**Shipped section versioning**:
- When v1.1 releases, rename current "Shipped" → "Shipped in v1.0"
- Add new "Shipped in v1.1" section for items completed after v1.0
- After 3 months, archive oldest versioned section to **CHANGELOG.md**

---

## Breaking Changes (v6→v7)

### Background Execution Removal (2026-02-15, cmd_089)

**Removed**:
- `config.yaml: execution.background_threshold`
- `config.yaml: execution.run_in_background`
- Parent support for `run_in_background: true` in Task tool

**Reason**: Claude Code Task background mode has 4 known bugs:
1. MCP tools unavailable in background tasks
2. output_file written with 0 bytes
3. Notification system unreliable
4. Parent cannot reliably detect background task completion

**Migration**: Use foreground-only execution. Parent runs independent tasks in parallel within single message (same behavior, no background needed).

**Impact**: Error code E008 (background_threshold validation) deprecated. Scripts/health_check.sh no longer validates background config.

---

## Execution Strategy

**Priority-based execution**:
1. **S-tier items first** (blockers): #1 (LICENSE), #8 (Error messages), #10 (Multi-round docs), #13 (Integration test), #22 (Numbering extension), #23 (Roadmap Maintenance automation)
2. **A-tier next** (high value): #2, #3, #4, #5, #9, #14, #15, #16, #24, #25
3. **B-tier when time permits**: #6, #7, #11, #12, #17-21

**Estimated schedule** (realistic, accounting for overhead):
- Week 1-3: S-tier items (18.5-21h) — assumes 5-6h/week availability
- Week 4-7: A-tier Foundation + Workflow (17.5-20h)
- Week 8-10: A-tier Quality + Tooling (16-20.5h)
- Week 11-13: B-tier items (16.5h)

**Total timeline**: 12-13 weeks (3+ months) at 5h/week velocity

**Schedule note**: Historical velocity data not available (effort tracking begins with item #24). Schedule assumes 5h/week completion rate with 20% overhead multiplier for context switching, dependency coordination, and debugging interactions. If actual rate differs, adjust timeline quarterly.

**Dependencies** (explicit blockers):
```
#1 (LICENSE) → #2 (README) → Public release
#13 (Integration test minimal) → #14 (CI/CD) → #16 (Integration test Rounds)
#5 (LP privacy audit) → Conditional #26, #27 activation
#25 (execution_log schema enhancement) → Conditional #28 activation
#23 (Roadmap Maintenance automation) → Long-term roadmap sustainability
```

Groups within same priority tier can execute in parallel.

---

## Completion Criteria (Roadmap-Level)

**v1.0 release ready**:
- ✅ LICENSE exists
- ✅ README has setup + disclaimer
- ✅ Error code system operational (DONE)
- ✅ Config/exec_log validation (DONE)
- ✅ Integration test passes
- ✅ CI/CD running
- ✅ Roadmap Maintenance automation operational

**v1.0.x maturity**:
- Worker timeout detection operational (validated via E2XX error log)
- Hierarchical aggregation supports 40+ tasks (tested with synthetic 50-task cmd)
- Custom persona guide published
- Integration test covers Rounds 2-7 (convergence criteria validated)
- Multi-round framework documented (unblocks Round 11+ work)
- Effort tracking integrated (execution_log.yaml captures actual vs. planned hours)

**v1.1+ optimization**:
- Wave metrics dashboard operational (JSON export + UI integration)
- LP privacy audit passes (no PII/secrets detected)
- Test coverage ≥60% for core scripts (HTML report generated)

---

## v6→v7 Changes Summary

### Structural Mutations

| Mutation Type | Change | Impact |
|---------------|--------|--------|
| **Item deletion** | Removed 6 completed items (Error system, LP system, Wave ETA, etc.) | Effort: 68.5h → 52h (-16.5h) |
| **Item addition** | Added 7 new items across v7.0-v7.2 (LP privacy audit, Config/hooks docs, Multi-round docs, Roadmap Maintenance automation, Effort tracking, Schema enhancement) | Effort: +10.5h |
| **Item merge** (v7.2) | Merged Config merge docs + Permission hooks guide → single item #6 | Saved 0.5h overhead (claimed) |
| **Item merge reversion** (v7.3) | Split item #6 back to #6 (Config) + #7 (Permission hooks) | Evidence showed no time savings, quality risk from uneven allocation |
| **Item removal** (v7.2) | Removed new_cmd.sh UI improvements (low ROI) | Saved 3h |
| **Priority changes** | Decomposer items #11, #12: A→B. Multi-round docs #10: A→S. Numbering extension #22: A→S. Roadmap Maintenance #23: NEW S-tier. | Reflects low utilization + blocking urgency adjustments |
| **Effort recalibration** (v7.3) | Revised 6 items (#8, #9, #13, #14, #23, #24) based on feasibility analysis | Total +7-12h (+13-21% increase) |
| **Implementation approach** (v7.3) | Changed item #23 from bash to Python | Maintenance-free compliance |
| **Phase restructuring** | Eliminated Phase 1-3 model → Shipped/Backlog model | Better reflects iterative reality |
| **New category** | Added "Skills Catalog" section | Documents user-invocable features |
| **Completion criteria** | Added measurable criteria for each item, cross-referenced with existing tooling | Enables progress validation |
| **Dependency strengthening** (v7.1) | Made blocker relationships explicit (#1→#2, #13→#14, #5→Conditional) | Prevents out-of-order execution |
| **Dependency completion** (v7.2) | Added #25→Conditional#28 prerequisite (schema dependency) | No undefined schema dependencies |
| **Dependency clarification** (v7.3) | Added interface spec (#13→#14), enforcement mechanism (#25→Conditional#28) | Prevents rework and premature activation |

### Content Changes

1. **"Shipped" section created**: 10 items recognized as complete (Error system, LP system, Wave ETA, Background deprecation, Config validation, Exec log validation, Persona system, Permission hooks, Config merge, Health check)

2. **Breaking Changes section added**: Documents background execution removal with migration path

3. **Skills Catalog added**: 2 skills documented (lp-check, commit)

4. **Reprioritization based on evidence**:
   - Decomposer optimization (items 11-12): A→B (low utilization)
   - LP privacy audit (item 5): NEW, priority A (security requirement)
   - Multi-round framework docs (item 10): A→S (blocking for Round 11+)
   - Numbering extension (item 22): A→S (trivial blocker)
   - Roadmap Maintenance automation (item 23): NEW S-tier (prevents staleness)

5. **Effort accuracy improvements**:
   - v6 estimated 68.5h total
   - v7 recognizes 16.5h already shipped
   - v7.2 backlog: 51.5h (optimistic)
   - v7.3 backlog: 58.5-63.5h (realistic with overhead)

6. **Completion criteria made measurable**:
   - v6: "Worker timeout detection & recovery" (vague)
   - v7: "Parent detects hung workers, logs timeout errors (E2XX range)" (testable)
   - v7.3: Cross-referenced completion criteria with existing test scripts, added interface specifications and enforcement mechanisms

### Rationale

v6 was created as a forward-looking plan before Rounds 1-10 meta-work. During cmd_081→089, the system evolved:

- LP system reached production maturity
- Error handling became comprehensive
- Background execution was deprecated
- Multi-round convergence became the primary workflow

v7 reflects this reality by:
- Recognizing shipped work (no duplicate effort)
- Documenting breaking changes (user migration path)
- Reprioritizing based on actual utilization patterns
- Adding missing documentation items (multi-round, LP privacy, etc.)

v7.1 added operational rigor:
- Roadmap maintenance process (staleness prevention)
- Measurement validation (LP entity count, Wave metrics scope)
- Conditional trigger automation (data-driven activation)
- Effort tracking integration (velocity-based planning)

v7.2 completed the transition from documentation to implementation:
- Roadmap Maintenance automation (item #23 S-tier) — converts process from aspirational to operational
- Effort tracking revised (0h → 2h) — realistic scope including validation
- Schema prerequisites added (item #25) — prevents Conditional trigger activation with missing infrastructure
- Complexity reduction (merged docs, removed low-ROI items) — cleaner backlog
- Archive destination clarified (CHANGELOG.md) — operational clarity

v7.3 applies feasibility verification for realistic execution:
- Effort recalibration (6 items revised based on historical data and scope analysis)
- Maintenance-free compliance (Python-based staleness detection)
- Dependency clarifications (interface specifications, enforcement mechanisms)
- Merge reversion (Config + Permission hooks split preserves quality)
- Overhead accounting (20% multiplier for context switching, coordination, debugging)
- Schedule adjustment (12-13 weeks realistic vs. 10-12 weeks aspirational)

---

## Feasibility Adjustments Log (Round 4)

### Effort Recalibration (6 items)

| Item | v7.2 Estimate | v7.3 Estimate | Rationale |
|------|--------------|--------------|-----------|
| #8 (Error inline troubleshooting) | 3h | 4-5h | Error analysis + fix drafting + testing 10 scenarios exceeds 3h (feasibility: multi-step workflow complexity) |
| #9 (Hierarchical aggregation) | 7h | 8-9h | Performance debugging for 40+ task aggregation historically exceeds estimates (feasibility: cmd_056 23-task data) |
| #13 (Integration test minimal) | 7h | 8-10h | Test infrastructure setup + debugging historically underestimated (feasibility: test harness complexity) |
| #14 (CI/CD setup) | 2.5h | 3-4h | First-time CI setup includes debugging permissions/environment issues (feasibility: bootstrapping overhead) |
| #23 (Roadmap Maintenance automation) | 2h | 4-5h | Multi-component integration: health_check (1-1.5h) + retrospector (1-1.5h) + test (0.5-1h) (feasibility: scope breakdown) |
| #24 (Effort tracking) | 2h | 2.5-3h | Backward compatibility for 60+ existing logs adds complexity (feasibility: edge case buffer) |

**Total effort increase**: +7-12h (+13-21% from v7.2's 51.5h baseline)

### Implementation Approach Changes (1 item)

| Item | v7.2 Approach | v7.3 Approach | Rationale |
|------|--------------|--------------|-----------|
| #23 (Roadmap Maintenance automation) | bash YAML parsing | Python-based detection | bash YAML parsing is brittle, violates maintenance-free principle. Python with PyYAML handles schema evolution gracefully (matches existing validate_*.py pattern). |

### Dependency Clarifications (3 items)

1. **Item #13 → #14 interface specification**: Added completion criteria requiring test harness to expose standardized exit codes (0=pass, 1=fail) and optional JSON summary for CI consumption. Prevents #14 rework when discovering incompatible interface.

2. **Item #25 completion criteria enhancement**: Added parent_guide.md update with Conditional Trigger pre-activation checklist ("Run scripts/check_blockers.sh TRIGGER_ID before activation"). Provides enforcement mechanism for BLOCKED BY relationships.

3. **Item #20 JSON schema clarification**: Added note specifying JSON schema convention: {wave_id, avg_wait_sec, parallelism_factor, timestamp}. Dashboard implementation deferred to v1.1+. Prevents scope creep.

### Merge Reversion (1 item)

**Item #6 (v7.2 merged Config + Permission hooks → v7.3 split)**:
- v7.2 claim: Merge saves 0.5h overhead (1.5h + 2.5h → 3.5h)
- Feasibility analysis: Documentation is linear in content (750w + 1250w = 2000w ≈ 4-5h at 400-500w/h). No overhead savings.
- Quality risk: Combined item risks uneven allocation (Config rushed 70%, Permission hooks shallow 30%)
- v7.3 decision: Split back to #6 (Config 1.5h) + #7 (Permission hooks 2.5h), prioritize Config A-tier, defer Permission hooks B-tier

### Schedule Adjustment

| Version | Total Effort | Timeline | Velocity Assumption |
|---------|-------------|----------|---------------------|
| v7.2 | 51.5h | 10-12 weeks | 5h/week (optimistic) |
| v7.3 | 58.5-63.5h | 12-13 weeks | 5h/week + 20% overhead (realistic) |

**Overhead multiplier rationale**: Bottom-up estimation (sum of individual item estimates) systematically underestimates total effort. 20% multiplier accounts for:
- Context switching overhead (reading docs, understanding implementations, test setup)
- Dependency coordination overhead (validating prerequisites, interface compatibility)
- Debugging unexpected interactions (schema changes affecting parsers, etc.)
- Quality iteration overhead (retries due to validation failures, observed in cmd_056)

---

## Changelog

**2026-02-15 (v7.3-final)** (Round 4 revisions):
- Applied feasibility verification adjustments from Task 7
- Revised effort estimates for 6 items (#8, #9, #13, #14, #23, #24): total +7-12h increase
- Changed item #23 implementation from bash to Python (maintenance-free compliance)
- Added completion criteria details for items #13 (test harness interface), #25 (Conditional trigger enforcement)
- Clarified item #20 JSON schema convention
- Reverted item #6 merge (split back to #6 Config + #7 Permission hooks) based on quality/time-saving concerns
- Adjusted schedule to 12-13 weeks (realistic velocity with 20% overhead multiplier)
- Net backlog: 58.5-63.5h across 19 items (up from v7.2's 51.5h/18 items)
- **Released to production** (docs/roadmap.md)

**2026-02-15 (v7.2-draft3)** (Round 3 revisions):
- Added Roadmap Maintenance automation (new item #22, S-tier, 2h) to implement staleness detection + retrospector logging
- Revised effort tracking estimate (item #23, was 0h config-only → 2h A-tier with validation scope)
- Added execution_log schema enhancement (new item #24, A-tier, 1.5h) to implement plan_status field
- Clarified archive destination (CHANGELOG.md) throughout Shipped + Roadmap Maintenance sections
- Merged Config merge docs + Permission hooks guide into single item #6 (saves 0.5h overhead)
- Removed new_cmd.sh UI improvements (low ROI, saves 3h)
- Added explicit BLOCKED BY relationship: Conditional #27 requires item #24
- Renumbered items 6-24 for consistency after consolidation
- Net backlog: 51.5h across 18 items (down from v7.1's 52h/19 items)

**2026-02-15 (v7.1-draft2)** (Round 2 revisions):
- Added Roadmap Maintenance section (refresh cadence, ownership, triggers, archival)
- Validated LP entity count (measured: 3, not 8-12 estimate)
- Clarified Wave metrics scope (renamed #20 to "Wave metrics dashboard")
- Added Conditional trigger automation mechanisms (monitoring, audit, triggers)
- Added effort tracking integration (new item #24)
- Elevated Multi-round docs (#10) to S-tier (blocking for Round 11+)
- Elevated numbering extension (#22) to S-tier (trivial blocker)
- Strengthened dependency chains (explicit BLOCKS/BLOCKED BY markers)
- Added schedule velocity context (aspirational, pending effort tracking)
- Cross-referenced completion criteria with existing tooling
- Added Shipped section archival note (prevent unbounded growth)
- Removed Alternative Paradigm discussion (state-based confirmed)

**2026-02-15 (v7.0-draft1)** (Round 1 baseline):
- Migrated from phase-based to state-based roadmap
- Added "Shipped" section (10 items)
- Added "Breaking Changes" section (background execution removal)
- Added "Skills Catalog" section (3 skills)
- Reprioritized decomposer items (#11, #12) from A→B
- Added 4 new backlog items (LP privacy audit, Config merge docs, Multi-round docs, Permission hooks guide)
- Removed 6 completed items from backlog (Error system, LP system, Wave ETA, Config validation, Exec log validation, Background deprecation)
- Updated effort estimates (68.5h → 52h backlog)
- Added measurable completion criteria for all items

---

## Sources Referenced

- `/home/shogun/claude-crew/work/cmd_090/results/result_6.md` — Roadmap v7.2-draft3 (baseline for Round 4 adjustments)
- `/home/shogun/claude-crew/work/cmd_090/results/result_7.md` — Feasibility verification results with 6 effort adjustments + 3 dependency clarifications
- `/home/shogun/claude-crew/work/cmd_090/tasks/task_8.md` — Round 4 adjustment task specification
- `/home/shogun/claude-crew/templates/worker_writer.md` — Writer persona guidelines
- `/home/shogun/claude-crew/templates/worker_common.md` — Worker output format and Self-Challenge requirements
