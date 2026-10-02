# Toolchain: commands and interpretation

Assumes `$AUDIT` points to the analysis venv (`/tmp/audit-venv/bin`) or that you use `uvx <tool>`. Set `<pkg>` to the project's root package and `<src>` to the code folder (`src/<pkg>` or `<pkg>`).

## ruff — style, latent bugs, complexity
```bash
# Full check with useful rules beyond the default
$AUDIT/ruff check <src> \
  --select E,F,W,B,C90,SIM,RUF,UP,ASYNC,S \
  --output-format concise
# McCabe complexity only (C901), with an explicit threshold
$AUDIT/ruff check <src> --select C901 --config "lint.mccabe.max-complexity=10"
```
Interpretation: `F` (real errors: broken imports, unused vars) weighs more than `E/W` (style). `B` (bugbear) and `ASYNC` are the ones that surface the most latent bugs in FastAPI. `S` (bandit via ruff) gives a first security pass. If the repo already has a ruff config, respect it and only add rules; don't replace it.

## radon — complexity and maintainability
```bash
$AUDIT/radon cc <src> -s -n C        # cyclomatic complexity, rank C or worse only
$AUDIT/radon mi <src> -s             # maintainability index per file
$AUDIT/radon raw <src> -s            # LOC, LLOC, comments
```
CC interpretation: 1-5 simple, 6-10 ok, 11-20 review, 21-30 refactor, >30 severe. MI: <20 hard to maintain. In `raw`, look for files with disproportionate LLOC and long functions (cross with `cc`).

## xenon — complexity gate (optional, for CI)
```bash
$AUDIT/xenon <src> --max-absolute B --max-modules A --max-average A
```
Useful if you want to propose a CI threshold. Fails when anything exceeds the grade.

## mypy / pyright — types
```bash
# Needs the project's deps. Run in the PROJECT's venv:
<proj-venv>/bin/mypy <src> --ignore-missing-imports --no-error-summary | tail -40
grep -rn "# type: ignore" <src> | wc -l
grep -rn ": Any\|-> Any" <src> | wc -l
```
Interpretation: count errors and `type: ignore`. Lots of `Any` in public signatures = decorative typing. If deps aren't installed, report "not measured".

## vulture — dead code
```bash
$AUDIT/vulture <src> --min-confidence 80
```
Interpretation: confidence <80 yields many false positives (FastAPI relies heavily on callbacks/decorators vulture can't see). Verify each finding before reporting it; endpoints and dependencies are often flagged as "unused" while the framework uses them.

## deptry — dependency hygiene
```bash
cd <proj-root> && $AUDIT/deptry .
```
Interpretation: DEP001 (missing: imported but not declared) is the most severe. DEP002 (declared but unused) = bloat. DEP003 (transitive used as direct) = fragile.

## import-linter — layers and cycles
```bash
# Needs a contract. If none exists, write a minimal one to detect cycles:
cat > /tmp/importlinter.ini <<EOF
[importlinter]
root_package = <pkg>
[importlinter:contract:no-cycles]
name = No cycles
type = independence
modules =
    <pkg>.api
    <pkg>.services
    <pkg>.repositories
    <pkg>.models
EOF
cd <proj-root> && $AUDIT/lint-imports --config /tmp/importlinter.ini
```
Alternative with grimp to explore the graph without a prior contract:
```bash
$AUDIT/python -c "import grimp; g=grimp.build_graph('<pkg>'); print(len(g.find_illegal_dependencies_for_layers))" 2>/dev/null
```
Interpretation: a cycle between modules is the strongest modularity finding; it means you can't touch one without the other. Healthy layer direction: api → services → repositories → models, never the reverse.

## pip-audit — vulnerabilities
```bash
cd <proj-root> && $AUDIT/pip-audit -r requirements.txt 2>/dev/null \
  || $AUDIT/pip-audit  # if it uses the active environment
```
Interpretation: report the CVE + the fixed version that resolves it. Not opinion, fact.

## bandit — static security
```bash
$AUDIT/bandit -r <src> -ll -ii   # medium+ severity and confidence only
```
Interpretation: focus on B105/B106 (secrets), B608 (SQL injection via string), B602 (shell=True), B301/B403 (pickle). In FastAPI, cross with where user data enters.

## coverage — real coverage
```bash
cd <proj-root> && <proj-venv>/bin/python -m pytest --cov=<pkg> --cov-report=term-missing -q 2>&1 | tail -30
```
Interpretation: the global number misleads. Look at `--cov-report=term-missing` to see WHICH lines aren't covered: if the uncovered part is business logic and the covered part is schemas, the "good" coverage is fake. If there are no tests or they don't run, report "not measured"; don't assume 0 or make it up.

## Markers and age
```bash
grep -rn "TODO\|FIXME\|HACK\|XXX" <src> | wc -l
# Age of the oldest (sign of fossilized debt):
grep -rln "FIXME" <src> | head -5 | xargs -I{} git log -1 --format="%ar {}" -S "FIXME" {} 2>/dev/null
```

## Counts and overall shape
```bash
which tokei && tokei <src> || $AUDIT/radon raw <src> -s | tail -10
```
