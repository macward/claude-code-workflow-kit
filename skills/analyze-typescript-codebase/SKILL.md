---
name: analyze-typescript-codebase
description: "Audit health and architecture of a TypeScript or JavaScript codebase (Node backends, React/Vite, Next) with real tools (tsc, eslint, knip, madge, jscpd, lizard, package-manager audit, coverage) plus idiomatic judgment. Use for 'analyze/audit the repo', 'tech debt', 'what to refactor', 'coupling' on a TS, JS or Node project. Not for a single PR (code-review) or writing features."
---

# TypeScript / JavaScript codebase audit

Audit a TypeScript or JavaScript repository (Node, browser, or both) by combining **measurement** (real static tools) with **judgment** (targeted reading of idiomatic patterns). The output is a prioritized, actionable report, not a flat list of findings.

## Principles that override everything else

1. **Evidence or it doesn't exist.** Every finding carries `path/file.ts:line` or a reproducible command with its output, and every `file:line` is checked against the real file before it goes in (step 4). Generic claims ("coupling is high") with no concrete file behind them stay out of the report.
2. **Don't hallucinate debt.** A healthy repo must be able to come out with few findings. If an axis is fine, say so in one line and move on.
3. **Fact vs opinion, kept apart.** Measurable things (`tsc` 14 errors, 212 `any`, a 3-module cycle) are facts. Debatable things (this abstraction is unnecessary) are opinions and labeled as such.
4. **Don't contaminate the audited project.** Never `npm install` a tool into the project, never touch `package.json`, the lockfile, `tsconfig*.json` or lint configs. Tools run ephemerally (`npx --yes`, `pnpm dlx`, `uvx`); any config you need goes in the scratchpad or `/tmp`. See `references/tooling.md`.
5. **Always prioritize.** The report ends in "what to fix first", ordered by impact × effort, not in 60 unranked findings.
6. **Read-only.** No builds that write into tracked paths, no `--fix`, no refactoring. This is an audit, not an intervention.

## Flow

1. Recon: package manager, framework, layout, tsconfig strictness.
2. Measure per axis with the tools, capturing raw output.
3. Targeted reading of what tools can't see (idiomatic TS/React/Node, pattern decisions).
4. Verify every anchor in the draft findings against the real files.
5. Synthesize into the fixed report format below.

Don't skip step 3: eslint and knip catch style and dead code, but they won't tell you that business logic lives in a React component or that every route handler re-validates input by hand. That's reading.

## 1. Recon

```bash
# Package manager (the lockfile decides; don't guess)
ls package-lock.json pnpm-lock.yaml yarn.lock bun.lockb bun.lock 2>/dev/null
# Monorepo?
ls pnpm-workspace.yaml turbo.json nx.json lerna.json 2>/dev/null; grep -n '"workspaces"' package.json
# Framework and runtime
grep -nE '"(react|next|vite|@nestjs/core|express|fastify|hono|vue|svelte)"' package.json
# Scripts the project already defines (prefer them over ad-hoc commands)
grep -nA20 '"scripts"' package.json
# Size and layout
git ls-files '*.ts' '*.tsx' | grep -v '\.d\.ts$' | wc -l
git ls-files '*.ts' '*.tsx' | cut -d/ -f1-2 | sort | uniq -c | sort -rn | head -15
# Are dependencies installed? Several tools need node_modules
test -d node_modules && echo "deps installed" || echo "NO node_modules"
```

**Decide the language mode before measuring anything** — it changes filters, which tools apply, and the Health axis:
```bash
git ls-files '*.ts' '*.tsx' | grep -vc '\.d\.ts$'          # TS files
git ls-files '*.js' '*.jsx' '*.mjs' '*.cjs' | grep -vcE '\.min\.js$|(^|/)(dist|build|coverage)/'   # JS files
ls tsconfig*.json jsconfig.json 2>/dev/null
grep -n '"type"' package.json                              # "module" = ESM; absent/"commonjs" = CJS
```

| Mode | When | What changes |
|------|------|--------------|
| **TS** | JS files are only configs/scripts | Everything as written |
| **JS** | No TS source (plain Node, JS React) | Skip every **[TS]** step; types measured as in "JS mode" below; add `references/typescript-idioms.md` §6 |
| **Mixed** | Both hold real source | Measure both; the TS/JS ratio and whether it's moving (`git log` of renames) is itself a fact for the report |

The filters (`G`, `EXT`) for each mode are defined at the top of `references/tooling.md`. Don't audit a JS project with TS filters: every grep comes back empty and an empty result reads as a healthy repo.

Read `tsconfig.json` or `jsconfig.json` if present (and whatever it `extends`/`references`). In TS mode the strictness flags are the first health fact: `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride`, `noFallthroughCasesInSwitch`, and whether `skipLibCheck` or `allowJs` hide anything. Note existing eslint/prettier/biome configs: you measure with them, you don't replace them.

In a monorepo, audit per package (each has its own tsconfig and deps) and add one cross-package section for the dependency graph between packages.

**If `node_modules` is missing:** `tsc`, eslint with type-aware rules, type-coverage, knip and tests can't run reliably. Don't install the project's deps yourself unless the user asks; report those sub-analyses as "not measured" and continue with what works without them (madge, jscpd, lizard, grep, audit from lockfile).

## 2. Measurement per axis

Exact commands, flags per package manager, and how to read each number are in `references/tooling.md`. **Read it before running**: several tools give misleading output under default flags (knip on framework entry points, madge without `--ts-config`, coverage without the provider installed).

### Axis A — Health (most quantitative)
- **[TS]** `tsc --noEmit` → real type errors. A repo that ships with type errors has a broken gate; that's a top finding.
- **[TS]** tsconfig strictness + `type-coverage` → how much of the code the type system actually sees.
- **[TS]** Escape hatches, counted: `any`, `as any`, `as unknown as`, `@ts-ignore`, `@ts-expect-error`, non-null `!`.
- **JS mode, instead of the three above:** validation at the boundaries (schemas on HTTP bodies, env, messages), `// @ts-check`/`checkJs`/JSDoc usage, and an optional informative `tsc --checkJs` pass (`references/typescript-idioms.md` §6). A JS repo isn't penalized for not being TS; it is for having no safety net at its inputs and no tests covering what types would have caught.
- `eslint-disable` count, in both modes.
- eslint (the project's config) → lint errors; add the `complexity` rule on the command line.
- `lizard` → cyclomatic complexity and function length (CCN > 10 review, > 20 severe; > 80 lines review).
- Coverage via the project's test runner → real coverage, crossed with *what* is covered.
- Package-manager audit → CVEs in prod dependencies.
- Security greps → `eval`, `new Function`, `dangerouslySetInnerHTML`, `innerHTML =`, secrets in client-exposed env vars.
- `TODO|FIXME|HACK|XXX` markers with age from `git log`.

### Axis B — Modularity / coupling (structure)
- `madge --circular` → **import cycles** (the strongest modularity finding).
- `madge` fan-in/fan-out or `dependency-cruiser` → god modules everyone imports, layers importing in the wrong direction.
- `knip` → unused files, unused exports, unused deps, used-but-undeclared deps.
- `jscpd` → duplicated blocks (copy-paste that asks for a shared function).
- Manual reasoning over the graph: do barrel files (`index.ts`) create cycles? Does domain logic import from UI or HTTP? Correct direction is UI/transport → domain → data, never the reverse.

### Axis C — Consistency (internal uniformity)
Not "does it follow best practices?" but "does it do the same thing the same way?". Reading + grep:
- Error handling: one strategy, or thrown errors, `Result`-style returns, `null` and swallowed `catch {}` coexisting without a rule?
- Data fetching: one client/hook pattern, or `fetch` in components next to a query library next to axios?
- Types: `interface` vs `type`, enums vs string unions, where shared types live.
- Naming and file layout: casing of files and components, feature-folders vs type-folders mixed.
- Imports: path aliases (`@/`) vs deep relative (`../../../`) mixed.

### Axis D — Idiomatic TS/JS (plus React / Node when present)
100% targeted reading. The full antipattern checklist, with what to grep and what to read, is in `references/typescript-idioms.md`. **Read it.** It covers: type-system escape hatches [TS], validation at trust boundaries, async/promise handling, module structure, React (effects, state, rendering), Node/backend handlers, config and process lifecycle, and JS-specific traps (CommonJS/ESM mixing, callback-era async, coercion) for JS mode.

### Axis E — Patterns (descriptive before evaluative)
First inventory which patterns exist (custom hooks layer, services/API client, repository, DI container, state store, adapters), then judge whether they're justified:
- **Over-engineering**: interfaces with one implementation and no foreseeable second, generic wrappers around a single call site, layers that only forward props or data, abstractions for scale the project doesn't have.
- **Under-engineering**: the same fetch + loading + error dance repeated in N components, the same validation in N handlers.
- A misapplied pattern (cargo cult) is worse than its absence: label it as such.

## 3. Verify every anchor (MANDATORY, before writing the report)

Wrong line numbers are the failure an audit doesn't notice: a number copied from a multi-file dump, a delegated summary or memory looks exactly as credible as a real one, and a single impossible anchor (`limiter.ts:624` in an 88-line file) discredits the whole report. For every `file:line` or range in the draft:

```bash
wc -l <file>                  # a line past EOF is a fabricated anchor
sed -n '<line>p' <file>       # or '<start>,<end>p' for a range
```

- The printed line must show what the finding claims (the symbol, call or construct); a range must contain it.
- If it doesn't, re-anchor with `grep -n '<symbol>' <file>` on the real file and fix the number. If the construct can't be found, drop the finding.
- Take line numbers only from the individual file (reading it, `grep -n`, tool output that names the path). Never from `cat a b c`, a concatenated dump or a subagent's summary; re-anchor those.
- Tool-reported locations (eslint, lizard, jscpd, knip) are trustworthy only when the tool ran on the audited working tree; spot-check one.
- State the result in Raw measurements: `Anchors verified: N/N (M re-anchored, K dropped)`.

## 4. Synthesis: MANDATORY output format

Use exactly this structure. No rhetorical padding or long executive summaries. Write the report in the user's language.

```markdown
# Audit — <repo name>
<commit / date> · <N files · N LOC> · <TS / JS / mixed (N% TS)> · <package manager · runtime/framework · CJS/ESM>

## Summary by axis
| Axis | Score | One-line status |
|------|-------|-----------------|
| Health | 0-5 | ... |
| Modularity | 0-5 | ... |
| Consistency | 0-5 | ... |
| Idiomatic | 0-5 | ... |
| Patterns | 0-5 | ... |

## What to fix first
Ordered by impact × 1/effort. Max 7 items. Each:
- **[title]** — what, where (file:line), why it matters, estimated effort (S/M/L).

## Findings
| # | Axis | Sev | Location | Finding | Type |
|---|------|-----|----------|---------|------|
| 1 | Health | High | src/api/client.ts:88 | response cast `as User[]` with no runtime validation; backend drift crashes at render | Fact |
...
Sev: High / Medium / Low. Type: Fact / Opinion.

## Raw measurements
Summarized output per tool + what could not be measured and why + anchors verified.

## What's fine
Brief. What NOT to touch and why it's already healthy. (Keeps the repo from looking worse than it is.)
```

### Scoring rules
0 = broken/absent · 3 = works with real debt · 5 = solid, no action needed. The score is an opinion calibrated by the data, not an automatic formula: justify it with the findings.

## Close
End by offering to go deeper on the worst-scored axis or to turn "What to fix first" into tasks. Don't start refactoring unless the user asks.
