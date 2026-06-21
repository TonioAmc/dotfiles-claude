#!/usr/bin/env bash
# Hook PreToolUse(Edit|Write|MultiEdit) — snapshot Btrfs automatico antes de
# editar configs criticas. Dedup 5min por config (home/root). Snap-pac ya
# cubre las operaciones de pacman/paru, este hook solo cubre ediciones.

set -u

DEDUP_SECS=300
TS_DIR="/tmp"

file=$(jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
[ -z "$file" ] && exit 0

case "$file" in
    /home/antolin/.config/hypr/*|\
    /home/antolin/.config/hypr/**|\
    /home/antolin/.config/fish/*|\
    /home/antolin/.config/fish/**|\
    /home/antolin/.config/kitty/*|\
    /home/antolin/.config/kitty/**|\
    /home/antolin/.config/mako/*|\
    /home/antolin/.config/waybar/*|\
    /home/antolin/.config/wofi/*|\
    /home/antolin/.config/hyprpaper.conf|\
    /home/antolin/.claude/settings.json|\
    /home/antolin/.claude/settings.local.json)
        config="home"
        ;;
    /etc/*|/usr/*)
        config="root"
        ;;
    *)
        exit 0
        ;;
esac

ts_file="$TS_DIR/claude-snap-$config.ts"
now=$(date +%s)
if [ -f "$ts_file" ]; then
    last=$(cat "$ts_file" 2>/dev/null || echo 0)
    if [ $((now - last)) -lt $DEDUP_SECS ]; then
        exit 0
    fi
fi

desc="claude-edit: $(basename "$file")"
if sudo snapper -c "$config" create --cleanup-algorithm number --description "$desc" 2>/dev/null; then
    echo "$now" > "$ts_file"
fi

exit 0
