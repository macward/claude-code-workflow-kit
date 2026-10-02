# Notes on `/meridian-run-plan` — evidence and decisions

This is **not the process**: the process lives entirely in `SKILL.md` and runs without reading this file. Here is the evidence behind the less obvious rules — what was measured, when, and which earlier wording turned out to be wrong.

Read it when you need to **change** one of those rules. It is kept separate because it is expensive to hold in context on every turn and is only needed when editing the skill. The evidence on the solve-task side (nested gates, the run-plan → solve-task boundary, why the commit lives there) is in `.claude/skills/meridian-solve-task/NOTES.md`.

---

## 2026-09-12 trim

`SKILL.md` was 459 lines (41KB, ~10K tokens) re-read on every turn of a run that can last dozens of tasks. It was trimmed to rules and the evidence moved here, as was done with solve-task. The hard rules remain at every entry point where they apply (self-sufficiency per section beats DRY); what was removed was the why.

The **Key Principles** section was removed: it summarized the whole file, and one of its bullets —"a task only enters when its blockers are `done`"— was exactly the admission filter that step 3 forbids (see below). A summary that contradicts the process is worse than none.

## Why solve-task does the commit and run-plan only verifies

The message is written where the information is: the diff, the criteria and why the work ended up that way. From run-plan you see a title and a prose report. When the commit lived here, the price was an entire defensive step to detect that solve-task had committed "on its own" — a sign that the contract was fighting the design. Verifying from outside against `git` is more robust than producing from outside.

## Why an interrupted run resumes by itself

It is a direct consequence of every task being committed when it finishes. Before, an interrupted run left N tasks of uncommitted work and the next invocation rejected it for a dirty tree.

## Why never a literal `main`, and detached HEAD

In a project with base `master`, comparing against `main` reads the base as "isolated branch" and publishes straight onto it. Detached HEAD: `git rev-parse --abbrev-ref HEAD` returns the literal `HEAD`, which passes the `≠ <base_branch>` test as if it were a working branch, so 7.1 would try to push something that is not a branch.

## Why the queue orders and doesn't filter (step 3)

The earlier rule said "a task enters only if all its blockers are `done`": an admission filter. When building the queue none of the plan's tasks is `done` yet, so a 001→002→003 chain admitted exactly one. A 6-task chained plan announced `run-plan started — 1 tasks` and the queue grew silently in step 5: every `[i/N]` was wrong and the arithmetic of 7.3 lost its meaning. The step 4 example —which lists `002 (depends_on: 001)` with 001 still pending— always showed the correct behavior; the rule was what didn't describe it.

## Why the `Branch` and `PR on close` lines of the announcement

A long run can compact midway, and `<run_branch>` travels in every delegation as the branch solve-task verifies against before committing. If it existed only as a remembered variable, the delegation after a compaction would have nothing to pass. The PR line was added by the same argument: `--no-pr` was the only datum of 7.2 with nowhere to anchor.

## Why `--confirm` is less control than before

With inline execution the user saw the full review, the test output and every edit, and could cut at any point; the principle said "retry / skip / abort at every decision" and it was literal. Today it is one decision per task, plus another if it fails. The trade was deliberate —the context boundary is what allows long runs—, but a guarantee that shrank and wasn't rewritten is a promise the skill doesn't keep. Since 2026-08-11 solve-task also delegates when invoked on its own, so without `--inline` there is no more visibility than here.

## Why delegate to a subagent and not inline

Inline, each task leaves in the orchestrator's context its full `context_refs`, every edit, the test output twice and the entire reports of both gates; with large N the run compacts midway and run-plan loses the state with which it verifies its own invariants. In a subagent only the step 10 report comes back, which solve-task already defines as the contract. Nothing important is lost on the way: the code, the commit and the state in Meridian don't travel through the context, and 5.1 verifies against `git`.

An explicit `<repo_root>` matters mostly in worktrees: the feature's repo is **not** the checkout the invocation came from, and a subagent starts with its own working directory.

## Why the literal header

When the child rewrote the header —or described the failure in prose with no header— and the failed task hadn't touched files, 5.1 saw a clean tree with no commits and recorded it as `done ✓ (no changes)`: a broken task recorded as completed.

## How the subagent is awaited: the evidence

- **Metadata, not report (2026-08-07 run).** The step said "wait for the subagent to finish", correct intent, but the only candidate for "waiting" was the tool call, which returns in seconds with the instruction to *continue with other work*. Read literally, the orchestrator was authorized to keep working with two live children on top of it. The "idle" alerts of that run were read as end of task.
- **Polling with Bash (2026-08-13, "seed" feature in `pfrm0301`).** Task 007 did 48 turns of `echo waiting` waiting for its gates: 8.14M tokens, 23% of the task's total cost. 005 did 26, 20%. The ones that didn't poll (006, 009) didn't have that cost. There is also a global hook that blocks the pattern (`hooks/block-gate-wait-polling.sh`).
- **`.git/index.lock` (2026-08-08).** Two processes committing in parallel on one repo left **6 of 13 commits**, silently losing the rest except for `fatal: Unable to create '.git/index.lock': File exists`. A run that "takes advantage" of the child's time is not faster: it corrupts the N-commits guarantee, which is the only thing run-plan contributes.
- **`name:` hangs (2026-08-08).** With a name the child is spawned as an addressable teammate (`task_type: in_process_teammate`). After four minutes it hadn't touched a file, committed or reported; it had to be killed. The same brief without `name:` finished in 29 seconds with commit, trailer and header.

## The notification diversion to the grandparent

**Correlation, not cause.** The `name:` test showed together the hung child and its nested agent's result delivered to run-plan, and this section attributed the second to the first. On tasks 004 and 006 of the following run the diversion was observed **also without `name:`**, at the third nesting level. Removing `name:` fixes the hang, not the diversion — and believing it does leaves the failure mode without a defense.

**Mechanism, observed on 2026-08-21.** A gate agent opened its report explaining why it delivered it where it did:

> I couldn't resolve `general-purpose` as an addressable peer (no matching agent
> found via SendMessage), so I'm reporting the result directly here instead.

The grandchild tries to reply to the child **by name**, the name doesn't resolve —`general-purpose` is an agent type, not an address— and it falls to the only destination left, upward. That is why it doesn't depend on `name:` and can't be fixed from the repo: the fallback lives in the reporting agent.

**Second symptom (2026-08-20 and 2026-08-21).** What was documented was "the child doesn't receive the review **and reports anyway**". Twice the opposite happened: the child kept waiting and notified with a one-line `<result>` with no header (`Waiting for the re-review`). "A notification is not a termination" covered it, but its only instruction was *wait again*, which on a child waiting for something that won't arrive is waiting forever.

**Forwarding works.** On the latest occurrence, the review forwarded with `SendMessage` came back `0 blockers, 0 suggestions` and the child closed citing it, noting that it had arrived by forwarding.

**The invented `GATE` line.** A subagent happened to claim "re-review landed clean, 0 blockers" with no backing; it retracted it itself in the final report. It is the failure mode that makes the third read useless: forwarding exists so the child doesn't have to choose between inventing and hanging.

## Why the per-task time bound

Without a bound a run gets stuck with no output or diagnostic: a test waiting for a connection to a DB that isn't there, or a forgotten `input()` in a fixture. `/goal` doesn't help there — the session isn't finishing, it is blocked. `ListAgents` is optional because the tool surface is not the same for every agent type, and a `ListAgents` that doesn't resolve can't be the only path to the cut.

## Why the third read of the report

Silence is not evidence of anything. A subagent that never spawned, died on its first tool call, ate a permission denial or returned a truncated response is indistinguishable from the outside from a task that ran and touched no files. And the judgment gates are the only thing separating "the code passed the tests" from "someone who didn't write it looked at it": a `done ✓` without `GATE` lines is exactly the diversion case, in which solve-task never received the review and reported anyway.

## Why 5.1 queries Meridian in the `0` case with a clean tree

It is the only check in the step not done against git, on purpose: git doesn't distinguish "had nothing to do" from "did nothing", and the task's state does. `get_task` is authoritative, machine-readable, cheap, and run-plan already has credentials to read it.

## Why the exact trailer accessor

The check feeds `scripts/mark_deployed.sh`, which reads with `%(trailers:key=Task,valueonly)`. Verifying with `git log -1 --format=%B` and asking whether it "contains" `Task: …` is weaker than the consumer: `%B` is satisfied by a `Task:` line anywhere, while `%(trailers:...)` only sees the last paragraph, and only if it parses as a trailer block. With the weak check, run-plan approved a commit the deploy was never going to see, and the task was silently skipped. Appending `Task: <id>` to the end of a text paragraph when amending produces exactly that message.

## Why the autonomous step 6 goes through step 7

This branch used to print a terminal block and end. That left the `i-1` already-verified commits unpushed, with no summary in the 7.3 format and saying nothing to the user about publishing — while 7.1 declared that the push depends on the branch "not the run's mode" and 7.2 and 7.3 had explicit partial-run cases reachable only through step 7. A cut run is still a run that has to be closed.

## Why `skipped` ≠ `not executed`

In the old summary they looked the same and they are not: in an autonomous run that gets cut, no task was *skipped*, their turn simply never came. On resume both go back to the queue, but only one was a decision.

## Why the PR only on a complete run

A PR with half a plan in it announces finished work that isn't. The already-open-PR check is not an exceptional case: a resumed run reaches 7.2 for the second time.
