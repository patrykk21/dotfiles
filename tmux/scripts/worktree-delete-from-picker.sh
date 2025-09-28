#!/usr/bin/env bash

# Delete a worktree from the picker
# This is a helper script to avoid recursion issues with fzf

# Source metadata functions
source "$(dirname "$0")/worktree-metadata.sh"

# Get the full selection line
SELECTION="$*"

# Extract the ticket/session name and worktree path
# Account for new format with session status indicator
TICKET=$(echo "$SELECTION" | sed 's/^[[:space:]]*[→○●[:space:]]*//' | awk '{print $1}')
WORKTREE_PATH=$(echo "$SELECTION" | awk '{print $NF}')

# Validate inputs
if [ -z "$TICKET" ] || [ -z "$WORKTREE_PATH" ]; then
    exit 1
fi

# Get repository name from worktree path
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
REPO_NAME=$(basename "$MAIN_REPO")

# Kill tmux session if it exists
tmux has-session -t "$TICKET" 2>/dev/null && tmux kill-session -t "$TICKET" 2>/dev/null

# Remove metadata if it exists
remove_session_metadata "$REPO_NAME" "$TICKET"

# Remove the git worktree
git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || git worktree prune

# Exit silently
exit 0