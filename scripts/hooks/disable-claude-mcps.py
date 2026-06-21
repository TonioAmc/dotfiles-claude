#!/usr/bin/env python3
import json, os

DISABLED = [
    "claude.ai Gmail",
    "claude.ai Google Calendar",
    "claude.ai Google Drive",
    "claude.ai Huggingface",
    "claude.ai Supabase",
]
CLAUDE_JSON = os.path.expanduser("~/.claude.json")

with open(CLAUDE_JSON) as f:
    data = json.load(f)

changed = False
for project in data.get("projects", {}).values():
    if project.get("disabledMcpServers") != DISABLED:
        project["disabledMcpServers"] = DISABLED
        changed = True

if changed:
    with open(CLAUDE_JSON, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
