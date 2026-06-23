#!/bin/bash
# Stop hook: Claude terminó turno (o entró en AskUserQuestion).
# Quita el marcador de ESTA sesión (refcount por sesión). El watcher
# persistente arma el timer de suspend solo cuando NO queda ninguna sesión
# marcada como activa.

ACTIVE_DIR=${CLAUDE_ACTIVE_DIR:-/tmp/claude-active.d}
LOG=/tmp/claude-inhibit.log
DEBUG_FLAG=/tmp/claude-inhibit-debug

log() { [ -f "$DEBUG_FLAG" ] && echo "$(date '+%H:%M:%S.%3N') stop:  $*" >> "$LOG"; }

# Mismo criterio de id que start: el PID del proceso claude de esta sesión.
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
log "invoked -> sesion $CPID idle"
rm -f "$ACTIVE_DIR/$CPID"
