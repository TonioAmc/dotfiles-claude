#!/bin/bash
# UserPromptSubmit hook: Claude empezó/continúa un turno.
# Marca ESTA sesión como activa (refcount por sesión, un marcador por consola)
# y asegura el par inhibidor+watcher persistente que maneja lid -> suspend.
#
# Rutas y comando de suspend salen por env (con defaults de producción) para
# poder testear el flujo aislado sin tocar el estado real ni suspender.

PIDFILE=${CLAUDE_INHIBIT_PIDFILE:-/tmp/claude-inhibit.pid}
WATCHER_PID=${CLAUDE_INHIBIT_WATCHER:-/tmp/claude-lid-watcher.pid}
TIMER_PID=${CLAUDE_INHIBIT_TIMER:-/tmp/claude-suspend-timer.pid}
ACTIVE_DIR=${CLAUDE_ACTIVE_DIR:-/tmp/claude-active.d}
LID_FILE=${CLAUDE_LID_FILE:-/proc/acpi/button/lid/LID0/state}
SUSPEND_DELAY=${CLAUDE_SUSPEND_DELAY:-60}
SUSPEND_CMD=${CLAUDE_SUSPEND_CMD:-"dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Suspend boolean:false"}
LOG=/tmp/claude-inhibit.log
DEBUG_FLAG=/tmp/claude-inhibit-debug

log() { [ -f "$DEBUG_FLAG" ] && echo "$(date '+%H:%M:%S.%3N') start: $*" >> "$LOG"; }

# Sube por la cadena de PPID hasta el proceso claude de ESTA sesión.
# Su PID es un id estable por consola y permite purgar marcadores huérfanos
# (sesión cerrada sin disparar Stop) con kill -0.
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

log "invoked"

# Marcar ESTA sesión activa (refcount): un marcador por sesión.
mkdir -p "$ACTIVE_DIR"
CPID=${CLAUDE_SESSION_PID:-$(find_claude_pid || echo "$PPID")}
touch "$ACTIVE_DIR/$CPID"
log "sesion $CPID marcada activa"

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
    log "par vivo (inhibidor=$(cat $PIDFILE) watcher=$(cat $WATCHER_PID)) -> exit"
    exit 0
fi

log "par roto (inhib=$INHIBITOR_ALIVE watcher=$WATCHER_ALIVE) -> relanzar"

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

# Watcher persistente: arma timer cuando lid=closed Y NINGUNA sesión activa.
# Cada CHECK_CLAUDE_EVERY iteraciones verifica que siga vivo algún claude;
# si no, libera todo y sale (auto-cleanup al cerrar Claude Code).
(
    # Cuenta sesiones activas y de paso purga marcadores huérfanos
    # (sesión que murió sin disparar Stop). Dir vacío/ausente -> 0.
    active_sessions() {
        local n=0 m pid
        for m in "$ACTIVE_DIR"/*; do
            [ -e "$m" ] || continue
            pid=${m##*/}
            if kill -0 "$pid" 2>/dev/null; then
                n=$((n+1))
            else
                rm -f "$m"
            fi
        done
        echo "$n"
    }

    PREV_LID="?"
    LOOPS=0
    CHECK_CLAUDE_EVERY=30
    while kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; do
        LOOPS=$((LOOPS+1))
        if (( LOOPS % CHECK_CLAUDE_EVERY == 0 )); then
            CLAUDE_RUNNING=false
            for cpid in $(pgrep -x claude 2>/dev/null); do
                if readlink "/proc/$cpid/exe" 2>/dev/null | grep -q "claude/versions"; then
                    CLAUDE_RUNNING=true
                    break
                fi
            done
            if ! $CLAUDE_RUNNING; then
                log "watcher: claude no detectado -> liberando inhibidor + exit"
                if [ -f "$PIDFILE" ]; then
                    P=$(cat "$PIDFILE")
                    pkill -P "$P" 2>/dev/null
                    kill "$P" 2>/dev/null
                    rm -f "$PIDFILE"
                fi
                rm -f "$WATCHER_PID" "$TIMER_PID"
                rm -rf "$ACTIVE_DIR"
                exit 0
            fi
        fi

        read -r _ STATE < "$LID_FILE" 2>/dev/null

        if [ "$STATE" != "$PREV_LID" ]; then
            log "watcher: lid $PREV_LID -> $STATE"
            PREV_LID=$STATE
        fi

        if [ "$STATE" = "closed" ]; then
            # Lid cerrado: armar timer solo si NINGUNA sesión activa y no hay timer
            if [ "$(active_sessions)" -eq 0 ] && [ ! -f "$TIMER_PID" ]; then
                log "watcher: lid closed + 0 sesiones activas -> armando timer ${SUSPEND_DELAY}s"
                (
                    log "timer: armado (${SUSPEND_DELAY}s, inhibidor sigue activo)"
                    for ((i=0; i<SUSPEND_DELAY; i++)); do
                        read -r _ S < "$LID_FILE" 2>/dev/null
                        [ "$S" != "closed" ] && {
                            log "timer: cancelado por lid=$S en t=${i}s"
                            rm -f "$TIMER_PID"; exit 0
                        }
                        [ "$(active_sessions)" -gt 0 ] && {
                            log "timer: cancelado por sesion activa en t=${i}s"
                            rm -f "$TIMER_PID"; exit 0
                        }
                        sleep 1
                    done
                    log "timer: ${SUSPEND_DELAY}s completos -> liberar inhibidor + Suspend"
                    rm -f "$TIMER_PID"
                    if [ -f "$PIDFILE" ]; then
                        P=$(cat "$PIDFILE")
                        pkill -P "$P" 2>/dev/null
                        kill "$P" 2>/dev/null
                        rm -f "$PIDFILE"
                    fi
                    # --print-reply OBLIGATORIO o polkit deniega silenciosamente
                    eval "$SUSPEND_CMD"
                ) &
                echo $! > "$TIMER_PID"
            fi
        else
            # Lid abierto: cancelar timer si existe
            if [ -f "$TIMER_PID" ]; then
                T=$(cat "$TIMER_PID")
                log "watcher: lid open -> matando timer PID=$T"
                kill "$T" 2>/dev/null
                rm -f "$TIMER_PID"
            fi
        fi

        sleep 1
    done
    log "watcher: salio (inhibidor murio)"
) &
WATCHER_NEW=$!
echo $WATCHER_NEW > "$WATCHER_PID"
log "watcher lanzado PID=$WATCHER_NEW"
