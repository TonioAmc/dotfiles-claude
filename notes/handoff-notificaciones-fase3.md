# Handoff — Notificaciones de Claude Code (Fase 3)

Continuación del rediseño de las notificaciones de Claude Code en Hyprland.
Fases 1 y 2 hechas y commiteadas (`1fd0dec` en dotfiles-claude). Esto es lo que falta.

## Arrancar esta sesión
1. Leé este doc y la memoria `reference_claude_notificaciones`.
2. Confirmá que el hook está activo (settings.json se recarga al iniciar Claude): debería
   llegar la notif rica de swaync, no la genérica de kitty.

---

## Estado actual (hecho — NO rehacer)

- **swaync** reemplazó a **mako** como daemon de notificaciones (activo, `exec-once = swaync`).
- Notif rica de Claude vía hook `Notification` → `claude-notify.sh` (+ `claude-notify-action.sh`).
- `preferredNotifChannel: "notifications_disabled"` apaga la notif nativa de kitty (sin duplicados).
- Diseño Catppuccin Mocha + ícono sunburst de Claude (`~/.local/share/icons/claude/`).
- Persistencia arreglada: `timeout-critical: 20` (antes 0 = se quedaban pegadas).
- **Saltar a la consola**: click en la notif o `Super+G` → enfoca la terminal de esa sesión.
- **Ampliar panel**: `Super+N`. **Descartar todas**: `Super+Shift+N`.
- Diferenciación por urgencia: permiso = borde rosa (critical), idle = normal.
- **Foco-aware**: no notifica si la terminal de Claude ya está enfocada.

### Archivos
| Qué | Dónde |
|---|---|
| Config swaync | `~/.config/swaync/config.json`, `style.css` |
| Hook (parsea, calcula ventana, lanza listener) | `dotfiles-claude/scripts/hooks/claude-notify.sh` |
| Listener (notif + acción de salto) | `dotfiles-claude/scripts/hooks/claude-notify-action.sh` |
| settings.json (hook + preferredNotifChannel) | `dotfiles-claude/machines/noti/settings.json` |
| Autostart + binds | `~/.config/hypr/hyprland.conf` (`exec-once` ~L64, binds ~L303-305) |
| Ícono | `~/.local/share/icons/claude/claude-{48,64}.png` |

---

## Requerimientos Fase 3

### 1. Expandir la notif con el extracto — ❌ DESCARTADO (2026-06-21)
Decisión del usuario: en vez de construir el "expandir", se reasignó el atajo de **saltar a
la consola** de `Super+G` → **`Super+Space`** (más cómodo). Razón: saltar a la ventana real
de Claude ya cubre el caso (ahí se ve todo con formato y se responde con el teclado normal),
y la parte de aprobar/inyectar teclas desde la notif era frágil.

Cambio aplicado: `~/.config/hypr/hyprland.conf` (bind `$mainMod, SPACE` → `swaync-client
--action 0`); `Super+G` quitado. Memoria `reference_claude_notificaciones` actualizada.

Investigación que quedó hecha por si se retoma: el extracto del último turno se saca del
`transcript_path` con `jq` — último mensaje genuino del usuario (los `type:"user"` con
`tool_result` NO cuentan) y se concatenan los bloques `text` de los `assistant` posteriores.
Probado en vivo. El vehículo para mostrarlo sin construir nada nuevo sería re-emitir la notif
con el extracto como cuerpo (swaync no expande contenido dinámico nativo; sin scroll).

### 2. Revisar el diseño para que combine con el sistema visual — ✅ HECHO (2026-06-21)
swaync `style.css` reskineado al tema del sistema (rojo sangre/carmesí sobre negro, ver
memoria `reference_paleta_tema`): notif normal borde carmesí `#c0392b`, permiso (critical)
borde coral `#ff6b6b` + glow, fondo `#120409`, texto `#f0d0d0`. Reemplaza el verde `#00ff99`
heredado de mako. Verificado con captura. **Fase 3 completa.**
- Sistema: **Catppuccin Mocha**, Hyprland, kitty, rofi (tema `propuesta-2`), wallpaper
  `PsychoGoremanTriptych` (rojizo/oscuro). Mirar colores de `~/.config/kitty/` y el bloque
  `decoration`/`general` de `hyprland.conf` para alinear acentos.
- El `style.css` actual usa borde **verde `#00ff99`** heredado de la config de mako —
  evaluar si combina o cambiarlo por el acento real del sistema (¿el terracota de Claude
  `#d97757`? ¿un color del wallpaper?). Verificar con `grim` + recorte (ver nota de escala).

---

## Notas técnicas (descubrimientos de la sesión anterior — ahorran reinvestigar)

- Claude Code emite la notif nativa por **OSC 99** → kitty la pasa a dbus con
  `app-name="kitty"`, summary `"Claude Code"`. Por eso las reglas mako `[app-name="Claude Code"]`
  nunca funcionaron.
- Payload del hook `Notification`: `cwd`, `notification_type`
  (`permission_prompt|idle_prompt|elicitation_dialog|auth_success|...`), `message`,
  `session_id`, `transcript_path`.
- `swaync-client --action [idx]` invoca la acción de la **última** notif. El nombre
  `"default"` NO cuenta como botón índice 0 (es el click-en-cuerpo); usar nombre propio
  (`jump`). Índice 0 = primer botón nombrado.
- `notify-send --action` implica `--wait` (bloquea) → por eso el listener corre desacoplado
  con `setsid`.
- **Mapeo ventana**: recorrer ancestros (`/proc/PID/stat`, PPID es el 2º campo tras `') '`)
  y cruzar con `hyprctl clients -j` (`pid`→`address`). Foco-aware: si `activewindow.pid`
  está en los ancestros, no notificar.
- **Captura con escala fraccionaria**: `hyprctl` da coords **lógicas**, `grim` captura
  **físico**. Monitor a escala **1.5** → multiplicar coords ×1.5 para recortar con `magick`.
- Hyprland **0.55.2**: `layerrule blur` con sintaxis vieja da `invalid field blur: missing
  a value`. El blur detrás de la notif quedó SIN implementar (sintaxis cambió; revisar wiki).
- Cambios en `settings.json` requieren **reiniciar** Claude Code.
- Revertir a mako: `swaync`→`mako` en hyprland.conf, quitar hook `Notification` y
  `preferredNotifChannel`. La config de mako sigue intacta en `~/.config/mako/config`.
