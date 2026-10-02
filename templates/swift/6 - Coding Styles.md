## Code Style

### Formatting

- Use guard for early exit
- Type annotations only where the type isn't obvious from the right-hand side
- Use trailing closure only for single closure, not multiple
- Use self only when required (closures, ambiguity)
- Use optional shorthand: `if let value { }` not `if let value = value { }`
- Access control: explicit `public`/`internal` in packages; in apps write only `private`,
  `private(set)` and `fileprivate`

### File Organization

- Use `// MARK: -` to separate sections (Properties, Lifecycle, Public Methods, Private Methods)
- Protocol conformances may go in extensions; in a `nonisolated` type, mark the extension's
  members `nonisolated` too (see Concurrency in 1 - Architecture and Patterns)

### Tooling

- SwiftLint: safety rules (`force_cast`, `force_try`, `force_unwrapping`) and size/complexity
  rules on; cosmetic rules off. Freeze existing debt in a baseline; never raise thresholds to
  get to zero
