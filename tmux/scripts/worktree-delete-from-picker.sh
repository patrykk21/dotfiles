#!/usr/bin/env bash

# Delete a worktree from the picker
# This is a helper script to avoid recursion issues with fzf

# Get the full selection line
SELECTION="$*"

# Extract the ticket/session name and worktree path
TICKET=$(echo "$SELECTION" | awk '{print $2}')
WORKTREE_PATH=$(echo "$SELECTION" | awk '{print $NF}')

# Validate inputs
if [ -z "$TICKET" ] || [ -z "$WORKTREE_PATH" ]; then
    exit 1
fi

# Kill tmux session if it exists
tmux has-session -t "$TICKET" 2>/dev/null && tmux kill-session -t "$TICKET" 2>/dev/null

# Remove the git worktree
git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || git worktree prune

# Exit silently
exit 0