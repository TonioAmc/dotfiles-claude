#!/usr/bin/env bash
# Hook Notification de Claude Code: emite una notificación de escritorio rica
# (proyecto, motivo, ícono, urgencia) en reemplazo de la notif nativa de kitty.
# Calcula la ventana de Hyprland de ESTA sesión para poder "saltar a la consola".
# Lanza un listener desacoplado (claude-notify-action.sh) que espera el click/acción.
# Lee el payload JSON por stdin. Doc: memoria reference_claude_notificaciones.
set -u

ICON="$HOME/.local/share/icons/claude/claude-64.png"

payload="$(cat)"
get() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

cwd="$(get '.cwd')"
ntype="$(get '.notification_type')"
message="$(get '.message')"
proj="$(basename "${cwd:-$HOME}")"
[ "$proj" = "antolin" ] && proj="home"

# ---------- Recorrer ancestros: detectar foco + ubicar la ventana de Claude ----------
get_ppid() {
  local stat
  stat="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
  stat="${stat##*) }"            # descarta 'pid (comm) ' (comm puede traer espacios)
  printf '%s' "$stat" | awk '{print $2}'   # tras ') ': state ppid ... → ppid es el 2º
}
active_pid="$(hyprctl activewindow -j 2>/dev/null | jq -r '.pid // empty' 2>/dev/null)"
clients="$(hyprctl clients -j 2>/dev/null)"
addr=""
pid=$$
while [ "${pid:-0}" -gt 1 ] 2>/dev/null; do
  pid="$(get_ppid "$pid")"
  [ -z "$pid" ] && break
  # foco-aware: si la ventana de Claude está enfocada, no molestar
  if [ -n "$active_pid" ] && [ "$pid" = "$active_pid" ]; then
    exit 0
  fi
  # ubicar el address de Hyprland de la kitty que contiene esta sesión
  if [ -z "$addr" ] && [ -n "$clients" ]; then
    addr="$(printf '%s' "$clients" | jq -r --arg p "$pid" '.[] | select(.pid==($p|tonumber)) | .address' 2>/dev/null | head -1)"
  fi
done

# ---------- Mapear motivo → título / cuerpo / urgencia ----------
case "$ntype" in
  permission_prompt)
    title="Claude · $proj"
    body="${message:-Necesito tu permiso para continuar}"
    urgency="critical" ;;
  idle_prompt)
    title="Claude · $proj"
    body="${message:-Terminé y te espero}"
    urgency="normal" ;;
  elicitation_dialog)
    title="Claude pregunta · $proj"
    body="${message:-Necesito que elijas una opción}"
    urgency="normal" ;;
  auth_success)
    title="Claude · $proj"
    body="${message:-Autenticación completada}"
    urgency="low" ;;
  *)
    title="Claude · $proj"
    body="${message:-Te espera}"
    urgency="normal" ;;
esac

# ---------- Emitir vía listener desacoplado (notify-send --action bloquea) ----------
export CN_ICON="$ICON" CN_URG="$urgency" CN_TITLE="$title" CN_BODY="$body" CN_ADDR="$addr" CN_NTYPE="$ntype"
setsid "$HOME/.local/bin/claude-notify-action.sh" >/dev/null 2>&1 < /dev/null &
exit 0
