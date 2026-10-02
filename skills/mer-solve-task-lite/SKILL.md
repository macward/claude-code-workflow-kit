---
name: mer-solve-task-lite
description: "Cheap variant of /meridian-solve-task: implement → tests → commit, no review/goal-check/simplify. For small, low-risk tasks; use /meridian-solve-task for anything you won't hand-review afterwards. Runs in a subagent; commits on the current branch with its `Task:` trailer; never pushes to the base branch."
---

# Meridian Solve Task (lite)

Executes a task with the minimum: implement, tests, commit. **The test command is the only verification.**

Usage: `/mer-solve-task-lite [NNN] [--model sonnet|opus|haiku|fable]`

`--model` picks the subagent's model for this run; without it, the one in `mer-task-runner`'s frontmatter (`sonnet`). It's consumed at the spawn and never reaches the brief — it's not part of the task argument.

## When NOT to use this

This skill trades a verification for cost, and that's its whole reason to exist. Use `/meridian-solve-task` (the full one) when:

- the task touches something irreversible in its content — a migration, a deletion, permissions, auth;
- the `acceptance_criteria` aren't covered by the test command, i.e. nothing executable says whether they were met;
- you won't look at the diff before pushing.

**The safety net of this version is you reading the commit.** If that's not going to happen, this isn't the right skill. It doesn't run `/simplify` either: the code ships as written.

What is **not** trimmed, because it's correctness rather than ceremony: the commit → `done` order, the `Task:` trailer, and the push rules.

## Where it runs

**Always inside a subagent**, resolved before anything else. If the invocation brief says you're already inside the boundary, continue with Setup and **don't delegate again**. Otherwise, delegate with the brief below, wait for the report and show it — that's all that stays in the user's context.

Spawn: `Agent` with `subagent_type: "mer-task-runner"`, **without `name:`**, and with `model: "<value>"` only if `--model` was passed (the tool's override beats the frontmatter). `mer-task-runner` is an agent dedicated to this path (Read/Edit/Write/Bash/Grep/Glob/Skill/`mcp__meridian__{list_tasks,get_task,update_task}`), smaller than `general-purpose` because this skill never runs code review, goal check or re-delegates. The tool call returns metadata, not the report: end the turn and resume with the notification. Retain `<repo_root>` with `git rev-parse --show-toplevel` **before** spawning — the subagent doesn't inherit the cwd.

```
Invoke the /mer-solve-task-lite skill for <task NNN | the first in-progress or pending task>
of project <project>.

You are already inside the boundary: run the process here and do NOT delegate again.

- The repo is at <repo_root>. `cd` there as the first step and in every bash call:
  the cwd doesn't persist.
- You commit the task. On <base_branch> you do NOT push; on a working branch
  you also push. You don't open a PR and you don't merge.
- You have no channel to the user: everything you'd resolve by asking closes
  with the failure report.

Budget: 15 minutes of wall-clock, and 40 tool calls as the ceiling. Bound with an
explicit timeout every command that could hang, the test one first. At the
ceiling, stop and close with the failure report — the changes stay on disk.

Return the full final report verbatim. The first line must be exactly
`Task <NNN> done ✓` or `Task <NNN> FAILED ✗`.
```

## Setup

Read from CLAUDE.md: `meridian-project: <project>`, `branch: <base_branch>`, and the **Git Policy**.

`<base_branch>` isn't always `main` — it's what CLAUDE.md declares, and every git decision is compared against that value, never against the literal `main`. If it's not declared, try `git symbolic-ref --short refs/remotes/origin/HEAD`; if that doesn't resolve either, **fail closed**: treat the current branch as base, commit anyway and don't push.

No channel to the user: every point you'd resolve by asking closes with the failure report.

## Process

**Batch independent tool calls into one turn.** Every turn re-sends the whole
context, so the turn count — not the payload — is what this process costs.
Measured over the runs in the history, **21% of turns were a single call that
had no dependency on the turn before it**: the `context_refs` read one file per
turn, a grep sweep issued one pattern per turn, edits to different files went
one per turn. All of those belong in a single turn.

Two calls are independent when neither one's input depends on the other's
output. Read every `context_refs` file at once; issue the whole grep sweep at
once; apply edits to *distinct* files at once. Two edits to the **same** file
are not independent — the second's match depends on the first's result — and a
command whose arguments come from a previous result never batches.

Sequential is still right when you need to *see* a result before choosing the
next call. Don't batch a test run with the fix for the failure it hasn't
reported yet.

### 1. Load the task

One `list_tasks` call, shaped by the argument — its result is re-read on every later turn of the run, so the smaller the better:

```
# no argument
mcp__meridian__list_tasks(project=<project>, status=["in-progress", "pending"])
# title-number argument (007)
mcp__meridian__list_tasks(project=<project>, status=["in-progress", "pending"], query="007", limit=5)
# task_id-prefix argument (ab9f628b) — query doesn't search ids; NO limit, the match can be anywhere
mcp__meridian__list_tasks(project=<project>, status=["in-progress", "pending"])
```

Use these calls as written: don't add a `limit` the line doesn't have (a task past the cut looks like a missing task), and don't try `get_task` with a prefix — it takes the full UUID, which you only have after resolving the list.

No argument → the first `in-progress`; if none, the first `pending` (the list comes ordered by creation, both statuses mixed: pick by `status`, not by position). With argument → resolve it against the list by **title** prefix (`007` → `007-do-...`) or **task_id** prefix (`ab9f628b`); `query` is full-text, so it narrows the payload but the prefix check is still yours. An argument that matches nothing, or matches several, **is a failure** — `Stage: step 1`, saying what was searched. Falling back to "the first pending" solves a task nobody asked for and commits it.

Read the content with `mcp__meridian__get_task(project, task_id)` and retain **goal**, **context_refs**, **changes_required**, **acceptance_criteria**, **constraints**, **validation**.

If it has `depends_on` not `done` → failure, `Stage: step 1`, listing the blockers.

### 2. Preflight

`git status --porcelain`. If the working directory is dirty → failure, `Stage: step 2`, with the output. **Don't clean anything**: those changes aren't this task's.

Then `mcp__meridian__update_task(project, task_id, status="in-progress")`.

### 3. Implement

Read the **context_refs**. Work through **changes_required**, one change at a time. **constraints** are invariants, not suggestions. Verify the **acceptance_criteria** when done and run the **validation** if defined.

**Only what the task describes. Nothing more.** Without downstream gates, this rule is the only thing keeping the commit attributable to its task.

### 4. Tests

Run the test command from CLAUDE.md, **with an explicit timeout**. If there is no command, skip.

**Copy the command as-is and don't probe the environment** — no hunting for the DB, trying ports or `which`-ing binaries. If the suite fails oddly, the cause is documented in CLAUDE.md; reading it costs one turn, rediscovering it costs thirteen. If the command doesn't work **and** CLAUDE.md doesn't explain the symptom, it's a step 4 failure, not an invitation to investigate the machine.

If they fail → fix and re-run, **at most 2 attempts** (the full skill allows 3; here the budget is shorter). If they don't resolve, or the command hangs: leave the changes on disk and close with failure, `Stage: step 4`, with the last run's error verbatim.

### 5. Commit

**The commit goes before marking `done`, and the order is non-negotiable.** A cut between the two leaves the task `done` with zero commits: it doesn't return to the queue — which loads only `pending` + `in-progress` —, never carries its trailer, and `scripts/mark_deployed.sh` never moves it to `deployed`. Committing first, the worst case is an `in-progress` task already committed: recoverable and visible.

`git status --porcelain` first. **If it's empty there is no commit to make**: jump to step 6 and report `No changes to commit`. It's not a failure — a pure verification task legitimately ends without touching files.

With changes, `git add -A` and commit with conventional commits, describing **the work** (not "task NNN done"):

```
<type>(<scope>): <what changed, one line>

Task: <short task_id (8 chars)>
```

**Never add AI co-authorship trailers or auto-generation signatures.**

**If the commit fails, stop.** The typical case is a pre-commit hook aborting because it regenerated an artifact: it's a legitimate signal, **don't use `--no-verify`**. The changes stay on disk, step 6 is skipped (the task stays `in-progress`) and close with failure, `Stage: step 5`, with the hook's output verbatim.

Retain the sha (`git rev-parse --short HEAD`) and the files (`git show --stat --name-only HEAD`): `git add -A` takes **everything** in the tree, including artifacts the task generated unintentionally.

**Push:** only if it committed and the branch is **not** `<base_branch>` (nor indeterminate): `git push -u origin <branch>`. On `<base_branch>` never push — it's what triggers the deploy, and Max triggers it. If the push fails, don't retry blindly: report it and leave the local commit. **Don't open a PR, don't merge, don't create or switch branches.**

### 6. Mark done

Only if step 5 committed, or there was nothing to commit:

```
mcp__meridian__update_task(project, task_id, status="done")
```

**Marking `done` when a commit was attempted and didn't land is forbidden.** When in doubt, don't mark: an `in-progress` task with the work done recovers by re-invoking; a `done` one without a commit doesn't recover on its own by any path.

### 7. Report

Two forms, and the **first line** decides which. Exact text, no decoration:

```
Task <NNN> done ✓

<1-3 lines: what was done and why, in prose>

Tests: <command> — <result, e.g. "1809 passed">
Commit <sha>: <files touched>
<git line: "Pushed to <branch>." | "Not pushed (Max pushes the base)." | "No changes to commit.">

Unverified: code review, goal check and simplify don't run in this skill.
```

```
Task <NNN> FAILED ✗
Stage: <step 1 | step 2 | step 4 | step 5 | turn budget> — <exact error>

<what stayed on disk and what it would take to close it>
```

The header is the only thing that signals termination outward: emitting it verbatim is the only signal by which the invoker knows the task ended. `<exact error>` is literal, not a paraphrase — nobody else saw it.

**The last line of the success report is mandatory.** This skill produces a `done ✓` with a fraction of the evidence the full one produces, and a report that doesn't say so reads the same as the other.
