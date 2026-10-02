---
name: meridian-run-plan
description: "Execute all pending Meridian tasks in dependency order, each via /meridian-solve-task in its own subagent, one commit per task on the current branch. Pushes once at the end and opens a PR only when the run branch isn't the base branch (`--no-pr` skips it); never merges. Autonomous by default; pauses per task if asked."
---

# Run Plan

Orchestrates the execution of all pending tasks. Each task is delegated whole to `/meridian-solve-task` in a subagent, which implements **and commits** it on the current branch. A plan of N tasks leaves N commits, which run-plan verifies one by one and pushes once at the end.

Usage: `/meridian-run-plan` (autonomous) | `--confirm` (step by step) | `--no-pr` (don't open a PR on close; combines with either mode)

> **`NOTES.md`** (in this same folder) holds the evidence behind the rules: measured incidents, and which earlier wording turned out wrong. **Executing the process doesn't require reading it.** Read it before **changing** a rule.

**Tip for the user — prefix autonomous runs with `/goal`** (the skill can't set it itself):

```
/goal all pending tasks in the plan are done, or the run stopped with an explicit failure/block report
/meridian-run-plan
```

"Stopped with a report" is part of the condition on purpose: a task that legitimately fails is a valid end of the run, not something to retry forever.

## Prerequisites

- Meridian connected with `list_tasks`, `get_task` and `update_task`. If not → warn and stop.
- Skill available: `/meridian-solve-task`.
- `git`, and `gh` authenticated if the run may close with a PR (7.2). Without `gh` only publishing the PR fails, and it's reported as such.

## Responsibility

run-plan decides which task runs and in what order (`depends_on`), what happens when one fails, **verifies each task's commit against git** and cuts the run if it's missing or malformed, pushes once at close, opens the PR and writes the summary.

run-plan does **not** implement, test, **commit** or merge. Its guarantee is exactly **N commits on one branch**, one per task, each with its `Task:` trailer.

## A cut run resumes on its own

A run can be cut by compaction, a closed session or a failing task. **Invoke `/meridian-run-plan` again** — the durable state isn't in the context: every completed task is committed (verified in 5.1) and `done` in Meridian, and the queue is rebuilt from `list_tasks` on every invocation, so the `done` ones don't enter. Only the previous run's narrative is lost; the shas are in `git log`.

If the run was cut with a task half-done, its changes stay uncommitted and the new preflight stops on the dirty tree. That's correct: those changes passed no gate, and a human looks at them.

---

## Setup

Read `meridian-project: <project>` and `branch: <base_branch>` from CLAUDE.md.

- **The push decision (7.1) compares against `<base_branch>`, never the literal `main`.** If CLAUDE.md doesn't declare `branch:`, try `git symbolic-ref --short refs/remotes/origin/HEAD`. If that fails too, **fail closed**: treat the current branch as the base and don't push. Commits still happen.
- **Mode:** autonomous by default; confirm if the user passes `--confirm` or asks for "confirm", "step by step", "one at a time".

## Process

### 1. Preflight

```bash
git status --porcelain
git rev-parse --abbrev-ref HEAD
git rev-parse --show-toplevel    # → <repo_root>
```

- **Dirty working directory** → stop, warn.
- **Detached HEAD** (the branch comes back as the literal `HEAD`) → stop. It would pass the `≠ <base_branch>` test and 7.1 would push something that isn't a branch.
- **Retain `<repo_root>`**: it travels in every brief because subagents don't inherit the working directory. If the invocation came with an explicit repo root (a worktree, for example) that doesn't match → stop.
- **Retain the branch as `<run_branch>`**: the N tasks commit there and only there. run-plan never creates, switches or re-picks it — it inherits it (`<base_branch>` for loose work, the feature's worktree branch for a feature).

### 2. Load tasks

```
mcp__meridian__list_tasks(project=<project>, status="pending")
mcp__meridian__list_tasks(project=<project>, status="in-progress")
```

If nothing is pending → warn and end.

### 3. Build the queue

Build it **whole and at once**, with every task from step 2, topologically ordered by `depends_on`:

- `in-progress` tasks first (resuming).
- Then `pending` ones in topological order: a task goes **after** its blockers — it isn't excluded for having them. Blockers inside this same queue count as satisfied.
- Among tasks with no dependency between them, numeric order (001, 002, ...).

**Order, don't filter.** **`N` is fixed from the announcement on**: step 5 unblocks tasks already in the queue, it never adds new ones.

Exclude from the queue, and report why:

- **Blocker external to the plan** — depends on a task not in this queue and not `done`.
- **Cycle** — tasks blocking each other with no topological order.

If nothing remains after excluding → show the blockers and stop.

### 4. Announce

```
run-plan started — N tasks
Mode: autonomous | confirm
Branch: <run_branch>   (base: <base_branch>)
PR on close: yes | no (--no-pr)

Queue:
  1. 001-setup-db
  2. 002-auth-service (depends_on: 001)
  3. 005-api-endpoints
```

**The `Branch` and `PR on close` lines are the durable anchors** of `<run_branch>` and `--no-pr`: both are decided at start and consumed at close, and printed text survives compaction where a remembered variable doesn't.

If `<run_branch>` later becomes unclear, re-derive it — from this line, or `git log -1 --format=%D` on the run's last commit — rather than guess. When in doubt, stop: never delegate a task with the expected branch in doubt.

**`<run_branch>` == `<base_branch>` and N > 1** → ask before step 5, even in autonomous mode: `N tasks on <base_branch>: they land without a PR. Continue, or stop to create the feature's worktree?` Several tasks on the base are usually a feature that forgot its branch (Git Policy in CLAUDE.md); a batch of loose fixes is a legitimate "continue".

### 5. Loop

For each task in the queue:

**(confirm mode)** Show the next task and ask `[Y / skip / abort]`.
- skip → mark it skipped; its dependents are skipped too.
- abort → go to step 7 with a partial result.

`Y` approves **entering** the task: from there to the commit everything runs inside the subagent, unseen and uninterruptible, and the next thing the user sees is the final report. To watch a risky task closely, the right tool is `/meridian-solve-task <NNN> --inline`.

**Verify a clean working directory.** Dirty (e.g. residue from a failed task) → stop and ask the user. **Never clean automatically** (no `git clean`, no `git branch -D`, no `git push --delete`).

**Retain the previous HEAD** — step 5.1 checks against it that the task produced exactly one commit:

```bash
git rev-parse HEAD    # → <head_before>
```

**Delegate to `/meridian-solve-task <NNN>` in a subagent**: an `Agent` with `subagent_type: "mer-task-runner-full"`, **without `name:`**, whose only job is to invoke that skill via the `Skill` tool. **Never run solve-task inline in this context**: context is what limits a run's length, and only the step 10 report should come back.

Subagent brief:

```
Invoke the /meridian-solve-task skill for task <NNN> of project <project>.

Invocation context:
- The repo is at <repo_root>. `cd` there as the first step, before anything
  else, and do it again in every bash call: the cwd doesn't persist.
- You come from /meridian-run-plan: you commit the task, but do NOT push. The
  push is a single one, at the close of the run, and the orchestrator does it.
- The run's branch is <run_branch>. Verify HEAD against it before committing
  (step 8.1 of that skill). If HEAD isn't there, don't commit and report it.

Budget: 30 minutes of wall-clock for the whole task. Bound every command that
could hang — the test one first — with an explicit timeout, and if something
exceeds the budget cut it and close with the failure report instead of waiting.

Turn budget: 60 tool calls as the budget, 100 as the hard ceiling. At 60, stop
exploring and converge with what you already know. At 100, stop and close with
the failure report, `Stage: turn budget`, saying which step you were on — the
changes stay on disk and the task stays in-progress, so it recovers by
re-invoking. It's not a clock budget: a run can burn 200 turns well within the
30 minutes.

Return the skill's final report (its step 10) in full and verbatim, including
the git status line. It's the only thing the orchestrator will see.

The first line must be exactly one of the two headers that step defines,
without rewriting them: `Task <NNN> done ✓` or `Task <NNN> FAILED ✗`. If
FAILED, also include the line `Stage: <stage> — <exact error>` the failure
template requires, with the literal error.
```

The brief passes what the child can't derive alone: that it **comes from run-plan** (commit, don't push), **`<run_branch>`** (without it, solve-task commits wherever it stands) and **`<repo_root>`** (always, even if it matches the cwd — in a worktree the child would otherwise work in the wrong repo). And it demands the exact header back: run-plan branches on that literal token, never on interpreting prose.

#### How to wait for the subagent

- **The `Agent` tool doesn't return the report: it returns spawn metadata**, in seconds. The report arrives **later**, as a `<task-notification>` whose `<result>` carries the child's final text. Waiting means **ending the turn** without doing anything else and resuming when the notification arrives.
- **Don't poll with `Bash`** (`echo waiting`, `sleep N; echo done` loops). Each poll resends the whole context and does nothing; ending the turn is free.
- **Between the spawn and that notification, run-plan doesn't touch `git` in the run's repo, doesn't run 5.1 and doesn't delegate the next task.** The child is writing git's index: two concurrent writers trip over `.git/index.lock` and lose commits silently.
- **A notification is not, by itself, a termination.** The same `task-id` can notify every time the child goes idle. Only a `<result>` that **opens with one of step 10's two headers** is a close. Without a header, wait again — unless it says it's waiting for a gate (next section).
- **Don't pass `name:` to `Agent`**: it spawns a mailbox-addressable teammate instead of a subagent, a different execution path that hung in testing. run-plan has nothing to say to the child while it runs.

**A gate's report can land here instead of in the child.** A nested gate agent (`run-plan` → `solve-task` → gate) sometimes delivers its result to the grandparent, with or without `name:`. It's platform behavior and isn't fixed from here; solve-task's literal `GATE` lines are what make the loss detectable. Two symptoms: the child reports anyway (a `done ✓` without `GATE` lines — the third reading below rejects it), or it notifies with no header, saying it's waiting for a (re-)review. For the second:

- **If the gate's report reached you**, forward it to the child with `SendMessage`, **verbatim**, unsummarized — so it closes quoting real evidence in its `GATE` line.
- **If it didn't**, tell the child to relaunch the gate **once**; if that doesn't come back either, to verify on its own what it had sent for review and close **stating in the report that the gate was lost and the verification was its own**. An honest `FAILED` is also valid.
- **Never acceptable:** a `GATE` line the child didn't see. If it can be invented, it stops being evidence of anything.

**Waiting isn't waiting forever.** The brief bounds each task to 30 minutes. If that expires with no header-bearing notification, kill the child with `TaskStop` on its id and treat it as the third reading below — failure. Checking liveness first with `ListAgents` is optional (not every agent type has it); `TaskStop` on a child that already finished is harmless.

When the notification arrives, its `<result>` has **three** possible readings:

- **Header `Task <NNN> done ✓`** → verify the commit (5.1), then `[i/N] <NNN> — done ✓ (<short sha>)`. Its dependents were already in the queue; `N` doesn't change.
- **Header `Task <NNN> FAILED ✗`** → step 6. The failed task's changes aren't committed.
- **No report, no recognizable header, no git status line, or a success report missing either `GATE` line** (`GATE code-review: …`, `GATE goal-check: …`) → **failure**, step 6 with `Reason: the subagent returned no parseable report`. A child that never spawned, died on its first call, hit a permission denial or returned a truncated response lands here, and from outside it looks like a task that touched no files. A `done ✓` without the `GATE` lines isn't a verified success.

Branch on the header token and the `GATE` lines — never on guessing from prose.

#### 5.1 Verify the task's commit

solve-task made the commit. This step **doesn't commit**: it verifies that what landed is exactly one commit, on the right branch, with the right trailer — and cuts the run if not. Verify against `git` (and, where git can't tell, the task status in Meridian), **never against the report**.

**1. Is the branch still the run's?**

```bash
git rev-parse --abbrev-ref HEAD
```

If it isn't `<run_branch>` — or `<run_branch>` couldn't be re-derived after compaction (step 4) — → **stop immediately**, reporting the expected branch, the current one, and which tasks were already committed.

**2. How many new commits are there?**

```bash
git rev-list --count <head_before>..HEAD
```

| Result | Reading | Action |
|---|---|---|
| `1` | the normal case | verify the commit **isn't empty** (below), then check 3 |
| `0` | solve-task didn't commit | see below |
| `>1` | the task was split into several commits | **stop the run** and report the shas. One commit per task; **don't squash automatically** — the user looks at the diff |

**If `1`**, confirm it changed something: `git diff --quiet HEAD~1 HEAD` must exit ≠ 0. An empty commit (`--allow-empty`) passes the count without committing work → **stop the run**.

**If `0`**, check `git status --porcelain`:

- **Clean tree** → git can't tell "had nothing to do" from "did nothing"; ask Meridian:

  ```
  mcp__meridian__get_task(project=<project>, task_id=<task_id>)
  ```

  - **status `done`** → completed without changes: record `[i/N] <NNN> — done ✓ (no changes)` and continue. The report should say `No changes to commit` under a success header. If it claims a commit that isn't here → **stop the run** (report and git contradict). If it says `Commit FAILED: nothing to commit`, solve-task is outdated: a clean tree with the task `done` is success.
  - **any other status** → **failure**, step 6: the child died before the end or was cut at a gate.
- **Dirty tree** → solve-task produced work and didn't commit it (a failed commit, or `<run_branch>` didn't reach it). **Stop the run** and report the error — or that it's missing. **Never commit that work from here.**

**3. Does the commit carry the right trailer?**

```bash
git log -1 --format='%(trailers:key=Task,valueonly)'
```

It must return exactly the first 8 chars of the `task_id` you **already have** from `list_tasks` (step 2) — not the one in the report. **Use exactly this accessor**: it's the one `scripts/mark_deployed.sh` reads. `%B` plus a "contains `Task:`" check is weaker and approves trailers the deploy never sees.

- **Correct** → continue.
- **Missing, or another task's** → `git commit --amend` to fix it (it isn't pushed yet — under run-plan it never is before close), and note it in the summary. The trailer goes in **its own trailer block**: last line of the message, preceded by a blank line. It's this step's only git write, and it changes metadata, not the tree.
- **After amending, re-run the same command** and confirm the value.
- **If the amend fails** → stop the run and report the sha.

**4. Retain the sha** (`git rev-parse --short HEAD`) for the final summary.

**Don't push here.** The push goes once, at close (7.1).

### 6. Failure handling

A failed task **isn't committed**: its changes stay in the working tree for the user to review or discard. run-plan neither commits nor cleans them, and doesn't touch the run's previous commits (no `git reset`, no automatic `git revert`).

**Autonomous:** stop executing tasks and **go to step 7 with a partial result** — same as confirm's `abort`. **Never end the run here without step 7**: the already-verified commits still need their push decision, and 7.2 and 7.3 have explicit partial-run cases.

```
[i/N] <NNN> — FAILED ✗
Reason: <what solve-task reported>

The changes of <NNN> were left uncommitted in the working tree.
```

Tasks left unrun are marked **`— not executed`** (where the run was cut), distinct from **`⊘ skipped`** (a decision: the user skipped it, or its blocker failed).

**Confirm:** offer options.

```
[i/N] <NNN> — FAILED ✗
Reason: <...>

Options: retry / skip / abort
```

In all three, **the working tree has the failed task's changes on top, and run-plan doesn't touch them** (no `git checkout --`, no `git stash`, no `git clean`).

- **retry** → ask the user to resolve the state, and only then re-delegate.
- **skip** → mark the task skipped (and its dependents), **but still ask the user to resolve the working tree before continuing**: otherwise the next task's commit would sweep those changes up under the wrong trailer.
- **abort** → go to step 7 with a partial result, leaving the tree as is.

### 7. Close

#### 7.1 Push

Decided by `<run_branch>` vs `<base_branch>`, not by the run's mode:

- **`<run_branch>` ≠ `<base_branch>`** → `git push -u origin <run_branch>`. The human gate remains at the merge.
- **`<run_branch>` == `<base_branch>`** → **don't push.** Pushing the base triggers the deploy — the user triggers it. The commits stay local and the summary says so.
- **`<base_branch>` indeterminate** → don't push, and say why (fail closed, see Setup).

A single push, not one per task. If it fails (diverged remote, no upstream, credentials) → don't retry blindly: report the error and leave the local commits. The run still succeeded; publishing didn't.

#### 7.2 Pull request

Open the PR against `<base_branch>` **only when all four hold:**

1. **7.1 pushed** — on the base there's no PR to open.
2. **The run finished complete**: no task failed or was skipped. If partial → don't open; leave the assembled command in the summary.
3. **No open PR for that branch yet** — check with `gh pr list --head <run_branch> --state open`. If one exists, report its URL; a resumed run normally gets here twice.
4. **Not invoked with `--no-pr`.**

```bash
gh pr create --base <base_branch> --head <run_branch> --title "<title>" --body <HEREDOC>
```

Body:

- `## Summary` — what the set of tasks does, 2-4 lines: what changes for whoever uses this, not the sum of commit messages.
- `## Tasks` — one line per completed task, with its short id.
- `## Test plan` — how it was verified (the test command from CLAUDE.md and its scope).

**No AI attribution**: no `Co-Authored-By: Claude`, no `Claude-Session:`, no "🤖 Generated with Claude Code".

**Stop there. Don't merge.** Merge and deploy are the user's. If `gh pr create` fails, report the error — the branch is already pushed and the PR can be opened by hand.

#### 7.3 Final summary

The header is `run-plan completed` if every task in the queue ran, `run-plan stopped` if a failure or an `abort` cut it. The rest of the block is the same in both cases.

```
run-plan stopped
Branch: <current-branch>

✓ 001-setup-db           a3f9c21
✓ 002-auth-service       7b1e044
✗ 003-user-model         FAILED (uncommitted)
· 004-integration-tests  not executed (the run was cut at 003)

2/4 completed, 1 failed, 1 not executed
2 new commits on <run_branch> — pushed ✓
PR: <url>
```

| Mark | Meaning | When |
|---|---|---|
| `✓` | committed and verified | the normal case |
| `✗` | failed | FAILED header, or 5.1 found a contradiction |
| `⊘ skipped` | **decision**: someone skipped it | `skip` in confirm, or its blocker failed |
| `· not executed` | the run was cut before reaching it | autonomous that stopped, or `abort` in confirm |

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
