#!/usr/bin/env bash
# Tracks AI activity in worktrees by watching tool use events.
# Detects PR creation and writes the completion marker so the
# autopilot runner can transition state — works for /autopilot
# AND manual Claude sessions.
#
# Hook events: PostToolUse
# Reads JSON from stdin with tool_name, tool_input, tool_output

MARKERS_DIR="$HOME/.config/autopilot/markers"
WORKTREES_BASE="$HOME/worktrees"
STATE_DIR="$HOME/.config/autopilot/projects"

# Read hook data
INPUT=$(cat)

# Parse with node (cross-platform)
json_get() {
    echo "$INPUT" | node -e "
        let d='';process.stdin.on('data',c=>d+=c);
        process.stdin.on('end',()=>{try{
            const o=JSON.parse(d);
            const path='$1'.split('.');
            let v=o;for(const k of path)v=v?.[k];
            console.log(v??'')
        }catch{console.log('')}})
    " 2>/dev/null || echo ""
}

# Get CWD and determine worktree
CWD=$(json_get cwd)
[ -z "$CWD" ] && CWD="${PWD:-}"

WORKTREE_NAME=""
if [[ "$CWD" == "$WORKTREES_BASE/"* ]]; then
    relative="${CWD#$WORKTREES_BASE/}"
    WORKTREE_NAME=$(echo "$relative" | cut -d'/' -f2)
fi

# Not in a worktree — skip
[ -z "$WORKTREE_NAME" ] && exit 0

# Get tool info
TOOL_NAME=$(json_get tool_name)
TOOL_INPUT=$(json_get tool_input)
TOOL_OUTPUT=$(json_get tool_output)

mkdir -p "$MARKERS_DIR"
DONE_MARKER="$MARKERS_DIR/${WORKTREE_NAME}.done"

# Detect PR creation — multiple methods:
# 1. gh pr create via Bash tool
# 2. GitHub MCP create_pull_request
# 3. Output containing a PR URL pattern

case "$TOOL_NAME" in
    Bash)
        # Check if the command was gh pr create
        if echo "$TOOL_INPUT" | grep -q "gh pr create\|gh pr create"; then
            # Extract PR URL from output
            PR_URL=$(echo "$TOOL_OUTPUT" | grep -oE 'https://github[^[:space:]]*pull/[0-9]+' | head -1)
            if [ -n "$PR_URL" ]; then
                echo "$PR_URL" > "$DONE_MARKER"
            fi
        fi
        ;;
    mcp__github-work__create_pull_request|mcp__github-personal__create_pull_request)
        # GitHub MCP tool — extract PR URL from output
        PR_URL=$(echo "$TOOL_OUTPUT" | grep -oE 'https://github[^"[:space:]]*pull/[0-9]+' | head -1)
        if [ -n "$PR_URL" ]; then
            echo "$PR_URL" > "$DONE_MARKER"
        fi
        ;;
esac

exit 0
