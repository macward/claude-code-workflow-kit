#!/usr/bin/env bash
# PostToolUse (Edit|MultiEdit|Write): runs `ruff check` on the Python file Claude just edited
# and hands the violations back to Claude as additionalContext. Feedback, not a block: the
# edit already happened, so it always exits 0.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

f=$(jq -r '.tool_input.file_path // empty')
[[ "$f" == *.py ]] || exit 0

if ! command -v ruff >/dev/null; then
  echo "ruff-check-on-edit: ruff not found, skipping lint (brew install ruff)" >&2
  exit 0
fi

out=$(ruff check --quiet --output-format concise "$f")
[[ -n "$out" ]] || exit 0

jq -n --arg ctx "$out" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
exit 0
