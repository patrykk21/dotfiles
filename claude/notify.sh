#!/bin/bash

# Claude Code ntfy.sh notification script
# Sends notifications when Claude needs attention

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

# Detect project and worktree from cwd
WORKTREES_BASE="$HOME/worktrees"
if [[ "$PWD" == "$WORKTREES_BASE/"* ]]; then
    relative="${PWD#$WORKTREES_BASE/}"
    project_name=$(echo "$relative" | cut -d'/' -f1)
    worktree_name=$(echo "$relative" | cut -d'/' -f2)
    working_dir="$project_name/$worktree_name"
else
    working_dir="$(basename "$PWD")"
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