#!/usr/bin/env python3
"""PreToolUse hook (matcher: Bash): bloquea el busy-wait polling con el que un
subagente a veces espera la notificación async de otro Agent que spawneó
(gates de code-review/goal-check en /meridian-solve-task, o el hijo que
/meridian-run-plan delega) en vez de terminar el turno.

La mecánica correcta vive en "How to wait for the subagent"
(.claude/skills/meridian-run-plan/SKILL.md): terminar el turno
sin tool call y retomar cuando llega el <task-notification>. Pollear con
Bash (`echo waiting`, `sleep N; echo done`) reenvía todo el contexto
acumulado en cada turno de poll — medido: 48 turnos así en una sola task
costaron 8.14M tokens de cache_read, el 23% del gasto total de esa task
(run de "semilla" en pfrm0301, 2026-08-13).

Global (no por-proyecto) porque estas skills se invocan desde cualquier
repo, no solo desde el de meridian.
"""
import json
import re
import sys

PATTERN = re.compile(
    r'^\s*(echo\s+.*waiting.*|sleep\s+[0-9.]+\s*;\s*(echo|date)\b.*)\s*$',
    re.IGNORECASE,
)

REASON = (
    "No pollees con Bash esperando a un subagente — terminá el turno. La "
    "notificación async del harness te despierta cuando el hijo cierra "
    '(ver "How to wait for the subagent" en '
    ".claude/skills/meridian-run-plan/SKILL.md). Medido: 48 "
    'turnos de "echo waiting" en una sola task costaron 8.14M tokens de '
    "cache_read, el 23% del gasto total de esa task."
)


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return

    if payload.get("tool_name") != "Bash":
        return

    command = (payload.get("tool_input") or {}).get("command", "")
    if not command or not PATTERN.match(command):
        return

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": REASON,
        }
    }))


if __name__ == "__main__":
    main()
