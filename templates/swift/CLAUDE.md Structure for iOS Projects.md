### 1. Project Overview

Short description of the project: what it does, architecture (MVVM, etc.), and main technologies (SwiftUI, SwiftData, Observation framework).

### 2. Tech Stack

Concrete list of frameworks and versions:

- Minimum supported iOS
- `Swift version`
- Main dependencies (SPM packages)

### 3. **Architecture & Patterns**

Architecture conventions:

- Folder structure: only what departs from `2 - Project Structure`, and the project's `Core/` capability map
- MVVM or whichever pattern you use
- Naming conventions
- Which stores, services and coordinators exist, and who owns what

### 4. **Code Style**

Specific style rules:

- Formatting preferences
- Optional handling
- Async/await conventions

### 5. **Build & Run Commands**

Frequent bash commands:

- Build the project
- Run tests
- Linting (SwiftLint if you use it)
- Custom scripts

### 6. **Testing Guidelines**

How to write and run tests:

- Naming conventions
- What to mock and what not to
- Commands for unit tests vs UI tests

### 7. **Common Patterns & Examples**

References to files that serve as examples:

- "To create a new View, look at `ExampleView.swift`"
- "For network services, follow the pattern in `APIClient.swift`"

### 8. **Known Issues & Gotchas**

Odd things about the project that Claude should know:

- Specific workarounds
- Expected warnings
- Xcode behaviors

### 9. **Git & Workflow**

Git conventions:

- Branch naming
- Commit format
- PR conventions

### 10. **Do's and Don'ts**

Explicit rules with emphasis:

- "ALWAYS use async/await, never completion handlers"
- "NEVER force unwrap optionals"

---