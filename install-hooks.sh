#!/bin/bash
set -euo pipefail

# Hooks are the exception to "nothing global": they are installed in ~/.claude/hooks/,
# not per project. It only creates the symlinks; registering them in ~/.claude/settings.json
# is manual. The symlink inherits the target mode, so the executable bit lives
# in the repo file.

SRC_DIR="$(cd "$(dirname "$0")" && pwd)/hooks"
DST_DIR="$HOME/.claude/hooks"

case "${1:-}" in
    install)
        mkdir -p "$DST_DIR"
        for src in "$SRC_DIR"/*.sh; do
            dst="$DST_DIR/$(basename "$src")"
            if [ -e "$dst" ] && [ ! -L "$dst" ]; then
                echo "⚠ $(basename "$src") (exists — skipped, remove it manually to install symlink)" >&2
                continue
            fi
            ln -sfn "$src" "$dst"
            echo "✓ $(basename "$src")" >&2
        done
        ;;
    uninstall)
        for src in "$SRC_DIR"/*.sh; do
            dst="$DST_DIR/$(basename "$src")"
            if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
                rm "$dst"
                echo "✓ removed $(basename "$src")" >&2
            fi
        done
        ;;
    *)
        echo "Usage: ./install-hooks.sh install|uninstall" >&2
        exit 1
        ;;
esac
