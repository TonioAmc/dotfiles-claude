#!/bin/bash
# Watcher persistente del inhibidor de tapa. Corre como ExecStart de
# claude-lid-watcher.service (de usuario), ENVUELTO por systemd-inhibit
# --what=handle-lid-switch --mode=block. O sea: el propio servicio sostiene
# el inhibidor mientras este loop vive. Si el loop muere (crash/OOM), el
# inhibidor se suelta solo y systemd lo reinicia (Restart=on-failure) -> ya
# no hay inhibidor "colgado" como cuando era un proceso hermano suelto.
#
# Decide cuándo suspender con la tapa cerrada:
#   1) PISO DE BATERIA (red propia, independiente): si está a batería, la tapa
#      cerrada y el % <= BATTERY_FLOOR -> suspende YA, aunque haya sesiones
#      activas. Es la única red real en esta máquina (UPower no puede hibernar
#      ni hacer poweroff: CanHibernate=na + AllowRiskyCriticalPowerAction=false).
#   2) Inactividad: tapa cerrada + NINGUNA sesión activa durante SUSPEND_DELAY s.
# "Sesión activa" = marcador refrescado dentro de ACTIVE_TTL (heartbeat).
#
# La suspensión es un Suspend() explícito a logind (un inhibidor block de
# handle-lid-switch NO bloquea el Suspend explícito), así que NO hace falta
# soltar el inhibidor antes: lo sigue sosteniendo el servicio para el próximo
# cierre de tapa. Rutas/comando/umbral salen por env (defaults de producción)
# para testear aislado sin suspender.

ACTIVE_DIR=${CLAUDE_ACTIVE_DIR:-/tmp/claude-active.d}
LID_FILE=${CLAUDE_LID_FILE:-/proc/acpi/button/lid/LID0/state}
SUSPEND_DELAY=${CLAUDE_SUSPEND_DELAY:-60}
ACTIVE_TTL=${CLAUDE_ACTIVE_TTL:-600}
BATTERY_FLOOR=${CLAUDE_BATTERY_FLOOR:-12}
SUSPEND_CMD=${CLAUDE_SUSPEND_CMD:-"dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Suspend boolean:false"}
CHECK_CLAUDE_EVERY=${CLAUDE_CHECK_EVERY:-30}
LOG=/tmp/claude-inhibit.log
DEBUG_FLAG=/tmp/claude-inhibit-debug

log() { [ -f "$DEBUG_FLAG" ] && echo "$(date '+%H:%M:%S.%3N') watch: $*" >> "$LOG"; }

# % de batería. Override por archivo para tests; default lee /sys. Sin batería
# (desktop) -> 100 (el piso nunca dispara).
battery_pct() {
    if [ -n "${CLAUDE_BATTERY_FILE:-}" ]; then
        local v; read -r v < "$CLAUDE_BATTERY_FILE" 2>/dev/null; echo "${v:-100}"; return
    fi
    local f cap
    for f in /sys/class/power_supply/BAT*/capacity; do
        [ -r "$f" ] && { read -r cap < "$f"; echo "$cap"; return; }
    done
    echo 100
}

# ¿A batería (no enchufado)? Override por archivo para tests (1=hay AC).
on_battery() {
    if [ -n "${CLAUDE_AC_ONLINE_FILE:-}" ]; then
        local v; read -r v < "$CLAUDE_AC_ONLINE_FILE" 2>/dev/null
        [ "$v" = "1" ] && return 1 || return 0
    fi
    local f type online
    for f in /sys/class/power_supply/*/type; do
        [ -r "$f" ] || continue
        read -r type < "$f"
        [ "$type" = "Mains" ] || continue
        online=$(cat "${f%/type}/online" 2>/dev/null)
        [ "$online" = "1" ] && return 1   # AC enchufado -> NO a batería
    done
    return 0
}

# Cuenta sesiones activas y purga marcadores huérfanos (PID muerto). Un marcador
# solo cuenta si su mtime está dentro de ACTIVE_TTL (heartbeat fresco).
active_sessions() {
    local n=0 m pid now mtime
    now=$(date +%s)
    for m in "$ACTIVE_DIR"/*; do
        [ -e "$m" ] || continue
        pid=${m##*/}
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$m"; continue
        fi
        mtime=$(stat -c %Y "$m" 2>/dev/null || echo 0)
        [ $(( now - mtime )) -le "$ACTIVE_TTL" ] && n=$((n+1))
    done
    echo "$n"
}

# ¿Sigue vivo algún claude? Si no, salimos con 0 (systemd NO reinicia en exit 0)
# y soltamos el inhibidor -> auto-cleanup al cerrar todas las consolas.
any_claude_alive() {
    local cpid
    for cpid in $(pgrep -x claude 2>/dev/null); do
        readlink "/proc/$cpid/exe" 2>/dev/null | grep -q "claude/versions" && return 0
    done
    return 1
}

log "watcher arrancó (floor=${BATTERY_FLOOR}% delay=${SUSPEND_DELAY}s ttl=${ACTIVE_TTL}s)"
trap 'log "watcher recibió SIGTERM -> salgo (inhibidor se suelta)"; exit 0' TERM INT

PREV_LID="?"
LOOPS=0
closed_secs=0

while true; do
    LOOPS=$((LOOPS+1))

    # Auto-cleanup: si no queda ningún claude, salir limpio (exit 0).
    if (( LOOPS % CHECK_CLAUDE_EVERY == 0 )) && [ -z "${CLAUDE_SKIP_CLAUDE_CHECK:-}" ]; then
        if ! any_claude_alive; then
            log "no hay claude vivo -> exit 0 (servicio queda inactivo, inhibidor liberado)"
            rm -rf "$ACTIVE_DIR"
            exit 0
        fi
    fi

    read -r _ STATE < "$LID_FILE" 2>/dev/null

    if [ "$STATE" != "$PREV_LID" ]; then
        log "lid $PREV_LID -> $STATE"
        PREV_LID=$STATE
        [ "$STATE" != "closed" ] && closed_secs=0
    fi

    if [ "$STATE" = "closed" ]; then
        # (1) PISO DE BATERIA: red propia, override de sesiones activas.
        PCT=$(battery_pct)
        if on_battery && [ "$PCT" -le "$BATTERY_FLOOR" ]; then
            log "PISO BATERIA: ${PCT}% <= ${BATTERY_FLOOR}% con tapa cerrada -> Suspend YA (ignora sesiones activas)"
            eval "$SUSPEND_CMD"
            closed_secs=0
            sleep 5   # backoff anti-loop si al despertar sigue bajo y cerrado
            continue
        fi
        # (2) Inactividad: contar segundos sin ninguna sesión activa.
        if [ "$(active_sessions)" -eq 0 ]; then
            closed_secs=$((closed_secs+1))
            if [ "$closed_secs" -ge "$SUSPEND_DELAY" ]; then
                log "tapa cerrada + 0 sesiones activas por ${SUSPEND_DELAY}s -> Suspend"
                eval "$SUSPEND_CMD"
                closed_secs=0
                sleep 5
            fi
        else
            closed_secs=0
        fi
    else
        closed_secs=0
    fi

    sleep 1
done
