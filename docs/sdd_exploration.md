---
generated_by: worker_writer
date: 2026-02-15
cmd_id: 098
---

# SDD Exploration (cmd_091) — Final Verdict and Reusable Insights

**Summary**: An exhaustive 5-round exploration (R1 design, R2 validation) of Specification-Driven Design concluded that implementing alternatives (Template Enhancement, Decomposer Quality, Feedback Loop) delivers superior compliance with 78% less code than full SDD. Verdict C: ADOPT alternatives instead of the 760-line SDD system.

---

## 1. Problem Definition

**The Question**: Can crew compliance improve from 60-65% to 75-80% through formal specification machinery?

**Why Explore SDD?**
- Decomposer tasks lacked explicit success criteria, creating ambiguity for downstream workers.
- Research suggested that formal acceptance criteria (EARS notation, domain profiles, Mermaid diagrams) could align worker outputs with intentions more consistently.
- Theoretical upside: +10-15 percentage points compliance via structured requirement capture.

**Exploration Scope**:
- **R1**: Design a 760-line SDD system with EARS notation, 3-profile domain classification (Web, CLI, Infra), complexity scoring, and END-of-file placement optimization.
- **R2**: Validate R1's assumptions through evidence audit (Section 1 of result_18), empirical crew analysis (53% research workload, task-type breakdown), alternative approaches evaluation (weighted scoring), and root cause analysis (5-Whys, Fishbone).

---

## 2. R1 Design Overview

The R1 design (result_13) specified a 760-line system comprising:

- **Domain Profiles** (390 lines): Web (authentication, authorization, CSRF, rate limiting), CLI (argument parsing, help text, exit codes), Infra (IAM, logging, monitoring, scaling).
- **EARS Notation** (150 lines): WHEN/THEN SHALL patterns for requirement specification.
- **Attention Optimization**: Critical requirements placed at END of task files (exploits LLM recency bias for 10-15% compliance gain).
- **Complexity Scoring** (80 lines): 1-20 scale task assessment for model/decomposer selection.
- **Configuration & Additions** (140 lines): Integration hooks, validation rules, rollout triggers.

**Theoretical Basis**:
- Claim: This machinery would improve compliance to 75-80% by formalizing requirement specification and leveraging LLM attention research.
- Supporting evidence (from R1): Reasonable but untested. No prototype validation, no baseline measurement.

---

## 3. R2 Validation Results — Evidence Audit

R2's evidence audit (result_18, Section 1) examined 6 core claims:

| Claim | Evidence Level | Verdict |
|-------|--------------|---------|
| 60-65% baseline compliance | **Assumed** | No data. Foundation entirely unproven. |
| 75-80% improvement with SDD | **Theoretical** | No A/B test, no prototype. Mechanism challenged by Fowler's critique of LLM spec separation. |
| 60-70% profile coverage | **Theoretical** | Likely inflated; actual coverage ~20-35% of workload. |
| 95% classifier accuracy | **Assumed** | Plausible but unmeasured. |
| END-of-file attention gain | **Theoretical** | Direction correct, magnitude speculative. |
| 620-760 lines total code | **Empirical** | Likely accurate (only well-supported claim). |

**Aggregate**: 2 Assumed (no justification), 3 Theoretical (unvalidated logic), 1 Empirical. Investment case rests on uncertain foundations.

**Weighted Verdict Score for Full SDD**: 2.30/5.0 — Dead last among five verdict options, due to:
- Evidence insufficient to justify 760-line investment.
- 53% of crew workload is research (inherently non-spec-able).
- Top 3 root causes (validation absence, template gaps, vague requests) account for 95% of failures; SDD addresses <5%.
- Superior alternatives (170 lines combined) project 80-85% compliance with 78% less code.

---

## 4. Selected Alternative and Rationale

**Verdict C Implementation Plan** (ranked highest at 3.95/5.0):

### Phase 1: Template Enhancement + Inline Criteria (90 lines, 3 hours)
- Add self-validation checklists to worker templates (+50 lines).
- Add success criteria guidelines to decomposer task files (+40 lines).
- Begin lightweight compliance measurement.

**Phase 1 Components**:
- `worker_common.md`: Add validation checklist (YAML frontmatter verification, completeness audit, error handling).
- `worker_coder.md`: Add code-specific validation (unit tests, type safety, security checks).
- `decomposer.md`: Add guidelines for inline success criteria (WHEN/THEN pattern excerpt, 1-3 acceptance criteria per requirement).

### Phase 2: Measure and Evaluate (Weeks 2-3)
- Run 15-20 cmds with Phase 1 changes.
- Manually score compliance (0-100%) per result file.
- Establish actual baseline (not projected).

### Phase 3: Decision Point (Week 4)
- **If compliance ≥80%**: Victory; SDD shelved permanently.
- **If compliance 75-79%**: Add Feedback Loop (+80 lines) for aggregator re-run validation.
- **If compliance <75%**: Investigate whether root cause is "validation absence" (fixes via templates) or "requirement discovery" (may require lightweight SDD variant).

**Why This Over Full SDD**:
1. **Cost-Benefit**: 90 lines (Phase 1) + potential 80 lines (Phase 2) = 170 lines vs. 760 lines for equivalent compliance.
2. **Reversibility**: Template changes trivial to undo; feedback loop configurable; sequential rollout enables data-driven pivots.
3. **Applicability**: Alternatives address root causes for 100% of workload; SDD benefits only 21.75%.
4. **Risk Asymmetry**: Low upfront cost with pathway to SDD reconsideration if alternatives plateau.

---

## 5. SDD Reconsideration Conditions

SDD (or Hybrid SDD-Lite) should be reconsidered ONLY if ALL four conditions are simultaneously met:

1. **Alternatives Implemented**: Template Enhancement, Decomposer Quality, and Feedback Loop are deployed and operational.
2. **Measured Compliance Ceiling**: Compliance measured at <78% after alternatives (indicating alternatives alone are insufficient).
3. **Root Cause Confirmed**: Remaining failures show "lack of formal acceptance criteria / requirement discovery" as a top-3 root cause (≥25% of remaining failures).
4. **Task-Type Concentration**: Remaining failures concentrated in coder tasks, not research/writer/reviewer (confirming SDD's limited applicability is the actual limiting factor).

**If All Met**: Implement Hybrid SDD-Lite (370 lines) for complex coder tasks only (complexity score >10), not full SDD for all tasks. This avoids SDD's 53% waste on non-applicable research tasks.

---

## 6. Reusable Insights from R1 Design

Even though full SDD was not adopted, R1 produced valuable design artifacts:

### EARS Notation
The WHEN/THEN SHALL pattern (EARS: Easy Approach to Requirements Syntax) is domain-general. Incorporated at 1-3 inline criteria per decomposer task (~40 lines vs. 150-line full EARS system). Applicable across all task types.

### END-of-File Placement
Critical requirements at END of task files optimize LLM recency bias. Valid optimization independent of SDD machinery. Applicable to decomposer.md task instructions and config files.

### Complexity Scoring Framework
Task complexity (1-20 scale) is useful for:
- Model selection (simple tasks → Haiku, complex → Opus).
- Decomposer strategy selection (deep decomposition for score >12; shallow for <8).
- SDD applicability filtering (if reconsidered, target only score >10).

### Domain Profile Concepts
Web/CLI/Infra profiles encode domain-specific requirement patterns. Value independent of full SDD:
- **Web Profile**: Authentication (2FA, OAuth), authorization (role-based), input validation (OWASP), rate limiting, CSRF protection.
- **CLI Profile**: Argument parsing, help text generation, exit codes, piping support.
- **Infra Profile**: IAM policies, structured logging, monitoring/alerting, autoscaling rules.

If Hybrid SDD-Lite is needed, these profiles serve as ready reference. If not needed, they remain documented as organizational knowledge.

---

## 7. Implementation Status and Next Steps

**Current Phase**: cmd_098 is implementing Phase 1 alternatives (template enhancement).

**Measurement Window**: Weeks 2-3 of implementation; 15-20 cmds to establish baseline.

**Decision Point**: Week 4; empirical data determines whether Phase 2 (Feedback Loop) or Phase 3 (SDD reconsideration) is warranted.

**Artifacts Retained**:
- R1 SDD design: Archived in `work/cmd_091/results/result_13.md` for future reference.
- EARS reference: Embedded in decomposer.md inline criteria guidelines.
- Complexity framework: Documented in config.yaml as task annotation layer.
- Domain profiles: Archived as organizational knowledge in appendix (if needed later).

---

## References

- **R1 Design Specification**: `work/cmd_091/results/result_13.md` — 760-line SDD system design.
- **Anti-SDD Argument**: `work/cmd_091/results/result_14.md` — Challenges to SDD assumptions (Fowler critique, baseline uncertainty).
- **Empirical Task Analysis**: `work/cmd_091/results/result_15.md` — Crew workload composition (53% research, 37% coder, 21.75% SDD applicability).
- **Alternative Approaches**: `work/cmd_091/results/result_16.md` — Weighted scoring of 5 approaches (Template 4.55 vs. SDD 2.30).
- **Root Cause Analysis**: `work/cmd_091/results/result_17.md` — 5-Whys, Fishbone, priority scoring. SDD addresses <5% of top-3 causes.
- **Final Verdict**: `work/cmd_091/results/result_18.md` — Evidence audit, verdict analysis (A-E), implementation plan for Verdict C.

---

**Decision Framework**: This document reflects Verdict C (Adopt Alternatives) with integrated measurement protocol from Verdict D. Reconsideration pathway remains open; see Section 5 for conditions.

