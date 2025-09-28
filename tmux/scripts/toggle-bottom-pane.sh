#!/usr/bin/env bash
# Toggle the bottom status pane on/off

# Check if a status bar pane exists
STATUS_PANE=$(tmux list-panes -F "#{pane_id}:#{pane_title}" | grep ":__tmux_status_bar__$" | cut -d: -f1)

if [[ -n "$STATUS_PANE" ]]; then
    # Bottom pane exists, kill it
    tmux kill-pane -t "$STATUS_PANE"
    tmux display-message "Bottom status bar hidden"
else
    # No bottom pane, create it
    ~/.config/tmux/scripts/create-bottom-pane.sh
    tmux display-message "Bottom status bar shown"
fi