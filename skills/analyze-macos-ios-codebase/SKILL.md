---
name: analyze-macos-ios-codebase
description: "Audit health and architecture of a Swift (iOS/macOS) codebase with real tools (SwiftLint, periphery, lizard, xccov) plus idiomatic judgment. Use for 'analyze/audit the project', 'tech debt', 'what to refactor', 'retain cycles' on a Swift app or package. Requires Xcode. Not for a single PR (code-review) or writing features."
---

# Swift codebase audit (iOS/macOS)

Audit a Swift project by combining **measurement** (real tools) with **judgment** (targeted reading of idiomatic Swift/SwiftUI and concurrency patterns). The output is a prioritized, actionable report.

## Environment constraint — read first
The full analysis **requires macOS with Xcode installed**. `SwiftLint` and `lizard` run anywhere, but `periphery`, `swiftlint analyze` (type-aware rules), compiler warning counts and coverage need a build with Apple's SDK, which only exists on a Mac. If you're running without Xcode (Linux CI, sandbox), run only the portable part and report explicitly what went unmeasured; don't invent the missing results.

## Principles that override everything else

1. **Evidence or it doesn't exist.** Every finding carries `Path/File.swift:line` or a reproducible command with its output, and every `file:line` is checked against the real file before it goes in (step 5). No "coupling is high" without a concrete file.
2. **Don't hallucinate debt.** A healthy repo comes out with few findings. Don't fill sections for the sake of it. If an axis is fine, one line and move on.
3. **Fact vs opinion, kept apart.** Measurable (CC=22 in `X`, 47 force-unwraps) is fact. Debatable (this protocol is unnecessary) is labeled opinion.
4. **Don't contaminate the project.** Tools via `mint`/`brew`/standalone binaries, never as target dependencies. The existing SwiftLint config is respected, not overridden.
5. **Always prioritize.** The report ends in "what to fix first" by impact × effort.
6. **Read-only.** No `--fix`/`--autocorrect`, no refactoring. This is an audit, not an intervention.

## Flow
1. Recon the project: build system, modules, where the code lives.
2. Set up the toolchain.
3. Measure per axis capturing raw output.
4. Targeted reading of what tools can't see (idioms, memory safety, concurrency, SwiftUI/UIKit architecture).
5. Verify every anchor in the draft findings against the real files.
6. Synthesize with the fixed format below.

Step 4 adds the most value in Swift: tools catch complexity and dead code, but they won't tell you there's a retain cycle, heavy logic in a SwiftUI `body` or a misplaced `@MainActor`. That's reading.

## 1. Project recon
```bash
# Build system (changes the WHOLE modularity analysis)
ls Package.swift 2>/dev/null && echo "SPM"
ls *.xcodeproj *.xcworkspace 2>/dev/null
ls Project.swift Tuist/ 2>/dev/null && echo "Tuist"
# Shape and size
find . -name "*.swift" -not -path "*/.build/*" -not -path "*/Pods/*" -not -path "*/DerivedData/*" | wc -l
# UIKit vs SwiftUI vs mixed
grep -rln "import SwiftUI" --include="*.swift" . | wc -l
grep -rln "import UIKit\|UIViewController" --include="*.swift" . | wc -l
# Concurrency: async/await vs Combine vs GCD
grep -rln "async\|await" --include="*.swift" . | wc -l
grep -rln "import Combine" --include="*.swift" . | wc -l
grep -rln "DispatchQueue" --include="*.swift" . | wc -l
```
Identify: build system (SPM / Xcodeproj / Tuist), app or package, UI and concurrency paradigm. What can be measured for modularity (see Axis B) and which antipatterns to prioritize depend on this.

## 2. Toolchain setup
```bash
# SwiftLint (portable). Prefer mint or brew; don't add it as a project dep.
which swiftlint || brew install swiftlint
# periphery (dead code, NEEDS Xcode/build)
which periphery || brew install peripheryapp/periphery/periphery
# lizard (multi-language cyclomatic complexity, supports Swift, portable)
which lizard || pipx install lizard
# Apple's swift-format (optional, formatting)
which swift-format
```
If the project already pins a SwiftLint version (`.swiftlint.yml`, Mintfile, SPM plugin), use it so the numbers match its CI.

## 3. Measurement per axis
Exact commands, flags and how to read each number are in `references/tooling-swift.md`. **Read it** before running; in Swift several commands need prior steps (a build, generating compiler logs) that aren't obvious.

### Axis A — Health
- `swiftlint lint` → style, latent bugs, and size/complexity rules (`cyclomatic_complexity`, `function_body_length`, `type_body_length`, `file_length`).
- `swiftlint analyze` → rules that need type info (`unused_import`, `unused_declaration`). Requires a compiler log.
- `lizard` → cyclomatic complexity and NLOC per function, independent of SwiftLint (good cross-check). Flag CC > 10 review, > 20 severe.
- **Memory safety (Swift-specific; replaces the "type checking" step of other languages, since Swift is already strongly typed):** count `!` force-unwraps, `try!`, `as!`, `fatalError`, `// swiftlint:disable`. They're Swift's `# type: ignore`.
- `xcodebuild` → compiler warning count (accumulated warnings are real debt).
- `xccov`/coverage from the `xcodebuild test` result.
- `TODO|FIXME|HACK` markers with `git blame` for age.

### Axis B — Modularity / coupling
The build system rules here:
- **Multi-module SPM or Tuist:** there's a real graph. `swift package show-dependencies`, or Tuist's graph (`tuist graph`). Look for cycles between modules and dependency direction (UI → domain → infra, never the reverse).
- **Monolithic Xcode target (a single module):** there's no module graph to measure; modularity is judged by folder/group organization and coupling between types. It's the weakest case to measure; be honest about that and lean on reading.
- External dependencies: check `Package.resolved` / `Podfile.lock` for count, outdated, abandoned, and whether a heavy dep is used for something trivial.
- God objects: `lizard`/SwiftLint flag huge types; an `AppManager`/`DataManager` everything depends on is the classic sign.

### Axis C — Consistency (internal uniformity)
Reading + grep; tools don't see it:
- Error handling: one strategy (`throws`/`Result`/`async throws`) or all three mixed without a rule?
- Concurrency: async/await, Combine and GCD coexisting in the same layer for no reason? (strong sign of a half-done migration).
- Dependency injection: one approach (init injection / container) or singletons scattered with manual instantiation?
- Naming: does it follow the Swift API Design Guidelines uniformly?
- SwiftUI: coherent state management (`@State`/`@StateObject`/`@Observable`) or does each view solve it differently?

### Axis D — Idiomatic Swift / SwiftUI / Concurrency
100% targeted reading. Full checklist, with what to grep and what to read, in `references/swift-idioms.md`. **Read it.** It covers: force unwraps and safety, retain cycles and `self` capture, value vs reference types, SwiftUI antipatterns (logic in `body`, `@StateObject` vs `@ObservedObject`, recomputation), concurrency (`@MainActor`, `Sendable`, uncancelled `Task`, GCD vs async), Massive View/Controller, and mutable singletons.

### Axis E — Patterns (descriptive before evaluative)
Inventory what exists (MVVM, MVC, Coordinator, TCA, Repository, etc.), then judge:
- **Over-engineering:** protocols with a single conformer "just in case", coordinators for 3 screens, an architecture (TCA/VIPER) whose cost the app's size doesn't justify, layers that only forward.
- **Under-engineering:** Massive View Controller / Massive SwiftUI View, networking logic duplicated in every view, a missing model layer.
- Cargo-culting (MVVM where the ViewModel is an empty pass-through) is worse than absence: label it.

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
- Tool-reported locations (SwiftLint, lizard, periphery, compiler warnings) are trustworthy only when the tool ran on the audited working tree; spot-check one.
- State the result in Raw measurements: `Anchors verified: N/N (M re-anchored, K dropped)`.

## 6. Synthesis: MANDATORY output format
Write the report in the user's language.
```markdown
# Audit — <project name>
<commit / date> · <N files · N LOC> · <SPM/Xcodeproj/Tuist · SwiftUI/UIKit/mixed>

## Summary by axis
| Axis | Score | One-line status |
|------|-------|-----------------|
| Health | 0-5 | ... |
| Modularity | 0-5 | ... |
| Consistency | 0-5 | ... |
| Idiomatic | 0-5 | ... |
| Patterns | 0-5 | ... |

## What to fix first
Ordered by impact × 1/effort. Max 7 items:
- **[title]** — what, where (File.swift:line), why it matters, effort (S/M/L).

## Findings
| # | Axis | Sev | Location | Finding | Type |
|---|------|-----|----------|---------|------|
| 1 | Idiomatic | High | Sources/Feed/FeedView.swift:88 | closure captures self strongly → retain cycle | Fact |
Sev: High/Medium/Low. Type: Fact/Opinion.

## Raw measurements
Summarized output per tool + what was NOT measured and why (e.g. "periphery skipped: no Xcode in this environment") + anchors verified.

## What's fine
Brief. What NOT to touch.
```

### Scoring
0 = broken/absent · 3 = works with real debt · 5 = solid. The score is an opinion calibrated by data, justified with findings, not a formula.

## Close
Offer to go deeper on the worst-scored axis or to turn "What to fix first" into tasks. This is an audit, not an intervention: don't refactor unless the user asks.
