# Swift rules — index

The Swift rules live in the numbered files next to this one. This file only
points at them, so nothing here drifts out of sync with the source.
`.claude/templates/BOOTSTRAP.md` decides which ones a project gets.

| File | Applies to |
|---|---|
| `0 - Tech Stack (App).md` | apps — defaults; the project lists its own platforms and packages |
| `0 - Tech Stack (Package).md` | packages — defaults; dependencies and concurrency settings come from `Package.swift` |
| `1- Architecture and Patterns.md` | always — layers, roles (Store / Service / Repository / Coordinator), concurrency |
| `2 - Project Structure (iOS-Visionos-macOS).md` | apps — `App/`, `Features/`, `Core/<Capability>/`, `Domain/`, `Platform/`, `DesignSystem/` |
| `3 - Swift Library Package Structure.md` | packages |
| `4 - Using ViewModels.md` | apps — when a view needs a ViewModel |
| `5 - Atomic Design.md` | apps — `DesignSystem/` levels |
| `6 - Coding Styles.md` | always |
| `7 - Testing.md` | always — plus build commands; UI testing only with a UI test target |
| `8 - App Composition.md` | apps — composition root, `@Environment` contracts, background work, SwiftData versions |

Project-specific sections of a CLAUDE.md (build commands, git workflow, known issues):
see `CLAUDE.md Structure for iOS Projects.md`.
