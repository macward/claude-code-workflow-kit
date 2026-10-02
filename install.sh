#!/bin/bash
set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
CLAUDE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Installed per project, never in ~/.claude/: the target is <project>/.claude/.
set_target() {
    if [ -z "${1:-}" ] || [ ! -d "$1" ]; then
        echo "Usage: ./install.sh $CMD <project-dir>" >&2
        exit 1
    fi
    TARGET_DIR="$(cd "$1" && pwd)/.claude"
    SKILLS_DIR="$TARGET_DIR/skills"
    AGENTS_DIR="$TARGET_DIR/agents"
    COMMANDS_DIR="$TARGET_DIR/commands"
    RULES_DIR="$TARGET_DIR/rules"
    TEMPLATES_DIR="$TARGET_DIR/templates"
}

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
DIM='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Helpers ─────────────────────────────────────────────────────────────────
info()  { echo -e "${BLUE}▸${NC} $1" >&2; }
ok()    { echo -e "${GREEN}✓${NC} $1" >&2; }
warn()  { echo -e "${YELLOW}⚠${NC} $1" >&2; }
err()   { echo -e "${RED}✗${NC} $1" >&2; }
dim()   { echo -e "${DIM}  $1${NC}" >&2; }

is_vibe_link() {
    local path="$1"
    if [ -L "$path" ]; then
        local real
        real="$(readlink "$path")"
        if [[ "$real" == "$CLAUDE_DIR"* ]]; then
            return 0
        fi
    fi
    return 1
}

# ─── Item collectors ─────────────────────────────────────────────────────────
get_vibe_skills() {
    [ -d "$CLAUDE_DIR/skills" ] || return 0
    for dir in "$CLAUDE_DIR"/skills/*/; do
        [ -f "$dir/SKILL.md" ] && basename "$dir"
    done
}

get_vibe_files_z() {
    local folder="$1"
    local ext="${2:-md}"
    [ -d "$CLAUDE_DIR/$folder" ] || return 0
    find "$CLAUDE_DIR/$folder" -name "*.$ext" -type f -print0 | while IFS= read -r -d '' f; do
        local rel="${f#$CLAUDE_DIR/$folder/}"
        printf '%s\0' "${rel%.$ext}"
    done
}

# ─── Generic symlink installer (defaults to .md) ─────────────────────────────
install_md_files() {
    local folder="$1"
    local dst_dir="$2"
    local ext="${3:-md}"
    local count=0

    mkdir -p "$dst_dir"

    while IFS= read -r -d '' rel; do
        local src="$CLAUDE_DIR/$folder/${rel}.${ext}"
        local dst="$dst_dir/${rel}.${ext}"
        local dst_parent display_name
        dst_parent="$(dirname "$dst")"
        display_name="$(basename "$rel")"

        mkdir -p "$dst_parent"

        if is_vibe_link "$dst"; then
            dim "$display_name (already linked)"
            count=$((count + 1))
            continue
        fi

        if [ -L "$dst" ]; then
            warn "$display_name (replacing symlink → $(readlink "$dst"))"
        fi

        if [ -e "$dst" ] && [ ! -L "$dst" ]; then
            warn "$display_name (exists — skipped, remove it manually to install symlink)"
            continue
        fi

        rm -f "$dst"
        ln -s "$src" "$dst"
        ok "$display_name"
        count=$((count + 1))
    done < <(get_vibe_files_z "$folder" "$ext")

    echo "$count"
}

uninstall_md_files() {
    local folder="$1"
    local dst_dir="$2"
    local ext="${3:-md}"
    local removed=0

    while IFS= read -r -d '' rel; do
        local dst="$dst_dir/${rel}.${ext}"
        local display_name
        display_name="$(basename "$rel")"
        if is_vibe_link "$dst"; then
            rm "$dst"
            ok "removed $display_name"
            removed=$((removed + 1))
        fi
    done < <(get_vibe_files_z "$folder" "$ext")

    echo "$removed"
}

list_md_files() {
    local folder="$1"
    local dst_dir="$2"
    local ext="${3:-md}"

    while IFS= read -r -d '' rel; do
        local dst="$dst_dir/${rel}.${ext}"
        local display_name
        display_name="$(basename "$rel")"
        if is_vibe_link "$dst"; then
            ok "$display_name ${DIM}(linked)${NC}"
        elif [ -L "$dst" ]; then
            local target
            target="$(readlink "$dst")"
            warn "$display_name ${DIM}(linked elsewhere → $target)${NC}"
        elif [ -f "$dst" ]; then
            warn "$display_name ${DIM}(copy — run install to link)${NC}"
        else
            err "$display_name ${DIM}(not installed)${NC}"
        fi
    done < <(get_vibe_files_z "$folder" "$ext")
}

# ─── Install ─────────────────────────────────────────────────────────────────
cmd_install() {
    echo -e "\n${BOLD}Installing Meridian claude assets${NC}" >&2
    echo -e "${DIM}Source: $CLAUDE_DIR${NC}" >&2
    echo -e "${DIM}Target: $TARGET_DIR${NC}\n" >&2

    mkdir -p "$SKILLS_DIR" "$AGENTS_DIR" "$COMMANDS_DIR" "$RULES_DIR" "$TEMPLATES_DIR"

    local skill_count=0
    echo -e "${BOLD}Skills${NC}" >&2
    for name in $(get_vibe_skills); do
        local src="$CLAUDE_DIR/skills/$name"
        local dst="$SKILLS_DIR/$name"
        if is_vibe_link "$dst"; then
            dim "$name (already linked)"
            skill_count=$((skill_count + 1))
            continue
        fi
        if [ -L "$dst" ]; then
            warn "$name (replacing symlink → $(readlink "$dst"))"
        fi

        if [ -e "$dst" ] && [ ! -L "$dst" ]; then
            warn "$name (exists — skipped, remove it manually to install symlink)"
            continue
        fi

        rm -f "$dst"
        ln -s "$src" "$dst"
        ok "$name"
        skill_count=$((skill_count + 1))
    done
    echo "" >&2

    echo -e "${BOLD}Agents${NC}" >&2
    local agent_count
    agent_count=$(install_md_files "agents" "$AGENTS_DIR")
    echo "" >&2

    echo -e "${BOLD}Commands${NC}" >&2
    local command_count
    command_count=$(install_md_files "commands" "$COMMANDS_DIR")
    echo "" >&2

    echo -e "${BOLD}Rules${NC}" >&2
    local rule_count
    rule_count=$(install_md_files "rules" "$RULES_DIR")
    echo "" >&2

    echo -e "${BOLD}Templates${NC}" >&2
    local template_count
    template_count=$(install_md_files "templates" "$TEMPLATES_DIR")
    echo "" >&2

    echo -e "${GREEN}${BOLD}Done.${NC} $skill_count skills, $agent_count agents, $command_count commands, $rule_count rules, $template_count templates installed." >&2
    echo "" >&2
}

# ─── Uninstall ───────────────────────────────────────────────────────────────
cmd_uninstall() {
    echo -e "\n${BOLD}Uninstalling Meridian claude assets${NC}\n" >&2

    local total=0

    echo -e "${BOLD}Skills${NC}" >&2
    local skill_removed=0
    for name in $(get_vibe_skills); do
        local dst="$SKILLS_DIR/$name"
        if is_vibe_link "$dst"; then
            rm "$dst"
            ok "removed $name"
            skill_removed=$((skill_removed + 1))
        fi
    done
    total=$((total + skill_removed))
    echo "" >&2

    echo -e "${BOLD}Agents${NC}" >&2
    local agent_removed
    agent_removed=$(uninstall_md_files "agents" "$AGENTS_DIR")
    total=$((total + agent_removed))
    echo "" >&2

    echo -e "${BOLD}Commands${NC}" >&2
    local command_removed
    command_removed=$(uninstall_md_files "commands" "$COMMANDS_DIR")
    total=$((total + command_removed))
    echo "" >&2

    echo -e "${BOLD}Rules${NC}" >&2
    local rule_removed
    rule_removed=$(uninstall_md_files "rules" "$RULES_DIR")
    total=$((total + rule_removed))
    echo "" >&2

    echo -e "${BOLD}Templates${NC}" >&2
    local template_removed
    template_removed=$(uninstall_md_files "templates" "$TEMPLATES_DIR")
    total=$((total + template_removed))
    echo "" >&2

    if [ "$total" -eq 0 ]; then
        info "Nothing to remove — no Meridian symlinks found."
    else
        echo -e "${GREEN}${BOLD}Done.${NC} Removed $total symlinks." >&2
    fi
    echo "" >&2
}

# ─── List ────────────────────────────────────────────────────────────────────
cmd_list() {
    echo -e "\n${BOLD}Meridian claude assets status${NC}\n" >&2

    echo -e "${BOLD}Skills${NC}" >&2
    for name in $(get_vibe_skills); do
        local dst="$SKILLS_DIR/$name"
        if is_vibe_link "$dst"; then
            ok "$name ${DIM}(linked)${NC}"
        elif [ -L "$dst" ]; then
            local target
            target="$(readlink "$dst")"
            warn "$name ${DIM}(linked elsewhere → $target)${NC}"
        elif [ -d "$dst" ]; then
            warn "$name ${DIM}(copy — run install to link)${NC}"
        else
            err "$name ${DIM}(not installed)${NC}"
        fi
    done

    echo "" >&2
    echo -e "${BOLD}Agents${NC}" >&2
    list_md_files "agents" "$AGENTS_DIR"

    echo "" >&2
    echo -e "${BOLD}Commands${NC}" >&2
    list_md_files "commands" "$COMMANDS_DIR"

    echo "" >&2
    echo -e "${BOLD}Rules${NC}" >&2
    list_md_files "rules" "$RULES_DIR"

    echo "" >&2
    echo -e "${BOLD}Templates${NC}" >&2
    list_md_files "templates" "$TEMPLATES_DIR"

    echo "" >&2
}

# ─── Usage ───────────────────────────────────────────────────────────────────
cmd_help() {
    echo -e "\n${BOLD}Meridian claude installer${NC}\n"
    echo "Usage: ./install.sh <command> <project-dir>"
    echo ""
    echo "Commands:"
    echo "  install     Symlink skills, agents, commands, rules, and templates to <project-dir>/.claude/"
    echo "  uninstall   Remove Meridian symlinks from <project-dir>/.claude/"
    echo "  list        Show install status of all Meridian claude items in <project-dir>"
    echo "  help        Show this message"
    echo ""
    echo "Skills are symlinked as directories (preserving internal references)."
    echo "Agents, commands, rules, and templates are symlinked as individual .md files."
    echo "Hooks are global, not per project: use ./install-hooks.sh."
    echo "Existing non-symlink files are skipped; existing symlinks may be replaced."
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────
CMD="${1:-help}"
case "$CMD" in
    install)            set_target "${2:-}"; cmd_install ;;
    uninstall|--uninstall) set_target "${2:-}"; cmd_uninstall ;;
    list)               set_target "${2:-}"; cmd_list ;;
    help|-h|--help)     cmd_help ;;
    *)
        err "Unknown command: $1"
        cmd_help
        exit 1
        ;;
esac
