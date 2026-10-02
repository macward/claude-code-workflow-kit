---
name: meridian-cut-release
description: "Cut a Meridian release with a semver-derived version bump. Reads the open release's accumulated tasks, suggests major/minor/patch from the rendered changelog, previews it, and cuts only after human confirmation. Stops before git/deploy."
---

# Meridian Cut Release

Cuts a project's open release, assigning it a **SemVer version suggested from what actually shipped**, and opens the next bucket. All the "which number is next?" logic lives here: the server stores `version` as a free string and computes nothing.

## Data model (read before touching anything)

- A task is marked shipped when it moves to `deployed`: the server stamps `shipped_release_id` = the `open` release at that moment (write-once, same transaction). That's what accumulates in the open release.
- The open release (`status: open`) is the "Unreleased" accumulator. A **cut** freezes it to `released` (immutable) and opens the next one.
- **API subtlety that governs the flow:** in the cut call, `version` names the **next** open release. The release being frozen **keeps the `version` it already had**. That's why this skill stamps the computed version on the open release with a `PATCH` **before** cutting, and uses the cut's `version` only for the next bucket.

## Human gate (mandatory)

The cut freezes a release to **immutable** `released` — it can't be deleted or edited afterwards. It's the hard-to-undo step of this flow.

- **Never cut without explicit user confirmation.** The skill stops at the preview and waits for OK.
- **Never run this skill through to the cut unattended** (`/schedule`, `/loop`). Unattended it may at most present the preview and the suggested version; Max triggers the cut.
- This is a Meridian write, not git. **Deploy remains 100% Max's** — this skill does no commit, push or deploy, and ends before all of that.

## How this skill talks to Meridian

The seven release tools are **not on the default MCP surface** — they live in
the `releases` opt-in toolset (`src/meridian/toolsets.py`), because a normal
session never cuts a release and would pay their schema anyway. This skill
reaches them over REST with `scripts/meridian_api.sh <METHOD> <PATH> [BODY]`,
which reads `MERIDIAN_API_URL`/`MERIDIAN_API_TOKEN` from the repo-root `.env`,
prints the JSON response and exits non-zero on a 4xx/5xx.

Nothing about the data model changes — these are the same operations behind the
same service. If a deployment runs with `MERIDIAN_TOOLSETS=releases`, the MCP
tools are there too and either path works.

## Setup

Read `meridian-project: <project>` from the active project's CLAUDE.md. That's the `project` for every call.

The user may invoke with or without an argument:
- No argument: cut the active project's open release, suggested version.
- Argument that is an explicit version (e.g. `/meridian-cut-release 2.0.0`): use that as the version of the release being shipped, skipping the bump computation (but still show the preview and confirm).

## Process

### 1. Locate the open release

```bash
scripts/meridian_api.sh GET "/projects/<project>/releases?status=open"
```

There must be exactly one. Save its `id` (`OPEN_ID`), `version` (`V_OPEN`, may be `null`) and `shipped_count`.

- If there is none → report that the release system hasn't been initialized yet (the open release is created on first use). Don't invent; stop.
- If `shipped_count == 0` → **warn that the release is empty** (no deployed tasks accumulated) and ask whether to cut anyway. Don't cut by default.

### 2. Preview of the accumulated changelog

```bash
scripts/meridian_api.sh GET "/projects/<project>/releases/$OPEN_ID?changelog=true"
```

The `changelog` field is the Keep a Changelog markdown of the tasks shipped in this release, grouped under `### Added / Changed / Deprecated / Removed / Fixed / Security`. It's the source for the bump.

### 3. Base version

```bash
scripts/meridian_api.sh GET "/projects/<project>/releases?status=released"
```

Newest-first. The `version` of the first one (`V_BASE`) is the last published version.
- If the list is empty → this is the **first release**: `V_BASE = 0.0.0`. Don't auto-suggest `1.0.0` (that's a human milestone decision); suggest `0.1.0` and flag it.

### 4. Compute the suggested bump

Over the sections present in the step 2 changelog, against `V_BASE = MAJOR.MINOR.PATCH`:

| Sections present | Bump | Result |
|---|---|---|
| `Removed` | **major** | `(MAJOR+1).0.0` |
| `Added` or `Deprecated` (no `Removed`) | **minor** | `MAJOR.(MINOR+1).0` |
| only `Changed` / `Fixed` / `Security` | **patch** | `MAJOR.MINOR.(PATCH+1)` |

Honesty rules (always say, never hide):
- **`Changed` is ambiguous.** It may be breaking (→ major) or not. There is no `breaking` flag on tasks yet. If there is a `Changed` section, **flag it explicitly** and ask the human to decide whether it warrants major.
- **0.x regime** (`V_BASE` is `0.y.z`): in pre-1.0 SemVer anything may break. Suggest: breaking → `0.(y+1).0`, features → `0.(y+1).0`, fixes → `0.y.(z+1)`. **Never** auto-jump to `1.0.0` — flag it as a human decision.
- If the user passed an explicit version as argument, skip the table but still show what the rule would have suggested (so they see whether it differs).

### 5. Present and wait for confirmation

Show, in this order:

```
Release to cut: <V_OPEN or "(no version assigned)">  ·  <shipped_count> tasks
Last published: <V_BASE>

Suggested bump: <V_SUGGESTED>  (<major|minor|patch> — <reason: which sections drive it>)
⚠ <flags: Changed section to review / 0.x regime / first release / etc.>

--- Changelog preview ---
<markdown from step 2>
```

**Stop here.** Ask: confirm `V_SUGGESTED`, or do you want another version? Don't proceed without an answer.

### 6. Execute the cut (only after OK)

Let `V_SHIP` be the confirmed version:

1. **Stamp the version on the release about to be frozen** (if `V_OPEN != V_SHIP`):
   ```bash
   scripts/meridian_api.sh PATCH "/projects/<project>/releases/$OPEN_ID" '{"version": "<V_SHIP>"}'
   ```
2. **Version of the next bucket** (the cut's `version` arg): propose an editable placeholder — by default the next patch of `V_SHIP` (e.g. `V_SHIP` = `1.4.0` → next `1.4.1`). Clarify it's only the label of the next "Unreleased" bucket and can be renamed later with another `PATCH`. Accept a user override.
3. **Cut:**
   ```bash
   scripts/meridian_api.sh POST "/projects/<project>/releases/$OPEN_ID/cut" \
       '{"version": "<next bucket>", "notes": "<optional>"}'
   ```

   Omit `notes` entirely when the user gave none.

### 7. Report

- Frozen release: `V_SHIP`, `released_at`.
- New open release: `<next bucket>`.
- Remind: **`CHANGELOG.md` update and deploy are still pending — Max does those.** The preview markdown (step 2) is exactly what goes in the new `## [V_SHIP] - <date>` section of `CHANGELOG.md`.
- Offer (optional, only if the user asks) to dump that block into the local `CHANGELOG.md`, moving the `[Unreleased]` content into the versioned section. **Leave it uncommitted** — stop before git.

## Rules

1. Always filter by the active project (`meridian-project:`).
2. The bump derives from the rendered changelog, it's never invented. If the changelog is empty, there is no bump to suggest.
3. Human confirmation mandatory before the cut. No exception, no unattended mode that reaches the cut.
4. The shipped release's version is set with a `PATCH` on the open release **before** the cut; the cut's `version` is the next bucket, never the one being published.
5. No commit, push or deploy. The skill ends at "release cut in Meridian, CHANGELOG.md and deploy pending on Max".
6. Don't fix or touch the tasks' `shipped_release_id` — it's write-once by the server at deploy.
