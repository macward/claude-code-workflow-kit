# Weekly Report Template

Template for weekly reports saved in Meridian (`reports/` folder). Same audience as `recap-template.md`: the whole team, no technical jargon. It works both for a single project and for several combined in one report — the "Per project" section is repeated once per project and works the same with just one.

---

## Authoring rules

1. **No unexplained technical terms.** No "refactor", "PR", "async", "schema", "endpoint". Translate: "the connection between systems", "the data structure", etc.
2. **No code.** No snippets, file names, or functions.
3. **What and why, never how.** Result and motivation, not implementation steps.
4. **One "Per project" section for each project covered.** With a single project, there is just one section — no need to announce it as "multi-project" or merge anything.
5. **The executive summary is mandatory, the rest is optional if it doesn't apply.** "Blockers", "Cross-project pending items" and the technical block are omitted entirely if there is nothing to say — don't force content.
6. **Short sentences. No nested bullets.** Direct tone, like explaining to someone smart who isn't a dev.
7. **Never invent progress.** If a project had no relevant movement during the week, say so in one line ("No changes this week") instead of omitting the section or padding it.

---

## Template

```markdown
---
week_start: YYYY-MM-DD
week_end: YYYY-MM-DD
projects: [<name>, <name>, ...]
author: <name inferred from git config or the conversation>
---

# Weekly Report: <YYYY-MM-DD> to <YYYY-MM-DD>

## Executive summary

<2-4 sentences with the big picture of the week. With a single project, it is the
summary of that project. With several, the common thread or the most relevant
milestones across all of them, before getting into the per-project detail.>

## Per project

### <Project name>

**What moved forward**
<2-4 sentences about what changed or was delivered this week, in terms of
functionality or observable behavior.>

**Blockers or risks**
<Optional. Only if something concrete is holding back progress. Omit if it doesn't apply.>

**Next week**
<1-3 sentences about what comes next.>

<!-- Repeat the whole "### <Project name>" block for each additional project. -->

## Pending items / open decisions

<Optional. Unresolved questions or decisions that cross projects or that
remain pending for next week. Omit if there is nothing relevant.>

---

<!-- TECHNICAL BLOCK: include only if there are details relevant to the technical team.
     If it doesn't apply, remove this whole section. -->

## For the technical team

<Concrete details per project: completed tasks, affected areas of the system,
relevant technical decisions. Technical terms may be used here.>
```
