---
name: next-round
description: "Read a completed cmd's report.md, detect continuation signals, present strategy options, and generate request.md for the next round."
user-invocable: true
---

# Claude Skill: next-round

## Overview

Analyze a completed cmd's report to identify continuation opportunities, present strategic options for the next round, and generate a ready-to-use request.md. Bridges the gap between completed rounds and the next iteration.

## Invocation

```
/next-round <report_path> [options]
```

## Arguments

- `<report_path>` (required): Path to the completed cmd's report.md
  - Example: `work/cmd_090/report.md`
- `--strategy=<type>` (optional): Force a specific strategy instead of auto-detection
  - Values: `review`, `mutation`, `deepen`, `synthesize`
- `--dry-run` (optional): Show detected signals and options without generating request.md

## Workflow

When user invokes `/next-round <report_path> [options]`:

### 1. Validate Input

- Read the file at `<report_path>`.
- If file does not exist or is empty: report "File not found or empty: {report_path}" and stop.
- If file lacks YAML frontmatter (no `---` delimiters): report "Not a valid report.md (missing YAML frontmatter)" and stop.
- Extract `cmd_id` from the YAML frontmatter. If missing, infer from the path (e.g., `work/cmd_090/report.md` -> `cmd_090`).

### 2. Read Report Content

- Read the full report.md content.
- Also check if `report_summary.md` exists in the same directory. If so, read it for additional context.
- Identify the report structure: Executive Summary, Task Results, Key Findings, Issues & Risks, Recommendations, Open Questions, Unexplored Dimensions, Conflict Detection, Quality Review sections.

### 3. Detect Continuation Signals

Read the report content and assess the following signal categories. For each, determine whether the signal is **present**, **absent**, or **ambiguous**, and assign a confidence level (HIGH/MEDIUM/LOW).

**Note**: For reports generated with enhanced aggregator (post-cmd_103), prioritize reading structured sections:
- '## Open Questions' (structured question list)
- '## Unexplored Dimensions' (structured gap list)

These sections provide higher-fidelity signals than generic prose scanning.

**Signal categories to assess:**

a. **Simplification-resistant complexity**: The report describes designs or solutions that remain complex after multiple rounds of simplification. Look for: multi-round revision history, "adjusted" or "recalibrated" estimates trending upward, high effort items persisting across rounds.

b. **Zero empirical evidence**: Claims or decisions in Key Findings or Recommendations that lack empirical data. Look for: phrases like "assumed", "estimated", "unvalidated", "preliminary", "pending data", absence of measured metrics.

c. **Single-paradigm saturation**: All exploration occurs within one paradigm or approach. Look for: all tasks using the same methodology, no Alternative Paradigm in Self-Challenge sections, Conflict Detection showing "no contradictions" across many tasks (potential groupthink indicator).

d. **Implementation-convergence**: Premature convergence on implementation details before design validation. Look for: specific technology choices made without alternatives analysis, effort estimates for implementation without design-level validation, "how" defined before "whether".

e. **Unresolved conflicts**: FUNDAMENTAL conflicts noted in the Conflict Detection section. Look for: `conflicts:` array in YAML frontmatter, FUNDAMENTAL entries in Conflict Detection section, unresolved disagreements between workers.

f. **High open-question density**: Read the '## Open Questions' section if present. If it contains items (not 'None' or '(All topics addressed, no gaps detected)'), signal is Present with confidence HIGH (≥5 items), MEDIUM (2-4 items), LOW (1 item). For backward compatibility with reports lacking this section, also check Recommendations for 'pending'/'TBD' items as supplementary evidence.

g. **Quality gaps**: Quality is YELLOW or RED, or completeness is below 90%. Look for: `quality: YELLOW/RED` or `completeness: <90` in YAML frontmatter, failed_tasks entries, Quality Review section flagging issues.

h. **Untested assumptions**: Assumptions identified in Self-Challenge sections that remain untested. Look for: Assumption Reversal items with no resolution, Pre-Mortem scenarios not mitigated, Evidence Audit flags without follow-up.

**Important**: This is not a checklist to match mechanically. Read the report holistically and use judgment about which signals are genuinely present. Not every report will have continuation signals — sometimes the work is complete.

### 4. Assess Completion Status

Before presenting options, make an explicit assessment:

- If the report has `status: success`, `quality: GREEN`, `completeness: >=95`, zero conflicts, and no strong continuation signals detected: state "This cmd appears complete. No strong continuation signals detected." Then ask the user if they still want to explore next-round options.

- Detect iteration depth: If the report references prior cmd_ids in Background or Input sections, extract the sequence (e.g., cmd_090 → cmd_101 → cmd_102 implies Round 3). If N > 5, display warning:

  **Warning: Extended iteration detected (Round N)**

  This is round N of exploration. Consider whether additional rounds will produce proportional value. Diminishing returns often appear after 5+ rounds. Review the delta between the last 2 reports to assess progress.

- Otherwise: proceed to Step 5.

### 5. Present Detected Signals

Display detected signals to the user:

```
## Detected Signals for {cmd_id}

| Signal | Status | Confidence | Evidence |
|--------|--------|------------|----------|
| {signal_name} | Present/Absent | HIGH/MED/LOW | {1-line evidence from report} |
| ... | ... | ... | ... |

**Overall assessment**: {1-2 sentence summary of what the signals suggest}
```

Only display signals that are Present or Ambiguous. Omit signals clearly Absent.

### 6. Generate Strategy Options

Present two categories of options:

#### Mechanical Options (always generated)

For each of the four standard strategies, generate a concrete option tailored to the report content:

**Option A: Review** — Critical review of the current output
- Maps to Layer 1 keyword: `"find flaws"` / `"red team"`
- Best when: Quality gaps detected, untested assumptions present, single-paradigm saturation
- Generate: A 2-3 sentence description of what specifically to review, citing specific sections or findings from the report

**Option B: Mutation** — Assumption reversal or alternative exploration
- Maps to Layer 1 keyword: `"challenge assumptions"` / `"explore alternatives"`
- Best when: Implementation-convergence, single-paradigm saturation, simplification-resistant complexity
- Generate: A 2-3 sentence description of which assumptions to challenge or which alternatives to explore, citing specific decisions from the report

**Option C: Deepen** — Deeper investigation of a specific area
- Maps to Layer 1 keyword: (none — this is a scope-narrowing strategy)
- Best when: Zero empirical evidence, high open-question density, specific Issues & Risks flagged as high-impact
- Generate: A 2-3 sentence description of which area to deepen, citing specific gaps or open questions from the report

**Option D: Synthesize** — Cross-cutting synthesis of multiple previous rounds
- Maps to Layer 1 keyword: `"critical challenges"` (comprehensive)
- Best when: Multiple rounds have been completed (check for references to prior cmds), unresolved conflicts between rounds, fragmented findings across tasks
- Generate: A 2-3 sentence description of what to synthesize, citing which round outputs or task findings need integration

#### Creative Options (LLM-generated, context-specific)

After the mechanical options, generate 1-3 creative options that are **specific to this report's content**. These must not be restatements of the mechanical options.

Use the following internal reasoning process (do not display this to the user):

```
Given the report content for {cmd_id}:
1. What is the most important gap or missed opportunity in this work?
2. What would an expert in this domain suggest as a non-obvious next step?
3. What question, if answered, would most change the conclusions?

Generate 1-3 concrete, actionable options. Each must:
- Reference specific content from the report (section names, finding numbers, task outputs)
- Propose a concrete deliverable (not "explore more" but "build X to test Y")
- Include a brief rationale (1 sentence explaining why this matters)
```

Display creative options as:

```
#### Creative Options

**Option E: {title}**
{2-3 sentence description referencing specific report content}
Rationale: {why this matters}

**Option F: {title}**
{2-3 sentence description}
Rationale: {why this matters}
```

### 7. User Selection

After presenting all options, prompt the user:

```
Select an option (A/B/C/D/E/F), modify one, or describe a custom direction:
```

The user may:
- Select a letter (e.g., "B")
- Modify an option (e.g., "B but focus only on the caching design")
- Provide a completely custom direction (e.g., "I want to test the performance claims with benchmarks")

### 8. Generate request.md

Based on the user's selection, generate a complete `request.md` file.

**Output location**: Print the generated content and ask the user where to save it. Suggest: `work/cmd_{NEXT}/request.md` (where NEXT is the next cmd number, or prompt user to run `new_cmd.sh` first).

**request.md template**:

```markdown
# Request: cmd_{NEXT}

## Purpose

{1-2 sentence purpose derived from the selected strategy}

## Background

This is a continuation of {cmd_id}. The previous round produced:
- **Status**: {status from report YAML}
- **Quality**: {quality from report YAML}
- **Key outcome**: {1-sentence summary from Executive Summary}

Previous report: `{report_path}`

### Continuation Signal

{Description of the signal(s) that motivated this round, with evidence from the report}

## Task

{Detailed task description, 3-8 sentences, specific to the selected strategy}

{If strategy is "review" or "mutation", include Layer 1 keyword naturally:}
{Example: "Conduct adversarial review to **find flaws** in the current design."}
{Example: "**Challenge assumptions** underlying the caching layer decision."}
{Example: "**Explore alternatives** to the current authentication approach."}

## Input

- `{report_path}` — Previous round's aggregated report
- {Any specific result files referenced in the strategy}

## Constraints

- Do not re-do work already completed successfully in {cmd_id}
- Focus on {specific area from the strategy}
- {Any additional constraints from the user's modifications}

## Success Criteria

{2-4 concrete, measurable criteria for what "done" looks like}
```

### 9. Final Instructions

After generating request.md, display:

```
## Next Steps

1. Create a new cmd directory: `bash scripts/new_cmd.sh`
2. Save the request.md to the new cmd's directory
3. Start the crew workflow with the new request

{If --dry-run was used: "Dry run complete. No files were generated."}
```

## Error Handling

- **File not found**: Report error and stop. Do not guess paths.
- **Not a report.md**: If file lacks YAML frontmatter with `cmd_id`/`status`/`quality` fields, warn: "This does not appear to be a crew report.md. Proceed anyway? [y/N]"
- **Report with status:failure**: Warn: "The previous round failed. Consider reviewing failure causes before planning next round." Then proceed normally (failure reports often have the richest continuation signals).
- **Report from non-design cmd**: Proceed normally. Signal detection is content-based, not cmd-type-based.
- **Empty Recommendations section**: Note that the previous round did not produce follow-up recommendations. Rely more heavily on Issues & Risks and Self-Challenge sections for signal detection.

## File Structure

```
.claude/skills/next-round/
  SKILL.md       # Complete skill definition (this file)
```

No additional files needed. No scripts, no config files, no defaults YAML.
