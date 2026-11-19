#!/bin/bash

# Claude Code ntfy.sh notification script
# Sends notifications when Claude needs attention

# Paused while this file exists; delete it to resume notifications.
[ -f "$HOME/.claude/notify.disabled" ] && exit 0

# Configuration via environment variables
NTFY_TOPIC="${CLAUDE_NOTIFY_TOPIC:-claude-code}"
NTFY_SERVER="${CLAUDE_NOTIFY_SERVER:-https://ntfy.sh}"
NTFY_PRIORITY="${CLAUDE_NOTIFY_PRIORITY:-default}"

# Function to send notification
send_notification() {
    local title="$1"
    local message="$2"
    local priority="${3:-$NTFY_PRIORITY}"
    
    # Check if topic is configured
    if [ -z "$NTFY_TOPIC" ] || [ "$NTFY_TOPIC" = "claude-code" ]; then
        echo "Warning: CLAUDE_NOTIFY_TOPIC not configured. Set it to your ntfy topic." >&2
        echo "Example: export CLAUDE_NOTIFY_TOPIC=your-topic-name" >&2
        return 1
    fi
    
    # Send notification to ntfy
    curl -s \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: robot,claude" \
        -d "$message" \
        "$NTFY_SERVER/$NTFY_TOPIC" > /dev/null 2>&1
    
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "Failed to send notification (exit code: $exit_code)" >&2
        return $exit_code
    fi
    
    echo "Notification sent: $title" >&2
    return 0
}

# Determine notification type from command line argument
hook_type="${1:-unknown}"
tool_name="${CLAUDE_TOOL_NAME:-}"

# Label resolution, first match wins:
#   1. CLAUDE_NOTIFY_LABEL — explicit per-session label set at launch
#   2. git: "project/worktree" in a linked worktree, "project" in the base repo.
#      In a linked worktree, --git-dir points inside the main repo's .git/worktrees/,
#      while --git-common-dir points at the main repo's .git — they differ only there.
#   3. basename of cwd
if [ -n "$CLAUDE_NOTIFY_LABEL" ]; then
    working_dir="$CLAUDE_NOTIFY_LABEL"
else
    toplevel=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$toplevel" ]; then
        git_dir=$(git -C "$PWD" rev-parse --path-format=absolute --git-dir 2>/dev/null)
        common_dir=$(git -C "$PWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
        if [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ]; then
            project_name=$(basename "$(dirname "$common_dir")")
            working_dir="$project_name/$(basename "$toplevel")"
        else
            working_dir=$(basename "$toplevel")
        fi
    else
        working_dir=$(basename "$PWD")
    fi
fi

case "$hook_type" in
    "Stop")
        send_notification \
            "Claude Code: Ready for Input" \
            "Claude has finished responding and is waiting for your input in $working_dir"
        ;;
    "Notification")
        send_notification \
            "Claude Code: Permission Needed" \
            "Claude needs your permission or input to continue in $working_dir" \
            "high"
        ;;
    "PostToolUse")
        if [ -n "$tool_name" ]; then
            send_notification \
                "Claude Code: Tool Complete" \
                "Tool '$tool_name' completed in $working_dir"
        else
            send_notification \
                "Claude Code: Task Complete" \
                "A task has completed in $working_dir"
        fi
        ;;
    "UserPromptSubmit")
        send_notification \
            "Claude Code: Processing" \
            "Processing your request in $working_dir" \
            "low"
        ;;
    *|"unknown")
        send_notification \
            "Claude Code: Permission Needed" \
            "Claude needs your permission or input to continue in $working_dir" \
            "high"
        ;;
esac