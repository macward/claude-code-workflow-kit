# Claude Code Workflow Kit

Skills, agents, commands, rules, templates and hooks for [Claude Code](https://claude.com/claude-code), built around a spec-driven development (SDD) workflow: discovery → task breakdown → autonomous, verified execution → recap.

Everything is installed **per project** as symlinks into `<project>/.claude/`, so each repo opts in to exactly what it uses and nothing leaks into every session. The one exception is hooks, which are installed globally (see [Hooks](#hooks-global)).

For **how the workflow is used in practice** (step by step, patterns, anti-patterns), see [`WORKFLOW.md`](./WORKFLOW.md) (Spanish). This README documents **what** exists.

## Requirements

- [Claude Code](https://claude.com/claude-code).
- The `meridian-*` / `mer-*` skills and agents need the **Meridian MCP server** (tasks, docs, timeline and memory tools exposed as `mcp__meridian__*`). The analyzers, generic agents, rules and templates work without it.
- `bash` and `python3` (the hooks are Python scripts).

## Layout

```
.
├── skills/           # one folder per skill with a SKILL.md — auto-discovered by description, invocable as /<name>
├── agents/           # flat .md files — subagents spawned by skills or other agents
├── commands/         # slash commands
├── rules/            # ALWAYS in context for the installed project — keep it small (see below)
├── templates/        # read on demand with Read (recap/report templates, swift/, python/, …)
├── hooks/            # Claude Code hooks (installed globally)
├── install.sh        # per-project symlink installer (idempotent)
├── install-hooks.sh  # global hook symlink installer
└── WORKFLOW.md       # the workflow, in practice
```

## Installation

### Per project

From the root of this repo, pointing at the target project:

```bash
./install.sh install <project-dir>     # symlink everything into <project-dir>/.claude/
./install.sh list <project-dir>        # show install status
./install.sh uninstall <project-dir>   # remove only the symlinks that point here
```

Idempotent: re-running is safe. Existing non-symlink files are never overwritten. Editing an existing file needs no reinstall (the symlink points at the source); **adding a new skill or agent does** require `install` again in each project.

Symlinks are absolute paths, so don't commit them in the target project — add the `.claude/` subfolders to its `.gitignore`.

### Hooks (global)

```bash
./install-hooks.sh install     # symlink hooks/*.sh into ~/.claude/hooks/
./install-hooks.sh uninstall   # remove those symlinks
```

This only creates the symlinks. Register each hook in `~/.claude/settings.json` yourself, e.g.:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Read|Bash", "hooks": [ { "type": "command", "command": "python3 \"$HOME/.claude/hooks/shunt-bulk-read.sh\"" } ] }
    ]
  }
}
```

| Hook | Event | What it does |
|---|---|---|
| `shunt-bulk-read.sh` | `PreToolUse` (Read, Bash) | Blocks full reads of large files (>350 lines by default) and redirects them to the cheap `bulk-reader` subagent, which returns a line-anchored summary. `CLAUDE_BULK_READ_THRESHOLD`, `CLAUDE_BULK_READ_OFF=1`. |
| `block-gate-wait-polling.sh` | `PreToolUse` (Bash) | Blocks `echo waiting` / `sleep N; echo` busy-wait loops while waiting on a subagent; the agent should end its turn and wait for the notification instead. |
| `meridian-autosave-session-end.sh` | `SessionEnd` | Launches the Meridian Memory v2 distiller (`/meridian-autosave`) headlessly when a session ends. |

## Skills

### SDD pipeline (`meridian-*`)

Philosophy: **depth levels, not a fixed pipeline.** The real output is a correct implementation with low ambiguity, not the document. Pick the lightest format that removes the feature's critical ambiguity.

| Skill | Purpose |
|---|---|
| `meridian-init` | Bootstrap the project workspace on the Meridian server. Once per project. |
| `meridian-requirements` | Discovery level 1: MoSCoW requirements + BDD scenarios (what, not how). |
| `meridian-spec` | Discovery level 2: concise, codebase-grounded design doc (~30–60 lines) for architecturally significant work. |
| `meridian-task-breakdown` | Turn the discovery doc into Meridian tasks with `depends_on`. |
| `meridian-analyze` | Consistency gate: every spec section has a task, no task contradicts the spec, parallel tasks don't overlap. |
| `meridian-task` | Create one task from a description and solve it right away — for features that fit in one session. |
| `meridian-solve-task` | Solve one task end to end in a subagent: implement → tests → simplify → code review → goal check → commit (`Task:` trailer) → mark done. |
| `mer-solve-task-lite` | Same, minus review/goal-check/simplify: tests are the only gate. For small, low-risk tasks. |
| `meridian-run-plan` | Run all pending tasks in dependency order, one subagent and one commit per task; push once and open a PR on a working branch. Never merges. |
| `mer-run-plan-lite` | `meridian-run-plan` over `mer-solve-task-lite`. |
| `meridian-review-pr` | Integration review of a feature PR against its spec and tasks (cross-task duplication, interface drift, leftovers). |

### Memory, timeline and releases

| Skill | Purpose |
|---|---|
| `meridian-recall` | Load relevant memory at the start of a task and reconcile it against local git (read-only). |
| `meridian-autosave` | Distill session observations into canonical memory facts. |
| `meridian-recap` | Non-technical session recap for the whole team. |
| `meridian-timeline-note` | Short milestone note for the project timeline. |
| `meridian-weekly-report` | Weekly report from timeline events and git history. |
| `meridian-cut-release` | Cut a release with a SemVer bump derived from what shipped; stops before git/deploy. |

### Codebase analysis and utilities

| Skill | Purpose |
|---|---|
| `analyze-fastapi-codebase` | Health/architecture audit of Python/FastAPI with ruff, pyright, radon, vulture, deptry, bandit, pip-audit, coverage. |
| `analyze-typescript-codebase` | Same for TypeScript/JavaScript with tsc, eslint, knip, madge, jscpd, lizard. |
| `analyze-macos-ios-codebase` | Same for Swift with SwiftLint, periphery, lizard, xccov. |
| `swift-concurrency-expert` | Swift 6.2+ concurrency review and remediation. |
| `mermaid` | Generate and render a Mermaid diagram from a description. |

## Agents

| Agent | Purpose |
|---|---|
| `code-review-expert` / `swift-code-review` | Code review (general / Swift-specific). |
| `commit-pr` | Mechanical git work from a brief: stage, commit, push, `gh pr create`. |
| `spec-author` | Requirements + spec for a feature, with a human checkpoint in between. |
| `meridian-requirements` / `meridian-spec` / `meridian-task-breakdown` | Executors for each SDD phase. |
| `mer-task-runner` / `mer-task-runner-full` | Workers that execute one task (lite / full). |
| `mer-goal-check` | Read-only verifier of a task's acceptance criteria. |
| `mer-recall` | Cheap worker behind `/meridian-recall`, keeps raw memory payloads out of the caller's context. |
| `bulk-reader` | Reads large files in a cheap context and returns a line-anchored summary. |
| `py-bootstrap` | Bootstrap Python/FastAPI projects with modern tooling. |
| `design-system-interactive` | Collaborative software-design exploration session (not a final document). |

## Commands, rules and templates

- **Commands:** `/devils-advocate` (adversarial code review), `/sdd-reconcile` (reconcile a spec against the shipped implementation).
- **Rules** (`rules/`): simplicity principles, changelog conventions, Python notes.
- **Templates** (`templates/`): recap and weekly-report structures, Swift and Python coding guidelines, and `BOOTSTRAP.md` for composing a project `CLAUDE.md`.

## Design notes

### `rules/` is a context budget, not a drawer

Everything under `.claude/rules/` is loaded in full on **every turn** of the project. A file there isn't paid once — it's paid on every turn of every session. `templates/` is installed the same way but only enters context when something reads it. So: **if it applies to every project, it goes in `rules/`; if it applies to one stack, it goes in `templates/<stack>/`** and is read when that stack is detected.

### A `SKILL.md` is a per-turn cost too

A `SKILL.md` stays in context while the skill runs. When a skill grows, material that isn't needed at every step moves into sibling files read on demand. `meridian-solve-task` is the example: `SKILL.md` (the executable process), `REPORT.md` (report format), `DELEGATE.md` (subagent brief), `FEATURE_ENRICH.md` (feature timeline step) and `NOTES.md` (evidence behind the rules, read only when changing them). The split is by risk, not size: **any instruction that decides whether something is safe stays in `SKILL.md`**, because a file that isn't read is a rule that doesn't exist.

### Git policy

- One branch per feature, never per task: a plan of N tasks leaves N commits on one branch.
- The branch decides how far a skill goes. On a working branch: commit + push + PR. On the base branch: commit only. **Merge and deploy are always human.** Unattended runs don't touch git at all.
- Whoever writes the code commits it (`meridian-solve-task`); `meridian-run-plan` only verifies each commit and pushes once at the end.
- `feat(...)` commits always carry a task (`Task: <id>` trailer); `fix`/`docs`/`refactor`/`test`/`chore` don't.
