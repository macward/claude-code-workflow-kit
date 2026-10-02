# Idiomatic TypeScript / JavaScript: antipatterns checklist

For each item: what to grep to find candidates, and what to read to confirm. A grep hit is a candidate, never a finding by itself. Skip the sections that don't apply: §1 in JS mode, §4 without React, §5 without a backend, §6 in pure TS mode.

`G` is the grep filter from `references/tooling.md`, set per language mode (TS mode only includes `*.ts`/`*.tsx`; JS/mixed mode adds `*.js`, `*.jsx`, `*.mjs`, `*.cjs`).

## 1. Type system [TS]

**Unvalidated data crossing a trust boundary.** The most expensive TS antipattern: `fetch`/`axios` responses, `JSON.parse`, `localStorage`, `req.body`, URL params and env vars typed by assertion instead of checked.
```bash
grep -rnE '\.json\(\)\s*(as|\))|JSON\.parse\(' $G <src>
grep -rnE 'as [A-Z][A-Za-z]+(\[\])?\s*[;)]' $G <src> | grep -iE 'res|data|body|json|response' | head
grep -rnE "from ['\"](zod|valibot|yup|io-ts|@sinclair/typebox|arktype)['\"]" $G <src> | wc -l
```
Read: the API client layer. Is there one place where responses get parsed (zod or similar), or is every call `as User`? A schema library that's installed but used in 2 of 40 endpoints is a consistency finding too.

**Assertions instead of narrowing.** `as Foo` to silence the compiler where a type guard, `in`, discriminant check or `satisfies` would prove it.
Read: each `as unknown as`, and `as` inside conditionals. `satisfies` usage (TS ≥ 4.9) is a positive signal.

**Stringly-typed state.** `status: string` where `'idle' | 'loading' | 'error'` belongs; parallel booleans (`isLoading`, `isError`, `data`) instead of a discriminated union, which allow impossible states.
```bash
grep -rnE 'is(Loading|Error|Success|Fetching)\b' $G <src> | wc -l
grep -rnE '(status|state|type|kind)\??:\s*string\b' $G <src>
```

**Enums.** Numeric `enum`s (reverse mappings, unsafe number assignment) and `enum` where a string-literal union or `as const` object is simpler. Not a finding on its own if used consistently; it is if `enum` and unions model the same concept in different places.
```bash
grep -rnE '^\s*(export\s+)?(const\s+)?enum\s' $G <src>
```

**`catch (e)` handled as `any`.** With `useUnknownInCatchVariables` (part of `strict`), `e` is `unknown`; code doing `e.message` without narrowing either has strict off or casts.
```bash
grep -rnA2 'catch\s*(\w\+)' $G <src> | grep -E '\.message|\.response|as any|as Error'
```

**Duplicated types.** The same shape declared in several files, or frontend types hand-copied from a backend that publishes OpenAPI/tRPC/GraphQL types that could be generated.
```bash
grep -rnhE '^export (interface|type) \w+' $G <src> | awk '{print $3}' | sort | uniq -d
```

## 2. Async and promises

**Floating promises.** Async calls whose rejection nobody handles: `void`-less calls in handlers, `useEffect(() => { load() })`, `array.forEach(async …)`.
```bash
grep -rnE '\.forEach\(\s*async' $G <src>
grep -rnE 'onClick=\{async|onSubmit=\{async' $G <src>
```
Read: if eslint has `no-floating-promises`, trust its count instead. `forEach(async)` is always a bug (nothing awaits it).

**Sequential awaits that could be parallel**, and the opposite: unbounded `Promise.all` over user-sized arrays.
```bash
grep -rnB1 -A1 'for (const .* of' $G <src> | grep -B1 -A1 'await '
```

**Swallowed errors.** `catch {}` or `catch (e) { console.log(e) }` that turns a failure into silent wrong state.
```bash
grep -rnE 'catch\s*(\(\w*\))?\s*\{\s*\}' $G <src>
grep -rnA1 'catch' $G <src> | grep -c 'console\.\(log\|error\)'
```

**`.then` chains mixed with `async/await`** in the same module without reason — a consistency finding, rarely a bug.

## 3. Module structure

**Barrel files causing cycles or pulling everything in.** `index.ts` re-exporting a whole folder, imported from inside that same folder.
```bash
git ls-files '*index.ts' '*index.tsx' | xargs grep -lE '^export \* from' 2>/dev/null
```
Read: cross with madge cycles. An internal module importing from its own folder's barrel is the classic cycle.

**Deep relative imports** where an alias exists, or no alias at all in a large tree.
```bash
grep -rnE "from ['\"](\.\./){3,}" $G <src> | wc -l
grep -n '"paths"' tsconfig*.json
```

**Catch-all modules.** `utils.ts`, `helpers.ts`, `common.ts` over ~300 lines mixing unrelated concerns.
```bash
git ls-files | grep -iE '(utils|helpers|common|misc)\.(ts|tsx)$' | xargs wc -l 2>/dev/null | sort -n | tail
```

**Scattered config.** `process.env.X` / `import.meta.env.X` read all over the code instead of one validated config module; missing vars discovered at runtime.
```bash
grep -rnE 'process\.env\.|import\.meta\.env\.' $G <src> | cut -d: -f1 | sort | uniq -c | sort -rn | head
```

## 4. React (when present)

**Effects for derived state or event logic.** `useEffect` that sets state computed from props/other state (should be computed during render or `useMemo`), or that reacts to a state change a handler already knew about.
```bash
grep -rnA4 'useEffect(' $G <src> | grep -E 'set[A-Z]\w*\(' | head -20
```
Read each: effect whose body only calls `setX(f(y))` with `[y]` deps is derived state.

**Disabled exhaustive-deps.** Each `eslint-disable … react-hooks/exhaustive-deps` is a stale-closure bug candidate.
```bash
grep -rn 'exhaustive-deps' $G <src>
```

**Data fetching in effects by hand** (`useEffect` + `fetch` + `setLoading`), especially when a query library (TanStack Query, SWR, RTK Query) is already a dependency — no caching, no dedup, race conditions on fast param changes.
```bash
grep -rnA6 'useEffect(' $G <src> | grep -cE 'fetch\(|axios\.|api\.'
grep -nE '"(@tanstack/react-query|swr|@reduxjs/toolkit)"' package.json
```

**Business logic inside components.** Pricing, permission rules, data mapping written inline in JSX files instead of hooks or plain modules. Proxy: large `.tsx` files with high lizard CCN.
```bash
git ls-files '*.tsx' | xargs wc -l | sort -n | tail -10
```

**Index as key** on lists that reorder, insert or delete.
```bash
grep -rnE 'key=\{(i|idx|index)\}' $G <src>
```

**Duplicated or mirrored state.** The same server data copied into `useState`, a global store and context; props copied into state (`useState(props.x)`) that then drift.
```bash
grep -rnE 'useState\((props\.|\{?\s*\w+\s*\}?\s*\))' $G <src> | head
```

**Context as a global store** re-rendering the whole tree on every change (one big provider with a frequently-changing object value, no memoization, no split).
```bash
grep -rn 'createContext' $G <src>
grep -rnA1 'Provider value=\{\{' $G <src>
```

**Prop drilling** through 3+ levels of components that don't use the prop — read, don't grep.

## 5. Node / backend (when present: Express, Fastify, Hono, NestJS, Next route handlers)

**Business logic in route handlers.** Handlers that validate, query the DB, apply rules and format the response in one function. Proxy: lizard CCN on handler files.
```bash
grep -rnE '\.(get|post|put|patch|delete)\(\s*["'"'"'/]' $G <src> | cut -d: -f1 | sort | uniq -c | sort -rn | head
```

**Unvalidated `req.body` / `req.query` / `params`.** Destructured and used directly.
```bash
grep -rnE 'req\.(body|query|params)\b' $G <src> | wc -l
```
Read: is there validation middleware or a schema per route, or only in some routes?

**Blocking calls on the request path.** `fs.*Sync`, `crypto.*Sync`, heavy `JSON.parse` of large payloads, synchronous loops over big datasets in handlers.
```bash
grep -rnE '\b\w+Sync\(' $G <src> | grep -v -E 'config|scripts/|\.test\.'
```

**Error handling not centralized.** Every handler with its own `try/catch` + `res.status(500)` instead of an error middleware/filter; errors leaking stack traces to clients.
```bash
grep -rn 'res.status(500)' $G <src> | wc -l
grep -rnE 'err(or)?\.stack' $G <src>
```

**Singletons created at import time.** DB clients, SDK clients or config read at module top level, making modules untestable without mocking imports; prefer creating them in a composition root and passing them in.
```bash
grep -rnE '^(export\s+)?const \w+\s*=\s*new (PrismaClient|Pool|Redis|\w+Client)\(' $G <src>
```

**SQL built with template strings.**
```bash
grep -rnE '(query|execute|raw)\w*\(\s*`[^`]*\$\{' $G <src>
```

**Process-level failure handling.** No `unhandledRejection`/`uncaughtException` handling and no graceful shutdown (`SIGTERM` closing the server and DB pool) in a long-running service.
```bash
grep -rnE "unhandledRejection|uncaughtException|SIGTERM|SIGINT" $G <src>
```
Read: absence in a deployed HTTP service or worker is a finding; in a CLI or a serverless handler it usually isn't.

## 6. JavaScript without TypeScript (JS and mixed mode)

Without a compiler, the checks the type system would do fall on runtime validation, JSDoc and tests. Judge the project by those, not by the absence of TS.

**No types anywhere at the boundaries.** Neither `// @ts-check`, `checkJs`, JSDoc types, nor runtime schemas on inputs (HTTP bodies, env, queue messages, files).
```bash
grep -rln '@ts-check' $G <src> | wc -l
grep -rnE '@(param|returns?|typedef|type)\s*\{' $G <src> | wc -l
grep -n 'checkJs' jsconfig.json tsconfig*.json 2>/dev/null
grep -nE '"(zod|joi|yup|ajv|valibot|express-validator|celebrate|@sinclair/typebox)"' package.json
```
Read: the entry points. Validation at the edges matters far more in JS than JSDoc coverage inside.

**CommonJS and ESM mixed.** `require` and `import` in the same package, `"type"` in `package.json` contradicting the files, `.mjs`/`.cjs` sprinkled without reason, `__dirname` in ESM.
```bash
grep -rlE '\brequire\(' $G <src> | wc -l
grep -rlE '^\s*import .* from ' $G <src> | wc -l
grep -rn '__dirname\|__filename' $G <src> | head
```
Read: mixing inside one package is a consistency finding; a deliberate CJS shim for an old dependency isn't.

**Callback-era async** mixed with promises: `function (err, …)` callbacks, `fs.readFile(path, cb)`, callbacks wrapped in `new Promise` by hand where `node:fs/promises`/`util.promisify` exist, error-first callbacks that ignore `err`.
```bash
grep -rnE 'function\s*\(\s*err\b|\(\s*err\s*,\s*\w+\s*\)\s*=>' $G <src> | wc -l
grep -rnE 'new Promise\(\s*\(?\s*resolve' $G <src> | wc -l
grep -rnA1 -E '\(\s*err\b' $G <src> | grep -vE 'if\s*\(\s*err|throw|reject|next\(err' | head
```

**Pre-ES2015 and coercion traps.** `var`, loose equality, `arguments`, prototype mutation of built-ins.
```bash
grep -rnE '^\s*var\s' $G <src> | wc -l
grep -rnE '[^=!]==[^=]|!=[^=]' $G <src> | grep -vE '==\s*null|!=\s*null' | wc -l
grep -rnE '(Array|Object|String)\.prototype\.\w+\s*=' $G <src>
```
Interpretation: `== null` is an accepted idiom (null or undefined) and is excluded. Counts only matter if no linter enforces `eqeqeq`/`no-var`: then report the missing rule, not the hundreds of hits.

**Shape checks by hand, repeated.** `typeof x === 'object' && x !== null && 'id' in x` scattered across handlers — the missing schema layer.
```bash
grep -rnE "typeof \w+(\.\w+)* === '(string|number|object)'" $G <src> | cut -d: -f1 | sort | uniq -c | sort -rn | head
```

**Optional type-checking pass (informative).** Running the compiler over JS without any config change shows what a `checkJs` migration would surface. Report it as a signal, never as a count of bugs: the project didn't opt into these checks.
```bash
npx --yes -p typescript tsc --allowJs --checkJs --noEmit --skipLibCheck --target es2022 \
  --module nodenext --moduleResolution nodenext $(git ls-files '<src>/*.js' '<src>/*.mjs' '<src>/*.cjs' | head -300) 2>&1 \
  | grep -oE 'error TS[0-9]+' | sort | uniq -c | sort -rn | head
```
Needs `node_modules`. Passing files on the command line ignores any tsconfig, so nothing in the repo is read or written. Look at `TS2339` (property doesn't exist) and `TS2345` (wrong argument) — the ones that are usually real bugs.
