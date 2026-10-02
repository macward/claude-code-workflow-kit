---
name: meridian-timeline-note
description: "Add a short (2-4 line) non-technical milestone recap of the session to the project's timeline feed. Shorter than /meridian-recap and lands in the timeline, not in reports/."
---

# Meridian Timeline Note

Adds a **manual narrative note** to the timeline feed: a short milestone explaining *what was done and why*, in the register of `/meridian-recap` but condensed (2–4 lines). Unlike the mechanical entries the server produces on its own (`task_completed`, `feature_completed`), this one is written by a person/agent to record something worth remembering: a deploy, a demo, a decision, a milestone.

Usage: `/meridian-timeline-note [topic]` — without argument, infers the session's milestone; with argument, uses it as the anchor.

## When to use it (and when not)

- **Use** when something happened in the session that deserves a place in the project's history: "deployed v2 to prod", "closed decision X", "demo to stakeholders", "migrated Y".
- **Not** for the full session recap → that's `/meridian-recap` (long document in `reports/`). This note is a short milestone in the **feed**.
- **Not** for distilling memory (decisions/gotchas for future retrieval) → that's `/meridian-autosave` (writes facts to `mem_*`).
- If no real milestone happened in the session, **don't force a note** — say so and end.

## Setup

Read `meridian-project: <project>` from the active project's CLAUDE.md. That's the `project` that receives the note.

## Process

### 1. Receive the context

- With argument (`/meridian-timeline-note payments deploy`) → use it as the milestone's topic/anchor.
- Without argument → review the conversation and identify **the** milestone (one, the most significant). If there are several independent ones, prefer the most relevant or ask once which to record.

### 2. Write the note (recap-lite register)

Write **2–4 lines** answering *what was done* and *why*, in plain language. Reuse the authoring rules of `/meridian-recap`:

- No unexplained jargon (no bare "refactor", "schema", "endpoint" — translate if needed).
- No file/function names or code snippets.
- *What* and *why*, not *how* it was implemented.
- Prefer "the system can now X" over "X was implemented".
- Never invent: only what actually happened in the session.

Difference from recap: this is **short** (a paragraph, not a document) and it's a **milestone**, not the full session summary.

### 3. (Optional) Refs

If the milestone relates to concrete entities, attach refs — `ref_type` ∈ `issue`/`task`/`commit`/`memory`:

- `commit` → the sha of the deploy/milestone.
- `task` → the task that materialized the work.
- `issue` → a related question/decision.
- `memory` → a fact from the memory graph.

Omit if none is clear.

### 4. Save

Writing a note is not on the default MCP surface — it lives in the `extras`
toolset, so it goes over REST. Reading the feed (`list_timeline`) is still MCP.

```bash
scripts/meridian_api.sh POST "/projects/<project>/timeline" '{
  "note": "<2-4 line narrative milestone>",
  "refs": [{"ref_type": "task", "ref_id": "<id>"}]
}'
```

`refs` is optional — omit the key entirely when no ref is clear. The wrapper
reads `MERIDIAN_API_URL`/`MERIDIAN_API_TOKEN` from the repo-root `.env`, prints
the created event as JSON, and exits non-zero on a 4xx/5xx.

The note is embedded on creation → it's searchable in the feed by meaning (`list_timeline(query=...)`) instantly. The `summary` is immutable once created.

### 5. Confirm

Show the user the saved note (text + refs) and the event `id`. Don't ask for confirmation before saving unless the milestone is ambiguous.

## Rules

1. **Short milestone, not a report.** 2–4 lines. If you need more, it's a `/meridian-recap`.
2. **Jargon-free register** — reuse the `/meridian-recap` rules.
3. **Don't invent** — only what happened in the session.
4. **Only the timeline note** (+ context reads). Doesn't touch git, tasks, docs or memory.
5. **Don't force it** — if there was no milestone, say so and end without writing.

## Installation

New skill: install it with the toolkit symlink —

```bash
cd claude && ./install.sh install
```

Afterwards it's available as `/meridian-timeline-note` (no reinstall needed when editing `SKILL.md`, only when adding the skill for the first time).
