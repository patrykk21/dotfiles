#!/usr/bin/env bash
# Hook script to ensure SERVER_PORT is set in new windows

# Get SERVER_PORT from tmux environment
SERVER_PORT=$(tmux show-environment -g SERVER_PORT 2>/dev/null | cut -d= -f2)

# Export it if found and not unset marker
if [ -n "$SERVER_PORT" ] && [ "$SERVER_PORT" != "-SERVER_PORT" ]; then
    export SERVER_PORT="$SERVER_PORT"
fi

# Execute the user's shell
exec "$SHELL"