#!/usr/bin/env bash
# Update tmux environment with current SERVER_PORT value

if [ -n "$TMUX" ]; then
    if [ -n "$SERVER_PORT" ]; then
        # Update session environment ONLY - each session has its own SERVER_PORT
        tmux set-environment SERVER_PORT "$SERVER_PORT"
    else
        # Remove from session environment if unset
        tmux set-environment -u SERVER_PORT
    fi
    
    # Refresh status bar
    tmux refresh-client -S
fi