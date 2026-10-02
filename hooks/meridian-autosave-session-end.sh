#!/bin/bash
# SessionEnd hook: dispara el destilador de Memory v2 al cerrar una sesión.
#
# El evento es SessionEnd, NO Stop: Stop dispara una vez por turno ("when Claude
# finishes responding"), así que montado ahí esto lanzaría una sesión headless
# después de cada respuesta. Ver skills/meridian-autosave/SKILL.md.

# Guard anti-recursión: el `claude -p` de abajo es una sesión que, al terminar,
# dispara su PROPIO SessionEnd. La env var se hereda (la doc lo garantiza:
# "Handlers run in the current directory with Claude Code's environment"), así
# que el hook de la sesión hija entra acá y sale sin re-armar nada.
[ -n "$MERIDIAN_AUTOSAVE_HOOK" ] && exit 0
export MERIDIAN_AUTOSAVE_HOOK=1

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"

# El JSON del hook (session_id, transcript_path, cwd, reason) llega por stdin y
# es la ÚNICA fuente del transcript: la sesión headless de abajo arranca vacía y
# no tiene forma de ver la conversación que acaba de cerrar. Durante 104 corridas
# este stdin se descartaba, así que la Fase 1 reportaba "Capturados: 0" siempre
# — el sistema de memoria corría entero en vacío. No volver a tirarlo.
HOOK_JSON=$(cat)

# El digest se inyecta en el prompt por argv en vez de pasarse como path porque
# --allowedTools no incluye Read (ni debe: es la frontera dura de la corrida
# desatendida). Que el transcript viaje en el prompt mantiene la superficie de
# tools en mem_* puro.
if command -v python3 >/dev/null 2>&1; then
    PROMPT=$(MERIDIAN_HOOK_JSON="$HOOK_JSON" python3 -c '
import json, os, sys

# Techo del digest en caracteres. El transcript crudo puede ser de megabytes;
# lo que entra es solo texto de turnos (sin tool_use ni tool_result), y aun así
# una sesión larga lo supera.
MAX_CHARS = 120000

try:
    hook = json.loads(os.environ.get("MERIDIAN_HOOK_JSON", ""))
except ValueError:
    sys.exit(3)

cwd = hook.get("cwd") or os.getcwd()

# El project sale del CLAUDE.md más cercano hacia arriba. Se resuelve acá y no
# en la skill por la misma razón que el digest: la sesión headless no puede leer
# archivos. Sin project no hay nada que la skill pueda hacer, así que el hook
# no la lanza (exit 3) — eso también apaga el ruido de las sesiones abiertas
# fuera de un proyecto Meridian.
project = ""
directory = os.path.abspath(cwd)
while not project:
    candidate = os.path.join(directory, "CLAUDE.md")
    if os.path.isfile(candidate):
        try:
            with open(candidate, encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    if line.startswith("meridian-project:"):
                        project = line.split(":", 1)[1].strip()
                        break
        except OSError:
            pass
    parent = os.path.dirname(directory)
    if parent == directory:
        break
    directory = parent

if not project:
    sys.exit(3)


def turn_text(content):
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts = []
    for block in content:
        if isinstance(block, dict) and block.get("type") == "text":
            text = block.get("text") or ""
            if text.strip():
                parts.append(text)
    return "\n".join(parts)


turns = []
try:
    with open(hook.get("transcript_path") or "", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if entry.get("isMeta"):
                continue
            kind = entry.get("type")
            if kind not in ("user", "assistant"):
                continue
            text = turn_text((entry.get("message") or {}).get("content")).strip()
            if not text:
                continue
            turns.append(("USER: " if kind == "user" else "CLAUDE: ") + text)
except OSError:
    turns = []

digest = "\n\n".join(turns)
if len(digest) > MAX_CHARS:
    # Se conservan las dos puntas: las decisiones de arquitectura suelen caer
    # temprano y las correcciones tarde. Cortar solo la cola perdería unas u otras.
    head = int(MAX_CHARS * 0.3)
    digest = digest[:head] + "\n\n[... transcripto elidido por presupuesto ...]\n\n" + digest[head - MAX_CHARS:]

prompt = "/meridian-autosave --project " + project + "\n\n"
if digest:
    prompt += (
        "Corrida headless desde el hook SessionEnd. Abajo, entre <transcript>, va la "
        "conversación de la sesión que acaba de cerrar: vos NO participaste de ella. "
        "Es la entrada de la Fase 1 (captura) y la única que hay — no busques más contexto.\n\n"
        "<transcript>\n" + digest + "\n</transcript>\n"
    )
else:
    prompt += (
        "Corrida headless desde el hook SessionEnd. No hay transcripto disponible "
        "(vacío o ilegible): saltear la Fase 1 y correr solo la Fase 2 (destilación del backlog).\n"
    )
sys.stdout.write(prompt)
')
    case $? in
        3)
            # cwd fuera de un proyecto Meridian, o JSON del hook ilegible.
            exit 0
            ;;
        0) ;;
        *)
            echo "[autosave] no se pudo armar el prompt desde el JSON del hook" >&2
            exit 0
            ;;
    esac
else
    # Sin python3 no hay digest posible. Se degrada a la corrida vieja (solo
    # Fase 2) en vez de no correr, pero ruidosamente: la Fase 1 no tiene red.
    echo "[autosave] sin python3: corriendo sin transcript, la captura queda sin hacer" >&2
    PROMPT='/meridian-autosave'
fi

# --allowedTools es la frontera dura de la corrida desatendida, no una
# convención: enumera exactamente la superficie mem_* que la skill usa, así no
# puede tocar tasks, docs ni git aunque el modelo lo intentara.
# mem_state is in the list because the project state is the part of memory that
# ages worst: one doc per project, overwritten in place, and until Phase 3 it was
# written only by /meridian-recap — run on some sessions, not others. On
# 2026-09-07 the meridian-server state was 47 days stale and still asserted a
# HEAD dozens of commits back, which /meridian-recall presents FIRST. It is a
# write, but a reversible one inside the project's own workspace: no git, no
# publish. The skill's Phase 3 guards it (read before write, carry forward what
# the session doesn't speak to, skip entirely with no transcript).
CMD=(claude -p "$PROMPT"
     --allowedTools "mcp__meridian__mem_save,mcp__meridian__mem_search,mcp__meridian__mem_get,mcp__meridian__mem_distill_batch,mcp__meridian__mem_distill_ack,mcp__meridian__mem_upsert_fact,mcp__meridian__mem_relate,mcp__meridian__mem_state")

# Techo de tiempo. Sin esto, una corrida trabada (un juicio de contradicción que
# no converge, un reintento en loop) corre sin límite contra la cuenta de
# producción, desatendida y sin nadie mirando. Overrideable para depurar.
TIMEOUT_SECONDS="${MERIDIAN_AUTOSAVE_TIMEOUT:-1800}"

# Desacople del proceso padre. SessionEnd no bloquea el cierre ("If a SessionEnd
# hook is slow, Claude Code will complete session termination independently") y
# la destilación tarda minutos: atada al padre, el teardown se la llevaría por
# delante. Hace falta una sesión nueva, no solo ignorar SIGHUP.
#
# Ni `setsid` ni `timeout` existen en macOS (los dos son de util-linux), así que
# el camino principal es un shim de Python que hace ambas cosas: os.setsid() para
# la sesión nueva y un wait con timeout para el techo. Sin este branch el hook
# moriría con "command not found" en la máquina de desarrollo, en silencio.
if command -v python3 >/dev/null 2>&1; then
    LAUNCH=(nohup python3 -c '
import subprocess, sys, os
os.setsid()
timeout = int(sys.argv[1])
proc = subprocess.Popen(sys.argv[2:])
try:
    sys.exit(proc.wait(timeout=timeout))
except subprocess.TimeoutExpired:
    proc.kill()
    print(f"[autosave] matado tras {timeout}s sin terminar", file=sys.stderr)
    sys.exit(124)
' "$TIMEOUT_SECONDS")
elif command -v setsid >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    LAUNCH=(setsid nohup timeout "$TIMEOUT_SECONDS")
else
    # Último recurso: sin sesión propia ni techo, pero al menos inmune a SIGHUP.
    echo "[autosave] sin python3 ni setsid+timeout: corriendo sin techo de tiempo" >&2
    LAUNCH=(nohup)
fi

# stdin a /dev/null: el JSON del hook ya lo consumió este script y viaja en el
# prompt; el hijo no debe quedar colgado del pipe.
"${LAUNCH[@]}" "${CMD[@]}" < /dev/null >> "$LOG_DIR/meridian-autosave.log" 2>&1 &

# Explícito: el estado del job en background no debe filtrarse como el del hook.
exit 0
