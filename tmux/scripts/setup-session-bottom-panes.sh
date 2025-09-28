#!/usr/bin/env bash

# Setup bottom panes for all windows in a session

SESSION="$1"

if [ -z "$SESSION" ]; then
    echo "Usage: $0 <session-name>"
    exit 1
fi

# Check if session exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    exit 0
fi

# Get all windows in the session
tmux list-windows -t "$SESSION" -F "#{session_name}:#{window_index}" | while read -r window; do
    ~/.config/tmux/scripts/create-bottom-pane-for-window.sh "$window"
done