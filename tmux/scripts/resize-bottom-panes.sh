#!/usr/bin/env bash
# Resize all bottom status panes in a session to 1 line

SESSION="$1"

if [ -z "$SESSION" ]; then
    exit 0
fi

# For each window in the session
for window_info in $(tmux list-windows -t "$SESSION" -F "#{window_index}" 2>/dev/null); do
    # Find the status bar pane
    STATUS_PANE=$(tmux list-panes -t "$SESSION:$window_info" -F "#{pane_id}:#{pane_title}" 2>/dev/null | grep "__tmux_status_bar__" | cut -d: -f1)
    
    if [ -n "$STATUS_PANE" ]; then
        # Resize to 1 line
        tmux resize-pane -t "$STATUS_PANE" -y 1 2>/dev/null
    fi
done