---
name: meridian-task-breakdown
description: "Break a feature or body of work into structured Meridian tasks, reading the SDD/requirements if present. Follows /meridian-spec; leads into /meridian-solve-task or /meridian-run-plan."
---

# Task Breakdown

Turns a feature or request into structured, actionable tasks.

```
requirements / spec → [task-breakdown] → solve-task / run-plan
```

## Philosophy

A good task is:

- **Small** — **30–90 minutes** of focused work. Longer means several tasks.
- **Concrete** — what changes, where, how it's verified.
- **Verifiable** — acceptance criteria the implementer can check unambiguously.
- **Bounded** — a single objective. A title with "and" is two tasks.
- **With minimal sufficient context** — references, patterns to follow, relevant files.

**Hard rule:** *a task must not require new architectural decisions.* If it would force deciding architecture, contracts, ownership or policy, that decision belongs in the SDD — pause the breakdown and go back to the SDD.

**YAGNI:** if it isn't in the SDD/requirements, don't invent the task.

## When NOT to use this skill

- Trivial change (one line, rename, obvious fix) — implement directly.
- Research or exploration with no clear deliverable — use conversation, not tasks.
- Feature not yet clear — generate requirements / an SDD first.
- The SDD has contradictions, gaps or undecided points — go back to the SDD first.

## Prerequisites

Meridian with: `list_tasks`, `create_task`, `update_task`, `add_task_dependency`, `get_task_dependencies`, `list_features`, `create_feature`, `get_feature`, `save_use_cases`, `update_doc`, `read_doc`, `list_docs`. If not connected, warn and stop. Always through these tools — never write tasks any other way.

## Before starting

1. **Active workspace**: read `meridian-project: <project>` from CLAUDE.md.

2. **Resolve the feature slug** with `mcp__meridian__list_features(project=<project>)`:
   - A matching feature exists → use its slug.
   - None matches → create it: `mcp__meridian__create_feature(project=<project>, name=<name>, slug=<slug>)`.
   - Miscellaneous work → `"misc"`.

3. **Re-link the discovery docs to the feature.** Requirements and spec run before the feature entity exists, so their docs were saved unlinked. Two slugs: `<slug>` is the one in the doc filenames, `<feature-slug>` the entity's from step 2 — they differ when the feature is `"misc"`.

   ```
   mcp__meridian__update_doc(project=<project>, folder="requirements", filename="requirements-<slug>.md", feature=<feature-slug>)
   mcp__meridian__update_doc(project=<project>, folder="specs", filename="sdd-<slug>.md", feature=<feature-slug>)
   ```

   - **Metadata-only**: never pass `content`, `find` or `replace` — the body stays intact. Idempotent.
   - `DocumentNotFoundError` → the doc doesn't exist; **skip silently**.
   - `FeatureNotFoundError` → **anomalous** (step 2 just resolved it): stop and warn before creating tasks.

4. **Show the feature's existing tasks** with `mcp__meridian__list_tasks(project=<project>, feature=<feature-slug>)`. If there are any, show them and ask whether to **extend them** (the default) or replace them. Never create duplicates silently.

5. **Read the prior docs** if they exist: `requirements/requirements-<slug>.md`, `specs/sdd-<slug>.md`. Ambiguities or contradictions → **pause and ask**. Don't invent interpretations.

6. **Materialize the requirements' scenarios as use cases**, so tasks can declare coverage (step 3.7). Mapping fixed by `meridian-requirements`:

   | Scenario | `items` field |
   |---|---|
   | the `### A — <group>` heading | `list_title` (one list per group) |
   | the `#### A1 — <name>` heading, ID included | `title` |
   | **Actor** | `actor` |
   | **Given** | `situation` |
   | **When** | `action` |
   | **Then** | `expected_output` |

   **Read first, never save blind** — `save_use_cases` creates every item without a `ref`, so a re-run would duplicate every case:

   ```
   mcp__meridian__get_feature(project=<project>, slug=<feature-slug>, include_use_cases=True)
   ```

   **Match by scenario ID, not title**: if a case whose title starts with the same ID (`A1 — `) exists, send its `ref` so it updates in place (a renamed scenario updates its case). Only unmatched IDs go without `ref`. One call per group:

   ```
   mcp__meridian__save_use_cases(
     project=<project>,
     feature=<feature-slug>,
     list_title="A — <group name>",
     items=[{"title": "A1 — <name>", "actor": ..., "situation": ..., "action": ..., "expected_output": ...}, ...],
   )
   ```

   - A requirements doc without scenario IDs has no groups: one list titled `Scenarios`, matched by full title.
   - **Never pass `replace=True`**: it would delete hand-added cases and their coverage.
   - **Save the `ID → ref` map** (`A1 → UC-4`) from the responses — steps 2 and 3.7 need it.
   - **Skip silently** when there's no requirements doc, it has no scenarios, or the feature is `"misc"`.

## Process

### 1. Analyze the request

- **What**: one sentence with the feature's goal.
- **Scope**: modules/files affected (from the SDD if it exists — don't re-ask what it already says).

If the request is ambiguous, **a single** clarifying question (prefer multiple choice).

### 2. Propose the task graph

Before creating anything, show the graph:

```
Proposed task graph:

001 — <task 1 title>                              [covers: A1]
002 — <task 2 title>  (depends_on: 001)           [covers: A2, B1]
003 — <task 3 title>  (depends_on: 001)
004 — <task 4 title>  (depends_on: 002, 003)      [covers: B2]

Uncovered: none
Create these tasks? ok | adjust
```

- **Design:** what can run in parallel, what blocks what, one responsibility and one work session per task. Each bullet of the SDD's "Architecture" section is usually 1–2 tasks.
- **Numbering:** `NNN-` prefix, three digits, from `001` or continuing the feature's last number — `meridian-solve-task` resolves tasks by it. **Keep it topological**: no edge may point to a higher number; if one does, renumber now.
- **Cycles:** check for them here. Meridian only rejects self-deps and direct `A ↔ B` cycles; a longer chain (`A → B → C → A`) goes in silently.
- **Coverage** (when step 6 materialized use cases): a task covers a scenario when, once it's `done`, that scenario's **Then** holds. Show it by scenario ID. Not every task covers one, but every case should be covered by some task; list the rest under `Uncovered:` — a missing task or a scenario the feature won't deliver, and both are the user's call.

**Wait for explicit confirmation** before step 3. On adjustments, revise and show it again.

### 3. Create the tasks

**Create in topological order** (the `NNN-` order from step 2): each task's edges are declared in its own `create_task`, and `depends_on` only resolves against tasks that already exist.

```
create_task(
    project=<project>,
    title="NNN-<verb + concrete object>",
    feature=<feature-slug>,

    goal="<1-3 paragraphs: what to achieve and why>",

    scope_includes=[
        "what it DOES include 1",
        "what it DOES include 2",
    ],
    scope_excludes=[
        "what it does NOT include 1",
        "what it does NOT include 2",
    ],

    context_refs=[
        "SDD: sdd-<slug>.md",
        "Requirements: requirements-<slug>.md",
        "Files: src/path/to/file.py",
    ],
    context_patterns=[
        "use X as reference",
        "replicate Y's behavior",
    ],

    writes=[
        "src/path/to/file.py",
        "tests/test_file.py",
    ],

    depends_on=["001", "002"],

    changes_required=[
        "concrete change 1",
        "concrete change 2",
    ],

    acceptance_criteria=[
        "verifiable condition 1",
        "verifiable condition 2",
    ],

    constraints=[
        "don't break compatibility with X",
        "don't add dependencies",
    ],

    validation="Executable command(s) that prove it's done: `uv run pytest tests/test_x.py`, `curl -f localhost:8000/health`.",
)
```

**Save each returned `task_id`** in a map `NNN-<title> → task_id` — steps 3.5, 3.6 and 3.7 work with UUIDs.

A `depends_on` reference that resolves to no task, matches several, or forms a direct cycle **fails the whole call and creates nothing**. It's a defect of the graph or the creation order: fix that before calling again, don't retry blindly.

**Rules per field:**

- **title**: `NNN-` + verb + concrete object. "001-add-compose-path-validation", not "001-compose-stuff".
- **goal**: what and why, 1–3 paragraphs. No implementation steps.
- **scope_includes / scope_excludes**: prevent scope creep. `excludes` matters even when it seems obvious.
- **context_refs**: the **read** axis — real repo or doc paths. A task that needs the SDD references it here.
- **context_patterns**: existing modules to follow ("use file_tools._validate_path"), so the implementer doesn't reinvent patterns.
- **writes**: **mandatory** — the **write** axis: repo-relative paths the task creates or modifies (a file both read and modified goes in both). It shows which tasks collide on the same file. **Max 20 paths**; more means the task must be split. No absolute paths or `..`. Declarative: a path that doesn't exist yet is valid.
- **depends_on**: the tasks blocking this one — `NNN-` prefix within the feature, UUID for a task in another feature.
- **changes_required**: concrete changes, not steps. "add `_validate_compose_path`", not "think about validation".
- **acceptance_criteria**: falsifiable conditions. "tests pass for case X" > "code works". **Never compare against a prior state** ("same as before", "still covers", "went down by 4") — that state won't exist when verifying. Convert:
  - **Parity** → a test freezing the old behavior, written **before** the change: an item in `changes_required` ("write the parity test for X **before** touching Y"), named in `validation`.
  - **Numeric delta** → a versioned absolute literal ("the surface ends at 41", with the number in the repo).
- **constraints**: real invariants only. Omit if there are none.
- **validation**: **quasi-mandatory and executable** — commands the implementer can run (`uv run pytest ...`, `curl -f ...`, `npm run type-check`). Prose only when the criterion genuinely isn't automatable, saying *what* to inspect. Omitting it needs a justification. Validation is the *method*; acceptance, the *conditions*.

**Empty sections are omitted** — no "N/A" or placeholders.

**Forbidden:**

- Code in any field.
- Architectural decisions in `changes_required` ("decide whether to use X or Y") — stop and go back to the SDD.
- More than ~5 items in `changes_required` or `acceptance_criteria` — the task is probably too big.
- Parity or delta criteria without the prior test or versioned literal that makes them verifiable.

### 3.5 Fallback: edges that couldn't be declared at creation

**Normally a no-op.** Use it only for: an edge to another feature's task that didn't exist yet at creation; a graph that changed after creating the tasks (including linking old tasks to new ones); or an approved edge that step 3.6 found missing. Within a feature, a backward edge isn't a case for this — renumber in step 2.

One call per edge, **UUIDs only** (never `NNN-`):

```
mcp__meridian__add_task_dependency(
    project=<project>,
    task_id=<uuid of the waiting task>,
    depends_on_id=<uuid of the blocking task>,
)
```

**Mind the direction:** `task_id` waits, `depends_on_id` must be `done` first. `002 (depends_on: 001)` → `task_id=<002>, depends_on_id=<001>`.

- Repeating an existing edge is a no-op — the step is re-runnable.
- **`CircularDependencyError`** (self-dep or direct cycle) → a graph defect: stop, show the user the two tasks, fix the graph. Don't retry.

### 3.6 Verify the graph against the approved one

Verify against Meridian, not against the intention — one call per created task:

```
mcp__meridian__get_task_dependencies(project=<project>, task_id=<uuid>)
```

It returns `depends_on` (what blocks it) and `dependents` (what it unblocks), each with `task_id`, `title` and `status`. Compare the edge set against the one approved in step 2, regardless of whether each edge came from step 3 or 3.5.

Match → one line, then step 3.7:

```
Dependencies: 5/5 verified.
```

Mismatch → **say so explicitly, never continue silently** (a plan without its edges still runs, as an unstructured sequence):

```
⚠ Incomplete graph: 5 edges approved, 3 created.
   Missing: 004 → 002, 004 → 003.
   Create them, or did the graph change?
```

An edge with inverted direction shows up as one missing plus one extra between the same two tasks.

### 3.7 Declare and verify coverage

Skip if step 6 materialized no use cases.

`create_task` doesn't take coverage: declare it afterwards, one call per covering task, translating scenario IDs to refs through the step 6 map (`A2, B1` → `UC-2, UC-3`):

```
mcp__meridian__update_task(
    project=<project>,
    task_file=<task uuid>,
    use_cases=["UC-2", "UC-3"],
)
```

**`use_cases` replaces, it doesn't add**: send the task's full set in one call — including refs it already had when extending a feature. A ref that doesn't exist or belongs to another feature fails the whole call and leaves coverage untouched: a defect of the step 6 map, not something to retry.

Then verify with one read — each case carries its `covered_by`:

```
mcp__meridian__get_feature(project=<project>, slug=<feature-slug>, include_use_cases=True)
```

```
Coverage: 4/4 use cases covered.
```

or, when an assignment didn't land or step 2 left a case uncovered:

```
⚠ Uncovered: B1 (UC-3) "<title>".
   Assign it to a task, or is it out of this feature?
```

### 4. Summarize and suggest next step

```
Created N tasks in <project> (feature: <feature-slug>):

001 — "<title>"                          [covers: A1]
002 — "<title>"  (depends_on: 001)       [covers: A2, B1]
...

Dependencies: E/E verified.
Coverage: M/M use cases covered.

Next:
- /meridian-solve-task 001  — start the first one
- /meridian-run-plan        — run them all in sequence
```
