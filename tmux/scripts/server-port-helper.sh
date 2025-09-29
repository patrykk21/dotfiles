#!/usr/bin/env bash
# Shell function to set SERVER_PORT and update tmux
# Source this in your .zshrc or .bashrc

set_server_port() {
    export SERVER_PORT="$1"
    
    # Update tmux if we're inside tmux
    if [ -n "$TMUX" ]; then
        tmux set-environment SERVER_PORT "$SERVER_PORT"
        tmux set-environment -g SERVER_PORT "$SERVER_PORT"
        tmux refresh-client -S
    fi
}

# Auto-update function that watches for SERVER_PORT changes
# This can be called from shell prompt hooks
update_tmux_server_port() {
    if [ -n "$TMUX" ] && [ -n "$SERVER_PORT" ]; then
        # Get current tmux value
        TMUX_PORT=$(tmux show-environment SERVER_PORT 2>/dev/null | cut -d= -f2)
        
        # Update if different
        if [ "$TMUX_PORT" != "$SERVER_PORT" ]; then
            tmux set-environment SERVER_PORT "$SERVER_PORT"
            tmux set-environment -g SERVER_PORT "$SERVER_PORT"
            tmux refresh-client -S
        fi
    fi
}