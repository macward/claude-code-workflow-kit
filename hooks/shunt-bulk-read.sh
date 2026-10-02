#!/usr/bin/env python3
"""PreToolUse hook (matchers: Read, Bash): bloquea la lectura completa de un
archivo grande y la redirige al subagente `bulk-reader`, que lo lee en un
contexto barato y devuelve un resumen anclado a `path:line`.

Es la versión local del "check-file-size" que Spotify montó sobre Portal
(engineering.atspotify.com, 2026-09): mismo mecanismo — interceptar el read
y delegarlo a un modelo barato — pero delegando a un subagente Haiku del
propio harness en vez de a un mode remoto, así que no hay infra ni API keys
de por medio.

Qué se bloquea:
  - `Read` de un archivo de texto con más de UMBRAL líneas y sin `limit`
    (o con un `limit` mayor al umbral).
  - `cat`/`less`/`more` pelado sobre un archivo así en Bash — el mismo
    agujero que el hook `check-bash-read` del artículo. Un `cat` con pipe,
    redirección o rango (`head`, `sed -n`, `grep`) no se toca.

Qué NO se bloquea, a propósito:
  - Lecturas con `offset`/`limit` acotados. Es la salida para editar (el
    resumen del worker no reemplaza ver el fragmento real) y es también lo
    que deja que el propio `bulk-reader` haga su trabajo por chunks sin
    chocar contra este hook de forma recursiva.
  - Binarios, imágenes, PDFs y notebooks: ahí `Read` hace otra cosa.

Env:
  CLAUDE_BULK_READ_THRESHOLD  umbral en líneas (default 350)
  CLAUDE_BULK_READ_OFF=1      desactiva el hook por completo

Global (no por-proyecto): el coste de leer un archivo de 3.000 líneas es el
mismo en cualquier repo.
"""
import json
import os
import re
import shlex
import sys

DEFAULT_THRESHOLD = 350

# Extensiones donde `Read` no devuelve texto plano (imágenes, PDF, notebooks)
# o donde contar líneas no significa nada.
BINARY_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".ico",
    ".pdf", ".ipynb",
    ".zip", ".gz", ".tar", ".whl", ".so", ".dylib", ".o", ".a",
    ".mp4", ".mov", ".mp3", ".wav", ".woff", ".woff2", ".ttf",
}

# `cat archivo` / `less archivo` pelado: un solo argumento, sin flags, sin
# pipe ni redirección. Cualquier cosa más compleja ya está acotando la salida.
BARE_CAT = re.compile(r"^\s*(cat|less|more|bat)\s+([^\s|<>;&]+)\s*$")


def threshold() -> int:
    try:
        return max(1, int(os.environ.get("CLAUDE_BULK_READ_THRESHOLD", "")))
    except ValueError:
        return DEFAULT_THRESHOLD


def count_lines(path: str, cap: int) -> int:
    """Cuenta líneas parando en `cap`; devuelve -1 si el archivo no es texto."""
    lines = 0
    try:
        with open(path, "rb") as fh:
            while chunk := fh.read(65536):
                if b"\x00" in chunk:
                    return -1
                lines += chunk.count(b"\n")
                if lines > cap:
                    return lines
    except OSError:
        return -1
    return lines


def is_readable_text(path: str) -> bool:
    if not path or not os.path.isfile(path):
        return False
    return os.path.splitext(path)[1].lower() not in BINARY_EXTS


def reason(path: str, lines: int, limit: int) -> str:
    return (
        f"{path} tiene ~{lines} líneas (umbral: {limit}). No lo leas entero — "
        "delegalo: Agent(subagent_type=\"bulk-reader\") con la pregunta "
        "concreta que querés responder y la ruta del archivo. El worker lo "
        "lee en un contexto barato y te devuelve un resumen con anclas "
        "`path:line`.\n"
        "Excepciones legítimas, sin delegar: leé el fragmento que necesitás "
        f"con offset/limit (limit <= {limit}) — es lo correcto antes de "
        "editar, porque el resumen del worker no trae el código literal."
    )


def deny(text: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": text,
        }
    }))


def check_read(tool_input: dict, cap: int) -> None:
    path = tool_input.get("file_path") or ""
    if not is_readable_text(path):
        return

    # Una lectura ya acotada por debajo del umbral es exactamente lo que
    # queremos que pase: no la tocamos.
    requested = tool_input.get("limit")
    if isinstance(requested, int) and 0 < requested <= cap:
        return

    lines = count_lines(path, cap)
    if lines > cap:
        deny(reason(path, lines, cap))


def check_bash(tool_input: dict, cap: int) -> None:
    match = BARE_CAT.match(tool_input.get("command", "") or "")
    if not match:
        return

    try:
        path = shlex.split(match.group(2))[0]
    except (ValueError, IndexError):
        return

    if not is_readable_text(path):
        return

    lines = count_lines(path, cap)
    if lines > cap:
        deny(reason(path, lines, cap))


def main() -> None:
    if os.environ.get("CLAUDE_BULK_READ_OFF") == "1":
        return

    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return

    tool_input = payload.get("tool_input") or {}
    cap = threshold()

    if payload.get("tool_name") == "Read":
        check_read(tool_input, cap)
    elif payload.get("tool_name") == "Bash":
        check_bash(tool_input, cap)


if __name__ == "__main__":
    main()
