---
name: meridian-requirements
description: "Generate a requirements document in MoSCoW format with BDD scenarios for a feature. Discovery phase — defines WHAT the feature must do, not HOW. Writes to requirements/ in the vibe workspace."
---

# Requirements

Generates a MoSCoW-format requirements document with BDD scenarios for a feature. Defines the *what*, not the *how*.

## HARD PROHIBITIONS

- ❌ Don't design architecture or technical solutions
- ❌ Don't create tasks or specs
- ❌ Don't implement anything
- ❌ Technical details the user mentions become observable behavior, never an implementation requirement: "use WebSockets" → "The user MUST see real-time updates"

## Setup

Read `meridian-project: <project>` from the active project's CLAUDE.md.

## Process

### 1. Receive the feature

The user describes the feature in their message. If the description is too vague (less than a sentence), ask **a single question** about the main goal. Never more than once. If the user already has written requirements, use them as the base and fill in what's missing.

**Resolve two things:**

- **`<slug>`** — the kebab-case feature slug that names the file (`requirements-<slug>.md`). If the user mentions a Meridian feature, take its slug from `mcp__meridian__list_features` / `get_feature`; otherwise derive it from the feature name. It's never `unknown`: every feature without an entity would land on the same file. `meridian-spec` and `meridian-task-breakdown` look the doc up by this slug.
- **Whether the feature exists as an entity** in Meridian — it decides the `feature` parameter in step 5. When it doesn't, the doc's `Feature` row says `unknown`.

**Check for an existing doc** with `mcp__meridian__read_doc(project=<project>, folder="requirements", filename="requirements-<slug>.md")`. Step 5 saves with `upsert=True`, which overwrites it: if it exists, it's the base — keep its content and scenario IDs, and bump `Version`. `DocumentNotFoundError` → a new doc.

### 2. Generate the document

Follow this structure, adapted to the scope — don't force sections that don't apply.

```markdown
# <Feature Name>

| Property | Value |
|----------|-------|
| Version  | 0.1   |
| Date     | YYYY-MM-DD |
| Feature  | `<feature-slug>` |
| Status   | Draft |

## Goal

Define what problem this feature solves and for whom.

## Requirements

### MUST
- The user MUST be able to...
- The system MUST validate...

### SHOULD
- The UI SHOULD show...
- The system SHOULD notify...

### COULD
- COULD support... in the future

### WON'T
- The system WON'T support multi-tenant in this version.
- WON'T <X> — explicitly out of scope.

## Out of scope

List of related functionality explicitly excluded from this feature.

## Scenarios

### A — <group name>

#### A1 — <happy path name>
- **Actor:** <who triggers it>
- **Given** <situation the actor starts from>
- **When** <action the actor takes>
- **Then** <observable expected result>

#### A2 — <error case name>
- **Actor:** <who triggers it>
- **Given** <situation the actor starts from>
- **When** <action the actor takes>
- **Then** <observable expected result>

### B — <group name>

#### B1 — <scenario name>
- ...
```

**Requirements:** MUST = mandatory for the MVP; SHOULD = important but not blocking; COULD = optional, future; WON'T = explicitly out of scope for this version. Written from the user's or the system's perspective, never the implementation's.

**Scenarios:** always the happy path, at least one relevant error or edge case, concrete and testable.

**Scenarios become use cases.** `meridian-task-breakdown` materializes each one as a Meridian use case with a stable `UC-n` ref that tasks declare as coverage, mapping one to one: the `### A — <group>` heading → the list (`list_title`); the `#### A1 — <name>` heading, ID included → `title`; **Actor** → `actor`; **Given** → `situation`; **When** → `action`; **Then** → `expected_output`. Write them in that shape and nothing is lost.

- **Every scenario has an ID**: a letter for its group, a number within it.
  - **The letter groups** scenarios around the same moment or area of the feature (the signup, keeping the profile up to date, a sync's error paths). Each group becomes its own use case list. A single group still uses `A`; open `B` only for a second real group, not to split a short list.
  - **The number orders** within the group, from 1.
- **IDs are never renumbered.** A new scenario goes last in its group (`A4`); a removed one leaves its gap. The spec and tasks cite scenarios by ID, and the breakdown uses it to recognize a scenario it already materialized — renumbering makes `A2` silently point at another case. Until the breakdown assigns `UC-n`, the ID is the only handle.
- **Name the scenario as a short noun phrase** — it becomes the use case title a coverage report lists. "Crear una lista vacía", not "El usuario puede crear una lista vacía cuando no hay ninguna".
- **One actor per scenario.** Two actors means two scenarios.

This skill does **not** call `save_use_cases`: it runs before the feature entity exists, so there's nothing to save against. The document is the handoff.

### 3. Verify before saving

Run these three controls on the draft **always**, including a "generate and save" request. Fix what you find **in the document itself** — no trace section.

**1. Everything the user asked for is accounted for.** List every concrete thing the user's message named — data, behaviors, constraints, examples ("edad, dónde vive, intereses" is three items, not one idea). Each ends up in:

- a requirement (MUST/SHOULD/COULD) that names it, or
- WON'T / Out of scope, **with the reason** it was left out.

Replacing an item with something close ("birthday" for "age") counts as dropping it.

**2. Every MUST and SHOULD has a scenario.** For each MUST, and each SHOULD whose effect a user can observe, a scenario whose Then proves it. If none, add one at the end of its group (next free ID). A requirement without a scenario produces no use case, so no coverage check downstream will ever flag it — this is the only place the gap is caught. COULD and WON'T need none. **Backwards too:** a Then describing behavior no requirement states → add the requirement.

**3. Requirements don't contradict each other, and where they meet, the doc says what happens.** Read in pairs the requirements that touch the same data or moment (what the user says vs. what the system infers, a limit vs. an exception, two flows that can overlap):

- If they contradict, resolve it and keep one.
- If one wins, say what happens to **the other side too**, in the requirement and in the scenario's Then. "The profile keeps Córdoba" is half an answer when the conversation also said Mendoza: state what becomes of Mendoza.

A prohibition goes in MUST as **MUST NOT** ("Other users MUST NOT be able to see…"); WON'T is scope, not prohibition.

**Some fixes aren't yours to make** — dropping an item the user asked for, picking one of two contradictory behaviors. Don't settle them: write down the call you would make and carry it to step 4 as an **open decision**.

### 4. Ask the open decisions, then confirm

An open decision is anything the draft settles that the user didn't say: step 3's set-aside calls, plus assumptions made while writing. **Test: would a requirement or scenario read differently if the answer were the other one?** If not, decide it and move on. Mechanical fixes (a missing scenario, `MUST NOT` phrasing, IDs) are never questions.

**Ask them before saving, even if the user said "generate and save"** — saving an answer the user never gave is exactly what the controls exist to catch.

- `AskUserQuestion`, **at most 3 questions** in one call. With more, ask the ones that change the doc most; settle the rest yourself and list them when presenting.
- **One decision per question.** The first option is your call, labeled `(Recommended)`, its description saying what the doc will state. Each alternative's description names which requirement or scenario changes.
- **Apply every answer to the document** — requirement, WON'T with its reason, scenario's Then — and re-run control 2 on what changed.
- A free-text answer ("Other") is the decision. If ambiguous, **one** follow-up at most; then take the closest reading and say so.

Then:

- "Generate and save" → save once answered, or directly if there were no questions.
- Only a draft → show it, list the decisions you settled without asking, and wait for confirmation.

**As a sub-agent** there is no user to ask: `AskUserQuestion` doesn't reach one. Settle each open decision with the lightest reasonable call, save, and list the decisions at the end of the response, in the format of `.claude/agents/meridian-requirements.md`.

### 5. Save

Pass `feature=<slug>` **only** if step 1 confirmed the feature exists as an entity. Otherwise **omit** it — a nonexistent slug makes `create_doc` fail with `FeatureNotFoundError` and nothing is saved. That's the usual case: requirements runs before task-breakdown creates the feature, which re-links the doc later.

```
mcp__meridian__create_doc(
  project=<project>,
  folder="requirements",
  filename=requirements-<slug>.md,
  content=<content>,
  feature=<feature-slug>,  # omit if the feature doesn't exist in Meridian yet
  upsert=True,
)
```

Without `upsert=True`, re-running the skill on a feature that already has a requirements doc fails with `DocumentAlreadyExistsError` — the same reason `meridian-spec` passes it.

### 6. Confirm save

```
Saved: requirements/requirements-<slug>.md
```
