# SDD Reconcile Command

Reconcile the original SDD against the real implementation, before archiving the feature. Detects divergences, proposes a resolution per category and updates the SDD so it reflects the post-implementation reality.

## When to use

After `solve-task` / `run-plan` and **before** `archive`. The feature is merged or ready to merge; the code exists; the original SDD is frozen in `specs/`.

## STRICT PROHIBITIONS

- ❌ Don't archive the feature (that's `archive`'s job)
- ❌ Don't modify implementation code during this step (only propose changes; `solve-task` applies them if the user decides so)
- ❌ Don't update the SDD without explicit confirmation per divergence

## Setup

1. Read `vibe: <project>` from the active CLAUDE.md.
2. Identify the SDD to reconcile:
   - If the user passed a name as an argument, use it.
   - If not, list the project's active SDDs and ask.
3. Identify the feature's commit range:
   - By default: commits from the base branch to HEAD.
   - The user can pass an explicit range.

## Process

### 1. Load artifacts

```
mcp__meridian__read_doc(project=<project>, folder="specs", filename=<sdd_file>)
```

Read the relevant commits with `git log --oneline <base>..HEAD` and diffs per affected file.

List the files touched in the range. For each one, read the current state (not the diff — the final result).

### 2. Extract verifiable claims from the SDD

Identify SDD claims that can be checked against the code. Categories:

- **Structural**: "module X is created at path Y", "service Z exposes method W", "table T has columns A,B,C".
- **Behavior**: "the endpoint returns 401 if the token is missing", "function F validates input".
- **Constraints**: "MUST", "MUST NOT", "maximum N".

Ignore purely descriptive or motivational claims ("this solves problem X") — they're not verifiable.

### 3. Verify each claim against the code

For each claim:
- Look for evidence in the code (path, function, test, schema).
- Classify the result into one of 3 categories:

| Category | Meaning |
|---|---|
| ✅ **Match** | The code reflects the claim |
| ⚠️ **Accidental divergence** | The code drifted with no documented reason (suspected bug or shortcut) |
| 🔄 **Intentional divergence** | The code reflects knowledge the SDD didn't anticipate (the implementation knew more) |

Heuristic to tell ⚠️ from 🔄:
- If the divergence introduces inconsistency or omits something from the SDD without justification → ⚠️.
- If the divergence adds information, simplifies something that was needlessly complex, or resolves an edge case → 🔄.
- When in doubt, mark as 🔄 and let the user decide.

### 4. Present report

```
## Reconcile Report — <sdd_filename>
_<date> · commits <base>..HEAD_

### ✅ Match (N claims)
- "Endpoint /healthz MUST exist without auth" — verified in src/api/health.py:12

### ⚠️ Accidental divergences (N)
- SDD: "table `latencies` has an index on `(operation, recorded_at)`"
  Code: index only on `operation`
  Suggestion: add composite index or document why it's omitted

### 🔄 Intentional divergences (N)
- SDD: "ObservationService.save returns {id, path}"
  Code: returns {id, path, deduped: bool}
  Suggestion: update SDD to reflect the dedup flag

### Unverifiable claims (N)
- "this design scales better than alternative X" — descriptive, no action
```

### 5. Resolve divergences

For each ⚠️ and 🔄, present the options to the user and wait for a decision:

**⚠️ Accidental:**
- a) Update code to go back to the SDD (creates a pending task for `solve-task`)
- b) Document as an accepted deviation in `## Deviations` of the SDD
- c) Skip (decide later)

**🔄 Intentional:**
- a) Update SDD to reflect reality
- b) Document as an explicit deviation in `## Deviations`
- c) Skip

Don't advance to step 6 until every one has a decision.

### 6. Apply updates to the SDD

For each decision that requires editing the SDD:

- **Direct update**: modify the SDD text so it matches the code.
- **Documented deviation**: add a block at the end of the SDD:

```markdown
## Deviations from original spec

### <YYYY-MM-DD> — <short title>

**Original:** <exact quote from the SDD pre-update>
**Implementation:** <what the code does>
**Reason:** <why the divergence was accepted>
**Type:** accepted accidental | intentional
**Trigger to revisit:** <condition under which we'd have to go back to the original>
```

Persist the updated SDD by overwriting the existing file:

```
mcp__meridian__create_doc(
  project=<project>,
  folder="specs",
  filename=<sdd_file>,   # the same one it was read with, not a derived one
  content=<updated_content>,
  upsert=True
)
```

`upsert=True` is mandatory: the generic CRUD is create-only by default, so without it this fails with `DocumentAlreadyExistsError` instead of overwriting. And `filename` is explicit because, if omitted, it's derived from the document's H1 and may not match the name of the SDD being reconciled — which would create a new one alongside instead of updating the one that was read.

### 7. Final verification

After applying updates, present a summary:

```
## Reconcile Complete

- Match:                 N
- Divergences resolved:  N
  - SDD updates:          N
  - Documented deviations: N
  - Pending tasks created: N
- Skipped:               N

SDD updated: <path>
```

If items remain in "Skipped", warn that the reconciliation is partial and the feature should NOT be archived until they're closed.

## Rules

1. It's an interactive command — wait for a decision per divergence. Don't auto-resolve.
2. ⚠️ and 🔄 are heuristics, the user has the final say.
3. Never delete content from the original SDD — only modify specific claims or add deviations.
4. If there are no divergences, say so: "✓ No divergences. SDD reflects the implementation. Ready to archive."
5. If the SDD doesn't exist or isn't identifiable, fail explicitly — don't invent one.
