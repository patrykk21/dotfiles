#!/usr/bin/env bash

# Clean up duplicate bottom panes in the current session

SESSION_NAME=$(tmux display-message -p "#{session_name}")

# Find all panes in the current session that are running bottom-pane-display.sh
BOTTOM_PANES=$(tmux list-panes -s -F "#{pane_id} #{pane_current_command}" | \
    grep "bottom-pane-display.sh" | \
    awk '{print $1}')

# Count how many bottom panes we have
PANE_COUNT=$(echo "$BOTTOM_PANES" | grep -v '^$' | wc -l)

if [ "$PANE_COUNT" -gt 1 ]; then
    echo "Found $PANE_COUNT bottom panes, keeping only the first one"
    
    # Keep the first one, kill the rest
    FIRST=true
    echo "$BOTTOM_PANES" | while read -r pane_id; do
        if [ "$FIRST" = true ]; then
            FIRST=false
            echo "Keeping pane: $pane_id"
        else
            echo "Killing duplicate pane: $pane_id"
            tmux kill-pane -t "$pane_id" 2>/dev/null
        fi
    done
elif [ "$PANE_COUNT" -eq 0 ]; then
    echo "No bottom panes found, creating one"
    ~/.config/tmux/scripts/create-bottom-pane.sh
else
    echo "Exactly one bottom pane found, no cleanup needed"
fi