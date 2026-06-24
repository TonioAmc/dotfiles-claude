#!/usr/bin/env bash
# Target de dos binds (Fase 7):
#   Super+Space        → modo "jump"    : salta a la sesión de Claude que espera y cierra
#                        esa notif. Si NO hay ninguna notif viva → abre el panel de swaync.
#   Super+Alt+Space    → modo "dismiss" (con --dismiss): cierra la notif de arriba SIN saltar.
#                        Si no hay ninguna → no hace nada (sirve para sacar una notif de
#                        pantalla antes de que expire sola a los 12s).
#
# La más reciente primero; repetí el atajo para ir ciclando/cerrando las anteriores.
#
# Por qué no usa swaync: las notifs de Claude no tienen botón ("Ir a la sesión" se quitó en
# Fase 5), y swaync-client --action sólo invoca acciones NOMBRADAS (= botones). Sin botón no
# hay acción que invocar, así que jump/cierre se resuelven por fuera de swaync:
# claude-notify-action.sh anota en un registro, por sesión, la address de Hyprland MÁS el id
# de la notif; acá leemos la entrada más nueva viva, (en jump) enfocamos la ventana y CERRAMOS
# esa notif por id — swaync-client no puede cerrar una notif puntual, así que el cierre va por
# dbus directo. Doc: memoria reference_claude_notificaciones.
set -u

mode="jump"
[ "${1:-}" = "--dismiss" ] && mode="dismiss"

REG="${XDG_RUNTIME_DIR:-/tmp}/claude-notify"

# Cierra una notif por id vía dbus (swaync-client no puede cerrar por id puntual).
close_notif() {
  [ -n "${1:-}" ] || return 0
  gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$1" >/dev/null 2>&1 || true
}
# Fuente de verdad de "hay notif viva": una entrada del registro cuya ventana sigue
# existiendo. Si NO hay ninguna, en modo jump se abre el panel/historial de swaync.
open_panel() { swaync-client -t >/dev/null 2>&1 || true; }

if [ ! -d "$REG" ]; then
  [ "$mode" = "jump" ] && open_panel
  exit 0
fi

clients="$(hyprctl clients -j 2>/dev/null)"
have_clients=0
printf '%s' "$clients" | jq -e 'type=="array"' >/dev/null 2>&1 && have_clients=1

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
  # Entrada viva = notif en pantalla. En jump enfocamos; en dismiss NO (sólo cerramos).
  [ "$mode" = "jump" ] && hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1
  # Cerrar SÓLO esta notif (la más reciente = la de arriba); su listener retorna y se
  # autolimpia. Las demás quedan en pie: al cerrarse ésta swaync sube la siguiente al
  # borde, y el próximo atajo la salda. Con el registro por sesión (Fase 6) hay una
  # entrada por notif, así que basta borrar la propia.
  close_notif "$nid"
  rm -f "$path"
  exit 0
done

# No había ninguna notif viva: en jump abrimos el panel; en dismiss no hacemos nada.
[ "$mode" = "jump" ] && open_panel
exit 0
