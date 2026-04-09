#!/usr/bin/env bash
# Switch current client to a session, creating a grouped child if
# the target session (or any session in its group) already has a client.
# Runs inside the popup shell — the popup's parent client is the one
# that will be switched.

source "$(dirname "$0")/tmux-session-utils.sh"

TARGET_FILE="/tmp/tmux-switch-to-session"

if [ ! -f "$TARGET_FILE" ]; then
    exit 0
fi

TARGET=$(cat "$TARGET_FILE")
rm -f "$TARGET_FILE"

if [ -z "$TARGET" ]; then
    exit 0
fi

# Check if the target session exists
if ! tmux has-session -t "$TARGET" 2>/dev/null; then
    exit 1
fi

# Count clients attached to ANY session in this group (master + children).
# This handles the case where the master has 0 clients but a child has 1.
GROUP_CLIENTS=0
while IFS= read -r sess; do
    n=$(tmux list-clients -t "$sess" 2>/dev/null | wc -l | tr -d ' ')
    GROUP_CLIENTS=$((GROUP_CLIENTS + n))
done < <(tmux list-sessions -F '#{session_name} #{session_group}' 2>/dev/null | \
    awk -v grp="$TARGET" '$2 == grp { print $1 }')

if [ "$GROUP_CLIENTS" -gt 0 ]; then
    # Session group already has a client — create a grouped child
    CHILD=$(next_grouped_session_name "$TARGET")
    tmux new-session -d -t "$TARGET" -s "$CHILD"
    # Copy SERVER_PORT env to the child session
    PORT=$(tmux show-environment -t "$TARGET" SERVER_PORT 2>/dev/null | cut -d= -f2)
    if [ -n "$PORT" ] && [ "$PORT" != "-SERVER_PORT" ]; then
        tmux setenv -t "$CHILD" SERVER_PORT "$PORT"
    fi
    tmux switch-client -t "$CHILD"
else
    tmux switch-client -t "$TARGET"
fi
