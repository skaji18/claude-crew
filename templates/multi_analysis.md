# Multi-Analysis — N-Viewpoint Parallel Analysis Framework

You are using a multi-analysis decomposition pattern. This template guides the decomposer in breaking a request into N independent analytical viewpoints, executing them in full parallel with the researcher persona, and synthesizing via the aggregator.

## When to Use

Apply this framework when the request involves:
- **Comparison analysis**: Evaluating multiple options, technologies, or strategies
- **Market research**: Investigating a market from multiple angles (competitors, trends, regulations, etc.)
- **Technology selection**: Assessing candidates across independent criteria
- **Risk evaluation**: Analyzing risks from different domains (technical, financial, legal, operational)
- **Feasibility study**: Examining feasibility from multiple independent perspectives

**Key indicator**: The request can be decomposed into 3–10 independent analytical axes where each axis produces useful findings on its own.

## Framework Structure

### Step 1: Define Viewpoints (Decomposer Phase)

Identify N independent viewpoints (3–10) from the request. Each viewpoint must satisfy:

| Criterion | Description |
|-----------|-------------|
| **Independence** | The viewpoint can be researched without results from other viewpoints |
| **Specificity** | The viewpoint has a clear, bounded scope |
| **Contribution** | The viewpoint contributes a distinct dimension to the overall analysis |
| **Researchability** | Sufficient information can be gathered within a single worker task |

**Viewpoint definition format** (include in each task file):

```markdown
## Viewpoint
- **Axis**: [Name of the analytical axis, e.g., "Cost Analysis"]
- **Scope**: [What to investigate, boundaries]
- **Key Questions**: [2-4 specific questions to answer]
- **Expected Output**: [Type of findings — data, recommendations, risk list, etc.]
```

### Step 2: Task Decomposition Rules

1. **One viewpoint = One task**. Do not merge viewpoints.
2. **All tasks use `worker_researcher` persona**. No exceptions.
3. **All tasks belong to the same Wave** (no dependencies between viewpoints). This enables full parallel execution.
4. **Each task receives identical context**: the original request and any shared reference materials.
5. **Weighted Scoring is mandatory** when the viewpoint involves comparison (per worker_researcher.md rules).
6. **Output follows standard result format** (`results/result_N.md` with YAML frontmatter).

### Step 3: Aggregator Integration Guidelines

The aggregator synthesizes all viewpoint results into a unified report. It must:

1. **Cross-reference findings**: Identify agreements and contradictions across viewpoints.
2. **Resolve contradictions**: When viewpoints disagree, document both perspectives and provide a reasoned resolution (or flag for human review if irreconcilable).
3. **Derive comprehensive judgment**: Combine per-viewpoint findings into an overall assessment. Use a synthesis matrix when applicable:

| Viewpoint | Key Finding | Supports Overall Conclusion? | Notes |
|-----------|-------------|:---:|-------|
| Viewpoint 1 | ... | Yes / No / Partial | ... |
| Viewpoint 2 | ... | Yes / No / Partial | ... |

4. **Preserve nuance**: Do not flatten conflicting data into false consensus. Report uncertainty where it exists.
5. **Quality Review**: Apply standard aggregator Quality Review (Consistency, Evidence, Task compliance).

## Sample Decomposition

### Request Example

> "Evaluate whether to adopt Framework X vs Framework Y for our backend rewrite."

### Viewpoint Decomposition

| # | Viewpoint (Axis) | Key Questions | Persona | Model | Depends On |
|---|------------------|---------------|---------|-------|------------|
| 1 | Performance & Scalability | Benchmark data? Horizontal scaling? Memory footprint? | worker_researcher | haiku | - |
| 2 | Developer Experience | Learning curve? Documentation quality? Tooling ecosystem? | worker_researcher | haiku | - |
| 3 | Community & Ecosystem | GitHub stars trend? Package ecosystem size? Corporate backing? | worker_researcher | haiku | - |
| 4 | Cost & Licensing | License type? Hosting cost implications? Vendor lock-in? | worker_researcher | haiku | - |
| 5 | Migration Risk | Breaking changes history? Compatibility with current stack? Migration effort? | worker_researcher | haiku | - |

### Resulting plan.md Structure

```markdown
## Execution Order
- Wave 1 (parallel): Tasks 1, 2, 3, 4, 5

## Risks
- Viewpoints may produce conflicting recommendations (resolved by aggregator)
- Some viewpoints may have limited publicly available data
```

### Task File Example (Task 1)

```markdown
# Task 1: Performance & Scalability Analysis

## Viewpoint
- **Axis**: Performance & Scalability
- **Scope**: Runtime performance benchmarks, horizontal/vertical scaling characteristics, memory and CPU profiles for Framework X vs Framework Y
- **Key Questions**:
  1. What do published benchmarks show for request throughput and latency?
  2. How does each framework handle horizontal scaling?
  3. What is the typical memory footprint under load?
- **Expected Output**: Comparative data with weighted scoring

## Input
- [Original request file path]
- [Any shared reference materials]

## Output
- **RESULT_PATH**: `work/cmd_xxx/results/result_1.md`
- ⚠️ Writing to this file is **MANDATORY**.

## Recommended Persona
worker_researcher

## Recommended Model
haiku

## Details
Research performance characteristics of both frameworks. Use weighted scoring to compare (per worker_researcher rules). Cite all benchmark sources.
```

## Model Selection for Multi-Analysis

| Condition | Recommended Model |
|-----------|-------------------|
| Straightforward factual research per viewpoint | haiku |
| Viewpoint requires multi-step reasoning or synthesis | sonnet |
| Viewpoint involves novel/complex architectural judgment | opus |

Default to **haiku** for most multi-analysis viewpoints. The aggregator typically uses **sonnet** (set by the parent, not by this template).

## Limits

- **Minimum viewpoints**: 3 (fewer than 3 does not justify this framework — use a single researcher task instead)
- **Maximum viewpoints**: 10 (more than 10 risks exceeding max_parallel and diluting focus)
- **If viewpoints are not independent**: Do not use this framework. Use sequential Wave decomposition with dependencies instead.
