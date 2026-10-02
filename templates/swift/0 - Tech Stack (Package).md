## Tech Stack

Defaults for a Swift package. The project's CLAUDE.md lists its platforms and minimum OS.

- Swift 6.2 (`swift-tools-version` in `Package.swift`)
- Observation (`@Observable`) only if the package exposes observable state; SwiftUI only if it
  ships views
- No SwiftData and no navigation by default; a package that needs them says so in its CLAUDE.md
- Dependencies: the ones declared in `Package.swift`, nothing else
- Concurrency model: read it from each target's `swiftSettings` in `Package.swift`
  (`.defaultIsolation(MainActor.self)`, `.enableUpcomingFeature(...)`). Without `defaultIsolation`,
  code is nonisolated by default
- Manual dependency injection (initializers), no DI library
- Networking: `URLSession`; Logging: OSLog (when the package needs them)
- Not using: third-party DI, mocking libraries, analytics
