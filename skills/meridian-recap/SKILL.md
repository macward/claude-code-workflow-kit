---
name: meridian-recap
description: "Generate a non-technical recap document of what was done in the current session. Targets the whole team (devs + stakeholders). Covers what changed, why, and impact. Saves to reports/ in the vibe workspace."
---

# Meridian Recap

Generates an executive summary document of the current session — no technical jargon — so any team member understands what was done, why, and what impact it has.

## HARD PROHIBITIONS

- ❌ No technical terms without explaining them (no "refactor", "PR", "async", "schema", etc.)
- ❌ No code snippets or file/function names
- ❌ Don't describe *how* something was implemented — only *what* changed and *why*
- ❌ Don't invent context that isn't in the conversation

## Setup

Read `meridian-project: <project>` from the active project's CLAUDE.md.

Read the template at `.claude/templates/recap-template.md` before generating the document. Follow its structure and authoring rules to the letter.

## Process

### 1. Receive the context

The user may invoke the skill with or without an argument:

- No argument: analyze the whole conversation to infer what was done.
- With argument (e.g. `/meridian-recap Payments integration`): use it as the main title/topic and complement with the conversation.

If the conversation lacks enough context for a useful recap, ask **a single question** summarizing what's missing. Don't ask more than once.

### 2. Generate the document

Use the template's structure (`.claude/templates/recap-template.md`). The main sections are:

**Meta block (always present):**
```
---
date: YYYY-MM-DD
project: <project name>
author: <infer from git config (`git config user.name`) or the conversation>
topic: <session topic or title>
---
```

**Body sections:**
- `What was done?` — 2–4 sentences, no technicalities
- `Why was it done?` — motivation or need
- `What impact does it have?` — observable effect for the team or users
- `Pending` — optional, only if there is something concrete

**Technical block (optional):**
Include it only if the conversation had technical decisions, completed tasks, or changes in specific system areas worth recording for the technical team. If nothing is relevant, omit it entirely — don't force it.

**Writing rules:**
- Clear, direct tone — like explaining to a smart non-developer
- Short sentences. No nested bullets.
- If something technical must be mentioned in the main body, translate it: "the API" → "the connection between systems", "the schema" → "the data structure"
- Prefer "the system can now X" over "X was implemented"

### 3. Present and save

Show the generated document and save it to Meridian immediately — without asking for confirmation.

### 4. Save

Before saving, get the author name with `git config user.name` if it wasn't inferred from the conversation.

```
mcp__meridian__create_doc(
  project=<project>,
  folder="reports",
  filename=recap-<YYYY-MM-DD>-<slug>.md,
  content=<content>
)
```

The slug derives from the `topic`: lowercase, hyphen-separated words, at most 5 words.

### 5. Update the project state

After saving the recap, generate and save the project's technical state with `mem_state`, passing `content`.

The state is for AI agents — unlike the recap (which is for humans). It must be concise and oriented to resuming work in the next session.

State structure (free markdown, no frontmatter):

```markdown
## State — <YYYY-MM-DD>

### Current focus
<1-2 sentences: what is being worked on and on which branch/context>

### In progress
- <item>: <brief status>

### Just finished
- <item>

### Next steps
- <item>

### Open / pending
- <unresolved decision or question>
```

Omit empty sections. Be specific but brief — the state should fit in ~20 lines.

```
mcp__meridian__mem_state(
  project=<project>,
  content=<generated state>
)
```

### 6. Confirm save

```
Saved: reports/recap-<date>-<slug>.md
Project state updated.
```

## Rules

1. The document is for people, not machines — prioritize clarity over completeness
2. If there isn't enough context in the conversation, ask for a single clarification
3. The user may pass a title as argument — use it as the document's anchor
4. Never invent achievements or impact — only what actually happened in the session
