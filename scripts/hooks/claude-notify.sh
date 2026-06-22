#!/usr/bin/env bash
# Hook Notification de Claude Code: emite una notificación de escritorio rica
# (proyecto, motivo, ícono, urgencia) en reemplazo de la notif nativa de kitty.
# Calcula la ventana de Hyprland de ESTA sesión para poder "saltar a la consola".
# Lanza un listener desacoplado (claude-notify-action.sh) que espera el click/acción.
# El cuerpo se enriquece (el campo .message del payload es siempre genérico,
# "Claude needs your permission", e idéntico para todo lo que llega como
# notification_type=permission_prompt, así que NO sirve para distinguir):
#  - idle  → extracto de lo último que dijo Claude, leído del transcript .jsonl.
#  - permission_prompt → llega igual para 3 cosas distintas; se desambiguan así:
#      · AskUserQuestion → "❓ Claude pregunta" + la pregunta (del transcript: el
#        tool_use SÍ está grabado al notificar, ~6s antes — verificado Fase 6).
#      · ExitPlanMode    → "📋 Claude propone un plan" + extracto del plan (transcript).
#      · permiso de tool real → "🔐 Claude pide permiso" + herramienta + comando,
#        raspados del diálogo de la TUI vía kitty get-text (este tool_use NO está
#        en el transcript hasta resolverse, por eso se lee de la pantalla).
# Lee el payload JSON por stdin. Doc: memoria reference_claude_notificaciones.
set -u

ICON="$HOME/.local/share/icons/claude/claude-64.png"

payload="$(cat)"
get() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

cwd="$(get '.cwd')"
ntype="$(get '.notification_type')"
message="$(get '.message')"
transcript="$(get '.transcript_path')"
session="$(get '.session_id')"
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
# horizontal (así descarta el "● Bash(…)" y "⎿ Waiting…" de arriba). Toma la
# ÚLTIMA ocurrencia del ancla (el diálogo está al final del get-text): así el
# scrollback de arriba —que puede contener esa misma frase de pasada— no lo pisa.
# Reintenta por si la TUI todavía no pintó el diálogo al dispararse el hook.
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
    { raw[NR]=$0 }
    END {
      last=0
      for (i=1;i<=NR;i++) if (raw[i] ~ /Do you want to proceed/) last=i
      if (last==0) exit
      start=1
      for (i=last-1;i>=1;i--) if (raw[i] ~ /^[[:space:]]*[─━]{3,}/) { start=i+1; break }
      for (i=start;i<last;i++) {
        line=raw[i]
        gsub(/^[[:space:]│┃]+|[[:space:]│┃]+$/,"",line)   # trim espacios + bordes laterales
        if (line=="" || line ~ /^[|╭╮╰╯─━]+$/) continue
        print line
      }
    }'
}
# ¿Hay un menú/plan pendiente de respuesta del usuario? A diferencia de los permisos
# de tool (cuyo tool_use NO está en el transcript hasta resolverse), AskUserQuestion y
# ExitPlanMode SÍ se escriben al transcript al pedir input (verificado: el tool_use se
# graba ~6s antes de que dispare el hook). Distingue ambos del permiso real, que llega
# con el MISMO notification_type/message genérico. Imprime "ASK\t<pregunta>" o
# "PLAN\t<plan>"; vacío si el último tool_use ya está resuelto (= es un permiso real).
pending_menu() {
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 0
  jq -rs '
    ([ .[] | select(.type=="assistant") | .message.content[]?
        | select(.type=="tool_use") ] | last) as $tu
    | if $tu == null then empty else
        ([ .[] | (.message.content // []) | if type=="array" then .[] else empty end
            | select(.type=="tool_result") | .tool_use_id ]) as $done
        | if ($done | index($tu.id)) then empty           # último tool_use ya resuelto
          elif $tu.name=="AskUserQuestion" then "ASK\t" + (($tu.input.questions[0].question) // "")
          elif $tu.name=="ExitPlanMode"    then "PLAN\t" + (($tu.input.plan) // "")
          else empty end
      end' "$transcript" 2>/dev/null
}
# Último bloque de texto del asistente → para el extracto del idle.
last_text() {
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 0
  jq -rs '[ .[] | select(.type=="assistant") | .message.content[]?
             | select(.type=="text") | .text ]
    | if length==0 then empty else last end' "$transcript" 2>/dev/null
}

# ---------- Mapear motivo → título / cuerpo / urgencia ----------
# timeout: ms que la notif queda EN PANTALLA (vacío = default de swaync, 6s normal /
# 20s critical). Ensanchamos las idle a 12s para que dé tiempo a ciclar con Super+Space
# entre varias sesiones antes de que se vayan al panel (ver memoria, "2 notis seguidas").
timeout=""
case "$ntype" in
  permission_prompt)
    # permission_prompt llega IGUAL (mismo notification_type y message genérico) para
    # tres cosas distintas: una pregunta (AskUserQuestion), un plan (ExitPlanMode) y un
    # permiso de tool real. El transcript las distingue: si hay un menú/plan pendiente,
    # lo leemos de ahí (robusto); si no, es un permiso real y rascamos la TUI.
    menu="$(pending_menu)"
    kind="${menu%%$'\t'*}"; mtext="${menu#*$'\t'}"
    [ "$kind" = "$menu" ] && kind=""         # sin tab → no es menú
    case "$kind" in
      ASK)
        title="❓ Claude pregunta · $proj"
        urgency="normal"
        body="$(esc "$(shorten "${mtext:-Necesito que elijas una opción}" 160)")" ;;
      PLAN)
        title="📋 Claude propone un plan · $proj"
        urgency="normal"
        body="$(esc "$(shorten "${mtext:-Revisá el plan que propongo}" 160)")" ;;
      *)
        title="🔐 Claude pide permiso · $proj"
        urgency="critical"
        kitty_win="$(find_kitty_win)"
        mapfile -t PL < <(scrape_pending)
        if [ "${#PL[@]}" -gt 0 ]; then
          tool="${PL[0]%% *}"                # "Bash" de "Bash command"
          detail="${PL[1]:-}"; detail="${detail//$HOME/\~}"
          if [ -n "$detail" ]; then
            body="<b>$(esc "$tool")</b> · $(esc "$(shorten "$detail" 90)")"
          else
            body="<b>$(esc "$(shorten "${PL[0]}" 90)")</b>"
          fi
        else
          body="$(esc "${message:-Necesito tu permiso para continuar}")"
        fi ;;
    esac ;;
  idle_prompt)
    title="Claude te espera · $proj"
    urgency="normal"
    timeout="12000"
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
# CN_SESSION → tag synchronous (swaync reemplaza la notif previa de la MISMA sesión en vez
# de apilar otra). CN_TIMEOUT → ms en pantalla (ver arriba).
export CN_ICON="$ICON" CN_URG="$urgency" CN_TITLE="$title" CN_BODY="$body" CN_ADDR="$addr"
export CN_SESSION="$session" CN_TIMEOUT="$timeout"
setsid "$HOME/.local/bin/claude-notify-action.sh" >/dev/null 2>&1 < /dev/null &
exit 0
