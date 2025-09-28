#!/usr/bin/env bash
# Protect the bottom status pane from being selected

# Get current pane title
CURRENT_PANE_TITLE=$(tmux display-message -p "#{pane_title}")

# If we just selected the status bar pane, immediately switch away
if [[ "$CURRENT_PANE_TITLE" == "__tmux_status_bar__" ]]; then
    # Get the last pane we were on
    tmux select-pane -l
fi