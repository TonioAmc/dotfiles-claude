#!/usr/bin/env bash
# Crea los symlinks de dotfiles-claude en el equipo actual.
# Uso: bash install.sh
# Prerequisito: el repo ya debe estar clonado (se detecta por la ubicación del script).

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_HOME="$HOME"
MACHINE="$(hostname)"
MACHINE_DIR="$REPO_DIR/machines/$MACHINE"

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

echo "Instalando dotfiles-claude en $USER_HOME (máquina: $MACHINE)..."

# Config por máquina
if [ -d "$MACHINE_DIR" ]; then
    link "$MACHINE_DIR/settings.json" "$USER_HOME/.claude/settings.json"
else
    echo "  AVISO: no hay config para '$MACHINE' en machines/. Creá machines/$MACHINE/settings.json"
fi

# Scripts compartidos
link "$REPO_DIR/scripts/cc-statusline.sh" "$USER_HOME/.local/bin/cc-statusline.sh"
chmod +x "$REPO_DIR/scripts/cc-statusline.sh"

# Scripts de hooks (los settings.json los referencian por nombre en ~/.local/bin/)
for hook in "$REPO_DIR"/scripts/hooks/*; do
    [ -e "$hook" ] || continue
    link "$hook" "$USER_HOME/.local/bin/$(basename "$hook")"
    chmod +x "$hook"
done

echo "Listo."
