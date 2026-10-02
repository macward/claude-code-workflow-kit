---
name: meridian-solve-task
description: "Execute one Meridian task end-to-end with full verification (tests → simplify → code review → goal check) and commit it on the current branch with its `Task:` trailer. Runs in a subagent; `--inline` runs it in view. Never pushes to the base branch, never opens PRs or merges. Optional arg: task NNN or short id."
---

# Meridian Solve Task

Executes one task end-to-end in four blocks: **contract** (1-2), **production** (3), **verification** (4-7: tests → simplify → code review → goal check) and **close** (8-10: commit, mark done, report). All code mutation ends at step 5: the two judgment gates read frozen code.

How far it goes in git is decided by the branch (Git Policy in CLAUDE.md): it always commits; it pushes only when standalone on a working branch. It never opens PRs or merges.

Usage: `/meridian-solve-task [NNN | short id]` | `--inline` (run in the user's context)

> Files in this folder: **`REPORT.md`** — the step 10 output contract, read before writing the report. **`DELEGATE.md`** — the spawn brief, read only in case 2 below. **`FEATURE_ENRICH.md`** — step 9.2, read only when a feature was completed. **`NOTES.md`** — the evidence behind the rules; not needed to execute, read it before **changing** a rule.

## Where it runs

Resolve this before anything else:

1. **You're already inside the boundary** — the brief comes from step 5 of `/meridian-run-plan` or from case 2's spawn. Continue with Setup and run the process. **Don't delegate again** (infinite spawn).
2. **Direct user invocation, without `--inline`** — the default. Don't run the process in this context: follow `DELEGATE.md`, wait for the subagent's report and show it.
3. **`--inline`** — run here, in view, with a channel to the user. The escape hatch for a risky task where watching every edit is worth the context.

## Setup

Read from CLAUDE.md: `meridian-project: <project>`, `branch: <base_branch>`, and the full **Git Policy** section.

- **Every git decision compares against `<base_branch>`, never the literal `main`.** If CLAUDE.md doesn't declare `branch:`, try `git symbolic-ref --short refs/remotes/origin/HEAD`. If that fails too, **fail closed**: commit, don't push, and say so in the report — the same reading `/meridian-run-plan`'s Setup makes.
- **Invocation mode:**
  - **standalone** — direct invocation, whether in case 2's subagent or `--inline`. Commits; pushes only off `<base_branch>`.
  - **under run-plan** — the brief comes from `/meridian-run-plan` step 5. Commits, **never pushes**. Retain the `<run_branch>` it carries: 8.1 verifies it.
- **No channel to the user, except with `--inline`.** Every point that would stop and ask — steps 2, 4, 6 and 7 — instead closes with step 10's failure report (`Task <NNN> FAILED ✗` + `Stage:`) carrying the exact error: nobody is listening, and the invoker is blocked until this closes. With `--inline` those points ask the user; nothing else changes.
- **The gates of steps 6 and 7 run regardless** of being inside a subagent. Skipping them turns into a report saying "no blockers" for a review that never ran.
- **A spawn returns metadata, not the result.** Wait by ending the turn until the notification — the mechanics, including **don't poll with Bash**, are in `/meridian-run-plan` step 5, "How to wait for the subagent". While a gate runs: no edits, no next gate, no commit.
- **A gate's result can fail to reach this context** (it gets delivered to the grandparent). "I didn't receive the review" and "the review found nothing" must stay distinguishable — hence the literal `GATE` lines, the 10-minute budget with `TaskStop`, and no success report without both lines.
- Step 10's header is the only termination signal the invoker sees: emit it verbatim.
- This skill never creates or switches branches, opens PRs or merges.

## Process

**Batch independent tool calls into one turn** — every turn re-sends the whole context, so turn count is the cost. Two calls are independent when neither's input depends on the other's output: read every `context_refs` file at once, issue the whole grep sweep at once, apply edits to *distinct* files at once. Stay sequential when you need to see a result first: two edits to the same file, or a test run and the fix for a failure it hasn't reported yet.

### 1. Load the task

```
mcp__meridian__list_tasks(project=<project>, status="in-progress")
mcp__meridian__list_tasks(project=<project>, status="pending")
```

- **No argument** → the first `in-progress`; if none, the first `pending`.
- **With argument** → resolve it against both lists by **title** prefix (`007` → `007-make-...`) or **task-id** prefix (`ab9f628b` → that task). `/meridian-task-breakdown` numbers titles; `/meridian-task` passes the 8-char id.
  - No match → failure report, `Stage: step 1 (lookup)`, saying what was searched. **Never fall back** to the first pending: that solves and commits a task nobody asked for.
  - Several matches → same failure, listing the candidates.

```
mcp__meridian__get_task(project=<project>, task_id=<task_id>)
```

Retain: **goal**, **context_refs**, **context_patterns**, **changes_required**, **acceptance_criteria**, **constraints**, **validation**, **writes**. `writes` doesn't restrict step 3; it's kept for 8.3. When absent, the task declared no writes — not an error.

If `depends_on` has tasks not `done` → failure report, `Stage: step 1 (dependencies)`, listing them.

### 2. Preflight

```bash
git status --porcelain
```

Dirty → failure report, `Stage: step 2 (preflight)`, with that output. Don't clean anything: those changes aren't this task's.

```
mcp__meridian__update_task(project, task_id, status="in-progress")
```

### 3. Implement

Read the **context_refs** files; note the **context_patterns** (reference modules).

- Work through **changes_required**, one change at a time.
- Respect **constraints** — invariants, not suggestions.
- When done, check the **acceptance_criteria** and run the **validation** if defined.

Only what the task describes. Nothing more.

### 4. Tests

Run the test command from CLAUDE.md **as-is, always with an explicit timeout**. No command → skip.

**Don't probe the environment**: no hunting for the DB, trying ports, `which`-ing binaries or inspecting containers. If the suite fails oddly, the cause is in CLAUDE.md's symptom table; if it isn't documented there, it's a step 4 failure like any other.

Failing → fix and re-run, **at most 3 attempts**. Still red → leave the changes on disk, failure report, `Stage: step 4 (tests)`, with the last run's error verbatim. A timeout is the same failure, stated as a hang.

### 5. Simplify

Invoke `/simplify` with two non-negotiable limits:

1. **Only this task's diff** (scope from `git status --porcelain` and `git diff`). Pre-existing code and previous tasks' code aren't touched: the `Task:` trailer must describe what changed.
2. **Quality, not scope.** Express the same thing better — no new cases, no generalizing, no anticipating the next task. A real improvement outside the diff is recorded with `create_issue(type="note")`, not applied.

A no-op is the expected outcome for small tasks. **Re-run the tests** afterwards with the step 4 command; if red, the simplification is the cause — revert it. At most 2 attempts; then discard this step's changes entirely and keep step 4's green code.

From here the code is **frozen**: it's only mutated to fix a real finding from a gate.

### 6. Code review

Launch the `code-review-expert` agent with this brief:

```
Review the changes just implemented for task <NNN>-<task-name>.

Task goal: <goal>
Changes required: <changes_required>
Acceptance criteria: <acceptance_criteria>
Constraints: <constraints>

Focus on:
- Correctness against acceptance criteria
- Constraint violations
- Code quality issues that would block merging
- Anything the implementer may have missed

Be direct and specific. Report **only blockers** — findings that must be fixed
before this merges. A finding below that bar is dropped, not reported as a minor
note and not promoted so it survives: this process acts on blockers and nothing
else, so anything else is read by no one.

Your response MUST end with this line, verbatim and as the very last line:

GATE code-review: <N> blockers

Write the literal counts. This line is a machine-read token, not prose — do
not translate it, reword it, or wrap it in formatting.
```

With `--inline`, show the full review to the user, `GATE` line included.

**Wait with a budget of 10 minutes of wall-clock.** Only a notification whose `<result>` carries the `GATE code-review:` line counts as the review; any other (an idle alert, a review delivered elsewhere) means keep waiting. On expiry, `TaskStop` the child and close with the failure report, `Stage: step 6 (gate not received)`. **Never continue to step 7 as if the review came back clean.**

- **Blockers** → fix them (back to step 3, re-run tests, re-review; no new step 5). **At most 2 iterations** — a separate limit from the wait budget. Still blockers → leave the changes on disk, failure report, `Stage: step 6 (code review)`, listing the open blockers verbatim.
- **No blockers** → continue.

### 7. Goal check

Verify the **acceptance_criteria** with an independent verifier: launch `mer-goal-check` (read-only; already knows the verdict scheme — the brief restates it so the contract lives with the caller):

```
Verify the acceptance criteria for task <NNN>-<task-name> against the ACTUAL code on disk.

Acceptance criteria:
<acceptance_criteria, one per line>

Validation command (if defined): <validation>

For EACH criterion: inspect the relevant files/tests and report PASS or FAIL with concrete evidence (file:line, test output). Do not assume — verify. If a criterion is not verifiable from the code, mark it UNVERIFIABLE and explain why.

Tag HOW each verdict was reached:
- `[cmd]` — backed by an executable check (a `validation` command, a test, a curl with exit code). Deterministic.
- `[judgment]` — verified by reading/reasoning about the code, no command behind it. Non-deterministic — this is an LLM opinion, flag it as such.

Return a checklist: one line per criterion with verdict + `[cmd]`/`[judgment]` tag + evidence.

Your response MUST end with this line, verbatim and as the very last line:

GATE goal-check: <N>/<total> PASS, <X> cmd, <Y> judgment, <Z> unverifiable

Write the literal counts. This line is a machine-read token, not prose — do
not translate it, reword it, or wrap it in formatting.
```

**Wait exactly as in step 6**: 10 minutes, only a notification carrying the `GATE goal-check:` line counts, on expiry `TaskStop` and failure report with `Stage: step 7 (gate not received)`. A gate not received is a failure, **never** an `UNVERIFIABLE` criterion.

- **All PASS** → step 8.
- **Any FAIL** → back to step 3, re-run tests, repeat the goal check. **At most 2 iterations**; then leave the changes on disk, failure report, `Stage: step 7 (goal check)`, listing the unmet criteria.
- **UNVERIFIABLE** → doesn't block; reported explicitly.

The report states how many criteria were verified by `[cmd]` vs. `[judgment]`.

### 8. Commit

**The commit goes before marking `done` (step 9), always.** Meridian's state never gets ahead of git's: a cut in between must leave an `in-progress` task with committed work, never a `done` task without a commit.

| Mode | Current branch | Commit | Push |
|---|---|---|---|
| standalone | ≠ `<base_branch>` | **this skill** (8.1) | **this skill** (8.2) |
| standalone | == `<base_branch>` | **this skill** (8.1) | no — pushing the base is the user's trigger |
| under run-plan | == `<run_branch>` ≠ `<base_branch>` | **this skill** (8.1) | no — run-plan, on closing the run |
| under run-plan | == `<run_branch>` == `<base_branch>` | **this skill** (8.1) | no — pushing the base is the user's trigger |
| any | `<base_branch>` indeterminate | **this skill** (8.1) | no — fail closed (see Setup) |
| under run-plan | ≠ `<run_branch>` | nobody — **stop** (see 8.1) | no |

#### 8.1 Commit

```bash
git rev-parse --abbrev-ref HEAD
```

- **standalone** → commits on any branch.
- **under run-plan** → if HEAD isn't the `<run_branch>` the brief carried, **don't commit**: failure report, `Stage: step 8.1 (branch)`, with the expected and current branch.

```bash
git status --porcelain
```

**Empty → nothing to commit.** Skip the rest of step 8, go to step 9, and report `No changes to commit`. It's not a failure: a pure verification task legitimately touches no files.

Otherwise `git add -A` and commit with conventional commits, describing **the task's work** (not "task NNN done"):

```
<type>(<scope>): <what changed, one line>

<optional body: why, if not obvious>

Task: <short task_id (8 chars)>
```

`feat` for product behavior changes; `fix`/`refactor`/`test`/`docs`/`chore` as applicable. One commit per task, one trailer per commit. **The trailer is the last line, preceded by a blank line** — a real trailer block, or `git log --format='%(trailers:key=Task,valueonly)'` doesn't see it. **Never add AI co-authorship trailers or auto-generation signatures.**

**If the commit fails** (typically a pre-commit hook that regenerated an artifact): **don't use `--no-verify`**, leave the changes on disk, **skip step 9**, and close with the failure report, `Stage: step 8.1 (commit)`, with the hook's output verbatim.

**Retain the short sha** (`git rev-parse --short HEAD`) **and the committed files** (`git show --name-only --format= HEAD`): `git add -A` takes everything in the tree, and the report must say what landed.

#### 8.2 Push

Only if 8.1 committed, the mode is standalone, **and** the branch isn't `<base_branch>` (nor indeterminate): `git push -u origin <branch>`.

- **Never on `<base_branch>`**, in any mode: the push to the base triggers the deploy.
- **Never under run-plan**, not even on a working branch: the run pushes once at its close.
- If the push fails, **don't retry blindly**: report it and leave the local commit. The task is just as solved.

**Don't open a PR.** A task isn't a feature.

#### 8.3 Divergence from `writes`

Only if 8.1 committed. **Informative, never blocks**: it doesn't change the header, prevent `done` or cut the run.

```bash
git diff-tree --no-commit-id --name-only -r HEAD
```

Compare that list literally (repo-relative paths, no globs or normalization) against `writes`, and report both sets: **declared not touched** and **touched not declared** — the latter unfiltered, including artifacts `git add -A` dragged along. Format in `REPORT.md`.

### 9. Mark done

**No failure path reaches here.** Mark `done` only if step 8 committed or there was nothing to commit. If a commit was attempted and didn't land — or you can't confirm it did — don't mark: the task stays `in-progress` and the report is a failure.

```
mcp__meridian__update_task(project, task_id, status="done")
```

Keep the response: when the server produced timeline events it carries `timeline_events: [<ids>]`.

#### 9.1 Enrich the task's entry

Runs **always** once the task is `done`. The server's mechanical entry records **what** happened; this adds **what was understood**.

1. **`event_id`** = the `task_completed` in `timeline_events`. None → skip 9.1.
2. **One issue per loose end** — an unanswered question, an adjacent out-of-scope bug, a postponed decision: `mcp__meridian__create_issue(project, title="<the question or finding>", type="question")`. Keep the ids. None → no refs.
3. **Write it:**

   ```
   mcp__meridian__enrich_timeline(
       project,
       event_id="<id of the task_completed>",
       enrichment="<curated narrative>",
       refs=[{"ref_type": "issue", "ref_id": "<issue id>"}, ...],
   )
   ```

**The narrative:** prose, 5 to 15 lines, for someone asking three months from now *why* this ended up this way — the finding (the headline if the task's premise turned out wrong), what was decided and what was decided **not** to do and why, real caveats, loose ends with their issue ids.

**What does NOT go:** `GATE` lines, sha, file list, test commands or counts, branch names — they are already in the commit and degrade the feed's semantic search. The server rejects over 2000 characters.

If `enrich_timeline` fails, note it in one line of the report; the header stays `done ✓`.

#### 9.2 Enrich the completed-feature entry

Only if `timeline_events` carries more than this task's `task_completed`/`task_deployed`: read `FEATURE_ENRICH.md` and follow it. Otherwise it's a no-op.

### 10. Report

**Read `REPORT.md` before writing the report** — it's the contract the invoker parses, not free prose. What can't be gotten wrong, and therefore also lives here:

- The **first line** is exactly one of `Task <NNN> done ✓` (task marked `done`) or `Task <NNN> FAILED ✗` (a stage was cut; the task stayed `in-progress`). One, never both or neither, never reworded: the invoker branches on that literal token.
- A failure report carries `Stage: <stage> — <exact error>` right after the header, with a `<stage>` token from `REPORT.md` and the **literal** error.
- **A success report quotes both `GATE` lines verbatim**, as each gate returned them. Missing either, it's invalid: the correct report was the failure one with `step 6 (gate not received)` or `step 7 (gate not received)`. **Facing a gate that didn't arrive, the report degrades noisily to failure, never silently to success.**
- The `Declared vs. touched writes` block (8.3) is informative: it never changes the header.
