#!/usr/bin/env bash

# Setup bottom status bars for all windows in current session

SESSION="${1:-$(tmux display-message -p '#S')}"

# Get all windows in the session
WINDOWS=$(tmux list-windows -t "$SESSION" -F '#I')

for window in $WINDOWS; do
    # Create bottom pane (if it doesn't exist) - silently
    ~/.config/tmux/scripts/create-bottom-pane-for-window.sh "$SESSION:$window" 2>/dev/null
done