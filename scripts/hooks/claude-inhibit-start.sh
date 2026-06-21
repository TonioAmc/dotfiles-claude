#!/bin/bash
PIDFILE=/tmp/claude-inhibit.pid
WATCHER_PID=/tmp/claude-lid-watcher.pid
TIMER_PID=/tmp/claude-suspend-timer.pid
ACTIVE=/tmp/claude-active
LID_FILE=${CLAUDE_LID_FILE:-/proc/acpi/button/lid/LID0/state}
LOG=/tmp/claude-inhibit.log
DEBUG_FLAG=/tmp/claude-inhibit-debug
SUSPEND_DELAY=${CLAUDE_SUSPEND_DELAY:-60}

log() { [ -f "$DEBUG_FLAG" ] && echo "$(date '+%H:%M:%S.%3N') start: $*" >> "$LOG"; }

log "invoked"

# Marcar Claude activo: el watcher NO armará timer mientras esto exista
touch "$ACTIVE"

# Cancelar timer pendiente (si lo había de un Stop previo)
if [ -f "$TIMER_PID" ]; then
    log "cancelando timer pendiente PID=$(cat $TIMER_PID)"
    kill "$(cat "$TIMER_PID")" 2>/dev/null
    rm -f "$TIMER_PID"
fi

# Verificar par inhibidor+watcher (deben estar vivos persistentemente)
INHIBITOR_ALIVE=false
WATCHER_ALIVE=false
[ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null && INHIBITOR_ALIVE=true
[ -f "$WATCHER_PID" ] && kill -0 "$(cat "$WATCHER_PID")" 2>/dev/null && WATCHER_ALIVE=true

if $INHIBITOR_ALIVE && $WATCHER_ALIVE; then
    log "par vivo (inhibidor=$(cat $PIDFILE) watcher=$(cat $WATCHER_PID)) → exit"
    exit 0
fi

log "par roto (inhib=$INHIBITOR_ALIVE watcher=$WATCHER_ALIVE) → relanzar"

# Limpiar artefactos zombies
if $INHIBITOR_ALIVE; then
    P=$(cat "$PIDFILE")
    pkill -P "$P" 2>/dev/null
    kill "$P" 2>/dev/null
fi
$WATCHER_ALIVE && kill "$(cat "$WATCHER_PID")" 2>/dev/null
rm -f "$PIDFILE" "$WATCHER_PID"

# Lanzar inhibidor (persistente entre turnos)
systemd-inhibit --what=handle-lid-switch --who="claude" \
    --why="Claude Code monitoreando lid" --mode=block \
    sleep infinity &
INHIB_NEW=$!
echo $INHIB_NEW > "$PIDFILE"
log "inhibidor lanzado PID=$INHIB_NEW"

# Watcher persistente: arma timer cuando lid=closed Y claude idle.
# Cada CHECK_CLAUDE_EVERY iteraciones, verifica que el proceso claude siga vivo;
# si no, libera todo y sale (auto-cleanup al cerrar Claude Code).
(
    PREV_LID="?"
    LOOPS=0
    CHECK_CLAUDE_EVERY=30
    while kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; do
        LOOPS=$((LOOPS+1))
        if (( LOOPS % CHECK_CLAUDE_EVERY == 0 )); then
            # Detectar claude por comm name + verificar exe apunta a versiones de claude
            CLAUDE_RUNNING=false
            for cpid in $(pgrep -x claude 2>/dev/null); do
                if readlink "/proc/$cpid/exe" 2>/dev/null | grep -q "claude/versions"; then
                    CLAUDE_RUNNING=true
                    break
                fi
            done
            if ! $CLAUDE_RUNNING; then
                log "watcher: claude no detectado → liberando inhibidor + exit"
                if [ -f "$PIDFILE" ]; then
                    P=$(cat "$PIDFILE")
                    pkill -P "$P" 2>/dev/null
                    kill "$P" 2>/dev/null
                    rm -f "$PIDFILE"
                fi
                rm -f "$WATCHER_PID" "$TIMER_PID" "$ACTIVE"
                exit 0
            fi
        fi

        read -r _ STATE < "$LID_FILE" 2>/dev/null

        if [ "$STATE" != "$PREV_LID" ]; then
            log "watcher: lid $PREV_LID → $STATE"
            PREV_LID=$STATE
        fi

        if [ "$STATE" = "closed" ]; then
            # Lid cerrado: armar timer si Claude está idle y no hay timer ya
            if [ ! -f "$ACTIVE" ] && [ ! -f "$TIMER_PID" ]; then
                log "watcher: lid closed + claude idle → armando timer ${SUSPEND_DELAY}s"
                (
                    log "timer: armado (${SUSPEND_DELAY}s, inhibidor sigue activo)"
                    for ((i=0; i<SUSPEND_DELAY; i++)); do
                        read -r _ S < "$LID_FILE" 2>/dev/null
                        [ "$S" != "closed" ] && {
                            log "timer: cancelado por lid=$S en t=${i}s"
                            rm -f "$TIMER_PID"
                            exit 0
                        }
                        [ -f "$ACTIVE" ] && {
                            log "timer: cancelado por claude-active en t=${i}s"
                            rm -f "$TIMER_PID"
                            exit 0
                        }
                        sleep 1
                    done
                    log "timer: ${SUSPEND_DELAY}s completos → liberar inhibidor + Suspend"
                    rm -f "$TIMER_PID"
                    if [ -f "$PIDFILE" ]; then
                        P=$(cat "$PIDFILE")
                        pkill -P "$P" 2>/dev/null
                        kill "$P" 2>/dev/null
                        rm -f "$PIDFILE"
                    fi
                    # --print-reply OBLIGATORIO o polkit deniega silenciosamente
                    dbus-send --system --print-reply \
                        --dest=org.freedesktop.login1 \
                        /org/freedesktop/login1 \
                        org.freedesktop.login1.Manager.Suspend \
                        boolean:false
                ) &
                echo $! > "$TIMER_PID"
            fi
        else
            # Lid abierto: cancelar timer si existe
            if [ -f "$TIMER_PID" ]; then
                T=$(cat "$TIMER_PID")
                log "watcher: lid open → matando timer PID=$T"
                kill "$T" 2>/dev/null
                rm -f "$TIMER_PID"
            fi
        fi

        sleep 1
    done
    log "watcher: salió (inhibidor murió)"
) &
WATCHER_NEW=$!
echo $WATCHER_NEW > "$WATCHER_PID"
log "watcher lanzado PID=$WATCHER_NEW"
