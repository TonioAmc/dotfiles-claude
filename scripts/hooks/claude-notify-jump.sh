#!/usr/bin/env bash
# Target del bind Super+Space: salta a la sesión de Claude que está esperando.
# La más reciente primero; repetí el atajo para ir ciclando a las anteriores.
#
# Por qué no usa swaync: las notifs de Claude ya no tienen botón ("Ir a la sesión" se
# quitó), y swaync-client --action sólo puede invocar acciones NOMBRADAS (= botones).
# Sin botón no hay acción que invocar, así que el salto se resuelve por fuera de swaync:
# claude-notify-action.sh anota en un registro, por sesión, la address de Hyprland MÁS
# el id de la notif; acá leemos la entrada más nueva viva, enfocamos la ventana y CERRAMOS
# esa notif por id (Tarea B) — swaync-client no puede cerrar una notif puntual, así que el
# cierre va por dbus directo. Doc: memoria reference_claude_notificaciones.
set -u

REG="${XDG_RUNTIME_DIR:-/tmp}/claude-notify"
[ -d "$REG" ] || exit 0

clients="$(hyprctl clients -j 2>/dev/null)"
have_clients=0
printf '%s' "$clients" | jq -e 'type=="array"' >/dev/null 2>&1 && have_clients=1

# Cierra una notif por id vía dbus (swaync-client no puede cerrar por id puntual).
close_notif() {
  [ -n "${1:-}" ] || return 0
  gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$1" >/dev/null 2>&1 || true
}

# Entradas por mtime descendente: la notif más reciente primero.
for f in $(ls -t "$REG"/ 2>/dev/null); do
  path="$REG/$f"
  [ -f "$path" ] || continue
  raw="$(cat "$path" 2>/dev/null)"
  addr="${raw%%$'\t'*}"                  # antes del tab: address de Hyprland
  nid="${raw##*$'\t'}"; [ "$nid" = "$raw" ] && nid=""   # tras el tab: id de la notif
  if [ -z "$addr" ]; then rm -f "$path"; continue; fi
  # Purgar entradas de ventanas que ya no existen (listener muerto sin limpiar, etc.).
  if [ "$have_clients" = 1 ] \
     && ! printf '%s' "$clients" | jq -e --arg a "$addr" 'any(.[]; .address==$a)' >/dev/null 2>&1; then
    rm -f "$path"; continue
  fi
  hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1
  # Cerrar la notif a la que saltamos (el --wait de su listener retorna y se autolimpia).
  close_notif "$nid"
  # Consumir TODAS las entradas de esta ventana (el coalescing de una misma sesión puede
  # dejar varias): así un solo Super+Space la salda y el próximo va a la SIGUIENTE sesión,
  # no de vuelta a la misma.
  for g in "$REG"/*; do
    [ -f "$g" ] || continue
    graw="$(cat "$g" 2>/dev/null)"; gaddr="${graw%%$'\t'*}"
    [ "$gaddr" = "$addr" ] && rm -f "$g"
  done
  exit 0
done
exit 0
