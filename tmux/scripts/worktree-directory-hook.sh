#!/usr/bin/env bash

# Hook to ensure we're in the correct worktree directory
# Called on window/pane focus

# Get the worktree path from session option
WORKTREE_PATH=$(tmux show-option -qv "@worktree_path")

# Only proceed if we have a worktree path
if [ -n "$WORKTREE_PATH" ]; then
    # Get current pane's working directory
    CURRENT_PATH=$(tmux display-message -p "#{pane_current_path}")
    
    # If we're not in the worktree path or a subdirectory of it
    if [[ "$CURRENT_PATH" != "$WORKTREE_PATH"* ]]; then
        # Get current pane command
        PANE_CMD=$(tmux display-message -p "#{pane_current_command}")
        
        # Only change directory if it's a shell
        if [[ "$PANE_CMD" =~ ^(zsh|bash|sh)$ ]]; then
            tmux send-keys C-u "cd $WORKTREE_PATH" Enter
        fi
    fi
fi