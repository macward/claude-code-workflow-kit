#!/usr/bin/env bash
# PreToolUse (Bash): refuses `rm -rf /`, `git push -f/--force` and `git reset --hard` before
# they run. Exit 2 is how Claude Code blocks a tool call; the reason goes to stderr.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

cmd=$(jq -r '.tool_input.command // empty')

if grep -qE 'rm -rf /( |$)|git push( .*)? (-f|--force)|git reset --hard' <<<"$cmd"; then
  echo "Blocked by project hook: dangerous command (rm -rf /, git push --force, git reset --hard)" >&2
  exit 2
fi
exit 0
