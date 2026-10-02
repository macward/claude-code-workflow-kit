#!/bin/bash
# SessionEnd hook: triggers the Memory v2 distiller when a session closes.
#
# The event is SessionEnd, NOT Stop: Stop fires once per turn ("when Claude
# finishes responding"), so mounted there this would launch a headless session
# after every response. See skills/meridian-autosave/SKILL.md.

# Anti-recursion guard: the `claude -p` below is a session that, when it ends,
# fires its OWN SessionEnd. The env var is inherited (the docs guarantee it:
# "Handlers run in the current directory with Claude Code's environment"), so
# the child session's hook gets in here and exits without re-arming anything.
[ -n "$MERIDIAN_AUTOSAVE_HOOK" ] && exit 0
export MERIDIAN_AUTOSAVE_HOOK=1

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"

# The hook JSON (session_id, transcript_path, cwd, reason) arrives on stdin and
# is the ONLY source of the transcript: the headless session below starts empty
# and has no way to see the conversation that just closed. For 104 runs this
# stdin was discarded, so Phase 1 always reported "Captured: 0" — the whole
# memory system ran empty. Do not throw it away again.
HOOK_JSON=$(cat)

# The digest is injected into the prompt via argv instead of being passed as a
# path because --allowedTools does not include Read (and must not: it is the
# hard boundary of the unattended run). Having the transcript travel in the
# prompt keeps the tool surface purely mem_*.
if command -v python3 >/dev/null 2>&1; then
    PROMPT=$(MERIDIAN_HOOK_JSON="$HOOK_JSON" python3 -c '
import json, os, sys

# Digest ceiling in characters. The raw transcript can be megabytes;
# what goes in is only turn text (no tool_use or tool_result), and even so
# a long session exceeds it.
MAX_CHARS = 120000

try:
    hook = json.loads(os.environ.get("MERIDIAN_HOOK_JSON", ""))
except ValueError:
    sys.exit(3)

cwd = hook.get("cwd") or os.getcwd()

# The project comes from the nearest CLAUDE.md going upward. It is resolved
# here and not in the skill for the same reason as the digest: the headless
# session cannot read files. Without a project there is nothing the skill can
# do, so the hook does not launch it (exit 3) — that also silences the noise
# from sessions opened outside a Meridian project.
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
    # Both ends are kept: architecture decisions tend to land early and
    # corrections late. Cutting only the tail would lose one or the other.
    head = int(MAX_CHARS * 0.3)
    digest = digest[:head] + "\n\n[... transcript elided for budget ...]\n\n" + digest[head - MAX_CHARS:]

prompt = "/meridian-autosave --project " + project + "\n\n"
if digest:
    prompt += (
        "Headless run from the SessionEnd hook. Below, inside <transcript>, is the "
        "conversation of the session that just closed: you did NOT take part in it. "
        "It is the input for Phase 1 (capture) and the only one there is — do not look for more context.\n\n"
        "<transcript>\n" + digest + "\n</transcript>\n"
    )
else:
    prompt += (
        "Headless run from the SessionEnd hook. No transcript is available "
        "(empty or unreadable): skip Phase 1 and run only Phase 2 (backlog distillation).\n"
    )
sys.stdout.write(prompt)
')
    case $? in
        3)
            # cwd outside a Meridian project, or unreadable hook JSON.
            exit 0
            ;;
        0) ;;
        *)
            echo "[autosave] could not build the prompt from the hook JSON" >&2
            exit 0
            ;;
    esac
else
    # Without python3 no digest is possible. It degrades to the old run (Phase 2
    # only) instead of not running, but loudly: Phase 1 has no safety net.
    echo "[autosave] no python3: running without transcript, capture is left undone" >&2
    PROMPT='/meridian-autosave'
fi

# --allowedTools is the hard boundary of the unattended run, not a
# convention: it enumerates exactly the mem_* surface the skill uses, so it
# cannot touch tasks, docs or git even if the model tried.
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

# Time ceiling. Without this, a stuck run (a contradiction judgment that does not
# converge, a retry in a loop) runs without limit against the production
# account, unattended and with nobody watching. Overridable for debugging.
TIMEOUT_SECONDS="${MERIDIAN_AUTOSAVE_TIMEOUT:-1800}"

# Detach from the parent process. SessionEnd does not block the close ("If a SessionEnd
# hook is slow, Claude Code will complete session termination independently") and
# distillation takes minutes: tied to the parent, the teardown would take it
# down with it. A new session is needed, not just ignoring SIGHUP.
#
# Neither `setsid` nor `timeout` exists on macOS (both are from util-linux), so
# the main path is a Python shim that does both: os.setsid() for the new
# session and a wait with timeout for the ceiling. Without this branch the hook
# would die with "command not found" on the development machine, silently.
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
    print(f"[autosave] killed after {timeout}s without finishing", file=sys.stderr)
    sys.exit(124)
' "$TIMEOUT_SECONDS")
elif command -v setsid >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    LAUNCH=(setsid nohup timeout "$TIMEOUT_SECONDS")
else
    # Last resort: no session of its own and no ceiling, but at least immune to SIGHUP.
    echo "[autosave] no python3 nor setsid+timeout: running without a time ceiling" >&2
    LAUNCH=(nohup)
fi

# stdin to /dev/null: the hook JSON was already consumed by this script and
# travels in the prompt; the child must not stay hanging off the pipe.
"${LAUNCH[@]}" "${CMD[@]}" < /dev/null >> "$LOG_DIR/meridian-autosave.log" 2>&1 &

# Explicit: the background job state must not leak out as the hook state.
exit 0
