# /lp-check -- Process LP signals from current session

Review the current conversation for LP signals (user corrections, repeated
specifications, rejections, afterthought supplements). If signals are found,
accumulate them into the LP signal log and generate candidates if thresholds
are met.

## Steps

0. Read `docs/lp_rules.md` (LP normative rules, ~40 lines).

1. Search Memory MCP for existing LP state:
   - mcp__memory__search_nodes(query="lp:_internal:signal_log")
   - mcp__memory__search_nodes(query="lp:")

2. Analyze the current conversation for LP signals using semantic analysis.
   Apply the signal types and weights from `docs/lp_rules.md`.

3. If signals found:
   a. Merge into signal_log (temporal independence check applies)
   b. Check thresholds (counter >= 3.0)
   c. If threshold reached: distill LP candidate (what/evidence/scope/action)
   d. Present candidates to user for approval (Y/n/edit)
   e. On approval: write to Memory MCP

4. If no signals: report "No LP signals detected in this session."

## Notes

- This skill reads the conversation context, not result files.
- Same quality guardrails apply (absolute quality filter).
- Same N>=3 accumulation rule applies.
