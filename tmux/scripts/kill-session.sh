#!/usr/bin/env bash

# Kill a tmux session
# Usage: kill-session.sh "session_name: ..."

# Extract session name from the input
session_name=$(echo "$1" | cut -d: -f1)

# Kill the session
tmux kill-session -t "$session_name" 2>/dev/null