# Handoff — Notificaciones de Claude Code (Fase 4)

> **ESTADO: COMPLETADO (2026-06-21).** Pendiente 1 → "Permitir aquí" eliminado (se quitó
> la inyección de teclas; el usuario prefirió aprobar desde la TUI real). Pendiente 2 →
> cuerpo enriquecido: idle = extracto del transcript, permiso = herramienta+comando leídos
> del diálogo de la TUI vía `get-text` (el tool_use pendiente NO está en el transcript al
> notificar). Detalle en memoria `reference_claude_notificaciones`. Lo de abajo es histórico.

Continuación del rediseño de las notificaciones de Claude Code en Hyprland.
Fases 1-3 hechas. Esto es lo que falta (lo pidió el usuario para un chat nuevo).

## Arrancar esta sesión
1. Leé este doc y la memoria `reference_claude_notificaciones`. Para colores, la memoria
   `reference_paleta_tema` (tema del sistema: rojo sangre/carmesí sobre negro).
2. Confirmá que el hook está activo: al pedir permiso debería llegar la notif rica de swaync
   (borde coral en permisos, carmesí en "terminé"), no la genérica de kitty.

---

## Estado actual (hecho — NO rehacer)

- **swaync** como daemon. Notif rica vía hook `Notification` → `claude-notify.sh` (+ listener
  `claude-notify-action.sh`). Muestra proyecto + motivo + ícono + urgencia; es foco-aware.
- **Atajos**: `Super+Space` salta a la consola de la última notif (reasignado desde `Super+G`).
  `Super+N` panel · `Super+Shift+N` descartar.
- **Reskin al tema (Fase 3)**: `style.css` en rojo sangre/carmesí sobre negro. Notif normal
  borde carmesí `#c0392b`, permiso (critical) borde coral `#ff6b6b` + glow, fondo `#120409`,
  texto `#f0d0d0`. Reemplazó el verde `#00ff99` heredado de mako.
- Idea de "expandir la notif con el extracto" (vieja Fase 3) → **descartada** por el usuario.

### Archivos
| Qué | Dónde |
|---|---|
| Hook (parsea payload, calcula ventana, lanza listener) | `dotfiles-claude/scripts/hooks/claude-notify.sh` → symlink `~/.local/bin/` |
| Listener (notif + acciones jump/allow) | `dotfiles-claude/scripts/hooks/claude-notify-action.sh` → symlink `~/.local/bin/` |
| Config swaync (NO versionada, local) | `~/.config/swaync/config.json`, `style.css` |
| settings.json (hook + preferredNotifChannel) | `dotfiles-claude/machines/noti/settings.json` |
| Binds + autostart | `~/.config/hypr/hyprland.conf` (`exec-once` swaync ~L64, binds notif ~L302-305) |
| Ícono | `~/.local/share/icons/claude/claude-{48,64}.png` |

---

## Pendiente 1 — el botón "Permitir aquí" no hace nada (placeholder)

**Estado hoy:** en `claude-notify-action.sh`, el botón "Permitir aquí" (acción `allow`, sólo
aparece en `permission_prompt`) cae en el mismo caso que `jump`: **únicamente enfoca la ventana
de Claude, NO aprueba el permiso**. El comentario lo marca como placeholder ("el envío de tecla
de aprobación se calibra con un caso real").

**Qué quiere el usuario:** que ese botón haga algo real, o ajustarlo. Decidir entre:
- (a) **Implementarlo de verdad**: aprobar el permiso sin tener que ir a la consola, inyectando
  la tecla de aprobación en la TUI de Claude de esa sesión.
- (b) **Quitarlo** si no vale la pena (queda sólo "Ir a la sesión").

**Para implementarlo (a) — investigar primero:**
- Cómo se aprueba un `permission_prompt` en la TUI de Claude Code: capturar un permiso real y
  ver las teclas (probablemente `1`/`2`/`3` o flechas + Enter para elegir "Yes").
- Inyección vía **kitty remote control**: `kitten @ send-text` o `send-key` apuntando a la
  ventana/socket de la sesión correcta. El listener ya calcula `CN_ADDR` (address Hyprland de
  la kitty de la sesión); falta mapear address → socket/match de kitty para el `send-text`.
- **Gotchas de input**: ver memoria `reference_pc_control_input_bug` (ahí era Electron/Obsidian;
  acá es terminal kitty, debería ser más directo por remote control). Y `reference_kitty_paneles`
  para sintaxis de `kitten @`.
- **Riesgo a cuidar**: no aprobar la sesión equivocada si hay varias kitty con Claude abiertas.
  El `--action 0` de swaync actúa sobre la ÚLTIMA notif; verificar que CN_ADDR corresponde.

---

## Pendiente 2 — contenido de la notif más rico de información

**Estado hoy:** el cuerpo es pobre. `claude-notify.sh` arma `body` = el campo `message` del
payload, o un fallback genérico por tipo ("Necesito tu permiso para continuar", "Terminé y te
espero", etc.). El usuario dice que "definitivamente no le gusta cómo está".

**A investigar / hacer:**
- **Qué trae realmente el payload** en cada `notification_type`. Loguear payloads reales a un
  archivo (agregar un `tee` temporal en `claude-notify.sh`) y disparar permisos/idle de verdad.
  Campos conocidos: `cwd`, `notification_type`, `message`, `session_id`, `transcript_path`.
- **Enriquecer según el tipo:**
  - `permission_prompt`: mostrar QUÉ se pide aprobar — la herramienta y el comando/argumento
    (ej. "Bash: rm -rf …" o "Edit: settings.json"). Ver si `message` ya lo trae; si no, sacarlo
    del último `tool_use` del `transcript_path`.
  - `idle_prompt`: un extracto de lo último que hizo/dijo Claude (último turno).
- **Parseo del transcript (ya probado en Fase 3, reusar):** el `.jsonl` tiene objetos con
  `type` ("user"/"assistant"/…) y `.message.content[]` (bloques `text`/`thinking`/`tool_use`/
  `tool_result`). Los `type:"user"` con sólo `tool_result` NO son mensajes genuinos del usuario.
  jq para el último turno de Claude:
  ```bash
  jq -rs '(to_entries | map(select(.value.type=="user" and (
      (.value.message.content|type=="string") or
      (.value.message.content|(type=="array" and (map(.type)|any(.=="text"))))))) | last | .key) as $i
    | .[$i+1:] | map(select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text)
    | join("\n\n")' "$TRANSCRIPT"
  ```
  Para el último `tool_use` (lo que está por aprobarse): filtrar el último bloque `tool_use` y
  leer `.name` + `.input`.
- **Límites de swaync**: el body NO tiene scroll y se trunca; recortar a unas pocas líneas y
  escapar markup pango (`&`, `<`, `>`). Soporta markup pango (negrita, color) en el body.

---

## Notas técnicas (de fases anteriores — ahorran reinvestigar)

- Claude emite la notif nativa por **OSC 99** → kitty la pasa a dbus con `app-name="kitty"`,
  summary `"Claude Code"`. Se apaga con `preferredNotifChannel: "notifications_disabled"`.
- `swaync-client --action 0` invoca la acción de la **última** notif. El nombre `"default"` NO
  es botón índice 0 (es el click-en-cuerpo); índice 0 = primer botón nombrado (`jump`).
- `notify-send --action` implica `--wait` (bloquea) → el listener corre desacoplado con `setsid`.
- **Mapeo ventana**: recorrer ancestros (`/proc/PID/stat`, PPID = 2º campo tras `') '`) y cruzar
  con `hyprctl clients -j` (`pid`→`address`). Foco-aware: si `activewindow.pid` está en los
  ancestros, no notificar.
- **Probar notifs sin Claude real**: `setsid notify-send -a Claude -i ICON -u critical "Claude ·
  home" "cuerpo" --action="jump=Ir a la sesión" --action="allow=Permitir aquí" &`. Para captura:
  `grim` + recorte con `magick` (monitor 1920×1200; la notif sale arriba-centro).
- Cambios en `settings.json` requieren reiniciar Claude Code; los de `scripts/` (symlinkeados) y
  `~/.config/` son inmediatos (swaync: `swaync-client --reload-css` / `--reload-config`).
- La config de swaync (`~/.config/swaync/`) y `hyprland.conf` NO están versionadas (locales).
