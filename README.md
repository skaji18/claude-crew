# claude-crew

日本語版: [README_ja.md](./README_ja.md)

A multi-agent framework powered by Claude Code's Task tool. One session, multiple sub-agents working in parallel — no complex setup required.

## Overview

claude-crew turns a single Claude Code session into a coordinated team of sub-agents. Instead of managing multiple processes, terminals, or communication protocols, you simply describe what you need — and the framework decomposes, delegates, executes, and aggregates the results automatically.

**Key idea**: The parent session acts as a lightweight coordinator, passing file paths between specialized sub-agents. All heavy lifting happens inside the sub-agents, keeping the parent's context consumption minimal.

### Architecture: 2-Layer Flat

```
                  ┌─────────────────────────┐
                  │     Parent Session       │
                  │  (coordinator / router)  │
                  └────────────┬────────────┘
                               │
            ┌──────────┬───────┼───────┬──────────┐
            ▼          ▼       ▼       ▼          ▼
         [Worker]  [Worker] [Worker] [Worker]  [Worker]
          Task 1    Task 2   Task 3   Task 4    Task 5
```

The parent session directly manages all sub-agents. Sub-agents cannot spawn other sub-agents — this is a platform constraint, not a design choice.

## Features

- **File-based communication** — Sub-agents read from and write to files. The parent passes paths, not content, keeping its context window lean.
- **Up to 10 parallel sub-agents** — Launch multiple workers simultaneously for independent tasks.
- **Persona switching** — Each worker can adopt a specialized role: researcher, coder, reviewer, or a custom persona defined by templates.
- **Permission-based safety** — Claude Code's built-in permission system applies to all sub-agents. No `--dangerously-skip-permissions` required.
- **Single-cycle completion** — A typical request (decompose → execute → aggregate → retrospect) completes within one context window, no compaction needed.
- **Model flexibility** — Assign `haiku` for simple tasks, `sonnet` for balanced work, `opus` for complex reasoning — per sub-agent.

## Quick Start

```bash
# 1. Clone the repository
git clone <repo-url> && cd claude-crew

# 2. Launch Claude Code in this directory
claude

# 3. Give it a task
> "Research the top 5 state management libraries for React and write a comparison report."
```

That's it. Claude Code reads `CLAUDE.md`, understands the framework, and orchestrates the work automatically.

## Directory Structure

```
claude-crew/
├── CLAUDE.md                  # Framework instructions for Claude Code
├── README.md                  # This file
├── config.yaml                # Runtime configuration
├── CHANGELOG.md               # Version history
├── .claude/
│   └── settings.json          # Permission settings for sub-agents
├── templates/
│   ├── decomposer.md          # Task decomposition template
│   ├── worker_default.md      # General-purpose worker template
│   ├── worker_researcher.md   # Research-focused worker template
│   ├── worker_coder.md        # Code implementation worker template
│   ├── worker_reviewer.md     # Code review worker template
│   ├── worker_writer.md       # Documentation & content creation worker template
│   ├── aggregator.md          # Result aggregation template
│   ├── retrospector.md        # Post-mortem analysis template
│   └── multi_analysis.md      # N-viewpoint parallel analysis framework
├── scripts/
│   └── new_cmd.sh             # Utility scripts
└── work/
    └── cmd_xxx/               # Working directory per request
        ├── request.md
        ├── plan.md
        ├── execution_log.yaml   # Execution progress log
        ├── tasks/
        │   └── task_N.md
        ├── results/
        │   └── result_N.md
        ├── report.md
        ├── report_summary.md     # Summary report (≤50 lines)
        └── retrospective.md      # Post-mortem analysis (Phase 4)
```

| Path | Purpose |
|------|---------|
| `CLAUDE.md` | Tells Claude Code how to operate as a multi-agent coordinator. This is the brain of the framework. |
| `config.yaml` | Runtime configuration: model selection, parallelism limits, retry settings, and worker timeout. |
| `.claude/settings.json` | Configures which operations sub-agents can perform without asking for permission. |
| `templates/` | Prompt templates that define how each role behaves. Customize these to tune agent behavior. |
| `work/` | Runtime working directory. Each request creates a subdirectory here with all intermediate and final outputs. |

## How It Works

```
 Human                Parent Session            Sub-agents
   │                       │                        │
   │  "Analyze X and Y"   │                        │
   ├──────────────────────>│                        │
   │                       │                        │
   │                       │── Decomposer ─────────>│ Reads request,
   │                       │<── plan.md ────────────│ writes plan
   │                       │                        │
   │                       │── Worker A (parallel) ─>│ Task 1
   │                       │── Worker B (parallel) ─>│ Task 2
   │                       │── Worker C (parallel) ─>│ Task 3
   │                       │<── result files ───────│
   │                       │                        │
   │                       │── Aggregator ─────────>│ Reads results,
   │                       │<── report.md ──────────│ writes report
   │                       │                        │
   │                       │── Retrospector ───────>│ Analyzes execution,
   │                       │<── retrospective.md ───│ writes proposals
   │                       │                        │
   │  Final report         │                        │
   │<──────────────────────│                        │
```

### Step by step

1. **Request** — You describe what you need. The parent saves it to `work/cmd_NNN/request.md`.
2. **Decompose** — A decomposer sub-agent analyzes the request and produces `plan.md`, breaking it into independent tasks.
3. **Execute** — Worker sub-agents are launched in parallel (up to 10). Each reads its task file and writes a result file.
4. **Aggregate** — An aggregator sub-agent reads all result files and produces the final `report.md` and `report_summary.md`.
5. **Retrospect** — A retrospector sub-agent analyzes the execution for failure patterns and success patterns, generating improvement and skill proposals (can be disabled in `config.yaml`).
6. **Report** — The parent returns the final report to you.

The parent's role at each step is minimal: read the output file path from one sub-agent, pass it as input to the next.

## Templates

Templates define how sub-agents behave. They are prompt instructions injected into the sub-agent's context at launch.

| Template | Role | When to use |
|----------|------|-------------|
| `decomposer.md` | Breaks a request into independent tasks | Automatically used at the start of each cycle |
| `worker_default.md` | General-purpose worker | Tasks that don't fit a specialized role |
| `worker_researcher.md` | Information gathering and analysis | Research, surveys, competitive analysis |
| `worker_writer.md` | Documentation and content creation | README, guides, tutorials, specifications |
| `worker_coder.md` | Code implementation | Writing code, fixing bugs, refactoring |
| `worker_reviewer.md` | Quality review and feedback | Code review, document review, testing |
| `aggregator.md` | Combines results into a final report | Automatically used at the end of each cycle |
| `retrospector.md` | Post-mortem and success analysis | Automatically used after aggregation (configurable) |
| `multi_analysis.md` | N-viewpoint parallel analysis framework | Referenced by decomposer for comparison/evaluation tasks |

You can create custom worker templates (e.g., `worker_translator.md`, `worker_designer.md`) by following the pattern in existing templates.

## Work Directory

Each request creates a self-contained subdirectory under `work/`:

```
work/
└── cmd_001/
    ├── request.md          # The original request from the human
    ├── plan.md             # Decomposition plan (tasks + assignments)
    ├── execution_log.yaml    # Execution progress log
    ├── tasks/
    │   ├── task_1.md       # Individual task description
    │   ├── task_2.md       # Individual task description
    │   └── task_3.md       # Individual task description
    ├── results/
    │   ├── result_1.md     # Worker output for task 1
    │   ├── result_2.md     # Worker output for task 2
    │   └── result_3.md     # Worker output for task 3
    ├── report.md           # Final aggregated report
    ├── report_summary.md   # Summary report (≤50 lines)
    └── retrospective.md    # Post-mortem analysis (Phase 4)
```

Everything is a plain Markdown file. You can inspect, edit, or reuse any intermediate output.

## Constraints and Notes

- **No nesting** — Sub-agents cannot launch other sub-agents. This is a Claude Code platform limitation. The framework works around this with a sequential phase approach (decompose → execute → aggregate → retrospect), where the parent bridges each phase.
- **Parallel limit: Up to 10** — Claude Code supports up to 10 simultaneous sub-agents. For tasks requiring more parallelism, the framework batches them automatically.
- **Soft scope restriction** — Worker scope is enforced via prompt instructions, not technical sandboxing. Workers are told which directories to access, but this is an honor system.
- **Background execution recommended for long tasks** — Use `run_in_background: true` for tasks that take more than a few seconds. The parent can check on them later with `TaskOutput`.
- **MCP tools unavailable in background** — Sub-agents running in background mode cannot use MCP tools (e.g., external API integrations). Run those tasks in the foreground.
- **Context independence** — Each sub-agent gets an independent 200k token context window. They don't share memory — all communication goes through files.
- **Language policy** — `CLAUDE.md` is written in Japanese as it serves as an internal instruction file for Claude agents. `README.md` and other user-facing documentation are in English.

## License

MIT
