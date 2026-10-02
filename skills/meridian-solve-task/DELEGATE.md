# Delegating `/meridian-solve-task` (case 2 of `## Where it runs`)

Read this only on a **direct user invocation without `--inline`**. The subagent never needs it.

Running in the user's context, the skill inherited the whole prior conversation and reread it on every turn; delegating starts the child with only the system prompt, `SKILL.md` and the brief (numbers in `NOTES.md`). What the user loses is watching every edit and stopping midway — `--inline` gives that back.

## How to spawn and wait

The rules are in `/meridian-run-plan` step 5, `#### How to wait for the subagent`, and apply in full: `subagent_type: "mer-task-runner-full"`, **without `name:`**; the `Agent` tool returns metadata, not the report; wait by ending the turn until the notification that carries the header; cut with `TaskStop` if the budget expires.

Retain `<repo_root>` with `git rev-parse --show-toplevel` **before** spawning, and always pass it: the subagent doesn't inherit the working directory.

## Brief

```
Invoke the /meridian-solve-task skill for <task NNN | the first in-progress or pending task>
of project <project>.

You are already inside the context boundary: run the full process here and do NOT
delegate this skill again.

Invocation context:
- The repo is at <repo_root>. `cd` there as the first step, before anything
  else, and do it again in every bash call: the cwd doesn't persist.
- Standalone invocation: you commit the task and apply the Git Policy for the push
  (on <base_branch> you commit and do NOT push; on a working branch you also
  push). You don't open a PR and you don't merge.
- You have no channel to the user: everything the process would resolve by asking
  is resolved by closing with the step 10 failure report.

Budget: 30 minutes of wall-clock for the whole task. Bound every command that could
hang — the test one first — with an explicit timeout, and if something exceeds the
budget cut it and close with the failure report instead of waiting.

Turn budget: 60 tool calls as the budget, 100 as the hard ceiling. At 60, stop
exploring and converge with what you already know. At 100, stop and close with
the failure report, `Stage: turn budget`, saying which step you were on — the
changes stay on disk and the task stays in-progress, so it recovers by
re-invoking. It's not a clock budget: a run can burn 200 turns well within the 30
minutes.

The test command is in CLAUDE.md, literal and verified. Copy it as-is: don't probe
the environment (looking for Postgres, trying ports, `which pg_ctl`). If the suite
fails oddly, the cause is in the symptom table of that same section.

Return the skill's final report (its step 10) in full and verbatim, including the
git status line. The first line must be exactly one of that step's two headers,
without rewriting them: `Task <NNN> done ✓` or `Task <NNN> FAILED ✗`.
If FAILED, also include the line `Stage: <stage> — <exact error>`.
```

## Tip for the user: `/goal`

The goal check verifies the criteria *within* the turn but can't keep the session from ending before reaching it. For an external guarantee the user can set a goal before invoking (the skill can't set it itself):

```
/goal task NNN meets all its acceptance criteria and tests pass, stop after 5 tries
/meridian-solve-task NNN
```
