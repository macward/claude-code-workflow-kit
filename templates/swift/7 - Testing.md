## Testing Guidelines

### Framework

- Unit tests: Swift Testing (`@Test`)
- UI tests and performance tests (`measure(metrics:)`): XCTest, which Swift Testing doesn't cover

### Naming

- Function names: `subjectAction` or `subjectActionCondition`
- ALWAYS add a descriptive string to `@Test`: `@Test("User login fails when password is empty")`

### Test doubles

- Add a protocol only at a real I/O seam a test must replace (network, process, clock, filesystem)
- Otherwise test the concrete type, with an in-memory `ModelContainer` or a temp directory
- Doubles are written by hand; do NOT use mocking libraries
- An object kept alive only by a `[weak self]` observer dies right after `init` in a test;
  hold it with `withExtendedLifetime`

### Coverage

**For Apps:**

- ALWAYS test ViewModels
- ALWAYS test Stores and Repositories
- Services: test only if they contain logic
- Do NOT write unit tests for Views

**For Packages:**

- ALWAYS test public API thoroughly
- Test internal logic only if complex
- Do NOT test private implementation details

### UI Testing

- Framework: XCUITest (`XCTestCase`)
- Test user-facing flows end-to-end, not individual views
- Use `.accessibilityIdentifier(_:)` on key views to make them queryable
- Test functions use `test` prefix (XCTest requirement), descriptive names: `testConnectFlowShowsTerminal`
- UI tests launch the app and take over the mouse and keyboard: the routine gate skips them
- visionOS limitation: only 2D SwiftUI interactions — no spatial gestures (pinch, gaze, hand tracking)

## Build & Run Commands

- Apps: `xcodebuild -scheme <Scheme> -destination '<platform>' -skip-testing:<Scheme>UITests test`
  (routine gate); never `swift build`/`swift test`
- Packages: `swift build`, `swift test`
- `swiftlint` - Run linter
