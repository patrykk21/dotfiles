#!/usr/bin/env bash

# Setup bottom panes for a worktree session
# This is called after the session is fully created and switched to

SESSION="$1"

if [ -z "$SESSION" ]; then
    echo "Usage: $0 <session-name>"
    exit 1
fi

# Check if session exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session $SESSION does not exist"
    exit 1
fi

# Setup bottom pane for each window
for window in 1 2 3; do
    # Check if this window already has a bottom pane
    EXISTING=$(tmux list-panes -t "$SESSION:$window" -F "#{pane_title}" 2>/dev/null | grep -c "__tmux_status_bar__")
    
    if [ "$EXISTING" -eq 0 ]; then
        # Create bottom pane for this window
        BOTTOM_PANE=$(tmux split-window -t "$SESSION:$window.1" -v -d -P -F "#{pane_id}" "~/.config/tmux/scripts/bottom-pane-display.sh")
        tmux select-pane -t "$BOTTOM_PANE" -T "__tmux_status_bar__"
        # Resize to 1 line
        tmux resize-pane -t "$BOTTOM_PANE" -y 1
    fi
done