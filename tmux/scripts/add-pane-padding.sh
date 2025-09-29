#!/usr/bin/env bash

# Add visual padding to all panes by inserting empty lines at the top
# This creates separation from the status bar without making it thicker

for pane in $(tmux list-panes -F '#{pane_id}'); do
    # Skip the bottom status bar pane
    if [[ $(tmux display-message -p -t "$pane" '#{pane_height}') -eq 1 ]]; then
        continue
    fi
    
    # Send a clear sequence that adds padding at the top
    tmux send-keys -t "$pane" C-l
done