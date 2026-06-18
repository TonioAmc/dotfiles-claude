#!/usr/bin/env bash
# Actualiza dotfiles-claude en el equipo actual (git pull).
# Uso local:  bash pull.sh
# Uso remoto: ssh <host> "bash ~/proyectos/dotfiles-claude/pull.sh"

set -e
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ubicacion canonica: el repo debe vivir en ~/proyectos (minuscula), junto al
# resto de proyectos. En maquinas donde todavia este en ~/Proyectos (mayuscula)
# u otra ruta, avisar al sincronizar para recordar la migracion pendiente.
if [ "$REPO_DIR" != "$HOME/proyectos/dotfiles-claude" ]; then
    echo "⚠  Este repo debería vivir en ~/proyectos/dotfiles-claude"
    echo "   Está en: $REPO_DIR"
    echo "   Migrá:   mv \"$REPO_DIR\" ~/proyectos/dotfiles-claude"
    echo "            bash ~/proyectos/dotfiles-claude/install.sh"
    echo ""
fi

prev=$(git -C "$REPO_DIR" rev-parse HEAD)
git -C "$REPO_DIR" pull --ff-only

new=$(git -C "$REPO_DIR" rev-parse HEAD)
if [ "$prev" = "$new" ]; then
    echo "Ya estaba al día."
    exit 0
fi

echo ""
echo "Cambios aplicados:"
git -C "$REPO_DIR" log --oneline "${prev}..${new}"

# Detectar si settings.json cambió → requiere reinicio de Claude Code
if git -C "$REPO_DIR" diff --name-only "${prev}..${new}" | grep -q "machines/$(hostname)/settings.json\|claude/settings.json"; then
    echo ""
    echo "  ⚠  settings.json actualizado — reiniciá Claude Code para que tome efecto."
fi

# Scripts symlinkeados: se reflejan de inmediato sin acción adicional.
echo ""
echo "Scripts actualizados en ~/.local/bin/ (symlinks — efecto inmediato)."
