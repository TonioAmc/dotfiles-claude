#!/usr/bin/env bash
# Listener desacoplado de claude-notify.sh. Emite la notificación y espera
# (notify-send --action implica --wait). La notif NO tiene botón: la navegación es
# por click en el cuerpo (acción "default") o por el bind Super+Space.
#
# Como sin botón no hay acción que swaync-client pueda invocar, el salto por teclado se
# resuelve con un registro: acá anotamos, mientras la notif vive, la address de Hyprland
# de esta sesión MÁS el id de la notif, y claude-notify-jump.sh (el bind) lee de ahí para
# enfocar la ventana y CERRAR esa notif por id (Tarea B). Registro indexado por sesión:
# un AskUserQuestion nuevo de la misma sesión reemplaza la notif por tag synchronous, así
# que acá cerramos primero la notif anterior de la sesión por su id viejo → su listener
# (que seguiría colgado en --wait, porque el reemplazo por tag NO lo hace retornar) se
# destraba y limpia, sin acumular basura. Contexto por variables CN_*.
set -u

REG="${XDG_RUNTIME_DIR:-/tmp}/claude-notify"
mkdir -p "$REG" 2>/dev/null
key="${CN_SESSION:-$$}"          # una entrada por sesión (cae a PID si no hay session)
entry="$REG/$key"

# Cierra una notif por id vía dbus (swaync-client no puede cerrar por id puntual).
close_notif() {
  [ -n "${1:-}" ] || return 0
  gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$1" >/dev/null 2>&1 || true
}

# Si la sesión ya tenía una notif viva, cerrarla: el reemplazo por tag deja su listener
# colgado en --wait; cerrar el id viejo lo hace retornar y limpiar.
if [ -f "$entry" ]; then
  old="$(cat "$entry" 2>/dev/null)"; old_id="${old##*$'\t'}"
  [ "$old_id" != "$old" ] && close_notif "$old_id"
fi

# Sólo acción "default" (click en el cuerpo) → navega. SIN botón nombrado = sin botón visible.
actions=( --action="default=Ir a la sesión" )

# Extras opcionales según lo que calculó el hook:
#  - tag synchronous → una notif nueva de la MISMA sesión reemplaza la anterior (no apila).
#  - -t TIMEOUT → ms en pantalla; Fase 7 manda CN_TIMEOUT=12000 (12s, luego al panel).
extra=()
[ -n "${CN_SESSION:-}" ] && extra+=( -h "string:x-canonical-private-synchronous:claude-${CN_SESSION}" )
[ -n "${CN_TIMEOUT:-}" ] && extra+=( -t "${CN_TIMEOUT}" )

# notify-send -p imprime el id en la 1ª línea de stdout APENAS crea la notif (verificado:
# llega antes de que --wait bloquee); al cerrarse imprime una 2ª línea con el resultado
# (la acción invocada, p.ej. "default", o "Wait timeout expired"). Leemos por pipe para
# capturar el id EN VIVO y registrarlo mientras la notif está en pantalla.
notif_id=""; act=""
while IFS= read -r line; do
  case "$line" in
    ''|*[!0-9]*) act="$line" ;;            # vacío o con no-dígitos → resultado/acción
    *)                                     # sólo dígitos → es el id
      if [ -z "$notif_id" ]; then
        notif_id="$line"
        [ -n "${CN_ADDR:-}" ] && printf '%s\t%s' "$CN_ADDR" "$notif_id" > "$entry"
      fi ;;
  esac
done < <(notify-send -p -a "Claude" -i "${CN_ICON:-}" -u "${CN_URG:-normal}" \
           "${extra[@]}" "${actions[@]}" "${CN_TITLE:-Claude}" "${CN_BODY:-}")

# La notif se cerró → limpiar el entry, pero SÓLO si sigue siendo el nuestro (un listener
# más nuevo de la misma sesión pudo haberlo sobrescrito con su propio id).
cur="$(cat "$entry" 2>/dev/null)"; cur_id="${cur##*$'\t'}"
[ "$cur_id" = "$notif_id" ] && rm -f "$entry"

case "$act" in
  default)
    [ -n "${CN_ADDR:-}" ] && hyprctl dispatch focuswindow "address:${CN_ADDR}" >/dev/null 2>&1 ;;
  *)
    : ;;   # vacío/timeout/cierre por dbus: no hacer nada (ya se enfocó desde el jump)
esac
exit 0
