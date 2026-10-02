---
name: analyze-fastapi-codebase
description: "Audit health and architecture of a Python/FastAPI codebase with real tools (ruff, pyright, radon, vulture, deptry, bandit, pip-audit, coverage) plus idiomatic judgment. Use for 'analyze/audit the repo', 'tech debt', 'what to refactor', 'coupling'. Not for a single PR (code-review) or writing features."
---

# Python/FastAPI codebase audit

Audit a Python/FastAPI repository by combining **measurement** (real static tools) with **judgment** (targeted reading of idiomatic patterns). The output is a prioritized, actionable report, not a flat list of findings.

## Principles that override everything else

1. **Evidence or it doesn't exist.** Every finding carries `path/file.py:line` or a reproducible command with its output, and every `file:line` is checked against the real file before it goes in (step 5). Generic claims ("coupling is high") with no concrete file behind them stay out of the report.
2. **Don't hallucinate debt.** A healthy repo must be able to come out with few findings. Don't invent problems to fill sections. If an axis is fine, say so in one line and move on.
3. **Fact vs opinion, kept apart.** Measurable things (38% coverage, cyclomatic complexity 24 in `X`) are facts. Debatable things (this abstraction is unnecessary) are opinions and labeled as such.
4. **Don't contaminate the audited environment.** Analysis tools are installed in isolation (`uvx` or a temporary venv), never in the project's venv. See "Isolated toolchain setup".
5. **Always prioritize.** The report ends in "what to fix first", ordered by impact × effort, not in 60 unranked findings.
6. **Read-only.** No `--fix`, no refactoring. This is an audit, not an intervention.

## Flow

1. Locate the project and understand its shape (layout, dependency manager, where the code lives).
2. Set up the isolated toolchain.
3. Run the tools per axis, capturing raw output.
4. Targeted reading of what tools can't see (idiomatic FastAPI, pattern decisions).
5. Verify every anchor in the draft findings against the real files.
6. Synthesize into the fixed report format below.

Don't skip step 4: ruff and radon catch complexity and style, but they won't tell you that business logic lives in an endpoint or that the DB session is mismanaged. That's reading.

## 1. Project recon

Before running anything, understand what you're auditing:

```bash
# Layout and size
find . -name "*.py" -not -path "*/.venv/*" -not -path "*/node_modules/*" | head -50
# Dependency manager
ls pyproject.toml poetry.lock uv.lock requirements*.txt Pipfile setup.py 2>/dev/null
# FastAPI entry point
grep -rn "FastAPI(" --include="*.py" -l | head
# Package structure (src layout vs flat)
ls src/ 2>/dev/null && echo "src layout" || echo "flat layout"
```

Identify the root package (the one tests import). You'll need it for `radon`, `import-linter` and coverage. If there's a `pyproject.toml`, read it: it gives the package name, declared deps and any tool config already present (respect the existing ruff/mypy config; don't override it).

## 2. Isolated toolchain setup

**Never** install these into the project's venv. Two options depending on what's available:

```bash
# Preferred: uvx runs each tool ephemerally, nothing installed persistently
which uvx && echo "use uvx <tool>"

# Fallback: a dedicated venv just for analysis
python3 -m venv /tmp/audit-venv
/tmp/audit-venv/bin/pip install -q ruff mypy radon vulture deptry import-linter bandit pip-audit
AUDIT=/tmp/audit-venv/bin
```

Tools that must import the project's code (mypy with deep type following, coverage, import-linter) do need the project's deps installed. For those, run inside the project's venv if it exists and is healthy; otherwise report that sub-analysis as incomplete instead of improvising an environment. Don't install the project's deps yourself unless the user asks.

If a tool fails for lack of network or environment, record it and degrade: the report says what was measured and what wasn't, never filling the gap with assumptions.

## 3. Measurement per axis

Run these and keep the raw output. Exact commands, flags and how to read each number are in `references/tooling.md`. **Read it** before running: several flags change with the layout and the thresholds aren't obvious.

### Axis A — Health (most quantitative)
- `ruff check` → style, latent bugs, broken imports, bugbear rules.
- `radon cc -s` and `radon mi` → cyclomatic complexity and maintainability per function/module. Flag outliers (CC > 10 review, > 20 severe).
- `radon raw` → LOC, comment ratio, logical lines. Spot giant files/functions.
- `mypy`/`pyright` → real type coverage, accumulated `# type: ignore`, explicit `Any`.
- `coverage`/`pytest --cov` → real coverage. Cross it with what is tested: 80% coverage over getters isn't worth the same as 50% over business logic.
- `pip-audit` → CVEs in dependencies.
- `bandit` → insecure patterns (hardcoded secrets, `eval`, raw SQL, `subprocess` with shell).
- `grep` for markers: `TODO|FIXME|HACK|XXX` with `git blame` for age.

### Axis B — Modularity / coupling (structure)
- `import-linter` or `grimp` → import graph, **cycle detection** (the most important thing here), and checking that layers respect their direction.
- `deptry` → declared but unused deps, used but undeclared, transitive treated as direct.
- Manual reasoning over the graph: is there a module everything depends on (god module)? Does domain logic import from the infra layer (DB, HTTP) or the other way around? The correct direction is infra → domain, not domain → infra.

### Axis C — Consistency (internal uniformity)
Not "does it follow best practices?" but "does it do the same thing the same way?". Reading + grep; tools don't see it:
- Error handling: one strategy, or `raise HTTPException`, error returns and custom exceptions coexisting without a rule?
- Response shape: consistent `response_model`, or raw dicts mixed with models?
- Async: `def` and `async def` endpoints mixed for no reason? Blocking calls inside async?
- Naming of endpoints, modules, files: a uniform convention?
- Dependency injection: `Depends` everywhere, or manual instantiation here and there?

### Axis D — Idiomatic FastAPI/Python
100% targeted reading. The full antipattern checklist, with what to grep and what to read, is in `references/fastapi-idioms.md`. **Read it.** It covers: business logic in endpoints, DB session management, `Depends` usage, Pydantic at the boundary, async/event loop, settings/config, and SQLAlchemy antipatterns.

### Axis E — Patterns (descriptive before evaluative)
First inventory which patterns exist (repository, factory, service layer, DI container, etc.), then judge whether they're justified:
- **Over-engineering**: single-implementation abstractions, interfaces with no foreseeable second implementer, layers that only forward data, architecture for a scale the project doesn't have.
- **Under-engineering**: logic duplicated across N endpoints that asks for a service layer, repeated queries that ask for a repository.
- A misapplied pattern (cargo cult) is worse than its absence: label it as such.

## 4. Targeted reading
Covered by Axes C–E above: read the code the greps point to before writing any finding from them.

## 5. Verify every anchor (MANDATORY, before writing the report)

Wrong line numbers are the failure an audit doesn't notice: a number copied from a multi-file dump, a delegated summary or memory looks exactly as credible as a real one, and a single impossible anchor discredits the whole report. For every `file:line` or range in the draft:

```bash
wc -l <file>                  # a line past EOF is a fabricated anchor
sed -n '<line>p' <file>       # or '<start>,<end>p' for a range
```

- The printed line must show what the finding claims (the symbol, call or construct); a range must contain it.
- If it doesn't, re-anchor with `grep -n '<symbol>' <file>` on the real file and fix the number. If the construct can't be found, drop the finding.
- Take line numbers only from the individual file (reading it, `grep -n`, tool output that names the path). Never from `cat a b c`, a concatenated dump or a subagent's summary; re-anchor those.
- Tool-reported locations (ruff, radon, bandit, vulture) are trustworthy only when the tool ran on the audited working tree; spot-check one.
- State the result in Raw measurements: `Anchors verified: N/N (M re-anchored, K dropped)`.

## 6. Synthesis: MANDATORY output format

Use exactly this structure. No rhetorical padding or long executive summaries. Write the report in the user's language.

```markdown
# Audit — <repo name>
<commit / date> · <N files · N LOC>

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
| 1 | Health | High | app/api/users.py:142 | CC=27 in create_user, mixes validation+DB+email | Fact |
...
Sev: High / Medium / Low. Type: Fact / Opinion.

## Raw measurements
Summarized output per tool + what could not be measured and why + anchors verified.

## What's fine
Brief. What NOT to touch and why it's already healthy. (Keeps the repo from looking worse than it is.)
```

### Scoring rules
0 = broken/absent · 3 = works with real debt · 5 = solid, no action needed. The score is an opinion calibrated by the data, not an automatic formula: justify it with the findings, not with an invented formula.

## Close
End by offering to go deeper on the worst-scored axis or to turn "What to fix first" into tasks. Don't start refactoring unless the user asks: this is an audit, not an intervention.
