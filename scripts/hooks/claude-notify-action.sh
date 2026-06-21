#!/usr/bin/env bash
# Listener desacoplado de claude-notify.sh. Emite la notificación con la acción
# "Ir a la sesión" y espera (notify-send --action implica --wait). Al accionar
# (click en el cuerpo / botón / atajo swaync-client --action 0) salta a la consola
# de esa sesión (focuswindow por el address de Hyprland que calculó el hook).
# Si la notif expira sin acción → no hace nada. Contexto por variables CN_*.
set -u

# "jump" = botón visible (índice 0 → atajo swaync-client --action 0)
# "default" = click en el cuerpo de la notif
actions=( --action="jump=Ir a la sesión" --action="default=Ir a la sesión" )

act="$(notify-send -a "Claude" -i "${CN_ICON:-}" -u "${CN_URG:-normal}" "${actions[@]}" "${CN_TITLE:-Claude}" "${CN_BODY:-}")"

case "$act" in
  jump|default)
    [ -n "${CN_ADDR:-}" ] && hyprctl dispatch focuswindow "address:${CN_ADDR}" >/dev/null 2>&1 ;;
  *)
    : ;;   # vacío → la notif expiró o se cerró sin acción: no hacer nada
esac
exit 0
