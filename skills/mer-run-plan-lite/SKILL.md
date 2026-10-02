---
name: mer-run-plan-lite
description: "Cheap variant of /meridian-run-plan: same orchestration but each task goes through /mer-solve-task-lite (tests are the only gate). For plans of small, low-risk tasks; use /meridian-run-plan for a plan you'll review in detail. `--confirm` pauses before each task; `--no-pr` skips the PR."
---

# Run Plan (lite)

Orchestrates all pending tasks, delegating each one whole to `/mer-solve-task-lite` — no code review, goal check or simplify; **the test command is the only verification**. Each task is implemented **and committed** on the current branch. N tasks leave N commits, verified one by one here and pushed once at the end.

Usage: `/mer-run-plan-lite` (autonomous) | `--confirm` (step by step) | `--no-pr` (don't open a PR on close; combines with either mode)

It's `/meridian-run-plan` with four differences: it delegates to `/mer-solve-task-lite` via `mer-task-runner`; per-task budgets are 15 minutes and 40 tool calls; the report carries no `GATE` lines to demand; and the summary says `lite`. Everything else — queue, branch, commit verification, push, PR, resumption — is the same mechanism, written out here in full. The evidence behind those rules lives in `.claude/skills/meridian-run-plan/NOTES.md`.

## When NOT to use this

Use the full `/meridian-run-plan` when:

- some task touches something irreversible in its content — migration, deletion, permissions, auth;
- you want a reviewer's verdict per task, not just passing tests;
- you won't review the N commits by hand before pushing/merging.

**The safety net of this version is you reading the N commits.** A plan with one risky task among small ones runs whole with the full skill: this one doesn't mix skills per task.

## Prerequisites

- Meridian connected with `list_tasks`, `get_task` and `update_task`. If not → warn and stop.
- Skill available: `/mer-solve-task-lite`.
- `git`, and `gh` authenticated if the run may close with a PR (7.2). Without `gh` only publishing the PR fails, and it's reported as such.

## Responsibility

run-plan-lite decides order (`depends_on`) and what happens on failure, **verifies each task's commit against git** and cuts the run if it's missing or malformed, pushes once at close, opens the PR and writes the summary. It does **not** implement, test, **commit** or merge. Its guarantee: exactly **N commits on one branch**, one per task, each with its `Task:` trailer.

## A cut run resumes on its own

**Invoke `/mer-run-plan-lite` again.** Every completed task is committed and `done` in Meridian, and the queue is rebuilt from `list_tasks` on every invocation. A task cut half-done leaves uncommitted changes, and the new preflight stops on the dirty tree — a human looks at them.

---

## Setup

Read `meridian-project: <project>` and `branch: <base_branch>` from CLAUDE.md.

- **The push decision (7.1) compares against `<base_branch>`, never the literal `main`.** If `branch:` isn't declared, try `git symbolic-ref --short refs/remotes/origin/HEAD`; if that fails too, **fail closed**: treat the current branch as the base and don't push. Commits still happen.
- **Mode:** autonomous by default; confirm if the user passes `--confirm` or asks for "confirm", "step by step", "one at a time".

## Process

### 1. Preflight

```bash
git status --porcelain
git rev-parse --abbrev-ref HEAD
git rev-parse --show-toplevel    # → <repo_root>
```

- **Dirty working directory** → stop, warn.
- **Detached HEAD** (the branch comes back as the literal `HEAD`) → stop: it would pass the `≠ <base_branch>` test as if it were a working branch.
- **Retain `<repo_root>`**: it travels in every brief, since subagents don't inherit the working directory.
- **Retain the branch as `<run_branch>`**: run-plan-lite never creates, switches or re-picks it.

### 2. Load tasks

```
mcp__meridian__list_tasks(project=<project>, status="pending")
mcp__meridian__list_tasks(project=<project>, status="in-progress")
```

If nothing is pending → warn and end.

### 3. Build the queue

Whole and at once, topologically ordered by `depends_on`: `in-progress` first, then `pending` in topological order, and numeric order among tasks with no dependency between them. **Order, don't filter**: a task goes after its blockers, and blockers inside this queue count as satisfied. **`N` is fixed from the announcement on.**

Exclude, and report why:
- **Blocker external to the plan** — depends on a task outside this queue that isn't `done`.
- **Cycle** — tasks blocking each other.

If nothing remains → show the blockers and stop.

### 4. Announce

```
run-plan-lite started — N tasks
Mode: autonomous | confirm
Branch: <run_branch>   (base: <base_branch>)
PR on close: yes | no (--no-pr)

Queue:
  1. 001-setup-db
  2. 002-auth-service (depends_on: 001)
  3. 005-api-endpoints
```

The `Branch` and `PR on close` lines are the **durable anchors** of `<run_branch>` and `--no-pr`: printed text survives compaction. If `<run_branch>` later becomes unclear, re-derive it (this line, or `git log -1 --format=%D` on the run's last commit). When in doubt, stop.

**`<run_branch>` == `<base_branch>` and N > 1** → ask before step 5, even in autonomous mode: `N tasks on <base_branch>: they land without a PR. Continue, or stop to create the feature's worktree?` A batch of loose fixes is a legitimate "continue".

### 5. Loop

For each task in the queue:

**(confirm mode)** Show the next task and ask `[Y / skip / abort]`.
- skip → mark it skipped; its dependents too.
- abort → go to step 7 with a partial result.

`Y` approves **entering** the task: the whole task then runs inside the subagent, unseen. To watch a task closely, the right tool is `/meridian-solve-task <NNN> --inline` — `/mer-solve-task-lite` always runs in a subagent.

**Verify a clean working directory.** Dirty → stop and ask the user. **Never clean automatically.**

**Retain the previous HEAD:**

```bash
git rev-parse HEAD    # → <head_before>
```

**Delegate to `/mer-solve-task-lite <NNN>` in a subagent**: `Agent` with `subagent_type: "mer-task-runner"`, **without `name:`** (with a name the child spawns as an addressable teammate, a path that hung in testing). `mer-task-runner` carries only the tools the lite path needs — not `general-purpose`, whose full tool surface bloats every turn. **Never run the task inline in this context.**

Subagent brief:

```
Invoke the /mer-solve-task-lite skill for task <NNN> of project <project>.

Invocation context:
- The repo is at <repo_root>. `cd` there as the first step, before anything
  else, and do it again in every bash call: the cwd doesn't persist.
- You come from /mer-run-plan-lite: you commit the task, but do NOT push. The
  push is a single one, at the close of the run, and the orchestrator does it.
- The run's branch is <run_branch>. Verify HEAD against it before committing.
  If HEAD isn't there, don't commit and report it.

Budget: 15 minutes of wall-clock for the whole task (the same one
/mer-solve-task-lite declares alone). Bound every command that could hang —
the test one first — with an explicit timeout, and if something exceeds the
budget cut it and close with the failure report instead of waiting.

Turn budget: 40 tool calls as a hard ceiling. Upon reaching it, stop and close
with the failure report, `Stage: turn budget`, saying which step you were on —
the changes stay on disk and the task stays in-progress, so it recovers by
re-invoking.

Return the skill's full final report verbatim, including the git status line.
It's the only thing the orchestrator will see.

The first line must be exactly one of the two headers that skill defines,
without rewriting them: `Task <NNN> done ✓` or `Task <NNN> FAILED ✗`.
If FAILED, also include the line `Stage: <stage> — <exact error>`.
```

#### How to wait for the subagent

- **`Agent` returns spawn metadata, not the report.** The report arrives later in a `<task-notification>`'s `<result>`. Wait by **ending the turn** and resuming on the notification; **don't poll with `Bash`** (`echo waiting`, `sleep` loops).
- **While the child lives, don't touch `git` in the run's repo, don't run 5.1 and don't delegate the next task**: two concurrent writers on `.git/index` lose commits silently.
- **A notification isn't, by itself, a termination.** The same `task-id` can notify each time the child goes idle; only a `<result>` opening with one of the two headers is a close.
- **Waiting isn't waiting forever.** If the 15 minutes expire with no header-bearing notification, `TaskStop` the child and treat it as the third reading below.

When the notification arrives, **three** readings:

- **Header `Task <NNN> done ✓`** → verify the commit (5.1), then `[i/N] <NNN> — done ✓ (<short sha>)`. `N` doesn't change.
- **Header `Task <NNN> FAILED ✗`** → step 6. The failed task's changes aren't committed.
- **No report, no recognizable header, or no git status line** → **failure**, step 6 with `Reason: the subagent returned no parseable report`. Silence isn't evidence. **`GATE` lines aren't required**: the lite path runs no gates, so the header plus the git line are all the evidence there is.

#### 5.1 Verify the task's commit

Verify against `git` (and the task status in Meridian where git can't tell), **never against the report**.

**1. Is the branch still the run's?**

```bash
git rev-parse --abbrev-ref HEAD
```

If it isn't `<run_branch>` — or `<run_branch>` couldn't be re-derived — → **stop immediately**, reporting the expected branch, the current one, and which tasks were already committed.

**2. How many new commits are there?**

```bash
git rev-list --count <head_before>..HEAD
```

| Result | Action |
|---|---|
| `1` | `git diff --quiet HEAD~1 HEAD` must exit ≠ 0; an empty commit → **stop the run**. Otherwise check 3 |
| `0` | see below — distinguish no-changes from never-ran |
| `>1` | **stop the run** and report the shas. One commit per task; **don't squash automatically** |

**If `0`**, `git status --porcelain`:
- **Clean tree** → `mcp__meridian__get_task(project, task_id)`. Status `done` → `[i/N] <NNN> — done ✓ (no changes)` and continue. Any other status → failure, step 6.
- **Dirty tree** → work produced and not committed. **Stop the run** and report the error. **Never commit it from here.**

**3. Does the commit carry the right trailer?**

```bash
git log -1 --format='%(trailers:key=Task,valueonly)'
```

It must return exactly the first 8 chars of the `task_id` you **already have** from `list_tasks` (step 2). **Use exactly this accessor** — it's the one `scripts/mark_deployed.sh` reads.

- **Missing, or another task's** → `git commit --amend` (never pushed before close), with the trailer in **its own trailer block**: last line, preceded by a blank line. Note it in the summary.
- **After amending, re-run the command** and confirm. If the amend fails → stop the run and report the sha.

**4. Retain the sha** (`git rev-parse --short HEAD`) for the summary. **Don't push here.**

### 6. Failure handling

A failed task **isn't committed**: its changes stay in the working tree. run-plan-lite neither commits nor cleans them, and doesn't touch previous commits (no `git reset`, no `git revert`).

**Autonomous:** stop executing tasks and **go to step 7 with a partial result** — never end the run without step 7.

```
[i/N] <NNN> — FAILED ✗
Reason: <what mer-solve-task-lite reported>

The changes of <NNN> were left uncommitted in the working tree.
```

Tasks left unrun are marked **`— not executed`**, distinct from **`⊘ skipped`** (a decision).

**Confirm:** offer `retry / skip / abort`. The working tree has the failed task's changes on top and run-plan-lite doesn't touch them (no `git checkout --`, no `git stash`, no `git clean`).

- **retry** → ask the user to resolve the state, then re-delegate.
- **skip** → mark it skipped (and its dependents), **but still ask the user to resolve the tree first**: otherwise the next commit sweeps those changes up under the wrong trailer.
- **abort** → step 7 with a partial result, tree as is.

### 7. Close

#### 7.1 Push

- **`<run_branch>` ≠ `<base_branch>`** → `git push -u origin <run_branch>`.
- **`<run_branch>` == `<base_branch>`** → **don't push.** Pushing the base triggers the deploy — the user triggers it.
- **`<base_branch>` indeterminate** → don't push, say why in the summary.

A single push. If it fails → don't retry blindly: report the error and leave the local commits.

#### 7.2 Pull request

Open a PR against `<base_branch>` **only when all four hold:**

1. 7.1 pushed.
2. The run finished complete — no task failed or was skipped. If partial, leave the assembled command in the summary.
3. No open PR for that branch yet (`gh pr list --head <run_branch> --state open`); if one exists, report its URL.
4. Not invoked with `--no-pr`.

```bash
gh pr create --base <base_branch> --head <run_branch> --title "<title>" --body <HEREDOC>
```

Body: `## Summary` (2-4 lines, what the set changes), `## Tasks` (one line per completed task, with its short id), `## Test plan` (the test command from CLAUDE.md — **say it's the only verification that ran**).

**No AI attribution**: no `Co-Authored-By: Claude`, no `Claude-Session:`, no "🤖 Generated with Claude Code".

**Stop there. Don't merge.** If `gh pr create` fails, report the error — the branch is already pushed.

#### 7.3 Final summary

Header `run-plan-lite completed` if every task in the queue ran, `run-plan-lite stopped` if it was cut.

```
run-plan-lite stopped
Branch: <current-branch>

✓ 001-setup-db           a3f9c21
✓ 002-auth-service       7b1e044
✗ 003-user-model         FAILED (uncommitted)
· 004-integration-tests  not executed (the run was cut at 003)

2/4 completed, 1 failed, 1 not executed
2 new commits on <run_branch> — pushed ✓
PR: <url>
Verification: tests only (no code review or goal check) — mer-solve-task-lite on all 4 tasks.
```

The `Verification:` line is fixed in every close: no task in the plan went through judgment gates.

| Mark | Meaning |
|---|---|
| `✓` | committed and verified |
| `✗` | failed (FAILED header, or 5.1 found a contradiction) |
| `⊘ skipped` | decision — the user skipped it, or its blocker failed |
| `· not executed` | the run was cut before reaching it |

The commits line reflects 7.1:
- working branch → `2 new commits on <run_branch> — pushed ✓`
- base branch → `2 new commits on <base_branch> — not pushed (pushing the base is the user's trigger).`
- failed push → `2 new commits on <run_branch> — push FAILED: <error>. The commits are local.`

The `PR:` line reflects 7.2:

| Situation | Line |
|---|---|
| PR opened | `PR: <url>` |
| Already existed | `PR: <url> (was already open)` |
| Partial run | `PR: not opened — the run didn't complete. When you want: gh pr create --base <base_branch> --head <run_branch>` |
| On the base | `PR: n/a — the run ran on <base_branch>.` |
| With `--no-pr` | `PR: not opened — invoked with --no-pr.` |
| `gh pr create` failed | `PR: FAILED — <error>. The branch is pushed; open it by hand.` |
