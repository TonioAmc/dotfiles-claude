#!/bin/bash
# PreToolUse hook (todas las herramientas): refresca el heartbeat de ESTA
# sesión mientras Claude trabaja. Así un turno largo (que usa herramientas)
# nunca deja caducar el marcador, y el equipo no se suspende a mitad del
# trabajo con la tapa cerrada. NO toca el inhibidor ni el watcher: de eso se
# encarga claude-inhibit-start.sh en UserPromptSubmit. Liviano e idempotente.

ACTIVE_DIR=${CLAUDE_ACTIVE_DIR:-/tmp/claude-active.d}

# Mismo criterio de id que start/stop: el PID del proceso claude de la sesión.
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

CPID=${CLAUDE_SESSION_PID:-$(find_claude_pid || echo "$PPID")}
# Solo refresca si la sesión ya está registrada (no crea el marcador: eso es
# trabajo de start.sh, que además levanta el inhibidor).
[ -e "$ACTIVE_DIR/$CPID" ] && touch "$ACTIVE_DIR/$CPID" 2>/dev/null
exit 0
