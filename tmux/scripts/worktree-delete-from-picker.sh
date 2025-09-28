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

# Write deletion info to a temp file for confirmation
TEMP_DELETE_FILE="/tmp/tmux-worktree-delete-$$"
echo "$TICKET|$WORKTREE_PATH|$REPO_NAME" > "$TEMP_DELETE_FILE"

# Exit to close current fzf and trigger confirmation
exit 99