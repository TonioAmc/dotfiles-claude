#!/usr/bin/env bash
# Listener desacoplado de claude-notify.sh. Emite la notificación y espera
# (notify-send --action implica --wait). La notif NO tiene botón: la navegación es
# por click en el cuerpo (acción "default") o por el bind Super+Space.
#
# Como sin botón no hay acción que swaync-client pueda invocar, el salto por teclado se
# resuelve con un registro: acá anotamos la address de Hyprland de esta sesión mientras
# la notif está viva, y claude-notify-jump.sh (el bind) lee de ahí. La entrada se borra
# cuando la notif se cierra (click / expira / la reemplaza otra de la misma sesión).
# Contexto por variables CN_*.
set -u

# ---------- Registro de sesión pendiente (para el bind Super+Space) ----------
REG="${XDG_RUNTIME_DIR:-/tmp}/claude-notify"
entry="$REG/$$"
if [ -n "${CN_ADDR:-}" ]; then
  mkdir -p "$REG"
  printf '%s' "$CN_ADDR" > "$entry"
fi

# Sólo acción "default" (click en el cuerpo) → navega. SIN botón nombrado = sin botón visible.
actions=( --action="default=Ir a la sesión" )

# Extras opcionales según lo que calculó el hook:
#  - tag synchronous → una notif nueva de la MISMA sesión reemplaza la anterior (no apila).
#  - -t TIMEOUT → ms en pantalla (idle se ensancha para poder ciclar con Super+Space).
extra=()
[ -n "${CN_SESSION:-}" ] && extra+=( -h "string:x-canonical-private-synchronous:claude-${CN_SESSION}" )
[ -n "${CN_TIMEOUT:-}" ] && extra+=( -t "${CN_TIMEOUT}" )

act="$(notify-send -a "Claude" -i "${CN_ICON:-}" -u "${CN_URG:-normal}" "${extra[@]}" "${actions[@]}" "${CN_TITLE:-Claude}" "${CN_BODY:-}")"

# La notif se cerró → ya no está pendiente.
rm -f "$entry"

case "$act" in
  default)
    [ -n "${CN_ADDR:-}" ] && hyprctl dispatch focuswindow "address:${CN_ADDR}" >/dev/null 2>&1 ;;
  *)
    : ;;   # vacío → expiró/cerró sin acción: no hacer nada
esac
exit 0
