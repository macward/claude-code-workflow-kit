## Tech Stack

Defaults for an app. The project's CLAUDE.md lists its platforms, minimum OS and the packages it adds.

- Swift 6.2, SwiftUI, Observation (`@Observable`)
- Manual dependency injection (initializers + `@Environment`), no DI library
- Networking: `URLSession`
- Persistence: SwiftData (versioning rules in 8 - App Composition); Keychain for tokens and secrets
- Navigation: `NavigationStack` with a path
- Logging: OSLog
- Not using: third-party DI, mocking libraries, analytics
