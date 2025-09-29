#!/usr/bin/env bash
# Smart pane selection that skips the top and bottom status panes

DIRECTION=$1

# Try to select pane in the requested direction
tmux select-pane -$DIRECTION

# Check if we landed on a status bar pane
CURRENT_PANE_TITLE=$(tmux display-message -p "#{pane_title}")
CURRENT_PANE_CMD=$(tmux display-message -p "#{pane_current_command}")

if [[ "$CURRENT_PANE_TITLE" == "__tmux_status_bar__" ]] || \
   [[ "$CURRENT_PANE_CMD" == *"bottom-prompt"* ]] || \
   [[ "$CURRENT_PANE_CMD" == *"top-status-bar"* ]]; then
    # Skip it and try again
    tmux select-pane -$DIRECTION
    
    # Check again if we're still on a status pane
    NEW_PANE_TITLE=$(tmux display-message -p "#{pane_title}")
    NEW_PANE_CMD=$(tmux display-message -p "#{pane_current_command}")
    
    if [[ "$NEW_PANE_TITLE" == "__tmux_status_bar__" ]] || \
       [[ "$NEW_PANE_CMD" == *"bottom-prompt"* ]] || \
       [[ "$NEW_PANE_CMD" == *"top-status-bar"* ]]; then
        # Go back to where we were
        tmux select-pane -l
    fi
fi