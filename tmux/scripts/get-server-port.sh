#!/usr/bin/env bash
# Get the actual SERVER_PORT for the current session

SESSION="$1"

# Method 1: Check if there's a bun/node process running and get port from lsof
SERVER_PIDS=$(tmux list-panes -t "$SESSION" -F '#{pane_pid}' | xargs -I {} pgrep -P {} -f 'bun|node' 2>/dev/null | head -5)

if [ -n "$SERVER_PIDS" ]; then
    for PID in $SERVER_PIDS; do
        # Get listening ports for this process
        PORT=$(lsof -Pi -p "$PID" 2>/dev/null | grep LISTEN | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
        if [ -n "$PORT" ]; then
            echo "$PORT"
            exit 0
        fi
    done
fi

# Method 2: Check tmux session environment
SERVER_PORT=$(tmux show-environment -t "$SESSION" SERVER_PORT 2>/dev/null | cut -d= -f2)
if [ -n "$SERVER_PORT" ] && [ "$SERVER_PORT" != "-SERVER_PORT" ]; then
    echo "$SERVER_PORT"
    exit 0
fi

# No port found
exit 0