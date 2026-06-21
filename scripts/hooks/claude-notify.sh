#!/usr/bin/env bash
# Hook Notification de Claude Code: emite una notificación de escritorio rica
# (proyecto, motivo, ícono, urgencia) en reemplazo de la notif nativa de kitty.
# Calcula la ventana de Hyprland de ESTA sesión para poder "saltar a la consola".
# Lanza un listener desacoplado (claude-notify-action.sh) que espera el click/acción.
# El cuerpo se enriquece (el campo .message del payload es siempre genérico,
# "Claude needs your permission"):
#  - idle  → extracto de lo último que dijo Claude, leído del transcript .jsonl.
#  - permiso → herramienta + comando a aprobar, leídos del diálogo de la TUI vía
#    kitty get-text (el tool_use pendiente NO está aún en el transcript: Claude lo
#    escribe recién al resolver el permiso, verificado en Fase 4).
# Lee el payload JSON por stdin. Doc: memoria reference_claude_notificaciones.
set -u

ICON="$HOME/.local/share/icons/claude/claude-64.png"

payload="$(cat)"
get() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

cwd="$(get '.cwd')"
ntype="$(get '.notification_type')"
message="$(get '.message')"
transcript="$(get '.transcript_path')"
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
anc=""
pid=$$
while [ "${pid:-0}" -gt 1 ] 2>/dev/null; do
  pid="$(get_ppid "$pid")"
  [ -z "$pid" ] && break
  anc="$anc $pid"
  # foco-aware: si la ventana de Claude está enfocada, no molestar
  if [ -n "$active_pid" ] && [ "$pid" = "$active_pid" ]; then
    exit 0
  fi
  # ubicar el address de Hyprland de la kitty que contiene esta sesión
  if [ -z "$addr" ] && [ -n "$clients" ]; then
    addr="$(printf '%s' "$clients" | jq -r --arg p "$pid" '.[] | select(.pid==($p|tonumber)) | .address' 2>/dev/null | head -1)"
  fi
done

# ---------- Helpers de enriquecimiento ----------
# Colapsa espacios/saltos y recorta a N caracteres (UTF-8-safe en locale UTF-8).
shorten() { printf '%s' "$1" | tr '\n\t' '  ' | sed -E 's/  +/ /g; s/^ //; s/ +$//; s/(.{'"$2"'}).+/\1…/'; }
# Escapa markup pango (& < >) para texto dinámico que va al body.
esc() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

# Ubica la ventana de kitty de esta sesión cruzando algún PID ancestro con el
# árbol de procesos de cada ventana de kitten @ ls. Requiere remote control
# (KITTY_LISTEN_ON, heredado de la kitty). Sólo se llama para permisos.
find_kitty_win() {
  [ -n "${KITTY_LISTEN_ON:-}" ] && [ -n "$anc" ] || return 0
  local anc_json
  anc_json="[$(printf '%s' "$anc" | tr ' ' '\n' | grep -E '^[0-9]+$' | paste -sd, -)]"
  kitten @ ls 2>/dev/null | jq -r --argjson anc "$anc_json" '
    [ .[].tabs[].windows[]
      | . as $w | ([$w.pid] + [$w.foreground_processes[]?.pid]) as $wp
      | select(any($wp[]; . as $p | $anc | index($p))) | .id ] | first // empty' 2>/dev/null
}
# Lee el diálogo de permiso de la TUI y devuelve sus líneas útiles: header
# (p.ej. "Bash command", "Edit file") + detalle (el comando o el archivo). Ancla
# en "Do you want to proceed?" y aísla el cuadro reseteando en cada separador
# horizontal (así descarta el "● Bash(…)" y "⎿ Waiting…" de arriba). Reintenta
# por si la TUI todavía no pintó el diálogo al dispararse el hook.
scrape_pending() {
  [ -n "$kitty_win" ] || return 0
  local txt i=0
  while [ "$i" -lt 6 ]; do
    txt="$(kitten @ get-text --match id:"$kitty_win" 2>/dev/null)"
    case "$txt" in *"Do you want to proceed"*) break ;; esac
    i=$((i+1)); sleep 0.15
  done
  case "$txt" in *"Do you want to proceed"*) ;; *) return 0 ;; esac
  printf '%s\n' "$txt" | awk '
    /Do you want to proceed/ { for (j=1;j<=c;j++) print b[j]; exit }
    /^[[:space:]]*[─━]{3,}/  { c=0; next }
    {
      line=$0; gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
      if (line=="" || line ~ /^[│┃|╭╮╰╯]+$/) next
      c++; b[c]=line
    }'
}
# Último bloque de texto del asistente → para el extracto del idle.
last_text() {
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 0
  jq -rs '[ .[] | select(.type=="assistant") | .message.content[]?
             | select(.type=="text") | .text ]
    | if length==0 then empty else last end' "$transcript" 2>/dev/null
}

# ---------- Mapear motivo → título / cuerpo / urgencia ----------
case "$ntype" in
  permission_prompt)
    title="🔐 Claude pide permiso · $proj"
    urgency="critical"
    kitty_win="$(find_kitty_win)"
    mapfile -t PL < <(scrape_pending)
    if [ "${#PL[@]}" -gt 0 ]; then
      tool="${PL[0]%% *}"                    # "Bash" de "Bash command"
      detail="${PL[1]:-}"; detail="${detail//$HOME/\~}"
      if [ -n "$detail" ]; then
        body="<b>$(esc "$tool")</b> · $(esc "$(shorten "$detail" 90)")"
      else
        body="<b>$(esc "$(shorten "${PL[0]}" 90)")</b>"
      fi
    else
      body="$(esc "${message:-Necesito tu permiso para continuar}")"
    fi ;;
  idle_prompt)
    title="Claude te espera · $proj"
    urgency="normal"
    tx="$(last_text)"
    if [ -n "$tx" ]; then
      body="$(esc "$(shorten "$tx" 160)")"
    else
      body="$(esc "${message:-Terminé y te espero}")"
    fi ;;
  elicitation_dialog)
    title="Claude pregunta · $proj"
    body="$(esc "${message:-Necesito que elijas una opción}")"
    urgency="normal" ;;
  auth_success)
    title="Claude · $proj"
    body="$(esc "${message:-Autenticación completada}")"
    urgency="low" ;;
  *)
    title="Claude · $proj"
    body="$(esc "${message:-Te espera}")"
    urgency="normal" ;;
esac

# ---------- Emitir vía listener desacoplado (notify-send --action bloquea) ----------
export CN_ICON="$ICON" CN_URG="$urgency" CN_TITLE="$title" CN_BODY="$body" CN_ADDR="$addr"
setsid "$HOME/.local/bin/claude-notify-action.sh" >/dev/null 2>&1 < /dev/null &
exit 0
