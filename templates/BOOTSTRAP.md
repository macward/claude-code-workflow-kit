# Project Bootstrap

Procedimiento para componer un CLAUDE.md local en un proyecto que no lo tiene. `~/.claude/CLAUDE.md` apunta acá.

When starting work on a project without a local CLAUDE.md, detect the stack and compose one automatically.

### Detection

| Indicator | Stack |
|---|---|
| .xcodeproj/.xcworkspace (with or without Package.swift) | Swift App |
| Package.swift without .xcodeproj/.xcworkspace | Swift Package |
| pyproject.toml / requirements.txt | Python |

### Swift Rules

Location: ~/.claude/templates/swift/ (repo: `project_rules/templates/swift/`)

Viven en `templates/` y no en `rules/` **a propósito**: todo lo que cuelga de `~/.claude/rules/` se carga en el contexto de cada turno de cada proyecto, y estas reglas sólo aplican a proyectos Swift. Leerlas con `Read` cuando la detección de arriba da Swift; no moverlas de vuelta a `rules/`.

**Always include:**
- 0 - Tech Stack.md
- 1- Architecture and Patterns.md
- 6 - Coding Styles.md
- 7 - Testing.md

**Swift App only** (has .xcodeproj or .xcworkspace):
- 2 - Project Structure (iOS-Visionos-macOS).md
- 4 - Uso de ViewModels.md
- 5 - Atomic Design.md
- 8 - App Composition.md

Además, el CLAUDE.md compuesto para una Swift App incluye esta sección, tal cual:

```markdown
## Referencia: lecciones de DeadCode

Antes de armar la estructura del proyecto, leer en Meridian `deadcode-app/architecture/referencia-07-por-donde-empezar.md`: una checklist de arranque que sale de los errores de DeadCode, con el índice de la serie en `referencia-00-indice.md`. Cada regla dice si está **probada** o es **propuesta**; si una regla probada choca con estas plantillas, avisar a Max antes de elegir.
```

**Swift Package only** (Package.swift without .xcodeproj):
- 3 - Swift Library Package Structure.md

### Python Rules

Location: ~/.claude/rules/python/ (repo: `project_rules/rules/python/`)

Sigue en `rules/` porque es un archivo mínimo y el stack por defecto acá es Python. Si crece, mudarlo a `templates/python/` por la misma razón que Swift.

### Process

1. Detect stack from project root
2. Read all applicable rule files from the template location
3. Compose a local CLAUDE.md concatenating them in order
4. Swift: add the project-specific sections from `Estructura de CLAUDE.md para proyectos iOS.md` (build commands, known issues, git workflow), filled from what the project actually has; leave out any section with nothing to say
5. State which templates were applied before continuing work

**Proyectos que ya tienen CLAUDE.md** no vuelven a pasar por acá: un cambio en las plantillas no les llega solo. Para actualizarlos, releer las plantillas y comparar contra el CLAUDE.md del proyecto cuando Max lo pida.

**Regla al agregar un set de reglas nuevo:** si aplica a *todo* proyecto, va en `rules/` y se paga en cada turno. Si aplica a un stack, va en `templates/<stack>/` y se lee cuando hace falta. `rules/` es un presupuesto de contexto, no un cajón.
