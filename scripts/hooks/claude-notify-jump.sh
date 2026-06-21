#!/usr/bin/env bash
# Target del bind Super+Space: salta a la sesión de Claude que está esperando.
# La más reciente primero; repetí el atajo para ir ciclando a las anteriores.
#
# Por qué no usa swaync: las notifs de Claude ya no tienen botón ("Ir a la sesión" se
# quitó), y swaync-client --action sólo puede invocar acciones NOMBRADAS (= botones).
# Sin botón no hay acción que invocar, así que el salto se resuelve por fuera de swaync:
# claude-notify-action.sh anota en un registro la address de Hyprland de cada sesión
# pendiente; acá leemos la más nueva viva, la enfocamos y la consumimos.
# Doc: memoria reference_claude_notificaciones.
set -u

REG="${XDG_RUNTIME_DIR:-/tmp}/claude-notify"
[ -d "$REG" ] || exit 0

clients="$(hyprctl clients -j 2>/dev/null)"
have_clients=0
printf '%s' "$clients" | jq -e 'type=="array"' >/dev/null 2>&1 && have_clients=1

# Entradas por mtime descendente: la notif más reciente primero.
for f in $(ls -t "$REG"/ 2>/dev/null); do
  path="$REG/$f"
  [ -f "$path" ] || continue
  addr="$(cat "$path" 2>/dev/null)"
  if [ -z "$addr" ]; then rm -f "$path"; continue; fi
  # Purgar entradas de ventanas que ya no existen (listener muerto sin limpiar, etc.).
  if [ "$have_clients" = 1 ] \
     && ! printf '%s' "$clients" | jq -e --arg a "$addr" 'any(.[]; .address==$a)' >/dev/null 2>&1; then
    rm -f "$path"; continue
  fi
  hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1
  # Consumir TODAS las entradas de esta ventana (el coalescing de una misma sesión puede
  # dejar varias): así un solo Super+Space la salda y el próximo va a la SIGUIENTE sesión,
  # no de vuelta a la misma.
  for g in "$REG"/*; do
    [ -f "$g" ] && [ "$(cat "$g" 2>/dev/null)" = "$addr" ] && rm -f "$g"
  done
  exit 0
done
exit 0
