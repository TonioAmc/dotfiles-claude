#!/bin/bash
# Stop hook: Claude terminó turno (o entró en AskUserQuestion).
# El watcher persistente se encarga del flujo de lid → suspend.
# Acá solo marcamos a Claude como idle para que el watcher pueda armar timer.

ACTIVE=/tmp/claude-active
LOG=/tmp/claude-inhibit.log
DEBUG_FLAG=/tmp/claude-inhibit-debug

log() { [ -f "$DEBUG_FLAG" ] && echo "$(date '+%H:%M:%S.%3N') stop:  $*" >> "$LOG"; }

log "invoked → marcando claude idle"
rm -f "$ACTIVE"
