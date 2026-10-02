# SDD Reconcile Command

Reconciliar el SDD original contra la implementación real, antes de archivar la feature. Detecta divergencias, propone resolución por categoría y actualiza el SDD para que refleje la realidad post-implementación.

## Cuándo usar

Después de `solve-task` / `run-plan` y **antes** de `archive`. La feature está mergeada o lista para mergear; el código existe; el SDD original está congelado en `specs/`.

## PROHIBICIONES ESTRICTAS

- ❌ No archivar la feature (eso lo hace `archive`)
- ❌ No modificar código de implementación durante este paso (sólo proponer cambios; los aplica `solve-task` si el usuario decide)
- ❌ No actualizar el SDD sin confirmación explícita por divergencia

## Setup

1. Leer `vibe: <project>` del CLAUDE.md activo.
2. Identificar el SDD a reconciliar:
   - Si el usuario pasó nombre como argumento, usarlo.
   - Si no, listar SDDs activos del proyecto y preguntar.
3. Identificar el rango de commits de la feature:
   - Por defecto: commits desde la rama base hasta HEAD.
   - El usuario puede pasar rango explícito.

## Proceso

### 1. Cargar artefactos

```
mcp__meridian__read_doc(project=<project>, folder="specs", filename=<sdd_file>)
```

Leer commits relevantes con `git log --oneline <base>..HEAD` y diffs por archivo afectado.

Listar archivos tocados en el rango. Para cada uno, leer el estado actual (no el diff — el resultado final).

### 2. Extraer afirmaciones verificables del SDD

Identificar afirmaciones del SDD que se pueden contrastar con el código. Categorías:

- **Estructurales**: "se crea el módulo X en path Y", "el servicio Z expone método W", "tabla T tiene columnas A,B,C".
- **Comportamiento**: "el endpoint devuelve 401 si falta token", "función F valida input".
- **Restricciones**: "MUST", "DEBE", "NO debe", "máximo N".

Ignorar afirmaciones puramente descriptivas o de motivación ("esto resuelve el problema X") — no son verificables.

### 3. Verificar cada afirmación contra el código

Por cada afirmación:
- Buscar evidencia en el código (path, función, test, schema).
- Clasificar el resultado en una de 3 categorías:

| Categoría | Significado |
|---|---|
| ✅ **Match** | El código refleja la afirmación |
| ⚠️ **Divergencia accidental** | El código se desvió sin razón documentada (sospecha de bug o atajo) |
| 🔄 **Divergencia intencional** | El código refleja conocimiento que el SDD no anticipó (la implementación supo más) |

Heurística para distinguir ⚠️ vs 🔄:
- Si la divergencia introduce inconsistencia o omite algo del SDD sin justificación → ⚠️.
- Si la divergencia agrega información, simplifica algo que era innecesariamente complejo, o resuelve un edge case → 🔄.
- En duda, marcar como 🔄 y dejar que el usuario decida.

### 4. Presentar reporte

```
## Reconcile Report — <sdd_filename>
_<fecha> · commits <base>..HEAD_

### ✅ Match (N afirmaciones)
- "DEBE existir endpoint /healthz sin auth" — verificado en src/api/health.py:12

### ⚠️ Divergencias accidentales (N)
- SDD: "tabla `latencies` tiene índice en `(operation, recorded_at)`"
  Código: índice sólo sobre `operation`
  Sugerencia: agregar índice compuesto o documentar por qué se omite

### 🔄 Divergencias intencionales (N)
- SDD: "ObservationService.save retorna {id, path}"
  Código: retorna {id, path, deduped: bool}
  Sugerencia: actualizar SDD para reflejar el flag de dedup

### Afirmaciones no verificables (N)
- "este diseño escala mejor que la alternativa X" — descriptiva, sin acción
```

### 5. Resolver divergencias

Por cada ⚠️ y 🔄, presentar las opciones al usuario y esperar decisión:

**⚠️ Accidental:**
- a) Actualizar código para volver al SDD (crea task pending para `solve-task`)
- b) Documentar como deviation aceptada en `## Deviations` del SDD
- c) Skip (decidir más tarde)

**🔄 Intencional:**
- a) Actualizar SDD para reflejar la realidad
- b) Documentar como deviation explícita en `## Deviations`
- c) Skip

No avanzar a paso 6 hasta que todas tengan decisión.

### 6. Aplicar updates al SDD

Por cada decisión que requiere editar el SDD:

- **Update directo**: modificar el texto del SDD para que matchee el código.
- **Deviation documentada**: agregar bloque al final del SDD:

```markdown
## Deviations from original spec

### <YYYY-MM-DD> — <título corto>

**Original:** <cita exacta del SDD pre-update>
**Implementación:** <qué hace el código>
**Razón:** <por qué se aceptó la divergencia>
**Tipo:** accidental aceptada | intencional
**Trigger para revisar:** <condición bajo la cual habría que volver al original>
```

Persistir el SDD actualizado sobrescribiendo el archivo existente:

```
mcp__meridian__create_doc(
  project=<project>,
  folder="specs",
  filename=<sdd_file>,   # el mismo con el que se leyó, no uno derivado
  content=<contenido_actualizado>,
  upsert=True
)
```

`upsert=True` es obligatorio: el CRUD genérico es create-only por defecto, así que sin él esto falla con `DocumentAlreadyExistsError` en vez de sobrescribir. Y el `filename` va explícito porque, omitido, se deriva del H1 del documento y puede no coincidir con el nombre del SDD que se está reconciliando — con lo cual crearía uno nuevo al lado en vez de actualizar el que se leyó.

### 7. Verificación final

Después de aplicar updates, presentar resumen:

```
## Reconcile Complete

- Match:                 N
- Divergencias resueltas: N
  - Updates al SDD:       N
  - Deviations documentadas: N
  - Tasks pending creadas: N
- Skipped:               N

SDD actualizado: <path>
```

Si quedan items en "Skipped", advertir que la reconciliación es parcial y NO se debería archivar la feature hasta cerrarlos.

## Reglas

1. Es un comando interactivo — espera decisión por divergencia. No autoresolver.
2. ⚠️ y 🔄 son heurísticas, el usuario tiene la palabra final.
3. Nunca borrar contenido del SDD original — sólo modificar afirmaciones específicas o agregar deviations.
4. Si no hay divergencias, decirlo: "✓ Sin divergencias. SDD refleja la implementación. Listo para archivar."
5. Si el SDD no existe o no está identificable, fallar explícitamente — no inventar uno.
