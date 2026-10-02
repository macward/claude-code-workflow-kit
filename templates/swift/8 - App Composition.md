## App Composition

Composition root and cross-store reactions apply to every app.
SwiftData applies to any app that uses it. Work that outlives the window applies to apps
with background processes, servers, watchers, timers or loops.

### Composition root

- Build the object graph inline in the `App` struct; past ~30 lines move it to `App/Bootstrap/`,
  in explicit stages (persistence → stores → services that depend on them)
- Every root/host view lists in its docstring the `@Environment` values it requires: a missing
  injection compiles, then crashes at runtime or breaks Previews

### Reacting across stores

- Capabilities don't subscribe to each other. Cross-store reactions ("when X changes in store A,
  do Y in store B") are wired in `App/`, in one place
- A reaction that must not miss a change: call it synchronously from the mutating method, or give
  the store an observer list once it has 2+ subscribers. Don't re-arm `withObservationTracking`
  inside a `Task`: it arms asynchronously and misses single mutations
- Handlers must be idempotent: a store may re-apply the same value

### Work that outlives the window

- Nothing that must keep running hangs off the view tree (`.onAppear`, `.task`, `.onChange`,
  a ViewModifier). When no view is on screen, the view tree doesn't run. The service is started
  from the composition root
- `.onDisappear` is not a "user is done" signal: it fires on re-layouts and tab switches.
  Tear down only on explicit actions and on app termination
- Every loop, timer, watcher, listener and child process has one owner type and a documented
  start and stop. Pause periodic work nobody is looking at
- macOS: the app can outlive its last window. On quit, shut down concurrently under a time
  ceiling (`applicationShouldTerminate` → `.terminateLater`) so a hung child can't block the exit

### SwiftData

- Freeze each shipped schema version as nested snapshot types inside its `VersionedSchema`
  enum before changing a live `@Model`. Pointing several versions at the live class makes the
  store fail to open once the class grows a property
- Add the new version + a `MigrationStage`, and move the container and in-memory test
  containers to it
- If a dev build and a release build can run side by side on the same machine, give each its own
  store folder (by bundle id and schema version), seeded by copying the previous one
