#!/bin/bash
# Advanced session picker for tmux

SESSIONS=$(tmux list-sessions -F "#{session_name}: #{session_windows} windows, created #{session_created}")

if [ $(echo "$SESSIONS" | wc -l) -eq 1 ]; then
    tmux display-message "Only one session active: $(echo "$SESSIONS" | cut -d: -f1)"
else
    # Use tmux's built-in chooser with enhanced format
    tmux choose-session -F "#{session_name}: #{session_windows} windows, #{?session_attached,attached,not attached}"
fi