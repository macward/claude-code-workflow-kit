# The `/meridian-solve-task` report (step 10)

The skill's **output contract**. Under `/meridian-run-plan` the orchestrator parses this format to decide whether to continue or cut the run: a malformed report reads as a different result from the real one.

---

Two **mutually exclusive forms**, decided by the first line, written with this exact text:

- `Task <NNN> done ✓` — the task was completed and marked `done` (step 9).
- `Task <NNN> FAILED ✗` — some stage was cut; the task stayed `in-progress`.

One of the two, never both or neither, never translated or decorated.

## Success report

```
Task <NNN> done ✓

GATE code-review: <N> blockers
GATE goal-check: <N>/<total> PASS, <X> cmd, <Y> judgment, <Z> unverifiable

Goal check: <N>/<total> acceptance criteria PASS
  verified by command [cmd]: <X>/<total>
  verified by judgment [judgment]: <Y>/<total>
<UNVERIFIABLE criteria, if any>

Branch: <current-branch>
Commit trailer: Task: <short task_id (8 chars)>
Committed files: <one per line, from git show --name-only HEAD>
<git status line — see below>
<writes divergence block — see below>
```

**The two `GATE` lines are mandatory and quoted verbatim** from each gate's `<result>` — never paraphrased, reconstructed or assumed. A success report missing either is invalid: the correct report was the failure one with `Stage: step 6 (gate not received)` or `step 7 (gate not received)`.

### Git status line (success)

| Situation | Line |
|---|---|
| standalone, committed and pushed | `Committed <short sha> and pushed to <branch>.` |
| standalone, committed, push failed | `Committed <short sha> — push FAILED: <error>. The commit is local.` |
| standalone, committed on `<base_branch>` | `Commit: <short sha> — not pushed (pushing the base is the user's trigger).` |
| under run-plan, committed on a working branch | `Commit: <short sha> — not pushed (the push belongs to the run's close).` |
| under run-plan, committed on `<base_branch>` | `Commit: <short sha> — not pushed (pushing the base is the user's trigger).` |
| `<base_branch>` indeterminate | `Commit: <short sha> — not pushed, couldn't determine the base branch.` |
| no changes in the working tree | `No changes to commit — the task touched no files.` |

### The `writes` divergence block

In every report that committed (8.1), right after the git status line:

```
Declared vs. touched writes:
  declared not touched: <one per line, or "none">
  touched not declared: <one per line, or "none">
```

If the task declared no `writes`, a single line — a valid result, not an error:

```
Declared vs. touched writes: the task declared no writes.
```

Informative only: it never turns `done ✓` into `FAILED ✗`, adds a `Stage:` line or cuts the run. Omitted when nothing was committed.

## Failure report

```
Task <NNN> FAILED ✗

Stage: <stage> — <exact error>

Branch: <current-branch>
Commit trailer: Task: <short task_id (8 chars)>
<git status line — from the table below>
```

The `Stage:` line is **mandatory**, right after the header. `<exact error>` is the **literal** error, not a paraphrase — under run-plan nobody else saw it; it may continue on following lines. These are the only valid tokens, one per failure exit of the skill:

| `<stage>` | Exit | `<exact error>` | Git status line |
|---|---|---|---|
| `step 1 (lookup)` | the argument matched no task, or several | what was searched; candidates if ambiguous | `Not committed: the task never started — the working tree is clean.` |
| `step 1 (dependencies)` | `depends_on` not `done` | ids/titles of the blocking tasks | `Not committed: the task never started — the working tree is clean.` |
| `step 2 (preflight)` | dirty tree before starting | `git status --porcelain` output | `Not committed: the working tree was already dirty before starting — those changes aren't this task's.` |
| `step 4 (tests)` | tests red after 3 attempts, or hung | last run's error, verbatim | `Not committed: the task's changes stayed in the working tree (tests red).` |
| `step 6 (code review)` | blockers after 2 iterations | open blockers, one per line, verbatim | `Not committed: the task's changes stayed in the working tree (unresolved code review blockers).` |
| `step 6 (gate not received)` | budget expired without a `GATE code-review:` line | what was expected, how long it waited, whether a notification without the line arrived | `Not committed: the task's changes stayed in the working tree (the code review never reached this context).` |
| `step 7 (goal check)` | criteria FAIL after 2 iterations | unmet criteria, one per line | `Not committed: the task's changes stayed in the working tree (goal check red).` |
| `step 7 (gate not received)` | budget expired without a `GATE goal-check:` line | what was expected, how long it waited, whether a notification without the line arrived | `Not committed: the task's changes stayed in the working tree (the goal check never reached this context).` |
| `step 8.1 (branch)` | HEAD isn't on `<run_branch>` | expected and current branch | `Not committed: expected <run_branch>, HEAD is on <current>. The run must stop.` |
| `step 8.1 (commit)` | `git commit` aborted | hook output or git error, verbatim | `Commit FAILED: <error>. The changes are in the working tree — the run must stop.` |
| `turn budget` | 100 tool calls reached without closing | which step and what remained | `Not committed: the task's changes stayed in the working tree (turn budget exhausted).` |

- The `Goal check` block also goes in a failure report **if the goal check ran** (step 7 and 8.1 failures).
- `GATE` lines that **actually arrived** are quoted verbatim; those that didn't are omitted, never invented.
- A failure report **never** says `done`.

`Branch` and `Commit trailer` go in **both** forms, always. The trailer itself is verified by run-plan in git (`git log -1 --format='%(trailers:key=Task,valueonly)'`), not parsed from here.

## 10.1 The report body

After the block above, in **both** forms, four prose sections. None is optional; in a failure report, steps that never ran are marked `didn't run`. The goal is that the reader can **decide whether to trust the work** without rereading the diff.

**What changed** — what the code does now, with `file:line`. Include what **wasn't broken** when touching a shared surface ("the 12 call sites of `X(repository:)` still compile unchanged").

**Tests** — the command and its **real scope**: full suite or subset, and the count. Linter state if there is one.

**Goal check caveats** — each criterion whose evidence is **weaker than its label** (a `[cmd]` proving half a condition). If none: `No caveats — the <N> criteria are verified by command end-to-end.`

**Simplify and review** — what each did, **including empty results** (`Simplify (step 5): no-op — 14 lines of implementation`, `Code review: no blockers`): a step that doesn't appear can't be told apart from a skipped one. This prose **doesn't substitute** for the `GATE` line: this section narrates, that one quotes.

No decorative bullets or filler. A section with nothing to say is short — but present.
