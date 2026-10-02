# Idiomatic Swift / SwiftUI / Concurrency antipatterns

Targeted reading: tools don't see this (or see it only partially). Each block has a starting grep; confirm by reading.

## 1. Safety: force unwrap / try / cast
```bash
SRC=$(find . -name "*.swift" -not -path "*/.build/*" -not -path "*/Pods/*")
grep -rn "try!\|as!" $SRC
grep -rn "= .*!\s*$" $SRC   # force unwrap at end of line
```
Bad sign: force-unwrap over network data, JSON, or user input → crash in production. `as!` that could be `as?` with handling. Legitimate: `@IBOutlet`, known bundle resources. Decide by context: the same `!` is a high-severity Fact over external data and acceptable over an internal literal.

## 2. Retain cycles / capturing self
```bash
grep -rn "self\." $SRC | grep -i "closure\|completion\|Task {\|sink\|handler"  # rough guide
grep -rn "{ \[weak self\]\|{ \[unowned self\]" $SRC   # the ones that DO break the cycle
grep -rn "delegate:" $SRC | grep -v "weak"            # non-weak delegates
```
Bad sign: an escaping closure that captures `self` strongly and is stored (retained completion handlers, `Combine.sink` without `[weak self]`, `Timer`, `NotificationCenter`). Delegate declared without `weak` → classic cycle. `[unowned self]` where the object can die before the closure → crash. Read every `escaping` closure that stores state.

## 3. Value vs reference types
Bad sign: `class` for something that's clearly a value (immutable data model, DTO) with no need for identity or inheritance → should be a `struct`. Conversely: a huge `struct` copied everywhere in a hot path. Bad sign: mutable state shared through a `class` where a `struct` + value semantics would avoid aliasing bugs.

## 4. SwiftUI — logic in body
```bash
grep -rn "var body:" $SRC   # inspect the long bodies
```
Bad sign: heavy computation, formatting, network calls or business logic inside `body` → re-runs on every render. It belongs in the ViewModel or in cached computed properties. A 150-line `body` = a view that needs decomposing.

## 5. SwiftUI — state management
```bash
grep -rn "@ObservedObject\|@StateObject\|@State\|@EnvironmentObject\|@Observable\|@Bindable" $SRC
```
Bad sign (the most common): `@ObservedObject` where the view owns the object; it should be `@StateObject`, because `@ObservedObject` doesn't preserve the object across renders and recreates it. Bad sign: `@State` with reference types, or state that should be lifted to a parent and is trapped in a leaf. Mixing `ObservableObject` (Combine) and the `@Observable` macro (iOS 17+) without a rule = half-done migration.

## 6. Concurrency
```bash
grep -rn "DispatchQueue\|@MainActor\|Task {\|Task.detached\|nonisolated\|actor " $SRC
grep -rn "DispatchQueue.main.async" $SRC | wc -l
```
Bad sign: updating UI off the main actor (or wrapping everything in manual `DispatchQueue.main.async` instead of `@MainActor`). `Task {}` launched without keeping a reference or handling cancellation, in an `onAppear` that fires multiple times. `Task.detached` used by default when it's almost never what you want. GCD + async/await + Combine mixed in the same layer = inconsistency (Axis C as well as D). `@unchecked Sendable` as a patch to silence the compiler instead of fixing the data race.

## 7. Massive View / View Controller
Bad sign (UIKit): an 800-line View Controller doing networking, parsing, navigation and UI logic. Bad sign (SwiftUI): a View that is also its own ViewModel, networking and router. `lizard`/SwiftLint give you the giant types (`type_body_length`); here you confirm the problem is mixed responsibilities, not just size.

## 8. Mutable global singletons
```bash
grep -rn "static let shared\|static var shared" $SRC
```
Bad sign: a singleton with mutable state accessed from everywhere → testing impossible, hidden coupling, races. An immutable `shared` or a stateless service is acceptable; one with a mutable `var` holding session/user state is debt. Cross with Axis B: it's usually the god object everything depends on.

## 9. Error handling
```bash
grep -rn "try?" $SRC | wc -l          # silently swallowed errors
grep -rn "catch {" $SRC | grep -v "catch let\|catch is"   # empty generic catch
```
Bad sign: `try?` discarding the error without logging or handling → invisible failures. Empty `catch {}`. Healthy: typed domain errors (`enum: Error`) propagated with `throws`/`Result`, translated to UI in one place. Mixing `throws`, `Result` and completion-with-Error without a rule = Axis C.

## 10. Optionals and API design
Bad sign: deep optional chains (`a?.b?.c?.d`) hiding a poorly defined model; using `Optional` for states that deserve an `enum`. Naming that ignores the Swift API Design Guidelines (methods that don't read as phrases, booleans without an `is/has` prefix, parameters without clear labels).

---
When reporting: latent bug (Fact: retain cycle, force-unwrap over network data, UI off the main actor, `try?` swallowing an error) vs questionable design decision (Opinion: `class` where a `struct` fits, missing ViewModel layer, mutable singleton). The former gets in by crash/bug risk; the latter is argued and left to the user's judgment.
