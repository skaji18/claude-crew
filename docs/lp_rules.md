# LP Normative Rules (Agent Reference)

> Source of truth for LP rules. If templates or guides conflict, this file wins.
> User-facing guide: docs/learned_preferences.md

<!-- This file MUST stay under 60 lines. Move explanations to docs/learned_preferences.md. -->

## Principles
1. Silent application: Do not announce LP use during work. Exception: direct user question.
2. Default not forced: Task instructions override LP.
3. Absolute quality immutable: correctness, completeness, security, safety, test coverage -- LP NEVER compromises these.
4. Change permitted: LPs can be updated/deprecated via contradiction signals.
5. Approval required: All LP candidates require human approval before MCP storage.

## Signal Types
| Type | Weight |
|------|--------|
| Course Correction | 1.0 |
| Afterthought Supplement | 0.7 |
| Rejection/Revert | 1.0 |
| Repeated Specification | 0.7 |

## Threshold
Counter >= 3.0 from independent sessions (2+ hours apart or different task types).
Explicit declaration ("always X", "never Y") bypasses to 3.0.

## Entity Format
Name: `lp:{cluster}:{topic}`
Observation: `[what] tendency [evidence] basis [scope] condition [action] directive`

## Clusters
vocabulary, defaults, avoid, judgment, communication, task_scope

## Quality Guardrails
- IMMUTABLE (absolute): correctness, completeness, security, safety, test coverage
- ADJUSTABLE (relative): code style, design patterns, doc depth, communication, tool choice
- Ambiguous case: treat as absolute.

## Forbidden Categories
Emotions, personality, work schedule, productivity metrics, health, politics, relationships, finances.
