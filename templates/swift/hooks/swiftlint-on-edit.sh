#!/usr/bin/env bash
# PostToolUse (Edit|MultiEdit|Write): lints the Swift file Claude just edited and hands the
# violations back to Claude as additionalContext. Feedback, not a block: the edit already
# happened, so it always exits 0.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

f=$(jq -r '.tool_input.file_path // empty')
[[ "$f" == *.swift ]] || exit 0

if ! command -v swiftlint >/dev/null; then
  echo "swiftlint-on-edit: swiftlint not found, skipping lint (brew install swiftlint)" >&2
  exit 0
fi

out=$(swiftlint lint --quiet "$f")
[[ -n "$out" ]] || exit 0

jq -n --arg ctx "$out" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
exit 0
