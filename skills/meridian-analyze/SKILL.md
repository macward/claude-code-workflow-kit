---
name: meridian-analyze
description: "Consistency gate between /meridian-task-breakdown and /meridian-run-plan: every SDD section has a task, no task contradicts the SDD (blocking), and parallel tasks don't overlap on writes (informative). Read-only."
---

# Meridian Analyze

Cross-checks a feature's SDD against the tasks derived from it, **before** `/meridian-run-plan` starts writing code.

Usage: `/meridian-analyze <feature-slug>` (no argument: the feature of the pending tasks, if there is only one)

## Why it exists

Breakdown and run are separated by a context boundary: whoever implements task 004 doesn't re-read the whole SDD, they read their task. If that task fell outside the spec — or a spec section landed in no task — nothing downstream catches it: `/meridian-solve-task` verifies *the task's* acceptance criteria, and `/meridian-review-pr` arrives once the code is written.

This is the only point in the pipeline where the plan is still cheap to fix: moving a task costs one call, moving code costs a run.

## Hard prohibitions

- Don't create or modify tasks. No `create_task`, no `update_task`, no `add_task_dependency`.
- Don't create or modify documents.
- Don't implement anything, don't touch git.

This skill produces **a report** and ends. Corrections are decided by the human (or by re-running the breakdown).

## Setup

Read from CLAUDE.md: `meridian-project: <project>`.

Resolve the feature:
- **With argument** → that slug.
- **Without argument** → `list_tasks(project, status=["pending", "in-progress"])` and look at the `feature` field. If all open tasks belong to a single feature, that's it. If there is more than one, **stop** and ask for the slug: analyzing two mixed features produces false orphans by the dozen.

## Process

### 1. Load the artifacts

```
mcp__meridian__list_docs(project=<project>, folder="specs", feature=<slug>)
mcp__meridian__read_doc(project=<project>, folder="specs", filename="sdd-<slug>.md")
mcp__meridian__list_tasks(project=<project>, feature=<slug>, status=["pending", "in-progress", "blocked", "done"])
```

If there is no SDD for the feature, end by saying so: without a spec there is no criterion to check against, and guessing one is worse than not running the gate. Suggest `/meridian-spec`.

Read the full body of every task with `get_task` — the consistency check needs `goal`, `changes_required`, `constraints` and `scope`, which the listing doesn't carry.

For edges, `get_task_dependencies(project, task_id)` per task: `depends_on` is what defines which tasks are **sequential**; those with no edge between them are the candidates to run in parallel, and the only ones where overlapping `writes` means anything.

### 2. Check A — Coverage (gate)

For every normative SDD section — `Surface`, `Architecture`, and every decision under `Design decisions` that implies a change — verify at least one task covers it.

A covered section is one that appears in some task's `goal` or `changes_required`, not one "inferred" from a similar title. When in doubt, report it as weak coverage, not as covered.

The SDD's `Non-goals` are the opposite: if a task covers something listed there, that's a check B finding, not coverage.

### 3. Check B — Consistency (gate)

For every task, verify it doesn't contradict the SDD:

| Class | What to look for |
|---|---|
| Direct contradiction | The task does X, the SDD says Y |
| Non-goal invaded | The task covers something explicitly listed under `Non-goals` |
| Orphan | The task can't be traced to any SDD section |
| Lost constraint | The SDD imposes an invariant (auth, ceiling, "don't touch Z") that the task for that area doesn't mention in `constraints` |

An orphan isn't always an error — it may be legitimate work outside the spec — but it has to be a conscious decision, which is why it's reported.

### 4. Check C — `writes` overlap (informative)

Compare the `writes` field of every pair of tasks **with no dependency edge between them** (neither direct nor transitive). A path appearing in both is an overlap.

**This check blocks nothing.** It's reported in its own section, marked informative, and an overlap doesn't turn a clean report into a blocked one.

**Why it doesn't block.** The check depends entirely on the recall of `writes`, and `writes` has no measurement yet: the only available figure (23% precision / 22% recall) is from the old `context_refs` field, which declared reads, not writes. A gate built on an uncalibrated signal rejects correct plans and approves plans that do collide. The measurement is accumulating downstream: the close of `/meridian-solve-task` compares the paths the commit touched against the declared `writes` and reports the divergence, task after task. Only with that recall in view is it decided whether this check moves from informative to gate — hardening it earlier skips the one step that would justify it.

Tasks with no declared `writes` (`[]` or absent) are reported separately as **not comparable**. They are not "no overlap": they are tasks the check says nothing about, and confusing the two is exactly the false green this section wants to avoid.

### 5. Report

```
## Analyze — <feature-slug>
_<date>_

VERDICT: <PASS | BLOCKED>

### Coverage (gate)
<N>/<M> SDD sections with a task
- [ ] <section> — no task
- [~] <section> — weak coverage: <why>

### Consistency (gate)
- <NNN-task> — <class>: <what it contradicts, quoting the SDD>

### Writes overlap (informative — doesn't block)
- <NNN-a> ∥ <NNN-b> — share `<path>`
- No writes declared: <NNN-x>, <NNN-y> (not comparable)

### Suggested actions
- <what would need fixing, without executing it>
```

Verdict rules:

- `BLOCKED` if there is **any** coverage or consistency finding. Those are the two checks that block.
- `PASS` if both are clean, **even with overlaps**. Block C never moves the verdict; if it did, it would be a gate, which is exactly what this SDD says it can't yet be.
- A `PASS` with overlaps is reported as `PASS` with section C populated — not silenced.

The analysis is heuristic: findings are "review this", not verdicts. A `BLOCKED` the human dismisses with a reason is a valid gate outcome; what isn't valid is the gate not having looked.
