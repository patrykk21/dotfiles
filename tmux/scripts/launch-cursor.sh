#!/usr/bin/env bash
# Launch Cursor IDE in current directory

# Get current directory from tmux
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Check if cursor command exists
if ! command -v cursor >/dev/null 2>&1; then
    tmux display-message "Cursor IDE not found in PATH"
    exit 1
fi

# Launch Cursor in the current directory
cd "$CURRENT_DIR" && cursor . >/dev/null 2>&1 &

tmux display-message "Launched Cursor IDE in $CURRENT_DIR"