#!/usr/bin/env bash

# Kill a tmux session (and all grouped children)
# Usage: kill-session.sh "session_name: ..."

# Source session group utilities
source "$(dirname "$0")/tmux-session-utils.sh"

# Extract session name from the input
session_name=$(echo "$1" | cut -d: -f1)

# Kill the session and all grouped children
kill_session_group "$session_name"