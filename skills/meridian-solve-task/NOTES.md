# Notes on `/meridian-solve-task` — evidence and decisions

This is **not the process**: the process lives entirely in `SKILL.md` and runs without reading this file. Here is the evidence behind the less obvious rules — what was measured, when, and which earlier wording turned out to be wrong.

Read it when you need to **change** one of those rules. A rule whose evidence nobody remembers undoes itself in the next refactor; that is this file's job, and it is kept separate because it is expensive to hold in context on every turn and is only needed when editing the skill.

---

## Nested gates: what is verified and what is not

**The gates of steps 6 and 7 run even when the skill is already inside a subagent** — verified on 2026-08-07. The chain `/meridian-run-plan` → `/meridian-solve-task` → gate agent ran to completion on two independent tasks, and the innermost agents produced reviews with line numbers and findings that the middle level had not passed to them: evidence that only an agent that actually read the files can produce. That settles only one of the two questions: **the innermost spawn is not silently declined**.

**That their result gets back to whoever launched them is not verified, and it is the open failure mode.** On tasks 004 and 006 of the 2026-08-08 run, the grandchild's notification was observed arriving in the **grandparent's** context (run-plan) instead of the parent's (solve-task): the gate ran and spoke, but its parent never received it and reported anyway. On 004 nobody noticed; on 006 it was saved by the agent itself getting suspicious and going to fetch the output by hand. That is luck, not a guarantee.

An agent reading the files and its output reaching its parent are two different things, and the 2026-08-07 test only proved the first. It is the failure mode these gates exist to cover, one level down: **"I didn't receive the review" and "the review found nothing" are indistinguishable from the outside** unless they are explicitly distinguished.

**Three SKILL.md rules come from this, and none is cosmetic:** the literal `GATE …` line that steps 6 and 7 require, the 10-minute bound with `TaskStop` on expiry, and step 10's ban on emitting a success report without the two quoted `GATE` lines. The notification diversion is platform behavior and can't be fixed from here; **the defense is detecting the loss, not avoiding it.**

## The run-plan → solve-task boundary, and why the cause wasn't here

Closed on 2026-08-08. A subagent running the full process —including spawning its own nested agent— reaches the commit and returns its report with the exact header: the control run took 29 seconds and left the commit with its trailer readable by `%(trailers:key=Task,valueonly)`.

What was failing was the orchestrator side. The `Agent` tool returns spawn metadata and not the report, so run-plan kept working —and committing— with the children still alive, and the two parties clobbered each other on `.git/index.lock`. Measured: two processes committing in parallel on one repo left **6 of 13 commits**, silently losing the rest except for `fatal: Unable to create '.git/index.lock': File exists`. The fix lives in step 5 of `/meridian-run-plan`.

What is closed is **that** boundary, measured on that call site. The same asynchronous mechanism governs every other spawn in the repo and not all of them were audited.

## Why the commit lives in this skill and not in run-plan

The information the message is written from is here: the diff, the criteria and why the work ended up the way it did. The orchestrator has the task title and a prose report, and a commit message written from outside is worse.

The previous split also forced run-plan to defend itself against this skill committing "on its own" — a sign that the contract was fighting the design.

**The `<base_branch>` row used to say "nobody — the user triggers it"**, which was the gate the Git Policy declares unnecessary (the irreversible line falls between the commit and the push, not before). It was expensive: it left the user committing a task's work by hand, and the `Task:` trailer —which exists precisely so a machine writes it— got forgotten, so the task never reached `deployed`. It is the failure mode `/meridian-task` was created to cover, and it slipped in through here anyway.

## Why step 8.1 checks whether there is anything to commit

Before, `git add -A` ran with an empty index, `git commit` exited non-zero, and the skill reported `Commit FAILED: nothing to commit`: under run-plan that **cut an entire run short over a task that went perfectly**. A pure verification task ("confirm the migration is idempotent; don't add code if it already is") legitimately ends without touching files.

## Why the report lists the committed files

`git add -A` takes **everything** in the tree, including artifacts the task itself generated unintentionally: coverage files, `.pytest_cache` if not ignored, or the `docs/schema.sql` that pre-commit regenerates. run-plan guarantees a clean tree at the start of each task, so the scope is correct by construction; what was missing was the commit saying what it took with it.

## Why the two tables in step 10 are indexed differently

The success one by git situation, the failure one by the `Stage:` token the report already carries. Before it was a single table with both conventions inside, and whoever had to map a token to its line did so by inference on half the rows and by literal match on the other half.

## Why run-plan doesn't parse the report's trailer

The trailer is written by this skill, derived from the `task_id` it got from `get_task` (step 1) — not from the text of any report. run-plan verifies the already-made commit with `git log -1 --format='%(trailers:key=Task,valueonly)'` —the same accessor `scripts/mark_deployed.sh` uses when deploying— against the `task_id` it has itself from `list_tasks` (its step 5.1).

The two skills derive the trailer from the same authoritative source separately and then cross-check the result in git, which is machine-readable. Coupling them through the text of a report that also carries four sections of free prose (10.1) would be fragile, and the failure mode was silent: commit without trailer and the task outside the `done→deployed` cycle.

**Consequence for step 8.1:** the trailer has to end up in a real trailer block — last line, preceded by a blank line.

## Why the gates' iteration limit is 2

Steps 6 and 7 are **judgment** gates, not deterministic ones. A third attempt on a blocker that survived two fixes is almost never a fix: it is the review and the implementer disagreeing about something that needs the user.

Without that limit, the 3→6 loop has no exit condition and the subagent silently hangs its invoker — the same failure mode steps 4 and 7 already have covered.

## Why step 1 accepts a title prefix and a task-id prefix

Both forms are used: the plans from `/meridian-task-breakdown` number the titles `NNN-`, and `/meridian-task` creates a standalone task and passes its **8-character id**, which will never prefix an `NNN-slug` title. With only the first form, every invocation from `/meridian-task` ended with no match.

## Why direct invocation is delegated to a subagent

Measured over the project's 31 runs between 2026-07-11 and 2026-08-11 with `scripts/skill_cost.py --context`, when direct invocation still ran in the user's context:

| | |
|---|---|
| context inherited at start | median **76K**, p90 285K, max 626K |
| what the run added per turn | ~900 tokens |
| what it wrote per turn | ~370 tokens |
| inheritance share of total read | **56.5%** (198.9M of 351.9M) |
| in runs of <60 turns (25 of 31) | **81-85%** |

That is: most of what the model read was prior conversation that this skill didn't generate and didn't need, re-read on every turn. `--inline` exists because step 5 of run-plan referred to "solve-task invoked on its own" as the tool for taking a close look at a risky task, and without an escape hatch that capability would disappear from the repo.

## Why SKILL.md carries rules and not whys (2026-09-12 trim)

`SKILL.md` had reached 493 lines and `REPORT.md` 153: ~13K tokens that the subagent loads on every run and re-reads on every turn. A third of it was justification that already lived here, repeated next to each rule. It was trimmed to rules, and the delegation brief (`DELEGATE.md`, read only by the parent) and step 9.2 (`FEATURE_ENRICH.md`, only when a feature is completed) moved out to files that are read conditionally.

**What was deliberately not consolidated:** the hard rules remain repeated at every entry point where they apply (task `in-progress` on failure, `GATE` lines, literal headers in step 10 and in `REPORT.md`). It is the earlier decision that "self-sufficiency per section beats DRY": whoever enters through a step doesn't have to reconstruct the rule by reading another. What was removed was the duplicated **why**, not the rule.

The whys that lived only in SKILL.md follow below.

## Why it never compares against a literal `main`, and fails closed

The base is `main`, `master` or `develop` depending on the project. Comparing against `main` in a repo with base `master` reads the base as "isolated branch, I can push" and publishes straight onto it. Without `branch:` or `origin/HEAD`, the safe option is the one that doesn't publish: the commit publishes nothing. run-plan does the same reading in its Setup, and the two have to match: if one skill assumes the task is committed and the other refuses, every run on a repo without `branch:` dies on its first task.

## Why the commit goes before `done`

They are the skill's two durable states, one in git and one in Meridian. The other way around, any cut between the two (aborting hook, unexpected branch, dead session) leaves the task `done` with zero commits: it doesn't return to run-plan's queue —which loads only `pending` + `in-progress`—, never carries its `Task:` trailer, and `mark_deployed.sh` never moves it to `deployed`. Committing first, the worst case is an `in-progress` task with the work committed: recoverable and visible.

## Why batch calls in one turn

Measured over the runners' transcripts: **21% of turns were a single call with no dependency on the previous turn** (reading `context_refs` one at a time, grep sweeps pattern by pattern, edits to different files in separate turns). Each turn resends the entire context, so the cost is the number of turns, not the payload. Details in the CHANGELOG.

## Why step 4 forbids probing the environment and requires a timeout

Across 212 subagent transcripts, **47% of runs probed the environment** and it was 14% of all their bash commands; reading the symptom table costs one turn, rediscovering it cost thirteen. The timeout: a hung test (waiting for a DB that isn't there, a forgotten `input()`) never fails, and under run-plan it blocks the subagent, which blocks the orchestrator — with no output or diagnostic. A red test stops one task; an unbounded hung one hangs the whole run.

## Why simplify is limited to the task's diff

In a plan of N tasks, if 003 refactors what 001 did, 003's commit stops being attributable and the `Task:` trailer lies about what changed. And step 5 is the only point where mutating invalidates nothing: the judgment gates haven't run yet and the deterministic one is cheap to repeat. That is why the code is frozen afterwards: the gates judge the same thing that gets committed.

## Why a gate not received is not `UNVERIFIABLE`

`UNVERIFIABLE` is a verdict the verifier issued on a concrete criterion, and it presupposes that it spoke. If it didn't speak there is no verdict of any kind, and putting it in the step's soft slot turns the failure mode into a success with an asterisk.

## Why `writes` divergence doesn't block

There is no measurement of how accurate `writes` is in practice, and a gate on an uncalibrated signal rejects correct work. Step 8.3 **is** that measurement: it accumulates real divergences, and only with that recall in view is it decided whether `/meridian-analyze`'s overlap check goes from informational to gate.

## Why the enrichment carries no sha, GATE or tests

The `enrichment` is embedded alongside the summary and is what ranks the feed's semantic search. A text that is half paths and exit codes answers worse to "why didn't we touch production in the sidebar task?", which is exactly what the feed has to be able to answer. And an enrich failure doesn't degrade the report: the task is already `done` and committed, and saying otherwise would lie about work that did land.

## Why run-plan doesn't push on every task

A push per task would publish intermediate states of a plan that can still fail and be cut short. The run does a single push on close (its step 7.1).
