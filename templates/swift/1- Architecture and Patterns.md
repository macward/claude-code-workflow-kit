## Architecture & Patterns

### Layers

View → ViewModel (when needed) → Store / Service

Each piece exists only when it has a job. Don't add a layer to complete the chain:
a view that only reads a store talks to the store.

### Roles

Name types by the role they play, with full words, never abbreviations (`HomeView`,
`HomeViewModel`, `SessionStore`). Each suffix means one thing:

- **Store** — `@Observable` source of truth for a piece of state; usually lives as long as the app
  (`SessionStore`, `CartStore`). Views and ViewModels read it; it owns the mutations
- **Service** — does I/O (network, processes, files, git, Keychain) and holds little or no state
  (`GitService`, `PaymentsService`)
- **Repository** — ONLY persistence access (SwiftData, SQLite, a DB). If it doesn't read or write
  storage, it is not a Repository
- **Coordinator** — coordinates UI concerns across views (focus, sheets, closing the active tab);
  no business logic

### ViewModels

When to use one (apps): see 4 - Using ViewModels.

- ALWAYS use final class
- Do NOT import SwiftUI unless strictly necessary for navigation types
- NEVER put business logic directly in Views

### Dependency Injection

- ALWAYS use @Environment for sharing stores and services across views
- NEVER use singletons or shared instances. Exception: stateless, thread-safe caches such as
  formatters (`static let dateFormatter`); say so in a comment
- Inject dependencies at the App root level
- ViewModels receive dependencies via init injection

### Concurrency

- App targets use default `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
  the Xcode 26 app default). Don't write `@MainActor` in an app target: everything already is.
  Packages without default isolation mark UI-bound types `@MainActor` explicitly
- Types that do blocking I/O or heavy work are `nonisolated`. Repeat `nonisolated` on every
  member declared in an extension, including protocol conformances: the type's modifier doesn't
  reach them, and the mistake crashes at runtime (`dispatch_assert_queue`) with no compiler warning
- `@concurrent` for async functions that must leave the caller's actor
- ALWAYS async/await in your own APIs, NEVER completion handlers or `DispatchQueue.main.async`.
  System APIs built on callbacks or GCD (FSEvents, Network.framework, delegates) are wrapped
  once at the boundary with a continuation or an `AsyncStream`
- AsyncStream for continuous data (sockets, listeners, delegate conversions); it MUST clean up
  in `onTermination`
- `.task` for async work scoped to the view's visibility (loading what it shows). Work that must
  outlive the view is started from the composition root (apps: see 8 - App Composition)
- Long loops check `Task.isCancelled` or call `try Task.checkCancellation()`

### Error Handling

- The type the view calls (ViewModel or store) catches errors and exposes them as state
- Views react to error state; they don't catch
- Work that runs without a screen logs its errors and records them in its own state

### Patterns to Avoid

- `Task { @MainActor in }` when already on MainActor
- `.task` with nested `Task { }` inside
- `try!` in async code
