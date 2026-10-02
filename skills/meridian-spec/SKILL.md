---
name: meridian-spec
description: "Write a concise, codebase-grounded Software Design Document (~30-60 lines) for a feature: public surface, hard constraints, where it lives, what's out of scope. Not an implementation plan."
---

# Meridian Spec

Generate a short SDD that answers a single question: *what does someone need to know to implement this feature without asking again*.

## Philosophy

A well-calibrated SDD contains **3 things + 1 negative**:

1. **What the feature is** — short goal and public surface.
2. **Hard rules** — authorization and security invariants.
3. **Where it lives in the code** — new files, modified files, integrations.
4. **Non-goals** — what's out of scope.

If something only affects the *how*, it doesn't go in the SDD. If it changes the *what*, it does. When a requirements doc exists, it already defines the *what* — don't redefine it.

**Target size: 30-60 lines** — the target, not an aspirational ceiling. Past 100, there is content that belongs in another artifact.

## Prerequisites

- Meridian connected (`list_docs`, `read_doc`, `create_doc`). If not, tell the user and stop.
- Active project: read `meridian-project: <project>` from CLAUDE.md.
- Always save through `create_doc` — never write to `specs/` with Write/Edit.

## Process

### 1. Resolve the slug and check for existing specs

**`<slug>`** names the file (`sdd-<slug>.md`) and must match the requirements doc's (`requirements-<slug>.md`): `meridian-task-breakdown` finds both by it. Take it from the invocation, from an existing requirements doc, or derive it in kebab-case from the feature name.

```
mcp__meridian__list_docs(project, folder="specs")
```

- **`sdd-<slug>.md` exists** → read it; it's the base to extend (step 6 overwrites it with `upsert=True`).
- **A spec on the same topic under another name** → ask whether to extend it, rename or replace. Don't duplicate.

### 2. Read prior context

If `requirements/requirements-<slug>.md` exists, read it as input — not mandatory:

```
mcp__meridian__read_doc(project, "requirements", "requirements-<slug>.md")
```

Don't re-ask what's already documented. If the scope still can't be described, ask **once**; stop if it's still unclear.

### 3. Ground in the codebase

Read the real files the feature touches or extends: existing modules and their public interfaces, patterns and conventions in use, stack constraints. Reference modules by their real path (`services/foo.py`, `Repositories/Bar.swift`) — a spec that ignores the code is fiction. If some file can't be read, note which and continue.

### 4. Draft

Use exactly this structure. Omit sections that don't apply — no N/A markers:

```markdown
# Feature: <Name>

## Goal
<1-2 lines: what it does and why>

## Surface
- <operation / tool / endpoint / command>
- <...>

## Authorization
- <rule 1>
- <...>

## Security
- <constraint 1>
- <...>

## Architecture
- <new module: `path/to/file.py`>
- <modified module: `path/to/file.py` — what changes>
- <key integration>

## Non-goals
- <out of scope 1>
- <...>
```

**Rules:**
- One-line bullets. A bullet needing 3 lines is noise or belongs in the task breakdown.
- **Architecture**: real repo paths, never invented ones.
- **Surface**: the operation name + main inputs in one sentence. The exact signature lives in the code.
- **Non-goals** isn't optional — there is always something worth excluding.
- A real constraint goes under Security or Architecture; a doubt gets resolved before writing, not listed.

**Forbidden:**
- "Risks", "Open Questions", "Implementation Plan", "Data Model" sections, extensive "Metadata".
- Numbered implementation steps — that's `/meridian-task-breakdown`.
- Full IDL (`operation: ... inputs: ... output: ... errors: ...`).
- ASCII diagrams — they almost always repeat the code.
- Narrative paragraphs longer than 3 lines — the one-line Goal replaces an overview.

If the draft passes 100 lines, stop and ask what's superfluous.

### 5. Show the user before saving

```
SDD: <title>
Lines: <count>
Filename: sdd-<slug>.md

Save to specs/?
```

Wait for confirmation.

### 6. Save

```
mcp__meridian__create_doc(
    project,
    folder="specs",
    filename="sdd-<slug>.md",
    content=<content>,
    feature=<feature-slug>,   # only if the feature exists as a Meridian entity
    upsert=True,
)
```

- **`filename` explicit**: without it the name derives from the H1 (`# Feature: MCP Tool Cleaning` → `sdd-feature-mcp-tool-cleaning.md`), and every regeneration leaves a new doc next to the old one.
- **`upsert=True`**: without it, re-running on a feature with an SDD fails with `DocumentAlreadyExistsError`.
- **`feature`**: pass it only when the feature exists as an entity; a nonexistent slug fails with `FeatureNotFoundError`. Usually omitted — task-breakdown creates the feature and re-links the doc.

If `create_doc` fails, show the error and offer to retry.
