#!/usr/bin/env bash

# Delete a worktree after confirmation
# This script is called after the user confirms deletion

# Source metadata functions
source "$(dirname "$0")/worktree-metadata.sh"

TICKET="$1"
WORKTREE_PATH="$2"
REPO_NAME="$3"

# Validate inputs
if [ -z "$TICKET" ] || [ -z "$WORKTREE_PATH" ] || [ -z "$REPO_NAME" ]; then
    tmux display-message -d 2000 "Error: Missing parameters for deletion"
    exit 1
fi

# Kill tmux session if it exists
tmux has-session -t "$TICKET" 2>/dev/null && tmux kill-session -t "$TICKET" 2>/dev/null

# Remove metadata if it exists
remove_session_metadata "$REPO_NAME" "$TICKET"

# Remove the git worktree
git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || git worktree prune

# Display success message
tmux display-message -d 2000 "✓ Deleted worktree: $TICKET"

# Refresh the picker if it's open
tmux send-keys -t '{last}' C-r 2>/dev/null || true