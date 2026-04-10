#!/usr/bin/env bash
# PostToolUse hook: when a PR is created in a worktree, write the .done marker
# so the autopilot runner can transition state. Updates on every PR creation,
# not just the first — handles follow-up PRs from continued chat.

MARKERS_DIR="$HOME/.config/autopilot/markers"
WORKTREES_BASE="$HOME/worktrees"

INPUT=$(cat)

# Parse with node
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

CWD=$(json_get cwd)
[ -z "$CWD" ] && CWD="${PWD:-}"

WORKTREE_NAME=""
if [[ "$CWD" == "$WORKTREES_BASE/"* ]]; then
    relative="${CWD#$WORKTREES_BASE/}"
    WORKTREE_NAME=$(echo "$relative" | cut -d'/' -f2)
fi
[ -z "$WORKTREE_NAME" ] && exit 0

TOOL_NAME=$(json_get tool_name)

# Only care about Bash and GitHub MCP PR creation tools
case "$TOOL_NAME" in
    Bash)
        # Check if output contains a PR URL (gh pr create output)
        OUTPUT=$(json_get tool_output)
        PR_URL=$(echo "$OUTPUT" | grep -oE 'https://github[^[:space:]"]*pull/[0-9]+' | head -1)
        ;;
    mcp__github-work__create_pull_request|mcp__github-personal__create_pull_request)
        OUTPUT=$(json_get tool_output)
        PR_URL=$(echo "$OUTPUT" | grep -oE 'https://github[^[:space:]"]*pull/[0-9]+' | head -1)
        ;;
    *)
        exit 0
        ;;
esac

if [ -n "$PR_URL" ]; then
    mkdir -p "$MARKERS_DIR"
    echo "$PR_URL" > "$MARKERS_DIR/${WORKTREE_NAME}.done"
fi

exit 0
