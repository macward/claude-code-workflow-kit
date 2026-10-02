# Workflow

How to work a feature end to end using the skills in this repo.

The README explains **what** exists. This document explains **how it's used in practice**.

## Principle

The real output is not the document — it's a correct implementation with low ambiguity. The document is just the tool to get there. If the feature already has low ambiguity without a document, don't write one.

## Process map

```
(at session start) /meridian-recall
                  ↓
1. (once per project) /meridian-init
                  ↓
   ┌────────────────────────────────────────────┐
   │  Does it fit in one session?               │
   └────────────────────────────────────────────┘
      yes ↓                           no ↓
   /meridian-task            2. Discovery — depth depends on complexity
   (one task, created           ├─ Level 1: /meridian-requirements
    and solved; skips           └─ Level 2: /meridian-spec
    2, 3 and 4)                        ↓
        │                     3. /meridian-task-breakdown
        │                            ↓
        │                     4. Execution
        │                        ├─ /meridian-solve-task  ← one by one
        │                        └─ /meridian-run-plan    ← autonomous
        │                            ↓
        └────────────→ ←─────────────┘
                       ↓
5. (commit/push/PR: the skill, if on a branch · merge + deploy: manual, by the user)
                  ↓
6. /meridian-recap  ·  /meridian-cut-release (when closing a version)
```

Every feature (`feat(...)`) goes through one of the two branches — the commit type decides it, not the size (Git Policy in `CLAUDE.md`). `fix`, `docs`, `refactor`, `test` and `chore` don't carry a task and go straight to step 5.

---

## 0. Start the session — `/meridian-recall`

At the start of any non-trivial session. Loads the memory context relevant to the topic and reconciles the project state against local git (read-only), flagging whatever went stale. Pass the topic as an argument so the recall is semantic: `/meridian-recall <topic>`.

---

## 1. Project bootstrap — `/meridian-init`

Once per project. Creates the vibe workspace structure on the MCP server (doesn't touch local files). If the workspace already exists, you don't need to run it.

---

## 2. Discovery — choosing the level

The key question: **what ambiguity do I have to resolve before writing code?**

### Level 1 — `/meridian-requirements`

For simple features: localized UI, CRUD, changes with no architectural impact.

- **Resolves**: what the feature must do, acceptance criteria (MoSCoW), edge cases (BDD)
- **Doesn't resolve**: how it's implemented, which modules it touches
- **Examples**: "add CSV export", "dark mode", "new filter in the list"
- **Output**: document in `requirements/` of the vibe workspace

If the feature fits in one session, skip this step and the breakdown: go straight to `/meridian-task`, which creates the task and solves it. If it's a `fix`, `docs`, `refactor`, `test` or `chore`, it doesn't carry a task — just implement it.

What is **not** an option is a new feature without a task: it was the way out this document used to offer ("or even implement") and it's the one that produced 12 `feat(...)` with no record in two weeks.

### Level 2 — `/meridian-spec` (SDD)

For architecturally significant features: architecture, concurrency, base persistence, protocol design, networking core, complex lifecycle, complex state management.

- **Resolves**: public surface, invariants, hard constraints (auth, security), critical ambiguities
- **Anchored to the codebase**: not theoretical, references real files and modules
- **No code**: defines interfaces, not implementation
- **Examples**: "Conversation Memory", "indexing engine", "base auth system"
- **Output**: document in `specs/` of the vibe workspace

### Rule of thumb

If you're torn between two levels, pick the lighter one. Going up is cheap; going down means you wrote a bloated document for nothing.

Signs you picked wrong:
- You wrote an SDD and all the decisions were obvious → a requirements doc was enough
- You wrote requirements and at breakdown you didn't know how to split the tasks → the SDD was missing

---

## 3. Task breakdown — `/meridian-task-breakdown`

Takes the discovery document and generates concrete tasks in the vibe workspace, with dependencies (`depends_on`) when they matter.

Good tasks:
- A closed unit of work (ideally one commit)
- Independent when possible; with `depends_on` when there's a real order
- With a clear "done" criterion

If after the breakdown the tasks come out vague or gigantic, the discovery document probably fell short — go up a level and rewrite it.

---

## 4. Execution

### `/meridian-solve-task` — one by one

For working a single task. **Runs inside a subagent**: only the final report lands in your context, not the process. With `--inline` it runs in plain sight, with an open channel — the escape hatch for a risky task you want to watch closely.

1. Takes the next pending task (or the one you pass by number)
2. Implements, runs tests
3. Simplifies the task's diff (`/simplify`) and re-runs the tests — last mutation of the code
4. Code review with `code-review-expert`; fixes blockers if any
5. Verifies the acceptance criteria with an independent verifier
6. Marks the task `done` and enriches the timeline
7. **Commits** (with the `Task: <id>` trailer) on the current branch, always. Pushes only when invoked on its own on a working branch: never on `<base_branch>`, and never under `/meridian-run-plan`, which pushes once at the end of the run. Never opens a PR or merges.

Steps 4 and 5 are judgment gates (an LLM giving its opinion on the code). They run *after* the simplification on purpose: that way they read the code that will be committed, not an intermediate one.

Ideal when you want to review each step or the feature is risky.

### `/meridian-run-plan` — autonomous

Iterates over all pending tasks, calling `/meridian-solve-task` for each one and respecting `depends_on`.

- By default: autonomous (doesn't stop between tasks)
- If you ask for "step-by-step" or "confirm": pauses before each task
- **Every task is committed** when it finishes, on the current branch: one commit per task with its `Task: <id>` trailer. `/meridian-solve-task` does it, same as when invoked on its own; run-plan verifies it and stops the run if it's missing. It's not optional — without a commit the working tree stays dirty and the next task doesn't start
- **Pushes once at the end** if the run's branch is not `<base_branch>`. On the base it doesn't push: it leaves the N commits local for you to trigger
- **Opens the PR against the base** when closing a complete run on a branch (unless `--no-pr`). **Doesn't merge or deploy**: that's the user's

Ideal when the plan is solid and you want to let it run.

**If the run is cut off midway —context full, session dead— invoke it again and it picks up.** Long runs are the norm and context is finite, so this will happen. There's nothing to rescue by hand: the work of every completed task is already committed and its task is `done` in Meridian, and the queue is rebuilt from `list_tasks` on every invocation. The only thing lost is the narrative of the previous run, which is in `git log`.

---

## 5. Git — the branch is what enables automation

The criterion is **not** "who presses the button", it's **where the irreversible line is**. A local commit is reversible; a merge into the base branch and a deploy are not. The branch is what separates one from the other, so it's the branch —not ceremony— that decides how far a skill goes.

**`<base_branch>`** is the integration branch the project's CLAUDE.md declares in `branch:`. Typically it's `main`, but skills **compare against that value, never against the literal `main`** — in a project whose base is `master`, hardcoding `main` would make the skill read the base as "isolated branch, I can push" and publish exactly where it shouldn't.

| | commit | push | PR | merge | deploy | delete branch |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **On a working branch** (the feature's worktree) | skill ✓ | skill ✓ | skill ✓ | **User** | **User** | **User** |
| **On `<base_branch>`** | skill ✓ | **User** | — | — | **User** | — |
| **Unattended** (`/schedule`, `/loop`) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

- **On a branch, a skill goes as far as the PR.** Committing, pushing and opening the PR is mechanical work: stopping there for the user to do it by hand adds friction, not safety. The real gate is the merge.
- **On `<base_branch>`, a skill commits but doesn't push.** The deploy is a manual runbook, but it ships whatever is on `origin/<base_branch>`: pushing the base releases those commits to the next deploy. Committing there is local and reversible; pushing isn't. That's why the line falls between the two.
- **If `<base_branch>` can't be determined, fail closed:** don't push. When in doubt, the safe option is the one that doesn't publish.
- **Nobody merges, deploys or deletes branches automatically.** Not on a branch, not on the base. Deleting a merged branch is the user's, at merge time.
- **An unattended routine doesn't touch git at all** — not even a local commit. It ends in "artifacts ready for review". See `CLAUDE.md` › Unattended automation.

And the shape rules that don't depend on the branch:

- **One feature = one branch = one worktree, cut from `origin/<base_branch>`** after a `git fetch`. Never from the local base: it may hold unpushed commits that the feature's PR would publish.
- **No published branch per task.** A plan of N tasks produces N commits on the feature branch. A task may only get a temporary local branch that is never pushed.
- **A multi-task plan on `<base_branch>` asks first**: it's a feature landing without a PR.
- **Every commit that completes a task carries the `Task: <id>` trailer** (consumed by `scripts/mark_deployed.sh` at deploy time to move the task to `deployed`).
- **Changes to this repo's assets are `chore(claude)`, never `feat`**, so they don't need a task.

---

## 6. Closing the session / the version

### `/meridian-recap`

Generates an executive recap (no jargon) of what was done, saves it in `reports/` and updates the project state so the next session picks up without rereading all the code.

### `/meridian-timeline-note`

A lighter alternative: a 2-4 line narrative note to the timeline feed (not a document in `reports/`). For milestones that don't warrant a full recap.

### `/meridian-cut-release`

When a batch of deployed work warrants closing a version: reads the open release's changelog, suggests the SemVer bump based on what shipped, previews, and after human confirmation stamps the version and cuts. Stops before git/deploy.

---

## Usage patterns

### Small feature you have clear
```
/meridian-task "<what you want to build>"
```
One task, created and solved in one go. No discovery document and no breakdown — the ambiguity is already low, and decomposing a single item is ceremony. It's the path that keeps an afternoon's feature inside Meridian instead of shipping it with no task behind it.

### Medium feature
```
/meridian-spec → /meridian-task-breakdown → /meridian-run-plan
```
The SDD aligns the surface and the constraints, run-plan executes.

### Large / architectural feature
```
/meridian-spec → /meridian-task-breakdown → /meridian-solve-task (one by one)
```
The SDD reduces risk, execution controlled by criticality.

### Resuming an old session
```
/meridian-recall → /meridian-solve-task <NNN>
```
Load the context and state, see what's left pending, pick up the next one.

---

## Anti-patterns

- **Writing an SDD for everything.** Produces giant docs nobody reads and discourages lightweight discovery when it is actually needed.
- **Skipping discovery when there's real ambiguity.** Ends in vague tasks, mid-implementation refactors, and work that gets redone.
- **Merging or deploying from a skill.** Forbidden by policy — it's the only real human gate. (Committing, pushing and opening the PR **on a working branch** is done by a skill; on `<base_branch>`, only committing. See section 5.)
- **Doing the breakdown before discovery.** If the tasks come out vague, the problem is upstream.
- **Starting a session without `/meridian-recall`.** You lose the state and prior decisions, and start with stale context.
