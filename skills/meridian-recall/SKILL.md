---
name: meridian-recall
description: "Load memory context from Meridian at the start of a task, ranked by relevance to the given topic (or to the state's current focus without one), and reconcile it against local git (read-only), flagging stale claims. Scoped to the active project. Runs in a Haiku subagent so the raw memory payloads never enter the caller's context; `--inline` runs it in view."
---

# Meridian Recall

Loads the active project's memory context from Meridian to prime you before starting a task. Operates **exclusively** on the memory subsystem (`mem_*`): it reads no docs, tasks or issues.

Recall is **semantic**: if you know what the session is about, pass that topic as `query` — the bundle comes back ranked by relevance to the topic (similarity + salience + recency + scope), not by arrival order. Without a topic, ranking falls back to salience + recency with decay. Superseded facts never appear.

## Where it runs

By default the fetching happens in the `mer-recall` agent (Haiku). The raw tool results — state doc, context bundle, search hits, expanded bodies, git output — are the bulk of a recall, and they stay in the subagent's context. What comes back to you is the already-formatted block, which is the only part you would have kept anyway. The whole process the agent follows lives in `.claude/agents/mer-recall.md`; this file only decides the scope and relays the result.

`--inline` skips the subagent and runs that same process in the current context. Use it when the `Agent` tool isn't available (inside a worker agent that doesn't declare it) or when the user wants to see the raw calls.

## Setup

Read `meridian-project: <project>` from the active project's CLAUDE.md. That's the `project` used in every call. The repo path is the current working directory.

## Process

### 1. Determine the scope

The user may invoke with or without an argument:

- **With argument** (e.g. `/meridian-recall worktree modal`): that's the topic.
- **Without argument**: if the conversation already made the task's topic clear, use it as the topic anyway. If no topic is discernible, pass `topic: none`.

The condition governing the topic is **having one**, not having an argument. When unsure whether there is a topic, pass none: the agent then derives one from the "current focus" section of the project state and ranks by it, falling back to the general bundle only when the state has no focus. Either way, with a topic the agent also runs a targeted search and expands the 2-3 most relevant hits.

### 2. Delegate (default)

Spawn the agent and wait for it:

```
Agent(
  subagent_type="mer-recall",
  description="Recall memory for <project>",
  prompt="project: <project>\nrepo: <cwd>\ntopic: <topic or 'none'>\n\nReturn the recall block verbatim as your agent definition specifies."
)
```

`Agent` returns metadata, not the report: end the turn and resume when the `<task-notification>` arrives. Don't poll with `Bash`.

If `Agent` fails because the type doesn't resolve (`Agent type 'mer-recall' not found`), the agent file wasn't symlinked into the project's `.claude/agents/` — run `./install.sh install <project-dir>` from the project_rules repo, or fall through to `--inline` for this session.

### 2 (inline). Run it yourself

With `--inline`, read `.claude/agents/mer-recall.md` and execute its process here: `mem_state` + `mem_context` (deriving the topic from the state first when there is none), the targeted `mem_search` + up to 3 `mem_get` when there is a topic, the git reconciliation, and the same output block.

### 3. Present the context

Print the block the agent returned **as-is**, before starting the task. Project state goes first — it's the narrative thread; memories are the complementary detail. Don't reorder, trim or annotate it, and don't add advice of your own on top: a recall reports what the server knows, not what you think about it.

One exception — the git reconciliation. The agent compares the state against `git log`/`git status` and marks discrepancies as `⚠ Stale vs. git`. That reading is the agent's, not the evidence: if a stale claim matters to the task at hand, confirm it with your own `git log` before acting on it.

## Rules

1. Always filter by the active project.
2. If there is a task topic, ALWAYS pass it — semantic ranking is the central fix of Memory v2; a recall without a topic when one exists wastes the relevance.
3. `mem_context` already applies a token budget and ranks server-side — the agent doesn't trim by hand, and neither do you.
4. Present the context before starting the task, not at the end.
5. Recall is strictly Meridian-side memory: no `list_docs`, `list_tasks` or generic `search`, in either mode. `neighbors` pointing at docs/tasks are references, not invitations to open them. The local git read is the only exception, and it's read-only.
6. **Never pass `content` to `mem_state`** — with `content` it overwrites, and that's the recap's job. Reading and writing the state are the same tool, distinguished by the parameter.
7. Report state↔git discrepancies, never "fix" them on the server.
