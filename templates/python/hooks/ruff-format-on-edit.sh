#!/usr/bin/env bash
# PostToolUse (Edit|MultiEdit|Write): runs `ruff format` on the Python file Claude just edited.
# ruff reads its settings from pyproject.toml. Silent when it works; always exits 0.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

f=$(jq -r '.tool_input.file_path // empty')
[[ "$f" == *.py ]] || exit 0

if ! command -v ruff >/dev/null; then
  echo "ruff-format-on-edit: ruff not found, skipping format (brew install ruff)" >&2
  exit 0
fi

ruff format --quiet "$f"
exit 0
