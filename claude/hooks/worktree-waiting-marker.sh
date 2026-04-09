#!/usr/bin/env bash
# Writes/clears a .waiting marker based on whether Claude is waiting for input.
# The worktree picker shows ">" for sessions with this marker.
#
# Called as both a Stop hook (write marker) and PreToolUse hook (clear marker).
# Reads JSON from stdin — uses hook_event_name to determine action.

MARKERS_DIR="$HOME/.config/autopilot/markers"
WORKTREES_BASE="$HOME/worktrees"

# Read hook data from stdin
INPUT=$(cat)

# Get CWD from hook data, fall back to PWD
CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "${PWD:-}")

# Determine worktree name from CWD
WORKTREE_NAME=""
if [[ "$CWD" == "$WORKTREES_BASE/"* ]]; then
    relative="${CWD#$WORKTREES_BASE/}"
    WORKTREE_NAME=$(echo "$relative" | cut -d'/' -f2)
fi

# Not in a worktree — skip silently
[ -z "$WORKTREE_NAME" ] && exit 0

MARKER="$MARKERS_DIR/${WORKTREE_NAME}.waiting"
mkdir -p "$MARKERS_DIR"

# Get event name
EVENT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_event_name',''))" 2>/dev/null || echo "")

case "$EVENT" in
    Stop)
        # Claude finished responding — waiting for user input
        echo "Waiting for input" > "$MARKER"
        ;;
    *)
        # PreToolUse or anything else — Claude is working, clear marker
        rm -f "$MARKER" 2>/dev/null
        ;;
esac

exit 0
