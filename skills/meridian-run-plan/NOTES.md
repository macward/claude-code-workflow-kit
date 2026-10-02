# Notas de `/meridian-run-plan` — evidencia y decisiones

Esto **no es el proceso**: el proceso vive entero en `SKILL.md` y se ejecuta sin leer este archivo. Acá está la evidencia detrás de las reglas menos obvias — qué se midió, cuándo, y qué redacción anterior resultó estar mal.

Leerlo cuando haga falta **cambiar** una de esas reglas. Está separado porque es caro de tener en contexto en cada turno y sólo hace falta al editar la skill. La evidencia del lado de solve-task (gates anidados, frontera run-plan → solve-task, por qué el commit vive allá) está en `.claude/skills/meridian-solve-task/NOTES.md`.

---

## Recorte del 2026-09-12

El `SKILL.md` tenía 459 líneas (41KB, ~10K tokens) releídas en cada turno de un run que puede durar decenas de tasks. Se recortó a reglas y la evidencia pasó acá, igual que se hizo con solve-task. Las reglas duras siguen en cada punto de entrada donde aplican (autosuficiencia por sección gana a DRY); lo que se sacó fue el porqué.

Se eliminó la sección **Key Principles**: resumía el archivo entero, y uno de sus bullets —"a task only enters when its blockers are `done`"— era exactamente el filtro de admisión que el step 3 prohíbe (ver abajo). Un resumen que contradice el proceso es peor que no tenerlo.

## Por qué el commit lo hace solve-task y run-plan sólo verifica

El mensaje se escribe donde está la información: el diff, los criterios y por qué el trabajo quedó así. Desde run-plan se ve un título y un reporte en prosa. Cuando el commit vivía acá, el precio fue un step defensivo entero para detectar que solve-task había commiteado "por su cuenta" — señal de que el contrato peleaba con el diseño. Verificar desde afuera contra `git` es más robusto que producir desde afuera.

## Por qué un run cortado se retoma solo

Es consecuencia directa de que cada task se commitee al terminar. Antes, un run cortado dejaba N tasks de trabajo sin commitear y la invocación siguiente lo rechazaba por tree sucio.

## Por qué nunca `main` literal, y detached HEAD

En un proyecto con base `master`, comparar contra `main` lee la base como "branch aislada" y publica directo sobre ella. Detached HEAD: `git rev-parse --abbrev-ref HEAD` devuelve el literal `HEAD`, que pasa el test `≠ <base_branch>` como si fuera una branch de trabajo, así que 7.1 intentaría pushear algo que no es una branch.

## Por qué la cola ordena y no filtra (step 3)

La regla anterior decía "una task entra sólo si todos sus blockers están `done`": un filtro de admisión. Al armar la cola ninguna task del plan está `done` todavía, así que una cadena 001→002→003 admitía exactamente una. Un plan de 6 tasks encadenadas anunció `run-plan started — 1 tasks` y la cola creció en silencio en el step 5: cada `[i/N]` estaba mal y la aritmética de 7.3 perdió sentido. El ejemplo del step 4 —que lista `002 (depends_on: 001)` con 001 todavía pendiente— siempre mostró el comportamiento correcto; la regla era la que no lo describía.

## Por qué las líneas `Branch` y `PR on close` del anuncio

Un run largo puede compactarse a mitad de camino, y `<run_branch>` viaja en cada delegación como la branch contra la que solve-task verifica antes de commitear. Si existiera sólo como variable recordada, la delegación posterior a una compactación no tendría nada que pasar. La línea del PR se agregó por el mismo argumento: `--no-pr` era el único dato de 7.2 sin dónde anclarse.

## Por qué `--confirm` es menos control que antes

Con ejecución inline el usuario veía el review completo, la salida de tests y cada edit, y podía cortar en cualquier punto; el principio decía "retry / skip / abort en cada decisión" y era literal. Hoy es una decisión por task, más otra si falla. El trade fue deliberado —la frontera de contexto es lo que permite runs largos—, pero una garantía que se achicó y no se reescribió es una promesa que la skill no cumple. Desde el 2026-08-11 solve-task también delega cuando se la invoca sola, así que sin `--inline` no hay más visibilidad que acá.

## Por qué se delega en subagente y no inline

Inline, cada task deja en el contexto del orquestador sus `context_refs` completos, cada edit, la salida de tests dos veces y los reportes enteros de los dos gates; con N grande el run compacta a mitad de camino y run-plan pierde el estado con el que verifica sus propias invariantes. En subagente sólo vuelve el reporte del step 10, que solve-task ya define como contrato. Nada importante se pierde en el camino: el código, el commit y el estado en Meridian no viajan por el contexto, y 5.1 verifica contra `git`.

`<repo_root>` explícito importa sobre todo en worktrees: el repo de la feature **no** es el checkout desde donde se invocó, y un subagente arranca con su propio working directory.

## Por qué el header literal

Cuando el hijo reescribía el header —o describía la falla en prosa sin header— y la task fallida no había tocado archivos, 5.1 veía un tree limpio sin commits y lo registraba como `done ✓ (no changes)`: una task rota registrada como completada.

## Cómo se espera al subagente: la evidencia

- **Metadata, no reporte (run del 2026-08-07).** El step decía "esperá a que el subagente cierre", intención correcta, pero el único candidato a "esperar" era el tool call, que vuelve en segundos con la instrucción de *seguir con otro trabajo*. Leído literal, el orquestador quedaba autorizado a seguir trabajando con dos hijos vivos encima. Las alertas "idle" de ese run se leyeron como fin de task.
- **Polling con Bash (2026-08-13, feature "semilla" en `pfrm0301`).** La task 007 hizo 48 turnos de `echo waiting` esperando sus gates: 8.14M tokens, 23% del costo total de la task. La 005 hizo 26, 20%. Las que no pollearon (006, 009) no tuvieron ese costo. Hay además un hook global que bloquea el patrón (`hooks/block-gate-wait-polling.sh`).
- **`.git/index.lock` (2026-08-08).** Dos procesos commiteando en paralelo sobre un repo dejaron **6 de 13 commits**, perdiendo el resto en silencio salvo por `fatal: Unable to create '.git/index.lock': File exists`. Un run que "aprovecha" el tiempo del hijo no es más rápido: corrompe la garantía de N commits, que es lo único que aporta run-plan.
- **`name:` cuelga (2026-08-08).** Con nombre el hijo se spawnea como teammate direccionable (`task_type: in_process_teammate`). A los cuatro minutos no había tocado un archivo, commiteado ni reportado; hubo que matarlo. El mismo brief sin `name:` cerró en 29 segundos con commit, trailer y header.

## El desvío de notificaciones al abuelo

**Correlación, no causa.** La prueba del `name:` mostró juntos el hijo colgado y el resultado de su agente anidado entregado a run-plan, y esta sección atribuía lo segundo a lo primero. En las tasks 004 y 006 del run siguiente el desvío se observó **también sin `name:`**, en el tercer nivel de anidamiento. Sacar `name:` arregla el cuelgue, no el desvío — y creer que sí deja el modo de fallo sin defensa.

**Mecanismo, observado el 2026-08-21.** Un agente de gate abrió su reporte explicando por qué lo entregaba donde lo entregaba:

> I couldn't resolve `general-purpose` as an addressable peer (no matching agent
> found via SendMessage), so I'm reporting the result directly here instead.

El nieto intenta responderle al hijo **por nombre**, el nombre no resuelve —`general-purpose` es un tipo de agente, no una dirección— y cae al único destino que le queda, hacia arriba. Por eso no depende de `name:` y no se arregla desde el repo: el fallback vive en el agente que reporta.

**Segundo síntoma (2026-08-20 y 2026-08-21).** Lo documentado era "el hijo no recibe el review **y reporta igual**". Dos veces pasó lo contrario: el hijo se quedó esperando y notificó con un `<result>` de una línea sin header (`Waiting for the re-review`). "Una notificación no es una terminación" lo cubría, pero su única indicación era *volver a esperar*, que sobre un hijo esperando algo que no va a llegar es esperar para siempre.

**El reenvío funciona.** En la última ocurrencia, el review reenviado con `SendMessage` volvió `0 blockers, 0 suggestions` y el hijo cerró con esa cita, aclarando que le había llegado por reenvío.

**La línea `GATE` inventada.** Pasó que un subagente afirmara "re-review landed clean, 0 blockers" sin respaldo; lo retiró él mismo en el reporte final. Es el modo de fallo que vuelve inútil la tercera lectura: el reenvío existe para que el hijo no tenga que elegir entre inventar y quedarse colgado.

## Por qué la cota de tiempo por task

Sin cota un run se clava sin output ni diagnóstico: un test esperando una conexión a una DB que no está, o un `input()` olvidado en un fixture. `/goal` no ayuda ahí — la sesión no está terminando, está bloqueada. `ListAgents` es opcional porque la superficie de tools no es la misma para todo tipo de agente, y un `ListAgents` que no resuelve no puede ser el único camino al corte.

## Por qué la tercera lectura del reporte

El silencio no es evidencia de nada. Un subagente que nunca spawneó, murió en su primer tool call, comió un permission denial o devolvió una respuesta truncada es indistinguible desde afuera de una task que corrió y no tocó archivos. Y los gates de juicio son lo único que separa "el código pasó los tests" de "alguien que no lo escribió lo miró": un `done ✓` sin líneas `GATE` es exactamente el caso del desvío, en el que solve-task nunca recibió el review y reportó igual.

## Por qué 5.1 consulta Meridian en el caso `0` con tree limpio

Es el único chequeo del step que no se hace contra git, a propósito: git no distingue "no tenía nada que hacer" de "no hizo nada", y el estado de la task sí. `get_task` es autoritativo, legible por máquina, barato, y run-plan ya tiene credenciales para leerlo.

## Por qué el accessor de trailers exacto

El chequeo alimenta `scripts/mark_deployed.sh`, que lee con `%(trailers:key=Task,valueonly)`. Verificar con `git log -1 --format=%B` y preguntar si "contiene" `Task: …` es más débil que el consumidor: `%B` se satisface con una línea `Task:` en cualquier lado, mientras `%(trailers:...)` sólo ve el último párrafo, y sólo si parsea como bloque de trailers. Con el chequeo débil, run-plan aprobó un commit que el deploy nunca iba a ver, y la task se salteó en silencio. Agregar `Task: <id>` al final de un párrafo de texto al hacer amend produce justo ese mensaje.

## Por qué el step 6 autónomo pasa por el step 7

Esta rama antes imprimía un bloque terminal y terminaba. Eso dejaba los `i-1` commits ya verificados sin pushear, sin resumen en el formato de 7.3 y sin decirle nada al usuario sobre publicar — mientras 7.1 declaraba que el push depende de la branch "no del modo del run" y 7.2 y 7.3 tenían casos explícitos de run parcial sólo alcanzables por el step 7. Un run cortado sigue siendo un run que hay que cerrar.

## Por qué `skipped` ≠ `not executed`

En el resumen viejo se veían igual y no lo son: en un run autónomo que se corta ninguna task fue *salteada*, simplemente no les llegó el turno. Al retomar las dos vuelven a la cola, pero sólo una fue una decisión.

## Por qué el PR sólo con run completo

Un PR con medio plan adentro anuncia trabajo terminado que no lo está. El chequeo de PR ya abierto no es un caso excepcional: un run retomado llega a 7.2 por segunda vez.
