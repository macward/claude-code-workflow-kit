# Swift toolchain: commands and interpretation

Remember the constraint: `periphery`, `swiftlint analyze`, compiler warnings and coverage need macOS + Xcode + a build. `swiftlint lint` and `lizard` are portable.

## SwiftLint — lint (portable)
```bash
# Standard lint. Respects the project's .swiftlint.yml if present.
swiftlint lint --quiet --reporter json > /tmp/swiftlint.json
# Summary per rule:
swiftlint lint --quiet --reporter csv | cut -d, -f5 | sort | uniq -c | sort -rn
```
Size/complexity rules that matter for Axis A (built in; the project may have disabled them in its yml, check it):
`cyclomatic_complexity`, `function_body_length`, `type_body_length`, `file_length`, `large_tuple`, `function_parameter_count`.
Interpretation: separate style violations (cosmetic) from bug/safety ones (`force_cast`, `force_try`, `force_unwrapping`, `implicitly_unwrapped_optional`, `weak_delegate`, `unowned_variable_capture`). The latter go into the report with high severity.

## SwiftLint — analyze (needs a compiler log)
```bash
# 1) Generate the build log
xcodebuild -scheme <Scheme> -destination 'generic/platform=iOS' \
  clean build > /tmp/xcodebuild.log 2>&1
# 2) Analyze with that log
swiftlint analyze --compiler-log-path /tmp/xcodebuild.log --quiet
```
Enables rules that need type info: `unused_import`, `unused_declaration`. If you can't build, skip this step and mark it "not measured".

## lizard — cyclomatic complexity (portable, cross-check)
```bash
lizard --languages swift -s cyclomatic_complexity \
  $(find . -name "*.swift" -not -path "*/.build/*" -not -path "*/Pods/*")
# Worst offenders only:
lizard --languages swift -w  # warnings: functions over the default thresholds
```
CC interpretation: 1-5 simple, 6-10 ok, 11-20 review, 21+ refactor. lizard also gives NLOC and parameter count per function. Useful as a second opinion against SwiftLint (they sometimes compute differently).

## periphery — dead code (needs Xcode/build)
```bash
periphery scan --quiet \
  --project <App>.xcodeproj --schemes <Scheme> --targets <Target>
# For SPM:
periphery scan --quiet  # autodetects Package.swift
```
Interpretation: reports unused declarations (types, functions, properties). Watch for false positives from symbols used only from Objective-C, via `@objc`, reflection, or Storyboards/XIBs. Verify before reporting. It's the best `vulture` equivalent in Swift and fairly reliable when the build is clean.

## xcodebuild — compiler warnings
```bash
xcodebuild -scheme <Scheme> -destination 'generic/platform=iOS' build 2>&1 \
  | grep -c "warning:"
# Group by warning type:
xcodebuild ... build 2>&1 | grep "warning:" | sed 's/.*warning://' | sort | uniq -c | sort -rn | head
```
Interpretation: accumulated warnings = real debt (deprecations, casts, implicit captures). A project with hundreds of normalized warnings signals low Health: nobody reads them, so a new, real warning goes unnoticed.

## Coverage (from xcodebuild test)
```bash
xcodebuild test -scheme <Scheme> -destination 'platform=iOS Simulator,name=iPhone 15' \
  -enableCodeCoverage YES -resultBundlePath /tmp/Result.xcresult
xcrun xccov view --report --only-targets /tmp/Result.xcresult
```
Interpretation: as in any stack, the global number misleads. Look at which targets/files sit at 0%: if business logic is uncovered and trivial models are at 100%, coverage is cosmetic. No simulator available → "not measured".

## Memory safety and suppressions (grep, portable)
```bash
SRC=$(find . -name "*.swift" -not -path "*/.build/*" -not -path "*/Pods/*")
grep -on "[a-zA-Z0-9_)\]]!" $SRC | grep -v "!=" | wc -l   # force unwraps (approx.)
grep -rn "try!" $SRC | wc -l
grep -rn "as!" $SRC | wc -l
grep -rn "fatalError\|preconditionFailure" $SRC | wc -l
grep -rn "swiftlint:disable" $SRC                          # silenced rules
grep -rn "@unchecked Sendable" $SRC                        # concurrency safety escape hatch
```
Interpretation: force-unwrap/try!/as! aren't always bad (legitimate cases: outlets, known literals), but high density in business logic or over external data (network, parsing) is real fragility → crashes. Report concrete locations, not just the total.

## Dependencies
```bash
swift package show-dependencies --format tree 2>/dev/null   # SPM
cat Package.resolved 2>/dev/null | grep -c '"identity"'
cat Podfile.lock 2>/dev/null | grep -A99 "DEPENDENCIES:"
tuist graph 2>/dev/null                                     # Tuist: module graph
```
Interpretation: number of direct deps, outdated, abandoned. A large dependency for something the stdlib solves is debt.
