#!/usr/bin/env bash
# Protect the bottom and top status panes from being selected

# Get current pane information
CURRENT_PANE_TITLE=$(tmux display-message -p "#{pane_title}")
CURRENT_PANE_CMD=$(tmux display-message -p "#{pane_current_command}")

# If we just selected a status bar pane, immediately switch away
if [[ "$CURRENT_PANE_TITLE" == "__tmux_status_bar__" ]] || \
   [[ "$CURRENT_PANE_CMD" == *"bottom-prompt"* ]] || \
   [[ "$CURRENT_PANE_CMD" == *"top-status-bar"* ]]; then
    # Get the last pane we were on
    tmux select-pane -l
fi