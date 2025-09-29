#!/usr/bin/env bash

# Kill a tmux session from the worktree picker
# This only kills the session, not the worktree itself

# Get the full selection line
SELECTION="$*"

# Extract the ticket/session name and type
# Account for new format with session status indicator
TICKET=$(echo "$SELECTION" | sed 's/^[[:space:]]*[→○●[:space:]]*//' | awk '{print $1}')
TYPE=$(echo "$SELECTION" | sed 's/^[[:space:]]*[→○●[:space:]]*//' | awk '{print $2}')
SESSION_STATUS=$(echo "$SELECTION" | sed 's/^[[:space:]]*[→○●[:space:]]*//' | awk '{print $3}')

# Validate inputs
if [ -z "$TICKET" ]; then
    exit 1
fi

# Check if this has an active session
if [[ "$SESSION_STATUS" != "[SESSION]" ]]; then
    tmux display-message -d 1000 "No active session to kill"
    exit 0
fi

# Get current session to avoid killing it
CURRENT_SESSION=$(tmux display-message -p '#S')

# Check if we're trying to kill the current session
if [ "$TICKET" = "$CURRENT_SESSION" ]; then
    tmux display-message -d 1000 "Cannot kill current session"
    exit 0
fi

# Kill the session if it exists
if tmux has-session -t "$TICKET" 2>/dev/null; then
    tmux kill-session -t "$TICKET" 2>/dev/null
    tmux display-message -d 1000 "✓ Killed session: $TICKET"
else
    tmux display-message -d 1000 "Session not found: $TICKET"
fi