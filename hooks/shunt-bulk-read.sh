#!/usr/bin/env python3
"""PreToolUse hook (matchers: Read, Bash): blocks the full read of a large
file and redirects it to the `bulk-reader` subagent, which reads it in a cheap
context and returns a summary anchored to `path:line`.

It is the local version of the "check-file-size" that Spotify mounted on Portal
(engineering.atspotify.com, 2026-09): same mechanism — intercept the read
and delegate it to a cheap model — but delegating to a Haiku subagent of the
harness itself instead of a remote mode, so there is no infra or API keys
involved.

What is blocked:
  - `Read` of a text file with more than THRESHOLD lines and no `limit`
    (or with a `limit` above the threshold).
  - Bare `cat`/`less`/`more` on such a file in Bash — the same
    hole as the article's `check-bash-read` hook. A `cat` with a pipe,
    redirection or range (`head`, `sed -n`, `grep`) is left alone.

What is NOT blocked, on purpose:
  - Reads with bounded `offset`/`limit`. That is the way out for editing (the
    worker's summary does not replace seeing the real fragment) and it is also
    what lets `bulk-reader` itself do its job in chunks without
    recursively running into this hook.
  - Binaries, images, PDFs and notebooks: `Read` does something else there.

Env:
  CLAUDE_BULK_READ_THRESHOLD  threshold in lines (default 350)
  CLAUDE_BULK_READ_OFF=1      disables the hook entirely

Global (not per-project): the cost of reading a 3,000-line file is the
same in any repo.
"""
import json
import os
import re
import shlex
import sys

DEFAULT_THRESHOLD = 350

# Extensions where `Read` does not return plain text (images, PDF, notebooks)
# or where counting lines means nothing.
BINARY_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".ico",
    ".pdf", ".ipynb",
    ".zip", ".gz", ".tar", ".whl", ".so", ".dylib", ".o", ".a",
    ".mp4", ".mov", ".mp3", ".wav", ".woff", ".woff2", ".ttf",
}

# Bare `cat file` / `less file`: a single argument, no flags, no
# pipe or redirection. Anything more complex is already bounding the output.
BARE_CAT = re.compile(r"^\s*(cat|less|more|bat)\s+([^\s|<>;&]+)\s*$")


def threshold() -> int:
    try:
        return max(1, int(os.environ.get("CLAUDE_BULK_READ_THRESHOLD", "")))
    except ValueError:
        return DEFAULT_THRESHOLD


def count_lines(path: str, cap: int) -> int:
    """Count lines, stopping at `cap`; return -1 if the file is not text."""
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
        f"{path} has ~{lines} lines (threshold: {limit}). Do not read it whole — "
        "delegate it: Agent(subagent_type=\"bulk-reader\") with the specific "
        "question you want answered and the file path. The worker reads it "
        "in a cheap context and returns a summary with `path:line` "
        "anchors.\n"
        "Legitimate exceptions, without delegating: read the fragment you need "
        f"with offset/limit (limit <= {limit}) — it is the right thing before "
        "editing, because the worker's summary does not include the literal code."
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

    # A read already bounded below the threshold is exactly what we want
    # to let through: we do not touch it.
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
