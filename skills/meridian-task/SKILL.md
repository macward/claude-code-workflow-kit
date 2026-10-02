---
name: meridian-task
description: "Create a single Meridian task from a natural-language description and solve it — no requirements, spec or breakdown. Use when the user describes something concrete to build now ('add X', 'make Y happen'). Multi-session features go through /meridian-requirements → /meridian-task-breakdown → /meridian-run-plan; an existing task through /meridian-solve-task."
---

# Meridian Task

Turns a description into a Meridian task and solves it on the spot.

Usage: `/meridian-task "<description of what to build>"`

## Why it exists

Between "record nothing" and the full pipeline (requirements + spec + breakdown + run-plan) there was nothing. For a feature that takes an afternoon, setting up the pipeline costs more than the work — so the rational default was to skip Meridian, and that's exactly what happened: in the two weeks after the `Task:` trailer was introduced, 12 of 16 task-less commits to `src/` were `feat(...)`.

This skill is that missing step. One task, zero documents, the same execution rigor.

**When NOT to use it:**
- The feature needs design decisions worth discussing first → `/meridian-requirements` (plus `/meridian-spec` if it has architecture).
- It's several pieces with dependencies between them → `/meridian-task-breakdown`.
- The task already exists in Meridian → `/meridian-solve-task NNN`.
- It's a `fix`, `docs`, `refactor`, `test` or `chore` → no task needed (Git Policy). Just do it.

## Setup

Read from CLAUDE.md: `meridian-project: <project>` and the full **Git Policy** section.

If no description was passed as argument, ask for it and stop. This skill doesn't guess what to build.

## Process

### 1. Ground the description in the code

Before writing the task, look at the codebase. A task whose `context_refs` are invented wastes more time than it saves.

- Locate the files the change will touch.
- Identify an existing pattern the change should follow (a sibling module, an analogous function).
- If the description is ambiguous in something that **changes the work** (not a cosmetic detail), ask now — one question, not an interrogation. If it's ambiguous in something minor, decide and note it as a constraint.

### 2. Write the task

```
mcp__meridian__create_task(
    project=<project>,
    title="<short, concrete title>",
    goal="<what to achieve and why, 1-2 paragraphs>",
    feature=<existing feature slug, or "misc">,
    scope_includes=[...],
    scope_excludes=[...],
    context_refs=["Files: src/...", ...],
    context_patterns=["<pattern to follow>", ...],
    changes_required=[...],
    acceptance_criteria=[...],
    constraints=[...],
    validation="<verification command or procedure>",
)
```

Two fields decide whether this is useful or not:

- **`acceptance_criteria`** — verifiable, not aspirational. "The endpoint returns 404 with `{detail}` when the doc doesn't exist" works; "the endpoint works fine" doesn't. The goal check in `/meridian-solve-task` (its step 7) will audit them one by one against the code.
- **`validation`** — whenever possible, an executable command (`uv run pytest tests/test_x.py`). A gate verified by command is worth far more than one verified by an LLM's judgment, and the solve skill reports the ratio.

For `feature`: check `list_features(project)` and reuse an existing slug if it fits. `misc` only if it genuinely belongs to none.

### 3. Confirm — a single stop

Show the user, compactly:

```
Task created: <title>
  id: <8 chars>   feature: <slug>

Goal: <1-2 lines>

Acceptance criteria:
  - ...

Validation: <command>

Starting implementation. (Ctrl-C to adjust the task first.)
```

It's an informational checkpoint, not a question: keep going unless the user interrupts. This skill exists to be cheap — asking for explicit approval here turns it into the pipeline it came to replace.

### 4. Solve

Run `/meridian-solve-task <id>` with the freshly created task, and follow that whole flow: implement → tests → code review → goal check → commit → mark done. Don't duplicate that logic here.

### 5. Close

The `/meridian-solve-task` report already includes `Commit trailer: Task: <id>`. Verify it's there and don't close without it: it's what keeps the commit from triggering the `scripts/hooks/commit-msg` warning and what moves the task to `deployed` on the next deploy.

This skill **doesn't commit on its own**: how far it goes in git is decided by `/meridian-solve-task` based on the branch (its step 8). The commit always happens, with its trailer; on a working branch it also pushes, and on `<base_branch>` it stops before the push, which is what triggers the deploy. In neither case is a PR opened or a merge done.
