# claude-crew

Claude Code + Task tool multi-agent system.
2-layer flat: parent spawns all subagents directly. No nesting.
File-based I/O: all input/output via files. Parent passes file paths only.
Read `docs/parent_guide.md` before starting.

## Workflow

Crew workflow (Phase 1 -> Phase 2 -> Phase 3) is mandatory for all tasks. Phase 4 (retrospect) is optional.
Parent session must NOT directly Edit/Write files (except execution_log.yaml).
Phase 1 (decomposer) is mandatory except for trivial single-line edits.
Plan mode output ("Implement the following plan:") is not a workflow exception. Start from Phase 1.
See `docs/parent_guide.md` for full rules, exception list, and role restrictions.

## Config

`config.yaml` required. Stop on missing.
Parent reads `work/cmd_NNN/config.yaml` (merged by `new_cmd.sh`).
If `local/config.yaml` exists, it is deep-merged into the work copy at cmd start.
Permission hook reads `local/hooks/permission-config.yaml` directly at runtime.

## Version

Include YAML frontmatter in all artifacts: `generated_by`, `date`, `cmd_id`.
Conventional Commits for approved improvements (see `docs/parent_guide.md`).

## Template Reference

| Role | Template | Purpose |
|------|----------|---------|
| Decomposer | `templates/decomposer.md` | Task decomposition |
| Worker Common | `templates/worker_common.md` | Shared worker rules |
| Researcher | `templates/worker_researcher.md` | Research & analysis |
| Writer | `templates/worker_writer.md` | Documentation & content |
| Coder | `templates/worker_coder.md` | Code implementation |
| Reviewer | `templates/worker_reviewer.md` | Review & quality check |
| Custom | `personas/*.md` | User-defined personas |
| Aggregator | `templates/aggregator.md` | Result integration |
| Retrospector | `templates/retrospector.md` | Post-mortem analysis |
| LP Flush | `templates/lp_flush.md` | LP processing (Phase 4 skip) |
| Multi-Analysis | `templates/multi_analysis.md` | N-viewpoint framework |

Template usage: Pass TEMPLATE_PATH in prompt. Subagent reads template as first action. Parent does not read template content.

## Memory MCP

Search `mcp__memory__search_nodes` at task start.
Write only via approval flow after Phase 4.
Naming: `{domain}:{category}:{identifier}`

## LP Signal Detection (Non-Crew Sessions)

For non-crew sessions: run `/lp-check` before ending long sessions to capture LP signals.
Full LP rules: `docs/lp_rules.md`

## Context Management

Parent is path-passing only. Do not read task/result content.
Foreground parallel execution only. Do not use `run_in_background: true` (background Task has known bugs: MCP unavailable, output_file 0-byte, notification failures).
