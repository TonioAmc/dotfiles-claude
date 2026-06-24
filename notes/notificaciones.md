# Sistema de notificaciones de Claude Code

> **Estado: Fase 7 cerrada (2026-06-24, commit `d845997`).** Este doc es el resumen
> vivo del subsistema. El detalle completo (gotchas, decisiones, historia de las
> fases 1-7) vive en la memoria `reference_claude_notificaciones`
> (`~/.claude/projects/-home-antolin/memory/reference_claude_notificaciones.md`).

Notificación de escritorio cuando Claude **espera respuesta o pide permiso**, vía
**swaync** (reemplazó a mako). Es **foco-aware**: no molesta si la terminal de la
sesión que avisa ya está enfocada.

## Archivos (versionados, en este repo)

| Script (`scripts/hooks/`) | Rol |
|---|---|
| `claude-notify.sh` | Hook `Notification` (en `machines/noti/settings.json`). Parsea el payload, ubica la ventana de la sesión, arma el cuerpo enriquecido y el título por tipo (🔐 permiso · ❓ pregunta · 📋 plan · ⏳ idle · ✓ auth), y lanza el listener. |
| `claude-notify-action.sh` | Listener: emite la notif (`notify-send`), coalescing por sesión (una notif nueva reemplaza la vieja de la misma sesión), registra `address⇥id` en `$XDG_RUNTIME_DIR/claude-notify/`, timeout 12s. |
| `claude-notify-jump.sh` | Disparado por los binds de Hyprland. **jump** (Super+Space): salta a la sesión que espera + cierra esa notif; si no hay ninguna viva, abre el panel. **dismiss** (`--dismiss`, Super+Alt+Space): cierra la notif de arriba sin saltar. |

Sólo `claude-notify.sh` es un hook que invoca `settings.json`; los otros dos son
*glue* de escritorio (uno lo lanza `claude-notify.sh`, el otro los binds de Hyprland).
Viven acá igual porque están acoplados entre sí e `install.sh` los symlinkea juntos.

## Config local (NO versionada)

- `~/.config/swaync/{config.json,style.css}` — tema rojo sangre/carmesí sobre negro
  (ver memoria `reference_paleta_tema`), diseño compacto, `notification-grouping: false`
  (el panel lista las notifs en vez de apilarlas).
- `~/.config/hypr/hyprland.conf` — los binds (`Super+Space`, `Super+Alt+Space`,
  `Super+N`, `Super+Shift+N`). En otra máquina hay que replicarlos a mano.

## Atajos

- **Super+Space** — saltar a la sesión que espera (más nueva primero, repetir para
  ciclar); sin notif viva, abre el panel.
- **Super+Alt+Space** — descartar la notif de arriba sin saltar.
- **Super+N** — panel · **Super+Shift+N** — descartar todas.

## Estado final (Fase 7)

Notifs **no persistentes** (expiran a 12s y pasan al panel), urgencia **normal** para
todo (suaves, no atraviesan No Molestar), diseño compacto. El overview de hyprexpo
muestra las notifs y el panel una sola vez encima del grid (fix del lado del plugin
hyprexpo, no de acá).
