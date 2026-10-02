---
name: meridian-weekly-report
description: "Generate a non-technical weekly report for one or more projects, combining timeline events and git history from the past week. Targets the whole team (devs + stakeholders). Saves to reports/ in the vibe workspace."
---

# Meridian Weekly Report

Generates a weekly report — no technical jargon — combining what happened in the Meridian timeline and in git history over the last week(s). Unlike `/meridian-recap` (which summarizes the current session), this skill looks back in time, not at the conversation.

## HARD PROHIBITIONS

- ❌ No technical terms without explaining them (no "refactor", "PR", "async", "schema", etc.)
- ❌ No code snippets or file/function names
- ❌ Don't describe *how* something was implemented — only *what* changed and *why*
- ❌ Don't invent progress not backed by the timeline or git log

## Setup

Read the template at `.claude/templates/weekly-report-template.md` before generating the document. Follow its structure and authoring rules to the letter.

## Process

### 1. Resolve the date range

No argument: last 7 days ending today. Compute with `date`, never by hand:

```bash
week_end=$(date +%Y-%m-%d)
week_start=$(date -v-6d +%Y-%m-%d 2>/dev/null || date -d '6 days ago' +%Y-%m-%d)
```

If the user passes an explicit range (e.g. "week of the 10th to the 14th", "last 2 weeks"), use that instead.

### 2. Resolve project(s)

- No argument: use `meridian-project: <project>` from the active project's CLAUDE.md.
- If the user names several projects (e.g. "report for meridian and vibedashboard"), or if invoked from the root of a monorepo with more than one `meridian-project` declared, cover them all — one "By project" section each.

### 3. Collect data per project

For each project:

**Timeline (primary source):**
```
mcp__meridian__list_timeline(project=<project>, limit=100)
```
Keep only events whose timestamp falls within `[week_start, week_end]`. They are the most reliable source of "what got completed" (`task_completed`, `task_deployed`, `feature_completed`).

**Git log (complementary source, if the project is a known local repo):**
```bash
git -C <repo_path> log --since="<week_start>" --until="<week_end> 23:59:59" --oneline --no-merges
```
Use this to fill in context or detect work that left no trace in the timeline (fixes, docs, chores — not everything goes through a task). Don't list raw commits in the report; they are input for writing, not final content.

**Open or blocked tasks (for "Blockers or risks"):**
```
mcp__meridian__list_tasks(project=<project>, status=["blocked", "pending"], include_done=False)
```
Only mention something here if a task is actually blocked or has a flagged risk — don't list the normal pending backlog.

If a project had no timeline events or commits in the range, don't invent: that project's section says "No changes this week" under "What progressed" and "Blockers" and "Next week" are omitted if there is nothing concrete.

### 4. Generate the document

Use the structure of `.claude/templates/weekly-report-template.md`:

**Meta block:**
```
---
week_start: YYYY-MM-DD
week_end: YYYY-MM-DD
projects: [<name>, <name>, ...]
author: <infer from git config (`git config user.name`)>
---
```

**Body:**
- `Executive summary` — 2-4 sentences, overview of the week (mandatory)
- `By project` — one `### <name>` subsection per project, with `What progressed`, `Blockers or risks` (optional) and `Next week`
- `Pending / open decisions` — optional, only cross-project items or something concrete for the following week
- Optional technical block at the end, only if there are decisions or system areas worth recording for the technical team (completed tasks with their id, features touched)

**Writing rules:** the same as `recap-template.md` — clear, direct tone, short sentences, no nested bullets, translate jargon.

### 5. Present and save

Show the generated document and save it to Meridian immediately — without asking for confirmation.

Save under the **first project** in the list (or the only one). The `projects` frontmatter already records that the report covers more than one.

```
mcp__meridian__create_doc(
  project=<first project>,
  folder="reports",
  filename=weekly-report-<week_start>-<week_end>.md,
  content=<content>
)
```

### 6. Confirm save

```
Saved: reports/weekly-report-<week_start>-<week_end>.md (project: <project>)
```

## Rules

1. The document is for people, not machines — prioritize clarity over completeness.
2. Every claim of progress must be backed by the timeline or the git log — never infer achievements from memory or the conversation.
3. A project with no activity in the week is declared so explicitly, not omitted or padded.
4. The user may pass a date range or a list of projects as argument — use them instead of the defaults.
