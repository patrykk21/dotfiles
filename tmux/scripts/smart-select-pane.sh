#!/usr/bin/env bash
# Smart pane selection that skips the bottom status pane

DIRECTION=$1

# Try to select pane in the requested direction
tmux select-pane -$DIRECTION

# Check if we landed on the status bar pane
CURRENT_PANE_TITLE=$(tmux display-message -p "#{pane_title}")
if [[ "$CURRENT_PANE_TITLE" == "__tmux_status_bar__" ]]; then
    # Skip it and try again
    tmux select-pane -$DIRECTION
    
    # If we're still on the status bar, go back to where we were
    NEW_PANE_TITLE=$(tmux display-message -p "#{pane_title}")
    if [[ "$NEW_PANE_TITLE" == "__tmux_status_bar__" ]]; then
        tmux select-pane -l
    fi
fi