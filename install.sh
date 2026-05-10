#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/commands" "$HOME/.claude/goal"

ln -sfn "$ROOT/goal" "$HOME/.claude/skills/goal"
chmod +x "$ROOT/goal/scripts/claude_goal.py"

# Older installs created a legacy ~/.claude/commands/goal.md shim. Claude Code
# now exposes the skill itself as /goal, so keeping both produces duplicate
# entries in /help.
if [ -L "$HOME/.claude/commands/goal.md" ] && [ "$(readlink "$HOME/.claude/commands/goal.md")" = "$ROOT/goal.md" ]; then
  rm "$HOME/.claude/commands/goal.md"
fi

python3 - "$HOME/.claude/settings.json" "$ROOT/goal/scripts/claude_goal.py" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
script_path = Path(sys.argv[2])
settings_path.parent.mkdir(parents=True, exist_ok=True)
if settings_path.exists():
    data = json.loads(settings_path.read_text())
else:
    data = {}


def ensure_hook(bucket_name: str, command: str) -> None:
    """Append a hook entry to settings['hooks'][bucket_name] if absent."""
    hooks = data.setdefault("hooks", {})
    bucket = hooks.setdefault(bucket_name, [])
    for item in bucket:
        for existing in item.get("hooks", []):
            if existing.get("command") == command:
                return
    bucket.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": command}],
    })


# Stop hook: blocks the worker session from stopping while a goal is
# active or pending_audit.
ensure_hook("Stop", f"python3 {script_path} stop-hook")
# SessionStart hook: propagates CLAUDE_SESSION_ID into the session's Bash
# env so parallel Claude Code sessions stay isolated even without
# TERM_SESSION_ID. Claude Code calls this once per session at start.
ensure_hook("SessionStart", f"python3 {script_path} session-start-hook")

settings_path.write_text(json.dumps(data, indent=2) + "\n")
PY

echo "Installed /goal for Claude Code."
echo "Skill: $HOME/.claude/skills/goal"
echo "Stop hook: python3 $ROOT/goal/scripts/claude_goal.py stop-hook"
echo "SessionStart hook: python3 $ROOT/goal/scripts/claude_goal.py session-start-hook"
echo "State DB: $HOME/.claude/goal/goals.sqlite"
