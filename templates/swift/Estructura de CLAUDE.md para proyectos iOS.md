### 1. Project Overview

Descripción breve del proyecto: qué hace, arquitectura (MVVM, etc.), y tecnologías principales (SwiftUI, SwiftData, Observation framework).

### 2. Tech Stack

Lista concreta de frameworks y versiones:

- iOS mínimo soportado
- `Swift version`
- Dependencias principales (SPM packages)

### 3. **Architecture & Patterns**

Convenciones de arquitectura:

- Estructura de carpetas: sólo lo que se aparta de `2 - Project Structure`, y el mapa de capacidades de `Core/` del proyecto
- Patrón MVVM o el que uses
- Naming conventions
- Qué stores, services y coordinators existen, y quién es dueño de qué

### 4. **Code Style**

Reglas de estilo específicas:

- Preferencias de formateo
- Manejo de opcionales
- Async/await conventions

### 5. **Build & Run Commands**

Comandos bash frecuentes:

- Build del proyecto
- Correr tests
- Linting (SwiftLint si usás)
- Scripts custom

### 6. **Testing Guidelines**

Cómo escribir y correr tests:

- Convenciones de naming
- Qué mockear y qué no
- Comandos para tests unitarios vs UI tests

### 7. **Common Patterns & Examples**

Referencias a archivos que sirven como ejemplo:

- "Para crear una nueva View, mirá `ExampleView.swift`"
- "Para servicios de red, seguí el patrón de `APIClient.swift`"

### 8. **Known Issues & Gotchas**

Cosas raras del proyecto que Claude debe saber:

- Workarounds específicos
- Warnings esperados
- Comportamientos de Xcode

### 9. **Git & Workflow**

Convenciones de git:

- Branch naming
- Formato de commits
- PR conventions

### 10. **Do's and Don'ts**

Reglas explícitas con énfasis:

- "ALWAYS use async/await, never completion handlers"
- "NEVER force unwrap optionals"

---