# Workflow

Cómo trabajar una feature de punta a punta usando las skills de `claude/`.

El README explica **qué** existe. Este documento explica **cómo se usa en la práctica**.

## Principio

El output real no es el documento — es una implementación correcta con baja ambigüedad. El documento es solo la herramienta para llegar ahí. Si la feature ya tiene baja ambigüedad sin documento, no escribas uno.

## Mapa del proceso

```
(al empezar la sesión) /meridian-recall
                  ↓
1. (una vez por proyecto) /meridian-init
                  ↓
   ┌────────────────────────────────────────────┐
   │  ¿Entra en una sesión?                     │
   └────────────────────────────────────────────┘
      sí ↓                            no ↓
   /meridian-task            2. Discovery — profundidad según complejidad
   (una task, creada            ├─ Nivel 1: /meridian-requirements
    y resuelta; saltea          └─ Nivel 2: /meridian-spec
    2, 3 y 4)                          ↓
        │                     3. /meridian-task-breakdown
        │                            ↓
        │                     4. Ejecución
        │                        ├─ /meridian-solve-task  ← una a una
        │                        └─ /meridian-run-plan    ← autónomo
        │                            ↓
        └────────────→ ←─────────────┘
                       ↓
5. (commit/push/PR: la skill, si hay branch · merge + deploy: manual de Max)
                  ↓
6. /meridian-recap  ·  /meridian-cut-release (al cerrar una versión)
```

Toda feature (`feat(...)`) pasa por una de las dos ramas — lo decide el tipo de commit, no el tamaño (Git Policy en `CLAUDE.md`). `fix`, `docs`, `refactor`, `test` y `chore` no llevan task y van derecho al paso 5.

---

## 0. Empezar la sesión — `/meridian-recall`

Al inicio de cualquier sesión no trivial. Carga el contexto de memoria relevante al tema y reconcilia el estado del proyecto contra git local (read-only), marcando lo que quedó stale. Pasá el tema como argumento para que el recall sea semántico: `/meridian-recall <tema>`.

---

## 1. Bootstrap del proyecto — `/meridian-init`

Una sola vez por proyecto. Crea la estructura del workspace vibe en el servidor MCP (no toca archivos locales). Si el workspace ya existe, no necesitás correrlo.

---

## 2. Discovery — elegir el nivel

La pregunta clave: **¿qué ambigüedad tengo que resolver antes de escribir código?**

### Nivel 1 — `/meridian-requirements`

Para features simples: UI localizada, CRUD, cambios sin impacto arquitectónico.

- **Resuelve**: qué debe hacer la feature, acceptance criteria (MoSCoW), edge cases (BDD)
- **No resuelve**: cómo se implementa, qué módulos toca
- **Ejemplos**: "agregar export CSV", "modo oscuro", "nuevo filtro en la lista"
- **Output**: documento en `requirements/` del workspace vibe

Si la feature entra en una sesión, saltate este paso y el breakdown: andá directo a `/meridian-task`, que crea la task y la resuelve. Si es un `fix`, `docs`, `refactor`, `test` o `chore`, no lleva task — implementá y ya.

Lo que **no** es una opción es una feature nueva sin task: era la salida que ofrecía este documento ("o incluso a implementar") y es la que produjo 12 `feat(...)` sin registro en dos semanas.

### Nivel 2 — `/meridian-spec` (SDD)

Para features arquitectónicamente significativas: arquitectura, concurrency, persistence base, protocol design, networking core, lifecycle complejo, state management complejo.

- **Resuelve**: superficie pública, invariantes, constraints duros (auth, seguridad), ambigüedades críticas
- **Anclado al codebase**: no es teórico, referencia archivos y módulos reales
- **Sin código**: define interfaces, no implementación
- **Ejemplos**: "Conversation Memory", "motor de indexación", "sistema de auth base"
- **Output**: documento en `specs/` del workspace vibe

### Regla práctica

Si dudás entre dos niveles, elegí el más liviano. Subir cuesta poco; bajar significa que escribiste un documento inflado para nada.

Señales de que elegiste mal:
- Escribiste un SDD y todas las decisiones eran obvias → un requirements alcanzaba
- Escribiste requirements y al breakdown no sabías cómo dividir las tasks → faltaba el SDD

---

## 3. Task breakdown — `/meridian-task-breakdown`

Toma el documento de discovery y genera tasks concretas en el workspace vibe, con dependencias (`depends_on`) cuando importan.

Buenas tasks:
- Una unidad de trabajo cerrada (idealmente un commit)
- Independientes cuando se pueda; con `depends_on` cuando hay orden real
- Con criterio de "done" claro

Si después de hacer breakdown ves que las tasks salen vagas o gigantes, probablemente el documento de discovery se quedó corto — subí un nivel y reescribilo.

---

## 4. Ejecución

### `/meridian-solve-task` — una a una

Para trabajar una task sola. **Corre dentro de un subagente**: en tu contexto queda sólo el reporte final, no el proceso. Con `--inline` corre a la vista, con canal abierto — el escape hatch para una task riesgosa que querés mirar de cerca.

1. Toma la siguiente task pendiente (o la que le pases por número)
2. Implementa, corre tests
3. Simplifica el diff de la task (`/simplify`) y re-corre los tests — última mutación del código
4. Code review con `code-review-expert`; arregla blockers si los hay
5. Verifica los acceptance criteria con un verificador independiente
6. Marca la task `done` y enriquece el timeline
7. **Commits** (with the `Task: <id>` trailer) on the current branch, always. Pushes only when invoked on its own on a working branch: never on `<base_branch>`, and never under `/meridian-run-plan`, which pushes once at the end of the run. Never opens a PR or merges.

Los pasos 4 y 5 son gates de juicio (LLM opinando sobre el código). Corren *después* de la simplificación a propósito: así leen el código que se va a commitear y no uno intermedio.

Ideal cuando querés revisar cada paso o la feature tiene riesgo.

### `/meridian-run-plan` — autónomo

Itera todas las tasks pendientes, llamando `/meridian-solve-task` por cada una y respetando `depends_on`.

- Por defecto: autónomo (no para entre tasks)
- Si pedís "step-by-step" o "confirmar": pausa antes de cada task
- **Cada task queda commiteada** al terminarla, sobre la branch actual: un commit por task con su trailer `Task: <id>`. Lo hace `/meridian-solve-task`, igual que invocada sola; run-plan lo verifica y corta el run si falta. No es opcional — sin commit el working tree queda sucio y la task siguiente no arranca
- **Pushea una vez al final** si la branch del run no es `<base_branch>`. Sobre la base no pushea: deja los N commits locales para que dispares vos
- **Abre el PR contra la base** al cerrar un run completo sobre una branch (salvo `--no-pr`). **No mergea ni deploya**: eso es de Max

Ideal cuando el plan está sólido y querés dejarlo correr.

**Si el run se corta a mitad —contexto lleno, sesión muerta— volvé a invocarlo y sigue.** Los runs largos son la norma y el contexto es finito, así que esto va a pasar. No hay nada que rescatar a mano: el trabajo de cada task completada ya está commiteado y su task está `done` en Meridian, y la cola se reconstruye desde `list_tasks` en cada invocación. Lo único que se pierde es la narrativa del run anterior, que está en `git log`.

---

## 5. Git — the branch is what enables automation

The criterion is **not** "who presses the button", it's **where the irreversible line is**. A local commit is reversible; a merge into the base branch and a deploy are not. The branch is what separates one from the other, so it's the branch —not ceremony— that decides how far a skill goes.

**`<base_branch>`** is the integration branch the project's CLAUDE.md declares in `branch:`. In Meridian it's `main`, but skills **compare against that value, never against the literal `main`** — in a project whose base is `master`, hardcoding `main` would make the skill read the base as "isolated branch, I can push" and publish exactly where it shouldn't.

| | commit | push | PR | merge | deploy | delete branch |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **On a working branch** (the feature's worktree) | skill ✓ | skill ✓ | skill ✓ | **Max** | **Max** | **Max** |
| **On `<base_branch>`** | skill ✓ | **Max** | — | — | **Max** | — |
| **Unattended** (`/schedule`, `/loop`) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

- **On a branch, a skill goes as far as the PR.** Committing, pushing and opening the PR is mechanical work: stopping there for Max to do it by hand adds friction, not safety. The real gate is the merge.
- **On `<base_branch>`, a skill commits but doesn't push.** The deploy is a manual runbook, but it ships whatever is on `origin/<base_branch>`: pushing the base releases those commits to the next deploy. Committing there is local and reversible; pushing isn't. That's why the line falls between the two.
- **If `<base_branch>` can't be determined, fail closed:** don't push. When in doubt, the safe option is the one that doesn't publish.
- **Nobody merges, deploys or deletes branches automatically.** Not on a branch, not on the base. Deleting a merged branch is Max's, at merge time.
- **An unattended routine doesn't touch git at all** — not even a local commit. It ends in "artifacts ready for review". See `CLAUDE.md` › Unattended automation.

And the shape rules that don't depend on the branch:

- **One feature = one branch = one worktree, cut from `origin/<base_branch>`** after a `git fetch`. Never from the local base: it may hold unpushed commits that the feature's PR would publish.
- **No published branch per task.** A plan of N tasks produces N commits on the feature branch. A task may only get a temporary local branch that is never pushed.
- **A multi-task plan on `<base_branch>` asks first**: it's a feature landing without a PR.
- **Every commit that completes a task carries the `Task: <id>` trailer** (consumed by `scripts/mark_deployed.sh` at deploy time to move the task to `deployed`).
- **`claude/` changes are `chore(claude)`, never `feat`**, so they don't need a task.

---

## 6. Cerrar la sesión / la versión

### `/meridian-recap`

Genera un recap ejecutivo (sin jerga) de lo que se hizo, guarda en `reports/` y actualiza el estado del proyecto para que la próxima sesión retome sin releer todo el código.

### `/meridian-timeline-note`

Alternativa más liviana: una nota narrativa de 2-4 líneas al feed del timeline (no un documento en `reports/`). Para milestones que no ameritan un recap completo.

### `/meridian-cut-release`

Cuando una tanda de trabajo deployado amerita cerrar una versión: lee el changelog del release abierto, sugiere el bump SemVer según lo que se shippeó, previsualiza, y tras confirmación humana estampa la versión y corta. Se detiene antes de git/deploy.

---

## Patrones de uso

### Feature chica que tenés clara
```
/meridian-task "<lo que querés construir>"
```
Una task, creada y resuelta de una. Sin documento de discovery y sin breakdown — la ambigüedad ya es baja, y descomponer un solo item es ceremonia. Es el camino que mantiene dentro de Meridian a la feature de una tarde en vez de shippearla sin task detrás.

### Feature media
```
/meridian-spec → /meridian-task-breakdown → /meridian-run-plan
```
El SDD alinea la superficie y los constraints, run-plan ejecuta.

### Feature grande / arquitectónica
```
/meridian-spec → /meridian-task-breakdown → /meridian-solve-task (una a una)
```
El SDD reduce riesgo, ejecución controlada por la criticidad.

### Retomar una sesión vieja
```
/meridian-recall → /meridian-solve-task <NNN>
```
Cargar el contexto y el estado, ver qué quedó pendiente, retomar la próxima.

---

## Anti-patrones

- **Escribir SDD para todo.** Genera docs gigantes que nadie lee y desincentiva discovery liviano cuando sí hace falta.
- **Saltarse discovery cuando hay ambigüedad real.** Termina en tasks vagas, refactors a mitad de implementación, y trabajo que se rehace.
- **Mergear o deployar desde una skill.** Prohibido por política — es el único gate humano real. (Commitear, pushear y abrir el PR **sobre una branch de trabajo** sí los hace una skill; en `<base_branch>`, solo commitear. Ver sección 5.)
- **Hacer breakdown antes del discovery.** Si las tasks salen vagas, el problema es upstream.
- **Empezar una sesión sin `/meridian-recall`.** Perdés el estado y las decisiones previas, y arrancás con contexto stale.
