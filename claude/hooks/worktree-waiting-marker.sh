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

# Parse JSON with node (cross-platform — python3 may be a stub on Windows)
json_get() {
    echo "$INPUT" | node -e "
        let d='';process.stdin.on('data',c=>d+=c);
        process.stdin.on('end',()=>{try{console.log(JSON.parse(d)['$1']||'')}catch{console.log('')}})
    " 2>/dev/null || echo ""
}

# Get CWD from hook data, fall back to PWD
CWD=$(json_get cwd)
[ -z "$CWD" ] && CWD="${PWD:-}"

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
EVENT=$(json_get hook_event_name)

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
