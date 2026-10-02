#!/bin/bash
set -euo pipefail

# Los hooks son la excepción a "nada global": se instalan en ~/.claude/hooks/,
# no por proyecto. Solo crea los symlinks; registrarlos en ~/.claude/settings.json
# es manual. El symlink hereda el modo del target, así que el bit ejecutable vive
# en el archivo del repo.

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
