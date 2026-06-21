# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Repo de dotfiles que versiona la configuración de **Claude Code** y la sincroniza
entre varias máquinas vía symlinks. La fuente de verdad vive acá (en git); lo que
hay en `~/.claude/` y `~/.local/bin/` son enlaces simbólicos a este repo.

> Este repo está bajo `/home/antolin`, así que al trabajar acá también aplica el
> `CLAUDE.md` global del home (entorno: CachyOS/Hyprland/fish/kitty). Este archivo
> cubre **solo** lo específico del repo; no repite lo global.

## Ubicación canónica

El repo debe vivir en **`~/proyectos/dotfiles-claude`** (minúscula), junto al resto
de proyectos. `pull.sh` detecta si está en otra ruta (ej. `~/Proyectos` mayúscula,
pendiente de migrar en alguna máquina) e imprime los pasos de migración al sincronizar.

## Comandos

```bash
bash install.sh                       # instala los symlinks en la máquina actual (por hostname)
bash pull.sh                          # git pull --ff-only + avisos (reinicio / migración)

# Validar antes de commitear (no hay build ni suite de tests):
jq . machines/$(hostname)/settings.json   # settings.json válido
bash -n pull.sh install.sh                # sintaxis de los scripts
bash -n scripts/cc-statusline.sh

# Probar la statusline manualmente (recibe JSON por stdin, imprime 1-2 líneas):
echo '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Opus 4.8"},"effort":{"level":"xhigh"}}' | scripts/cc-statusline.sh
```

## Arquitectura

**Config por máquina.** `install.sh` autodetecta su ubicación (`REPO_DIR` relativo,
por eso el repo se puede mover sin romper nada) y crea los symlinks:

- `machines/$(hostname)/settings.json` → `~/.claude/settings.json`
- `scripts/cc-statusline.sh` → `~/.local/bin/cc-statusline.sh`
- cada archivo de `scripts/hooks/` → `~/.local/bin/<nombre>` (uno por uno)

**Scripts de hooks.** Los `settings.json` invocan hooks por nombre en `~/.local/bin/`
(`hmail-hook.sh`, `claude-inhibit-{start,stop}.sh`, `claude-edit-snap.sh`,
`disable-claude-mcps.py`). Esos scripts viven en `scripts/hooks/` y se symlinkean a
`~/.local/bin/`, así una máquina nueva no queda con hooks que apuntan a archivos
inexistentes. Son **compartidos** entre máquinas; cada `settings.json` decide cuáles
activa (p. ej. `pici` usa un subconjunto). `claude-edit-snap.sh` tiene paths
`/home/antolin/...` hardcodeados — portable solo entre máquinas con el mismo usuario.

Cada host tiene su carpeta en `machines/` con un `settings.json` propio, así divergen
sin pisarse: p. ej. `noti` (laptop) usa `opus[1m]` + effort `xhigh` + todos los hooks;
`pici` (MSI) usa `sonnet` + effort `high` + un subconjunto de hooks. **Agregar una
máquina** = crear `machines/<nuevo-hostname>/settings.json` y correr `install.sh` ahí.

**Editar la config real.** Como `~/.claude/settings.json` es un symlink al repo,
editar ese archivo (o `machines/<hostname>/settings.json` directo) es lo mismo: el
cambio queda versionado. Tras editar → commit + push; las otras máquinas lo reciben
con `pull.sh`.

**Flujo git.** Trabajo directo sobre `main`, `pull --ff-only`, sin ramas ni PRs (es
config personal de un solo usuario). `pull.sh` avisa cuando `settings.json` cambió en
un pull: **los cambios de `settings.json` (hooks, model, effort) requieren reiniciar
Claude Code**; los de `scripts/` (symlinkeados) tienen efecto inmediato.

**`scripts/cc-statusline.sh`** es lo más sustancial del repo. Lee JSON de Claude Code
por stdin e imprime la statusline. Detalles no obvios al modificarlo:
- Usa `|` como separador en el `jq` (no tab/`@tsv`) porque los tabs colapsan cuando
  un campo es `null` y desplazan todas las columnas.
- Detecta **worktrees** (separa nombre del repo del sufijo del worktree) y muestra la
  rama + dirty flag.
- Detecta **dev servers** del worktree actual escaneando sockets `LISTEN` (`ss`) cuyo
  proceso tiene el `cwd` dentro del toplevel git. Filtra por línea de comando
  (Django/vite/next/uvicorn/...): **para soportar otro framework, agregar su patrón**
  a la lista del `case "$sp_cmd"`.
- Resuelve el **ancho de terminal** en cascada (Claude Code no pasa `COLUMNS` y el
  script corre sin TTY): kitty remote-control → "pts-walk" subiendo el árbol de
  procesos hasta el de Claude Code para leer `stty size` → `COLUMNS`/`tput`/`200`.
- Umbrales de color: contexto `13%`/`25%`, rate-limit `50%`/`80%`.

## Gotchas

- `install.sh` enlaza `machines/<hostname>/`, **no** `claude/settings.json`. Este
  último es un template base que hoy no se symlinkea (solo lo referencia el hook
  `Stop` de `pici`); no es la config activa de ninguna máquina.
- Los scripts emiten texto en español con acentos y símbolos (`⚠`, `🌐`): mantener
  UTF-8, no degradar a ASCII.
