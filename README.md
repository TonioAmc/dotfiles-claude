# dotfiles-claude

Configuración de [Claude Code](https://claude.ai/code) versionada y sincronizada
entre máquinas. La fuente de verdad es este repo: `~/.claude/settings.json` y los
scripts de `~/.local/bin/` son symlinks que apuntan acá.

**Ubicación canónica:** `~/proyectos/dotfiles-claude`

## Instalar en una máquina

```bash
git clone https://github.com/TonioAmc/dotfiles-claude.git ~/proyectos/dotfiles-claude
cd ~/proyectos/dotfiles-claude
bash install.sh
```

`install.sh` crea, según el `hostname` actual:

| Symlink | Apunta a |
|---|---|
| `~/.claude/settings.json` | `machines/<hostname>/settings.json` |
| `~/.local/bin/cc-statusline.sh` | `scripts/cc-statusline.sh` |
| `~/.local/bin/<cada hook>.sh` | `scripts/hooks/<cada hook>` |

Si no existe `machines/<hostname>/`, avisa para que crees esa carpeta con el
`settings.json` de la máquina nueva.

## Actualizar

```bash
bash pull.sh
```

Hace `git pull --ff-only` y avisa si algún `settings.json` cambió (requiere
**reiniciar Claude Code**). Los cambios en `scripts/` son symlinks → efecto inmediato.

## Estructura

```
claude/settings.json          # template base (no se symlinkea; referencia heredada)
machines/<hostname>/settings.json   # config por máquina (la que se enlaza)
scripts/cc-statusline.sh      # statusline: rama, path, modelo, contexto, dev server
scripts/hooks/                # scripts que los settings.json invocan como hooks
install.sh                    # crea los symlinks de esta máquina
pull.sh                       # actualiza + avisa
```

Cada máquina diverge en su carpeta de `machines/` (modelo, effort, hooks). Editar
`~/.claude/settings.json` edita el repo directamente (es un symlink); commit + push y
las demás máquinas lo reciben con `pull.sh`.

## Máquinas

- **noti** — laptop HP Pavilion Aero (Opus 4.8 1M, effort xhigh, hooks completos)
- **pici** — desktop MSI (Sonnet, effort high)

## Migración pendiente

La ubicación canónica es `~/proyectos` (minúscula). En máquinas donde el repo aún
viva en `~/Proyectos` (mayúscula) u otra ruta, `pull.sh` lo detecta y muestra los
pasos para migrar:

```bash
mv ~/Proyectos/dotfiles-claude ~/proyectos/dotfiles-claude
bash ~/proyectos/dotfiles-claude/install.sh
```
