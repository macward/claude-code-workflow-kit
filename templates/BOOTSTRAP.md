# Project Bootstrap

Procedure for composing a local CLAUDE.md in a project that doesn't have one. A CLAUDE.md can point here.

When starting work on a project without a local CLAUDE.md, detect the stack and compose one automatically.

### Detection

| Indicator | Stack |
|---|---|
| .xcodeproj/.xcworkspace (with or without Package.swift) | Swift App |
| Package.swift without .xcodeproj/.xcworkspace | Swift Package |
| pyproject.toml / requirements.txt | Python |

### Swift Rules

Location: .claude/templates/swift/ (repo: `templates/swift/`)

They live in `templates/` and not in `rules/` **on purpose**: everything under `.claude/rules/` is loaded into the context of every turn of every project, and these rules only apply to Swift projects. Read them with `Read` when the detection above gives Swift; don't move them back to `rules/`.

**Always include:**
- 0 - Tech Stack.md
- 1- Architecture and Patterns.md
- 6 - Coding Styles.md
- 7 - Testing.md

**Swift App only** (has .xcodeproj or .xcworkspace):
- 2 - Project Structure (iOS-Visionos-macOS).md
- 4 - Using ViewModels.md
- 5 - Atomic Design.md
- 8 - App Composition.md

In addition, the CLAUDE.md composed for a Swift App includes this section, verbatim:

```markdown
## Reference: lessons from DeadCode

Before laying out the project structure, read in Meridian `deadcode-app/architecture/referencia-07-por-donde-empezar.md`: a starter checklist drawn from DeadCode's mistakes, with the series index in `referencia-00-indice.md`. Each rule says whether it is **proven** or **proposed**; if a proven rule clashes with these templates, tell the user before choosing.
```

**Swift Package only** (Package.swift without .xcodeproj):
- 3 - Swift Library Package Structure.md

### Python Rules

Location: .claude/rules/python/ (repo: `rules/python/`)

It stays in `rules/` because it is a minimal file and the default stack here is Python. If it grows, move it to `templates/python/` for the same reason as Swift.

### Process

1. Detect stack from project root
2. Read all applicable rule files from the template location
3. Compose a local CLAUDE.md concatenating them in order
4. Swift: add the project-specific sections from `CLAUDE.md Structure for iOS Projects.md` (build commands, known issues, git workflow), filled from what the project actually has; leave out any section with nothing to say
5. State which templates were applied before continuing work

**Projects that already have a CLAUDE.md** don't go through here again: a change in the templates doesn't reach them on its own. To update them, re-read the templates and compare against the project's CLAUDE.md when the user asks.

**Rule when adding a new rule set:** if it applies to *every* project, it goes in `rules/` and is paid for on every turn. If it applies to one stack, it goes in `templates/<stack>/` and is read when needed. `rules/` is a context budget, not a junk drawer.
