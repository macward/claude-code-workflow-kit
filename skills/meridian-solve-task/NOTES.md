# Notas de `/meridian-solve-task` — evidencia y decisiones

Esto **no es el proceso**: el proceso vive entero en `SKILL.md` y se ejecuta sin leer este archivo. Acá está la evidencia detrás de las reglas menos obvias — qué se midió, cuándo, y qué redacción anterior resultó estar mal.

Leerlo cuando haga falta **cambiar** una de esas reglas. Una regla cuya evidencia nadie recuerda se deshace sola en el refactor siguiente; ese es el trabajo de este archivo, y por eso está separado: es caro de tener en contexto en cada turno y sólo hace falta al editar la skill.

---

## Gates anidados: qué está verificado y qué no

**Los gates de los steps 6 y 7 corren aunque la skill ya esté dentro de un subagente** — verificado el 2026-08-07. La cadena `/meridian-run-plan` → `/meridian-solve-task` → agente de gate corrió completa en dos tasks independientes, y los agentes del nivel más interno produjeron reviews con números de línea y hallazgos que el nivel intermedio no les había pasado: evidencia que sólo puede producir un agente que efectivamente leyó los archivos. Eso cierra una sola de las dos preguntas: **el spawn más interno no se declina en silencio**.

**Que su resultado vuelva a quien los lanzó no está verificado, y es el modo de fallo abierto.** En las tasks 004 y 006 del run del 2026-08-08 se observó que la notificación del nieto llega al contexto del **abuelo** (run-plan) en vez del padre (solve-task): el gate corrió y habló, pero su padre nunca lo recibió y reportó igual. En la 004 nadie lo notó; en la 006 lo salvó que el propio agente sospechara y fuera a buscar el output a mano. Eso es suerte, no una garantía.

Que un agente lea los archivos y que su output llegue a su padre son dos cosas distintas, y la prueba del 2026-08-07 sólo probó la primera. Es el modo de fallo que estos gates existen para tapar, corrido un nivel: **"no recibí el review" y "el review no encontró nada" son indistinguibles desde afuera** salvo que se los distinga explícitamente.

**De ahí salen tres reglas del SKILL.md, y ninguna es cosmética:** la línea `GATE …` literal que exigen los steps 6 y 7, la cota de 10 minutos con `TaskStop` al vencer, y la prohibición del step 10 de emitir un reporte de éxito sin las dos líneas `GATE` citadas. El desvío de notificaciones es comportamiento de la plataforma y no se arregla desde acá; **la defensa es detectar la pérdida, no evitarla.**

## La frontera run-plan → solve-task, y por qué la causa no estaba acá

Cerrada el 2026-08-08. Un subagente que corre el proceso completo —incluido spawnear su propio agente anidado— llega al commit y devuelve su reporte con el header exacto: la corrida de control tardó 29 segundos y dejó el commit con su trailer legible por `%(trailers:key=Task,valueonly)`.

Lo que fallaba era el lado del orquestador. El `Agent` tool devuelve metadata de spawn y no el reporte, así que run-plan seguía trabajando —y commiteando— con los hijos todavía vivos, y las dos partes se pisaban el `.git/index.lock`. Medido: dos procesos commiteando en paralelo sobre un repo dejaron **6 de 13 commits**, perdiendo el resto en silencio salvo por `fatal: Unable to create '.git/index.lock': File exists`. El arreglo vive en el step 5 de `/meridian-run-plan`.

Lo cerrado es **esa** frontera, medida sobre ese call site. El mismo mecanismo asincrónico rige cualquier otro spawn del repo y no todos se auditaron.

## Por qué el commit vive en esta skill y no en run-plan

Acá está la información con la que se escribe el mensaje: el diff, los criterios y por qué el trabajo quedó como quedó. El orquestador tiene el título de la task y un reporte en prosa, y un mensaje de commit escrito desde afuera es peor.

El split anterior además obligaba a run-plan a defenderse de que esta skill commiteara "por su cuenta" — señal de que el contrato peleaba con el diseño.

**La fila de `<base_branch>` decía antes "nadie — lo dispara el usuario"**, que era el gate que la Git Policy declara innecesario (la línea irreversible cae entre el commit y el push, no antes). Costaba caro: dejaba a Max commiteando a mano el trabajo de una task, y el trailer `Task:` —que existe justamente para que lo escriba una máquina— se olvidaba, con lo que la task no llegaba nunca a `deployed`. Es el modo de fallo que `/meridian-task` fue creada para tapar, y que se colaba igual por acá.

## Por qué el step 8.1 chequea si hay algo que commitear

Antes se hacía `git add -A` con el índice vacío, `git commit` salía con código distinto de cero, y la skill reportaba `Commit FAILED: nothing to commit`: bajo run-plan eso **cortaba un run entero por una task que salió perfecta**. Una task de verificación pura ("confirmar que la migración es idempotente; no agregar código si ya lo es") termina legítimamente sin tocar archivos.

## Por qué el reporte lista los archivos commiteados

`git add -A` toma **todo** lo que haya en el árbol, incluidos artefactos que la propia task generó sin proponérselo: archivos de coverage, `.pytest_cache` si no está ignorado, o el `docs/schema.sql` que el pre-commit regenera. run-plan garantiza tree limpio al empezar cada task, así que el alcance es correcto por construcción; lo que faltaba era que el commit dijera qué se llevó puesto.

## Por qué las dos tablas del step 10 se indexan distinto

La de éxito por situación de git, la de falla por el token `Stage:` que el reporte ya trae. Antes era una sola tabla con las dos convenciones adentro, y quien tuviera que mapear un token a su línea lo hacía por inferencia en la mitad de las filas y por match literal en la otra mitad.

## Por qué run-plan no parsea el trailer del reporte

El trailer lo escribe esta skill, derivado del `task_id` que trajo de `get_task` (step 1) — no del texto de ningún reporte. run-plan verifica el commit ya hecho con `git log -1 --format='%(trailers:key=Task,valueonly)'` —el mismo accessor que usa `scripts/mark_deployed.sh` al deployar— contra el `task_id` que él mismo tiene de `list_tasks` (su step 5.1).

Las dos skills derivan el trailer de la misma fuente autoritativa por separado y después contrastan el resultado en git, que es máquina-legible. Acoplarlas por el texto de un reporte que además lleva cuatro secciones de prosa libre (10.1) sería frágil, y el modo de fallo era silencioso: commit sin trailer y la task fuera del ciclo `done→deployed`.

**Consecuencia para el step 8.1:** el trailer tiene que quedar en un bloque de trailers real — última línea, precedida por una línea en blanco.

## Por qué el límite de iteraciones de los gates es 2

Los steps 6 y 7 son gates de **juicio**, no determinísticos. Un tercer intento sobre un blocker que sobrevivió a dos arreglos casi nunca es un arreglo: es el review y el implementador desacordando sobre algo que necesita a Max.

Sin ese límite, el bucle 3→6 no tiene condición de salida y el subagente cuelga al invocador en silencio — el mismo modo de fallo que los steps 4 y 7 ya tienen tapado.

## Por qué el step 1 acepta prefijo de título y de task-id

Las dos formas se usan: los planes de `/meridian-task-breakdown` numeran los títulos `NNN-`, y `/meridian-task` crea una task suelta y pasa su **id de 8 caracteres**, que nunca va a prefijar un título `NNN-slug`. Con sólo la primera forma, toda invocación desde `/meridian-task` terminaba sin match.

## Por qué la invocación directa se delega a un subagente

Medido sobre los 31 runs del proyecto entre 2026-07-11 y 2026-08-11 con `scripts/skill_cost.py --context`, cuando la invocación directa todavía corría en el contexto del usuario:

| | |
|---|---|
| contexto heredado al arrancar | mediana **76K**, p90 285K, max 626K |
| lo que el run agregaba por turno | ~900 tokens |
| lo que escribía por turno | ~370 tokens |
| herencia sobre el total leído | **56.5%** (198.9M de 351.9M) |
| en runs de <60 turnos (25 de 31) | **81-85%** |

O sea: la mayor parte de lo que el modelo leía era conversación previa que esta skill no generó y no necesitaba, releída en cada turno. El `--inline` existe porque el step 5 de run-plan remitía a "solve-task invocada sola" como la herramienta para mirar de cerca una task riesgosa, y sin escape hatch esa capacidad desaparecía del repo.

## Por qué el SKILL.md trae reglas y no porqués (recorte del 2026-09-12)

El `SKILL.md` había llegado a 493 líneas y `REPORT.md` a 153: ~13K tokens que el subagente carga en cada run y relee en cada turno. Un tercio era justificación que ya vivía acá, repetida al lado de cada regla. Se recortó a reglas, y el brief de delegación (`DELEGATE.md`, sólo lo lee el padre) y el step 9.2 (`FEATURE_ENRICH.md`, sólo cuando se completa una feature) salieron a archivos que se leen bajo condición.

**Lo que no se consolidó a propósito:** las reglas duras siguen repetidas en cada punto de entrada donde se aplican (task `in-progress` al fallar, líneas `GATE`, headers literales en el step 10 y en `REPORT.md`). Es la decisión previa de "autosuficiencia por sección gana a DRY": quien entra por un step no tiene que reconstruir la regla leyendo otro. Lo que se sacó fue el **porqué** duplicado, no la regla.

Los porqués que vivían sólo en el SKILL.md quedan abajo.

## Por qué nunca se compara contra `main` literal, y fail closed

La base es `main`, `master` o `develop` según el proyecto. Comparar contra `main` en un repo con base `master` lee la base como "branch aislada, puedo pushear" y publica directo sobre ella. Sin `branch:` ni `origin/HEAD`, la opción segura es la que no publica: el commit no publica nada. run-plan hace la misma lectura en su Setup, y tiene que coincidir: si una skill asume que la task se commitea y la otra se niega, todo run sobre un repo sin `branch:` muere en su primera task.

## Por qué el commit va antes de `done`

Son los dos estados durables de la skill, uno en git y otro en Meridian. Al revés, cualquier corte entre los dos (hook que aborta, branch inesperada, sesión muerta) deja la task `done` con cero commits: no vuelve a la cola de run-plan —que carga sólo `pending` + `in-progress`—, nunca lleva su trailer `Task:` y `mark_deployed.sh` nunca la mueve a `deployed`. Commiteando primero, el peor caso es una task `in-progress` con el trabajo commiteado: recuperable y visible.

## Por qué agrupar llamadas en un turno

Medido sobre los transcripts de los runners: **21% de los turnos eran una sola llamada sin dependencia del turno anterior** (lecturas de `context_refs` de a una, barridos de grep patrón por patrón, ediciones a archivos distintos en turnos separados). Cada turno reenvía el contexto entero, así que el costo es la cantidad de turnos, no el payload. Detalle en el CHANGELOG.

## Por qué el step 4 prohíbe sondear el entorno y exige timeout

Sobre 212 transcripts de subagente, **47% de los runs sondeaba el entorno** y era el 14% de todos sus comandos bash; leer la tabla de síntomas cuesta un turno, redescubrirla costaba trece. El timeout: un test colgado (esperando una DB que no está, un `input()` olvidado) nunca falla, y bajo run-plan bloquea al subagente, que bloquea al orquestador — sin output ni diagnóstico. Un test rojo corta una task; uno colgado sin cota cuelga el run entero.

## Por qué simplify se limita al diff de la task

En un plan de N tasks, si la 003 refactoriza lo que hizo la 001, el commit de la 003 deja de ser atribuible y el trailer `Task:` miente sobre qué cambió. Y el step 5 es el único punto donde mutar no invalida nada: los gates de juicio todavía no corrieron y el determinístico es barato de repetir. Por eso después el código se congela: los gates juzgan lo mismo que se commitea.

## Por qué un gate no recibido no es `UNVERIFIABLE`

`UNVERIFIABLE` es un veredicto que el verificador emitió sobre un criterio concreto, y presupone que habló. Si no habló no hay veredicto de ningún tipo, y meterlo en el slot blando del step convierte el modo de fallo en un éxito con asterisco.

## Por qué la divergencia de `writes` no bloquea

No hay medición de qué tan preciso es `writes` en la práctica, y un gate sobre una señal sin calibrar rechaza trabajo correcto. El step 8.3 **es** esa medición: acumula divergencias reales, y sólo con ese recall a la vista se decide si el chequeo de overlap de `/meridian-analyze` pasa de informativo a gate.

## Por qué el enrichment no lleva sha, GATE ni tests

El `enrichment` se embebe junto al summary y es lo que rankea la búsqueda semántica del feed. Un texto mitad paths y exit codes responde peor a "¿por qué no tocamos producción en la task del sidebar?", que es justo lo que el feed tiene que poder responder. Y un fallo del enrich no degrada el reporte: la task ya está `done` y commiteada, decir lo contrario mentiría sobre trabajo que sí quedó.

## Por qué run-plan no pushea en cada task

Un push por task publicaría estados intermedios de un plan que todavía puede fallar y cortarse. El run hace un único push al cerrar (su step 7.1).
