#!/usr/bin/env bash
# Listener desacoplado de claude-notify.sh. Emite la notificación con acciones y
# espera (notify-send --action implica --wait). Al accionar:
#   - "default" (click en el cuerpo / atajo swaync-client --action 0) → salta a la consola
#   - "allow" (solo en permisos)                                       → salta + envía aprobación
# Recibe el contexto por variables de entorno (CN_*). Si la notif expira → no hace nada.
set -u

# "jump" = botón visible (índice 0 → atajo swaync-client --action 0)
# "default" = click en el cuerpo de la notif
actions=( --action="jump=Ir a la sesión" --action="default=Ir a la sesión" )
if [ "${CN_NTYPE:-}" = "permission_prompt" ]; then
  actions+=( --action="allow=Permitir aquí" )
fi

act="$(notify-send -a "Claude" -i "${CN_ICON:-}" -u "${CN_URG:-normal}" "${actions[@]}" "${CN_TITLE:-Claude}" "${CN_BODY:-}")"

jump() {
  [ -n "${CN_ADDR:-}" ] && hyprctl dispatch focuswindow "address:${CN_ADDR}" >/dev/null 2>&1
}

case "$act" in
  jump|default)
    jump ;;
  allow)
    jump ;;   # placeholder: el envío de tecla de aprobación se calibra con un caso real
  *)
    : ;;      # vacío → la notif expiró o se cerró sin acción: no hacer nada
esac
exit 0
