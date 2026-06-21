#!/usr/bin/env bash
# Hook para Claude Code: inyecta el correo activo del TUI como contexto
FILE="/tmp/hmail-current.json"

[ -f "$FILE" ] || exit 0

# Solo inyectar si el archivo tiene menos de 10 minutos
AGE=$(( $(date +%s) - $(stat -c %Y "$FILE") ))
[ "$AGE" -lt 600 ] || exit 0

# Dedup: no reinyectar el mismo correo en cada prompt (ahorra ~800 tokens/turno)
HASH=$(md5sum "$FILE" | cut -d' ' -f1)
LAST="/tmp/hmail-last-injected.md5"
[ -f "$LAST" ] && [ "$(cat "$LAST")" = "$HASH" ] && exit 0
echo "$HASH" > "$LAST"

python3 - << 'EOF'
import json, sys

with open("/tmp/hmail-current.json") as f:
    m = json.load(f)

subj = m.get("subject", "")
frm  = m.get("from", {})
date = m.get("date", "")
body = (m.get("body", "") or "")[:3000]
acct = m.get("account", "")
mid  = m.get("id", "")

print(f"[CORREO SELECCIONADO EN TUI]")
print(f"Cuenta : {acct}  (ID: {mid})")
print(f"De     : {frm.get('name','')} <{frm.get('addr','')}>")
print(f"Asunto : {subj}")
print(f"Fecha  : {date}")
print(f"{'─'*60}")
print(body.strip())
print(f"[/CORREO SELECCIONADO]")
EOF
