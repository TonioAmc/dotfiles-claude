#!/bin/bash
# UserPromptSubmit hook: Claude empezó/continúa un turno.
# (1) Marca ESTA sesión como activa (un marcador por consola, heartbeat).
# (2) Asegura que el servicio de usuario claude-lid-watcher.service esté
#     corriendo. systemd garantiza singleton (no hay doble arranque) y
#     Restart=on-failure (si el watcher cae, vuelve solo): por eso este hook
#     ya NO lanza el inhibidor ni el watcher a mano.
#
# Rutas salen por env (defaults de producción) para testear aislado. Poné
# CLAUDE_LID_SERVICE_SKIP=1 en tests para no tocar el servicio real.

ACTIVE_DIR=${CLAUDE_ACTIVE_DIR:-/tmp/claude-active.d}
SERVICE=${CLAUDE_LID_SERVICE:-claude-lid-watcher.service}
LOG=/tmp/claude-inhibit.log
DEBUG_FLAG=/tmp/claude-inhibit-debug

log() { [ -f "$DEBUG_FLAG" ] && echo "$(date '+%H:%M:%S.%3N') start: $*" >> "$LOG"; }

# Sube por la cadena de PPID hasta el proceso claude de ESTA sesión. Su PID es
# un id estable por consola (permite purgar marcadores huérfanos con kill -0).
find_claude_pid() {
    local pid=$$ i
    for ((i=0; i<15; i++)); do
        pid=$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null)
        { [ -z "$pid" ] || [ "$pid" = "0" ]; } && break
        if readlink "/proc/$pid/exe" 2>/dev/null | grep -q "claude/versions"; then
            echo "$pid"; return 0
        fi
    done
    return 1
}

# (1) Marcar ESTA sesión activa.
mkdir -p "$ACTIVE_DIR"
CPID=${CLAUDE_SESSION_PID:-$(find_claude_pid || echo "$PPID")}
touch "$ACTIVE_DIR/$CPID"
log "sesion $CPID marcada activa"

# (2) Asegurar el servicio watcher (idempotente: si ya corre, no-op).
if [ -z "${CLAUDE_LID_SERVICE_SKIP:-}" ]; then
    systemctl --user start "$SERVICE" 2>/dev/null \
        && log "servicio $SERVICE asegurado" \
        || log "no se pudo iniciar $SERVICE (¿unit instalada? ¿bus de usuario?)"
fi
