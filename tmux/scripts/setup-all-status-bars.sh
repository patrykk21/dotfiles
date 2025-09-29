#!/usr/bin/env bash

# Setup bottom status bars for all windows in current session

SESSION="${1:-$(tmux display-message -p '#S')}"

# Get all windows in the session
WINDOWS=$(tmux list-windows -t "$SESSION" -F '#I')

for window in $WINDOWS; do
    echo "Setting up bottom status bar for window $window..."
    
    # Create bottom pane (if it doesn't exist)
    ~/.config/tmux/scripts/create-bottom-pane-for-window.sh "$SESSION:$window"
done

echo "Bottom status bars setup complete for session: $SESSION"