---
name: meridian-autosave
description: "Memory v2 distiller: save session observations as episodes, then distill the pending backlog into canonical facts (cluster, upsert, judge contradictions, promote scope, ack cursor). The only memory step with LLM judgment. Scoped to the active project."
---

# Meridian Autosave — Distiller

Two responsibilities, in order:

1. **Capture** — analyze the current conversation and save valuable observations as **episodes** (`mem_save`). Aggressive filter, as always.
2. **Distill** — consume the backlog of pending episodes (`mem_distill_batch`), cluster them, summarize each cluster into a **canonical fact** (`mem_upsert_fact`), link the evidence (`mem_relate` with `derived_from`), judge contradictions against existing facts, and advance the cursor (`mem_distill_ack`).

This skill is the only piece of the memory system that uses LLM judgment. The server does only the deterministic part (KNN, dedup, cursor, reinforcement).

**It never deletes anything.** Neither facts nor episodes. A wrong fact is replaced (`supersedes`); a doubtful one is flagged (`contradicts`). Deletion doesn't exist in this flow.

## Setup

Determine the `project`:
- Manual use: read `meridian-project: <project>` from the active project's CLAUDE.md.
- Headless use (`SessionEnd` hook): it arrives in the prompt as `--project <name>`. The wrapper resolves it by searching for `meridian-project:` in the nearest CLAUDE.md upward from the `cwd`; if it finds none, it doesn't launch the skill.

## Phase 1 — Capture (the usual skill)

**Where the conversation to review comes from:**

- **Manual use**: the current session, the one being closed.
- **Headless use**: the `<transcript>` block in the prompt — user and assistant turns in plain text, without tool calls or their results, elided in the middle if it exceeded budget. **The headless session starts empty: that block is all there is.** If it doesn't appear, Phase 1 has no input and is skipped — report 0 captured and move to Phase 2, don't invent observations or treat the prompt itself as a conversation.

Review the conversation and identify observations that meet **at least one**:

- **Gotcha or trap**: something that failed unexpectedly, surprising behavior, hidden constraint — **including the fix to a wrong assumption**, something Claude assumed wrongly and the user corrected. The two used to be separate criteria and they are the same shape: something was believed one way and turned out another. It's the type that pays, and no trim of this policy touches it.
- **User preference**: how they want Claude to behave, in this project or in general.
- **Technical decision, and only when the discarded alternative is the durable part**: X was chosen over Y — or it was decided **not** to do Z — and the *why not* isn't written anywhere else. The normal case is that it doesn't qualify; see the type policy below.

**Don't save:** what's already in the code, CLAUDE.md, a `SKILL.md` or the CHANGELOG; **perishable state** (what's pending, what was just applied, what was deployed, which env var was turned on); **feature and task metadata Meridian already models** (that a feature has 9 tasks, that an SDD exists); implementation steps or summaries (that's `/meridian-recap`); stack trivia; nothing if nothing new happened.

**Where the diverted material goes.** What this filter rejects isn't lost: it has another destination, one that's updated as a side effect of the work and doesn't depend on the distiller running. **This skill writes to none of those destinations** — its surface remains `mem_*` and nothing else (Rule 6); the table says who already populates them, so the filter can reject without orphaning the material.

| Material | Destination |
|---|---|
| Decision already materialized in a rule or a flow | The `CLAUDE.md` or `SKILL.md` that implements it |
| Product behavior change | `CHANGELOG.md` |
| Pending work, loose end, open question | A Meridian issue (`create_issue`) |
| What was done and why in a task | The timeline enrichment of `/meridian-solve-task` (step 9.1) |
| Infra and deploy state | `docs/deployment.md` and the CHANGELOG |
| Session recap | `/meridian-recap` → `reports/` |

### Type policy — which ones the distiller writes

**The enum still has four values and this policy doesn't change it.** `MEMORY_TYPES` in `db/models.py` is `("decision", "gotcha", "preference", "context")`, validation is app-layer and **gates only writes**: historical rows of any type keep being read. What's narrowed here is which of those four values **this skill produces**, a smaller subset than the enum. A retired type stops being written; what's already saved is neither deleted nor migrated.

| Type | Does the distiller write it? |
|---|---|
| `gotcha` | **Yes.** It's the type that pays and justifies the whole system. |
| `preference` | **Yes.** Durable knowledge about how to work with the owner; there's nowhere else it lives. |
| `decision` | **Narrowed.** Only when the durable part is the discarded alternative and its reason, and that isn't written in any doc. |
| `context` | **No.** Everything valuable that landed here was actually a `gotcha` or a `preference`; the rest is perishable state. |

#### Why, and what evidence counts and what doesn't

**The 2026-08-02 measurement can't support this policy, and it matters to say why.** That day 121 memories / 447 reads were measured and read as a type distribution: `gotcha` 47 rows, `decision` 38 with 1.29 reads on average, `preference` 3, `context` 3 with 11.67 on average. The same day `e82f74a` was committed, *"fix(autosave): the hook never passed the transcript to the skill"*: until then Phase 1 ran **104 times without ever receiving the conversation** (see the `SessionEnd` hook section). And the hook itself is from 2026-07-23 (`7bd08a7`), so those 121 facts are the sum of two thin regimes: two months of **manual, sporadic** distillation — only when someone invoked the skill by hand — plus ten days of automation that captured zero. Precision matters here: it's **not** that the distiller was blind the whole time (a manual run did see the conversation), it's that it almost never ran on a real session. In both cases the effect on the snapshot is the same — those per-type counts measure **coverage**, not filter selectivity — which is why "3 `preference` rows" can't be read as "the `preference` criterion is narrow".

The following 18 days, with the hook delivering the transcript at every session close, confirm it: `preference` went from 3 rows to more than 30 and is today the most numerous type in the base. Ten times the volume in a tenth of the time, without anyone touching the criterion. **That's the answer to "why was `preference` produced so little": the filter was never too narrow — what was missing were runs on real sessions. It doesn't need widening, and widening it now, on a regime that's just starting to produce, would be the same mistake of reading a thin aggregate as if it measured the criterion.**

What does decide is the case-by-case reading, the only uncontaminated evidence:

- **`context` is retired by composition, not by performance.** Its 11.67 average reads are real and aren't the reason: read one by one, the `context` facts in the base are two distinct populations and neither needs the type. One half is **mistyped** — *"Task done auto-closes the issue it came from"* is a textbook gotcha (surprising server behavior + what not to do as a result), *"The CHANGELOG also records changes to `claude/`"* is an explicit owner preference, *"`.meridian` uses feature, not project"* is a fix to a wrong assumption. The other half is **perishable state** — *"2 diagnostic points missing"*, *"pending: structure refactor"*, *"`MERIDIAN_TOOLSETS=admin` enabled in prod"*, *"stitch and pencil removed"*: true when written, ages without notice, and on top ranks high because the type's high average pushes it up. Retiring `context` doesn't lose the first half — it's written as `gotcha` or `preference`, which is what it always was — and takes the second half out of the bundle, which is where it did harm.
- **`decision` is narrowed instead of retired.** Retiring it entirely leaned on the 1.29 average, which is exactly the number the contaminated measurement can't support. The cases, instead, show a different, fixable problem: most `decision` facts in the base **are already written as a rule elsewhere** — *"solve-task commits the task; run-plan only verifies"* is literally in the Git Policy of `CLAUDE.md` and in `meridian-solve-task/SKILL.md` — or are **feature metadata Meridian already models** (*"feature X has 9 tasks and an SDD"*). The **Don't save** block already forbade both; the type wasn't failing, the filter was applied loosely. What remains is the residue no doc captures: the decision **not** to do something, with its reopening condition (*"code RAG in Meridian: no, until the waste is measured"*). A doc records what was built; nothing records what was discarded or why, and that's exactly what a future session proposes again.

> This is the only deviation from the direction agreed with the user ("keep `gotcha` and `preference`"), and it's deliberate: the part of that direction aimed at `context` was confirmed case by case, and the part aimed at `decision` leaned on an aggregate that turned out invalid. Retiring `decision` remains one line of a table if the user prefers to close it entirely.

**`access_count` is a directional signal, not proof.** It counts bundle appearances, which is popularity induced by the ranking itself (`docs/memory-system.md`). Don't close or reopen this policy with averages: look at the cases.

For each candidate:

```
mcp__meridian__mem_save(
  project=<project>,
  type=<"gotcha" | "preference" | narrowed "decision" — see the type policy>,
  title=<short title, max 8 words>,
  content=<2-5 lines: what happened, why it matters, how to apply>,
  scope=<"project" | "global">   # see the 2.5 test — default "project"
)
```

**`scope`: default `project`.** `global` only if the fact serves a session in another project **with another stack** — not if it's merely true in the abstract. A framework gotcha (SwiftUI, FastAPI, React) is `project` even if always true; an owner convention or a shared-infra gotcha is `global`. The full criterion, with examples on both sides, is in 2.5.

The `type` enum is closed: the four in `MEMORY_TYPES` and nothing else. Any other value is rejected by the server with `InvalidMemoryTypeError` — don't invent new types for what doesn't fit, that material is precisely what the filter above says not to save. And of those four, the distiller writes the three in the policy: `context` is a valid value this skill no longer produces.

`mem_save` deduplicates (exact + semantic hash) and redacts secrets server-side; don't look for duplicates by hand. If it returns `reinforced_fact_id`, the observation was already distilled — no further work needed. Quality over quantity: better 1 valuable episode than 5 trivial ones.

## Phase 2 — Distillation

### 2.1 Fetch the backlog

```
mcp__meridian__mem_distill_batch(project=<project>, limit=50)
```

- Returns `{episodes: [...], cursor}`. The `cursor` is **opaque**: received here and returned in the ack, never constructed.
- **At-least-once contract**: if the skill dies midway, the same batch is redelivered on the next run. That's why the flow order matters: facts and edges are written BEFORE the ack, and `mem_upsert_fact` is idempotent (same content → reinforces, doesn't duplicate) — reprocessing a batch is safe.
- If `episodes` is empty → **end without writing anything**. Report "no pending episodes".

### 2.2 Cluster

Group the batch's episodes by topic/underlying claim (LLM judgment — there is no mechanical threshold). A cluster may be a single episode if it's substantial on its own.

**Fact quality criterion** (inherits Phase 1's aggressive filter, **type policy included**): a cluster deserves distilling only if it produces a fact that would help at the start of a future session, and only in one of the three types the distiller writes — an actionable gotcha, a stable preference, or a decision whose discarded alternative isn't in any doc. An episode judged "doesn't make a fact" **is let go without guilt**: the ack covers it and it's never redelivered. Don't force facts.

**The filter is applied again here, not assumed applied in Phase 1.** The backlog brings old episodes, written under the previous policy: a pending `[context]` episode **is not distilled as `context`**. It's retyped as what it really is — gotcha or preference — or let go if it was perishable state. Same for a `[decision]` that only repeats a rule already written in `CLAUDE.md`, a `SKILL.md` or the CHANGELOG: it doesn't make a fact. Retyping is why retiring `context` loses nothing — the good material gets in anyway, with the right type.

### 2.3 Distill each cluster

For each cluster that deserves a fact:

1. **Search existing facts on the topic** (`mem_search(query=<topic>, project, limit=5)`), to decide between create, reinforce or contradict.
2. **Write the canonical fact**:
   ```
   mcp__meridian__mem_upsert_fact(
     project=<project>,
     type=<dominant type of the cluster, retyped per the policy: "gotcha" | "preference" | "decision">,
     title=<canonical claim, max 10 words>,
     content=<the consolidated fact: what, why, how to apply>,
     scope=<see 2.5>
   )
   ```
   Dedup is by content hash: if it returns `created: false`, the fact already existed and was reinforced — new edges are written anyway.
3. **Link the evidence** — one edge per episode in the cluster:
   ```
   mcp__meridian__mem_relate(project, from_id=<fact_id>, to_type="episode", to_id=<episode_id>, relation="derived_from")
   ```
   Optionally link related entities (`documented_in` → document, `about_task` → task, `relates_to` → another fact).

### 2.4 Judge contradictions

If the new fact clashes with an existing fact (found in 2.3.1):

- **Clear replacement evidence** (the old fact is obsolete and the new one explicitly corrects it — e.g. "we no longer use X, we migrated to Y"):
  ```
  mem_relate(project, from_id=<new_fact>, to_type="memory", to_id=<old_fact>, relation="supersedes")
  ```
  The server stamps `superseded_by` on the old fact automatically (the edge is the evidence; the column is authoritative). The old fact disappears from default retrieval but **isn't deleted**.
- **Ambiguous** (both could be true, different contexts, no certainty):
  ```
  mem_relate(project, from_id=<new_fact>, to_type="memory", to_id=<old_fact>, relation="contradicts")
  ```
  Both facts stay alive. The doubt is information — it's resolved in a future session with more evidence.

**Default when in doubt: `contradicts`.** `supersedes` only with unequivocal evidence.

### 2.5 Scope promotion

A fact is born `project`. Promoting it to `global` puts it in the recall bundle of **every** project of the owner and also adds a score boost, so the promotion is paid in the context of sessions that didn't ask for it.

**The test isn't whether the claim is true in any project: it's whether it serves a session that doesn't share this stack.** The previous rule said "true in any project" and that's why it failed — a SwiftUI gotcha *is* true in any project; what it isn't, is applicable in one that doesn't use SwiftUI. Truth and applicability aren't the same, and scope is decided by the latter.

Concrete one-line test: **name two of the owner's projects with different stacks. If in either the fact would be noise, it's `project`.**

`global` — the shared working environment, which doesn't change with what's being built:
- Stable preferences about how you want Claude to work ("close the task; the leftover goes to a blocker issue").
- Owner-wide conventions (conventional commits, Spanish in prose, no AI attribution).
- Infra and tools common to several projects: Meridian, git, Docker, the prod server. Canonical example: *"meridian-postgres is a standalone container, use `docker exec` not `docker compose exec`"* — any session touching that server needs it, be it Python, Swift or TypeScript.

`project` — everything depending on a stack, a product or a codebase, **however true in the abstract**:
- Framework gotchas. Explicit counterexample, the one that motivated this rule: *"SwiftUI's .task(id:) doesn't re-fire for the same identity"*, *"withTaskGroup hangs with a non-cancellable continuation"*, *"@Observable doesn't allow `Self` in a stored property"*. All three are always true and all three are noise in a Python server. They were marked `global` and topped the `meridian-server` bundle.
- Architecture or product decisions of a codebase.
- UI or domain conventions of a single app.

When in doubt, `project`. Demoting an already-promoted fact has no write path today (`mem_upsert_fact` only fills `scope` when NULL, and rewriting the same content **reinforces** the fact instead of correcting it), so a wrong promotion is expensive to undo and cheap to avoid.

If the cluster mixes episodes on cross-project topics, that alone doesn't make it global: apply the same test to the distilled fact.

### 2.6 Ack

Only when ALL facts and edges of the batch are written:

```
mcp__meridian__mem_distill_ack(project=<project>, cursor=<batch cursor>)
```

If more episodes remain pending (the batch came full), repeat from 2.1.

## Phase 3 — Refresh the project state

The state (`mem_state`) is the narrative thread `/meridian-recall` reads first, and it is the part of memory that ages worst: it is one document per project, overwritten in place, and until now only `/meridian-recap` wrote it. A recap that gets run on some sessions and not others produces a state that is weeks stale and silently wrong — measured on 2026-09-07, the meridian-server state was 47 days old and still claimed a HEAD that was dozens of commits back. A stale state is worse than none: recall presents it first, so it front-loads the session with claims that are confidently false.

Run this phase **only when Phase 1 had a transcript**. With no transcript there is no evidence about where the work stands, and overwriting the state with a guess is exactly the failure this phase exists to fix.

### 3.1 Read what is there

```
mcp__meridian__mem_state(project=<project>)
```

**Never pass `content` to read.** The same tool reads and writes, and passing `content` overwrites.

### 3.2 Write the updated state

Produce the *whole* document — the write replaces it, there is no patch. Build it from the previous state plus what this session's transcript shows, and **carry forward every claim the session gives no evidence about**. A session about the REST layer says nothing about a pending migration; dropping that pending item because it went unmentioned is how a state quietly loses the things nobody is working on.

```
mcp__meridian__mem_state(project=<project>, content=<full updated state>)
```

Shape — the same contract `/meridian-recap` writes, ~20 lines, for an agent resuming work, not for a human reading a report:

```markdown
## Estado — <YYYY-MM-DD>

### Current focus
<what the work is about right now, 1-3 lines>

### Just finished
- <what closed, with task/issue short ids when the transcript names them>

### Open / pending
- <what is unfinished, and what the next step is>
```

Omit empty sections.

**Do not assert what you cannot see.** This runs headless with only `mem_*` tools: there is no git, no filesystem, no task list. So the state records **where the work stands**, never what the tree is. Concretely: no commit shas, no "working tree clean", no "`main` in sync with origin" unless the transcript itself shows that check being run, and then attributed to the session's date. Those unverifiable claims are precisely what went stale before, and `/meridian-recall` now flags them against git — it should have nothing to flag.

If the previous state carries such claims and this session gives no evidence either way, **drop them** rather than copy them forward. Losing a stale sha costs nothing; repeating it costs a session's trust.

## Report

```
**Autosave** (meridian)

Captured: N episodes
Distilled: M facts (K reinforced)
  - [<type>] <title>  ← derived_from: X episodes
Supersedes: … / Contradicts: …
Backlog: acked up to <short cursor> (~N pending remain | drained)
State: updated (<one line on what moved) | unchanged (no transcript)
```

With nothing to do: `No new observations or pending episodes.`

## Trigger — SessionEnd hook

Distillation runs at session close via the **`SessionEnd`** hook (allowed by the automation policy: it writes to Meridian, touches no git and publishes nothing).

> **The event is `SessionEnd`, not `Stop`.** This section said `Stop` and was wrong.
> The Claude Code docs are explicit: `Stop` is *"once per turn — When
> Claude finishes responding"*, while `SessionEnd` is *"once per session —
> When a session terminates"*. Mounted on `Stop`, the hook would launch a
> headless session **after every assistant response**, not once per session.
> Fixed 2026-07-23; see task `f9295fd0` for the full verification.

**Mandatory anti-recursion:** the hook launches a headless `claude -p` session which, on finishing, would fire its OWN `SessionEnd` — infinite loop. The wrapper breaks the chain with an env var guard. Inheritance is guaranteed by the docs (*"Handlers run in the current directory with Claude Code's environment"*), so the guard suffices and no lockfile is needed on top.

**The script lives at `hooks/meridian-autosave-session-end.sh`** and is installed by symlink with `./install.sh install <project-dir>`. It isn't reproduced here: a copy in the doc drifts from the original at the first change, and this doc already had that outdated version. What the script resolves, besides the guard:

- **Injecting the transcript and the `project`**, reading the hook's `stdin` JSON (`transcript_path`, `cwd`). It's the only thing that makes Phase 1 possible: the `claude -p` session starts empty and doesn't see the conversation that closed. The script distills the `.jsonl` into turn text (no tool calls) and passes it via argv, not as a path — so `--allowedTools` doesn't need `Read` and the boundary stays pure `mem_*`. **This step was missing from day one and nobody noticed**: 104 consecutive runs reported `Captured: 0` with plausible explanations ("the session started with the command"), which was literally true and hid that the transcript never arrived. If you see a streak of zeros again, suspect the wrapper before the filter.
- **Time ceiling** (30 min by default, `MERIDIAN_AUTOSAVE_TIMEOUT` to override). Without it, a stuck run runs unbounded against the production account, unattended.
- **Real decoupling from the parent**, because `SessionEnd` doesn't block the close (*"If a SessionEnd hook is slow, Claude Code will complete session termination independently"*) and distillation takes minutes.
- **Portability**: neither `setsid` nor `timeout` exist on macOS — both are util-linux. The main path is a Python shim that does both; without it the hook dies with `command not found`, silently.

In the project's `.claude/settings.json` — **merge into the existing array, don't replace the block**: if `SessionEnd` already has a hook, overwriting it breaks it.

```json
{
  "hooks": {
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/meridian-autosave-session-end.sh" } ] }
    ]
  }
}
```

**No matcher, on purpose.** `SessionEnd` accepts a matcher on why the session ended (`clear`, `resume`, `logout`, `prompt_input_exit`, `bypass_permissions_disabled`, `other`). None is used: the hook fires on all of them.

The reason is an asymmetry between the two failure modes. This skill does **two** things, and the at-least-once contract covers only the second: Phase 2 distills already-saved episodes and is idempotent, but **Phase 1 captures the current conversation and has no net**. If the hook doesn't run for a session, its observations aren't pending in any backlog — they don't exist.

- **Firing too much** (e.g. on `resume`, and again at the real close): the second run rereads the same conversation, but `mem_save` deduplicates by exact and semantic hash. It costs a few tokens and leaves no damage.
- **Firing too little**: that session leaves no trace. Unrecoverable, and silent on top.

Excluding a reason is betting those sessions had nothing worthwhile. `resume` was the most obvious candidate to exclude and it's exactly where the bet is worst: if you resume a session, it's because it had content. And `clear` is the *strongest* case for firing, not the weakest — it deliberately throws away the context, so distilling right before is the moment of maximum value.

If it turns out noisy in practice, adding a matcher is one line. The inverse fix — recovering sessions that were never captured — doesn't exist.

`prompt_input_exit` is the reason the headless session itself ends with: it's intercepted by the env var guard, not the matcher, so being permissive with reasons doesn't reintroduce the loop risk.

`--allowedTools` enumerates exactly the `mem_*` surface this skill uses — it's the hard boundary of the unattended run, not a convention: the skill can't touch tasks, docs or git even if the model tried.

The hook is best-effort: if the session dies before the ack, the at-least-once contract guarantees the next run resumes the same batch.

## Rules

1. Never delete — neither facts nor episodes; there is no delete tool in this flow and none should be sought.
2. Ack only after writing — dying before the ack is safe; acking before writing loses information.
3. Quality over quantity — an episode without a fact is a valid outcome; the cursor covers it.
4. `supersedes` is irreversible in effect (it removes the old fact from retrieval): it demands clear evidence; when ambiguous, `contradicts`.
5. Don't ask for confirmation — execute and report at the end.
6. Only `mem_*` tools. No writing documents (`create_doc`/`update_doc`), no git.
7. The state is overwritten, never patched: read it before writing it, and carry forward what this session says nothing about. Skip Phase 3 entirely when there was no transcript.
8. Never write a claim into the state that this run could not verify — no shas, no branch-sync, no "tree clean". Headless has no git.
