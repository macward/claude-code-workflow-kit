## Swift Library Package Structure

Structure for medium-sized utility packages (Networking, Analytics, etc.) with multiple related responsibilities.

```
MyLibrary/
├── Package.swift
├── README.md
├── Sources/
│   └── MyLibrary/
│       ├── Client/
│       ├── Caching/
│       ├── Interceptors/
│       ├── Transport/
│       ├── Retry/
│       └── MyLibrary.docc/
│           ├── MyLibrary.md
│           └── GettingStarted.md
├── Tests/
│   └── MyLibraryTests/
│       ├── Client/
│       ├── Caching/
│       ├── TestSupport/
│       │   ├── Mocks/
│       │   └── Fixtures/
│       └── Resources/
```

### Rules

- Organize by responsibility, not by type (Client/, Caching/, not Models/, Extensions/)
- Use `public`/`internal` access control in code, not separate folders
- Tests mirror source structure
- Shared test helpers go in `Tests/*/TestSupport/` with `Mocks/` and `Fixtures/` subfolders
- Test resources (JSON, etc.) go in `Tests/*/Resources/`
- Include a DocC catalog inside the target's source folder (`Sources/MyLibrary/MyLibrary.docc/`,
  where SwiftPM finds it) with at least the landing page `MyLibrary.md` and `GettingStarted.md`
- Platform-specific code uses `#if os()` inline, not separate folders
- Small packages don't need subfolders - flatten if <5 files per area
