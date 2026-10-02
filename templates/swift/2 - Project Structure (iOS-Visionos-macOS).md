## Project Structure

Organize by responsibility, not by file type, the same rule as Swift packages.
A folder is named after what its code manages
(`Git/`, `Sessions/`, `Checkout/`), never after what kind of file it holds
(`Services/`, `Repositories/`, `Helpers/`).

```
MyApp/
├── App/             entry point + composition root (Bootstrap/ once it outgrows the App struct)
├── Features/        one folder per screen or flow, with the logic only it uses
│   ├── Shell/       window/root navigation and UI coordinators shared across features
│   ├── Home/
│   └── Settings/
├── Core/            logic without screens, one folder per capability
│   ├── Git/
│   └── Sessions/
├── Domain/          types several capabilities use, including @Model types
├── Platform/        infrastructure with no domain knowledge (Keychain, Retry, Logging)
├── DesignSystem/    controls and composites (see 5 - Atomic Design)
└── Resources/
```

Small apps start with `App/` + `Features/`. Every other folder appears with its first file.

### Where a new file goes

First match wins:

1. Runs without a screen (a process, watcher, server, timer, sync), or is a store that
   outlives a screen → `Core/<Capability>/`, even if only one screen shows it
2. UI coordination across features (focus, sheets, active tab, window chrome) → `Features/Shell/`
3. A screen or a piece of one → `Features/<Feature>/`
4. Logic used by one feature only → stays in that feature
5. Logic a second feature now needs → move it to `Core/<Capability>/`, creating the capability
   folder if none fits. NEVER into a generic `Shared/`, `Common/` or `Utils/`
6. Visual, reusable, no dependencies → `DesignSystem/`
7. A type several capabilities need, and every `@Model` → `Domain/`
8. Infrastructure with no domain knowledge → `Platform/`
9. `ModelContainer`, schema versions and migration plan → `App/`

### Dependency direction

`App` → `Features` (+ `DesignSystem`) → `Core` → `Domain` / `Platform`. Nothing references a
layer above it: when lower code needs a type from higher up, move the type down.
Capabilities may call each other, without cycles, but never subscribe to each other's changes;
those reactions are wired in `App/` (see 8 - App Composition).

### Rules

- Subfolders by type (`Views/`, `Models/`) only once a feature or capability passes 10 files
- Tests mirror the source tree (`Tests/Core/Git/`, `Tests/Features/Home/`)
- Each `Core/<Capability>/` is shaped like a package: extracting it to SPM later means moving the folder
- visionOS: immersive spaces and volumes are features
