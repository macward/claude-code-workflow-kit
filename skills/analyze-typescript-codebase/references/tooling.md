# Toolchain: commands and interpretation

Replace `<src>` with the code folder (`src`, `app`, `lib`, `packages/<name>/src`; in many Node JS projects the code sits at the root next to `package.json`) and `<tsconfig>` with the tsconfig that covers it (often `tsconfig.app.json` in Vite projects, not the root `tsconfig.json`, which may only hold `references`).

**Language mode** (decided in recon, see `SKILL.md`): sections marked **[TS]** only apply in TS or mixed mode; everything else applies to both. Set the shared filters once, per mode:
```bash
# TS mode
G='--include=*.ts --include=*.tsx --exclude=*.d.ts --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build --exclude-dir=coverage'
EXT='ts,tsx'
# JS or mixed mode (mixed = a migration in progress: measure both)
G='--include=*.ts --include=*.tsx --include=*.js --include=*.jsx --include=*.mjs --include=*.cjs --exclude=*.d.ts --exclude=*.min.js --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build --exclude-dir=coverage'
EXT='ts,tsx,js,jsx,mjs,cjs'
# madge flag: only when a tsconfig/jsconfig exists (it resolves path aliases)
TSC_FLAG=$( [ -f <tsconfig> ] && echo "--ts-config <tsconfig>" )
```

**Isolation rule.** Tools run ephemerally: `npx --yes <tool>@latest` (npm), `pnpm dlx <tool>` (pnpm), `bunx <tool>` (bun), `uvx <tool>` (Python tools). Never `npm install -D`. Temporary configs go in `$TMP_AUDIT` (the scratchpad or `mktemp -d`), never in the repo. If a tool already exists in the project's `node_modules/.bin`, using it is fine — it's the version the project is pinned to.

If a tool fails for lack of network or environment, record it and degrade: the report says what was measured and what wasn't, never fills the gap with assumptions.

## tsc — type errors [TS]
```bash
npx tsc --noEmit -p <tsconfig> --pretty false 2>&1 | tail -40
npx tsc --noEmit -p <tsconfig> --pretty false 2>&1 | grep -c 'error TS'
# Project references (tsconfig with "references"): build mode, still no emit
npx tsc -b --noEmit 2>&1 | tail -40
```
Needs `node_modules`. Interpretation: any error in a repo whose CI/build passes means the build doesn't type-check (common with Vite/esbuild, which strip types without checking). Group errors by code: `TS2322/TS2345` (assignability) are real bugs more often than `TS7006` (implicit any).

## Strictness and escape hatches [TS]
```bash
# Effective config after extends
npx tsc -p <tsconfig> --showConfig | grep -E 'strict|noUnchecked|exactOptional|noImplicit|skipLibCheck|allowJs'

# Escape hatches ($G from the top of this file)
grep -rnE ':\s*any\b|<any>|as any\b|any\[\]' $G <src> | wc -l
grep -rn 'as unknown as' $G <src> | wc -l
grep -rnE '@ts-ignore|@ts-nocheck' $G <src> | wc -l
grep -rn '@ts-expect-error' $G <src> | wc -l
grep -rn 'eslint-disable' $G <src> | wc -l
grep -rnE '[A-Za-z0-9_\)\]]!\.' $G <src> | wc -l   # non-null assertions (approximate)
```
Interpretation: `@ts-ignore`/`@ts-nocheck` are worse than `@ts-expect-error` (the latter fails once the error is gone). `as unknown as` is a deliberate type-system bypass — read each one. Report counts plus the 3–5 worst files, not every hit.

## type-coverage — how much is really typed [TS]
```bash
npx --yes type-coverage -p <tsconfig> --strict --at-least 0 2>&1 | tail -3
npx --yes type-coverage -p <tsconfig> --strict --detail 2>&1 | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
```
Needs `node_modules`. Interpretation: percentage of identifiers whose type isn't `any`. ≥ 98% healthy, 90–98% leaks worth locating, < 90% the type system is decorative in parts. The `--detail` grouping shows where the `any` concentrates.

## eslint — lint + complexity
```bash
# Only if the project has an eslint config. Use the project's own eslint.
npx eslint <src> --format compact 2>&1 | tail -30
npx eslint <src> --format json -o $TMP_AUDIT/eslint.json; \
  node -e 'const r=require(process.argv[1]);const c={};for(const f of r)for(const m of f.messages)c[m.ruleId]=(c[m.ruleId]||0)+1;console.log(Object.entries(c).sort((a,b)=>b[1]-a[1]).slice(0,15))' $TMP_AUDIT/eslint.json
# Suppressions (both modes; the [TS] section above repeats it for TS escape-hatch totals)
grep -rn 'eslint-disable' $G <src> | wc -l
# Complexity on top of the existing config, without editing it
npx eslint <src> --rule '{"complexity":["warn",10],"max-depth":["warn",4]}' --format compact 2>&1 | grep -E 'complexity|max-depth'
```
Interpretation: rank by rule, not by raw count — 400 `prettier/prettier` hits say nothing, 12 `@typescript-eslint/no-floating-promises` are 12 potential bugs. The type-aware rules that find the most real bugs: `no-floating-promises`, `no-misused-promises`, `no-unsafe-*`, `react-hooks/exhaustive-deps`. If the project uses Biome instead: `npx @biomejs/biome lint <src>`. No linter at all is itself a Health finding; don't create a config in the repo to compensate.

## lizard — complexity and function length (no node_modules needed)
```bash
uvx lizard -l typescript -l javascript -C 10 -L 80 -w <src> 2>/dev/null | head -40
uvx lizard -l typescript -l javascript <src> 2>/dev/null | tail -5   # totals
```
Interpretation: `-w` prints only warnings (CCN > 10 or length > 80). CCN 1–5 simple, 6–10 ok, 11–20 review, 21–30 refactor, > 30 severe. React components with high CCN are usually rendering too many states inline; handlers with high CCN are usually mixing validation, logic and I/O.

## madge — import cycles and fan-in
```bash
npx --yes madge --circular --extensions $EXT $TSC_FLAG <src>
# Most-depended-on modules (fan-in)
npx --yes madge --json --extensions $EXT $TSC_FLAG <src> > $TMP_AUDIT/graph.json
node -e 'const g=require(process.argv[1]);const c={};for(const d of Object.values(g))for(const x of d)c[x]=(c[x]||0)+1;console.log(Object.entries(c).sort((a,b)=>b[1]-a[1]).slice(0,10))' $TMP_AUDIT/graph.json
# Orphans (nothing imports them) — cross-check with knip before reporting
npx --yes madge --orphans --extensions $EXT $TSC_FLAG <src>
```
Interpretation: without `--ts-config` (when a tsconfig/jsconfig exists), path aliases (`@/…`) don't resolve and cycles get silently missed. A cycle is the strongest modularity finding; cycles through an `index.ts` barrel are the most common cause. High fan-in on a `utils.ts`/`types.ts` is normal; high fan-in on a component or a service means a god module. In CommonJS, madge follows `require` calls too, but not dynamic `require(variable)`. `type`-only imports can form harmless cycles — check whether the edge is `import type` before reporting.

For layer rules (e.g. `components/` must not import `api/` directly), `dependency-cruiser` with a temporary config:
```bash
npx --yes -p dependency-cruiser depcruise <src> $TSC_FLAG --config $TMP_AUDIT/.dependency-cruiser.cjs --output-type err
```

## knip — dead code and dependency hygiene
```bash
npx --yes knip --reporter compact 2>&1 | tail -60
npx --yes knip --include dependencies,unlisted,unresolved   # deps only
```
Needs `node_modules`. Interpretation, per category: `unlisted` (imported but not in `package.json`) is the most serious — it works by accident through a transitive dep. `dependencies` (declared, unused) is bloat. `files`/`exports` have false positives: framework entry points (Next `app/`/`pages/`, Remix routes, Vite/Storybook configs, files loaded by glob or string). knip ships plugins for most frameworks, but verify every unused-file hit by grepping its name before reporting it.

## jscpd — duplication
```bash
npx --yes jscpd <src> --min-tokens 70 --format typescript,tsx,javascript,jsx --ignore '**/*.test.*,**/*.spec.*,**/*.d.ts,**/*.min.js' --reporters console --silent 2>&1 | tail -20
```
Interpretation: < 3% duplicated lines is normal. Look at *which* blocks repeat: duplicated JSX layout is cheap; duplicated validation, mapping or fetch/error handling is a missing abstraction.

## Dependency vulnerabilities
```bash
npm audit --omit=dev                      # npm
pnpm audit --prod                         # pnpm
yarn npm audit --environment production   # yarn berry
yarn audit --groups dependencies          # yarn v1
# bun has no audit: report "not measured" or run npm audit against a generated lockfile only if the user agrees
```
Works from the lockfile, no `node_modules` needed. Interpretation: report package, severity, and the fixed version. Split prod from dev deps: a critical CVE in a build-time tool matters far less than one in a runtime dependency. Don't run `audit fix`.

## Security greps
```bash
grep -rnE '\beval\(|new Function\(' $G <src>
grep -rnE 'dangerouslySetInnerHTML|\.innerHTML\s*=|document\.write' $G <src>
grep -rnE '(VITE|NEXT_PUBLIC|REACT_APP)_[A-Z_]*(SECRET|TOKEN|KEY|PASSWORD)' -r <src> .env* 2>/dev/null
grep -rnE "(api[_-]?key|secret|password|token)['\"]?\s*[:=]\s*['\"][A-Za-z0-9_\-]{16,}" $G <src>
grep -rnE 'child_process|exec\(|execSync\(' $G <src>
```
Interpretation: client-exposed env prefixes (`VITE_`, `NEXT_PUBLIC_`, `REACT_APP_`) end up in the bundle — any secret there is public. `dangerouslySetInnerHTML` is only a finding if the HTML can come from user input; trace where it's fed from.

## Coverage — real coverage
```bash
# Use the project's runner; don't install a coverage provider
npx vitest run --coverage --coverage.reporter=text-summary 2>&1 | tail -15
npx jest --coverage --coverageReporters=text-summary 2>&1 | tail -15
```
Needs `node_modules`. Coverage writes a `coverage/` folder: check it's gitignored before running, and delete it afterwards if it wasn't there. If vitest reports a missing `@vitest/coverage-v8`, run the tests without coverage and report coverage as "not measured". Interpretation: the global number lies. With the full text reporter, check *what* is uncovered — if hooks, API clients and reducers are uncovered while presentational components are covered, the good number is fake. No tests or tests that don't run: report "not measured", don't assume 0.

## Markers and age
```bash
grep -rnE 'TODO|FIXME|HACK|XXX' $G <src> | wc -l
git log -S FIXME --format='%ar' --reverse -- <src> | head -1   # age of the oldest one still introduced
```

## Size and shape
```bash
which tokei && tokei <src> || uvx lizard -l typescript <src> | tail -3
```

## Bundle size (frontend, optional)
Only if the user asks or `dist/` already exists: a build writes files. If `dist/`/`build/` is gitignored and present, inspect it without rebuilding:
```bash
du -sh dist/assets/* 2>/dev/null | sort -h | tail -10
```
A single JS chunk > 500 kB (uncompressed) with no code splitting on a multi-route app is a finding.
