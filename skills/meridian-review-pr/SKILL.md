---
name: meridian-review-pr
description: "Integration review of a feature PR against its SDD and Meridian tasks. Looks for failures that exist only BETWEEN tasks (cross duplication, interface drift, leftovers, migration vs model, spec fidelity), not per-task correctness. Proposes comments and posts them only after user OK."
---

# Meridian Review PR

Reviews the **accumulated diff** of a feature PR against the spec that originated it.

Usage: `/meridian-review-pr <pr-url-or-number>` (no argument: the current branch's PR)

## Why it exists

`/meridian-solve-task` already runs `code-review-expert` per task, scoped to *that* task and against *its* acceptance criteria, **before the commit**. That covers local correctness well.

What that review can't see, by construction, is everything that exists only **between** tasks. That's this skill's sole target:

| Class | Example |
|---|---|
| Cross duplication | Task 3 and task 9 each wrote a near-identical helper; both passed their review |
| Interface drift | Task 2 defined a signature, task 7 changed it, task 4's caller went stale |
| Dead code | Leftovers of an approach abandoned mid-plan |
| Migration vs model | One task wrote the Alembic migration and another the SQLAlchemy model; out of sync |
| SDD fidelity | Is what was built what the spec said? No task answers that |
| Undeclared surface | Endpoints, MCP tools or env vars that appeared without being in the spec |

**Don't re-review per-task correctness.** If a finding fits entirely within a single task, it already had its review — omit it unless it's serious and evident.

## Human gate (mandatory)

Posting comments on GitHub is an **outward action that doesn't clean itself up**: three runs leave three batches of comments.

- **Never post without explicit OK.** The skill presents the findings in the terminal and waits for confirmation.
- **Post only blocking and major.** Minor (nits, style) goes in the local summary, not to GitHub.
- **Never merge, never deploy, never push commits.** This skill only reads and, after OK, comments.
- **Never fix the code.** At this point it's already committed; if something is wrong, it's reported and Max decides.
- Unattended (`/schedule`, `/loop`) it may at most present the findings. Posting is triggered by Max.

## Setup

1. Read `meridian-project: <project>` and `branch: <base_branch>` from the active project's CLAUDE.md.
2. Resolve the PR:
   - With argument: URL or number.
   - Without argument: `gh pr view --json number,url,headRefName,baseRefName` on the current branch. If there is no PR → warn and stop.
3. Verify Meridian is connected (`mcp__meridian__list_tasks`). If not → continue anyway, but warn that the review runs **without spec criteria** (degraded to a plain integration review).

## Process

### 1. Gather the material

```bash
gh pr view <pr> --json title,body,baseRefName,headRefName,commits
gh pr diff <pr>
git log <base>..<head> --format='%H %s%n%b'   # the Task: trailers live here
```

- **Accumulated diff**: `gh pr diff`. It's the object of the review, not the per-task diffs.
- **Tasks**: extract the ids from the `Task: <id>` trailers of the commits. For each, `mcp__meridian__get_task` → goal, acceptance criteria, constraints.
- **Spec**: `mcp__meridian__list_docs(project, folder="specs")` and read the `sdd-<slug>.md` matching the branch slug. If it doesn't show up, also look in `requirements/`.

If the diff exceeds ~2000 lines, review it by area (by directory under `src/meridian/`) and consolidate, instead of silently truncating.

### 2. Review

Launch `code-review-expert` with this brief:

```
Integration review of PR #<n>: <title>
Branch: <head> → <base>. <N> commits from <M> Meridian tasks.

SDD (what this feature was supposed to be):
<spec content>

Tasks that produced this diff:
- <id> <goal> | criteria: <acceptance_criteria>
  (one per line)

SCOPE — read carefully:
Each task ALREADY had its own code review against its own acceptance
criteria, before commit. Do NOT re-review per-task correctness.

Review ONLY what emerges from combining the tasks:
- Duplication across tasks (near-identical helpers, parallel implementations)
- Interface drift (a signature changed by a later task, stale callers left behind)
- Dead code from approaches abandoned mid-plan
- Alembic migration vs SQLAlchemy model disagreement
- Fidelity to the SDD: was what the spec described actually built?
- Undeclared surface: endpoints, MCP tools, env vars not in the spec

Project rules that override defaults: see CLAUDE.md — async all the way,
no bare `except Exception`, no `Any`, DI over singletons, typed signatures.

For each finding return: file:line, severity (blocking | major | minor),
one-sentence defect, and a concrete failure scenario. No praise, no summary
of what the code does. If you find nothing, say so plainly.
```

### 3. Present (always, before posting)

```
Integration review · PR #<n>  <title>
<head> → <base>  ·  N commits, M tasks, <±L> lines

BLOCKING (2)
  src/meridian/db/models.py:84
    Migration 0021 adds `owner_id NOT NULL` but the model declares it
    optional → inserts from REST fail at runtime.
  ...

MAJOR (1)
  ...

MINOR (3)  — not posted, stay here
  ...

SDD: 4/5 requirements covered. Missing: rate limiting on /api/v1/auth.

Post the 3 blocking/major findings as comments on the PR? [y/N]
```

If there are no findings, say so and end — don't open empty comments.

### 4. Post (only after OK)

- One line comment per blocking/major finding: `gh pr comment` doesn't anchor to a line; use `gh api repos/{owner}/{repo}/pulls/{n}/comments` with `path`, `line` and `side`.
- If anchoring fails (line outside the diff), degrade to a general PR comment with the path in the text — don't lose the finding silently.
- One summary comment with the verdict and the SDD check.
- **No AI attribution** in any comment: no `Co-Authored-By: Claude`, no `Claude-Session:`, no "🤖 Generated with Claude Code".

### 5. Close

Report what was posted and what stayed local. Remind that the merge is Max's.

## Re-execution

It's designed to run several times on the same PR (review → fix → push → review).

- Before posting, read the existing comments (`gh api .../pulls/{n}/comments`) and **don't repeat** an already-commented finding that's still current.
- If a previous finding is already fixed, mention it in the local summary. Don't resolve threads automatically — Max does that.

## Error handling

| Situation | Action |
|---|---|
| No PR for the branch | Warn and stop; suggest `/meridian-run-plan` (opens it on a completed run) or `gh pr create` |
| Meridian not connected | Continue in degraded mode (no spec or tasks), warning |
| No `Task:` trailers in the commits | Continue without task criteria; warn that the PR isn't linked to Meridian |
| SDD not found | Continue without the fidelity check; say so explicitly |
| Huge diff (>2000 lines) | Review by area and consolidate; never truncate silently |
| `gh` not authenticated | Report and stop before reviewing |

## Key Principles

- **Only what emerges from combining tasks.** Per-task correctness was already reviewed. Repeating it is noise that buries what matters.
- **The spec is the criterion, not taste.** The central check is "is this what the SDD said?".
- **Proposes, doesn't post.** GitHub is outward; the human gate goes before the first comment.
- **Reports, doesn't fix.** The code is already committed; what to do with a finding is Max's call.
- **Re-runnable without accumulating noise.** Deduplicate against existing comments.
