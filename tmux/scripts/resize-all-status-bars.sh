#!/usr/bin/env bash

SESSION="${1:-base}"

# Find all windows in the session
WINDOWS=$(tmux list-windows -t "$SESSION" -F "#{window_index}" 2>/dev/null)

for window in $WINDOWS; do
    # Find all status bar panes in this window
    STATUS_PANES=$(tmux list-panes -t "$SESSION:$window" -F "#{pane_id} #{pane_title}" 2>/dev/null | grep "__tmux_status_bar__" | awk '{print $1}')
    
    # Resize each status bar pane to 1 line
    for pane in $STATUS_PANES; do
        tmux resize-pane -t "$pane" -y 1 2>/dev/null || true
    done
done

# Remove the hook after running
tmux set-hook -t "$SESSION" -u client-attached 2>/dev/null || true