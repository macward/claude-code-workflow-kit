#!/usr/bin/env python3
"""PreToolUse hook (matcher: Bash): blocks the busy-wait polling a subagent
sometimes uses to wait for the async notification of another Agent it spawned
(code-review/goal-check gates in /meridian-solve-task, or the child that
/meridian-run-plan delegates) instead of ending the turn.

The correct mechanics live in "How to wait for the subagent"
(.claude/skills/meridian-run-plan/SKILL.md): end the turn
with no tool call and resume when the <task-notification> arrives. Polling with
Bash (`echo waiting`, `sleep N; echo done`) resends all the accumulated context
on every poll turn — measured: 48 turns like that in a single task
cost 8.14M cache_read tokens, 23% of that task's total spend
("seed" run in pfrm0301, 2026-08-13).

Global (not per-project) because these skills are invoked from any
repo, not just the meridian one.
"""
import json
import re
import sys

PATTERN = re.compile(
    r'^\s*(echo\s+.*waiting.*|sleep\s+[0-9.]+\s*;\s*(echo|date)\b.*)\s*$',
    re.IGNORECASE,
)

REASON = (
    "Do not poll with Bash while waiting for a subagent — end the turn. The "
    "harness async notification wakes you up when the child finishes "
    '(see "How to wait for the subagent" in '
    ".claude/skills/meridian-run-plan/SKILL.md). Measured: 48 "
    'turns of "echo waiting" in a single task cost 8.14M tokens of '
    "cache_read, 23% of that task's total spend."
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
