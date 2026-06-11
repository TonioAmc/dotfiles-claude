#!/usr/bin/env bash
# Crea los symlinks de dotfiles-claude en el equipo actual.
# Uso: bash install.sh
# Prerequisito: el repo ya debe estar clonado (se detecta por la ubicación del script).

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_HOME="$HOME"

link() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        mv "$dst" "${dst}.bak"
        echo "  backup: ${dst}.bak"
    fi
    ln -sf "$src" "$dst"
    echo "  $dst -> $src"
}

echo "Instalando dotfiles-claude en $USER_HOME..."

link "$REPO_DIR/claude/settings.json"    "$USER_HOME/.claude/settings.json"
link "$REPO_DIR/scripts/cc-statusline.sh" "$USER_HOME/.local/bin/cc-statusline.sh"
chmod +x "$REPO_DIR/scripts/cc-statusline.sh"

echo "Listo."
