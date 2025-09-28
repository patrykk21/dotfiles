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

# Show fzf confirmation dialog
confirm=$(printf "NO - Cancel\nYES - Delete worktree '$TICKET'" | fzf-tmux -p 50%,30% \
    --prompt=" Delete worktree '$TICKET'? " \
    --header="This will permanently delete the worktree and its session" \
    --header-lines=0 \
    --no-sort \
    --color="fg:250,bg:235,hl:168,fg+:235,bg+:168,hl+:235,prompt:168,pointer:168,header:180" \
    --border=rounded \
    --border-label=" ⚠️  Confirm Deletion " \
    --no-multi)

# Check if user confirmed deletion
if [[ "$confirm" == "YES"* ]]; then
    # Kill tmux session if it exists
    tmux has-session -t "$TICKET" 2>/dev/null && tmux kill-session -t "$TICKET" 2>/dev/null
    
    # Remove metadata if it exists
    remove_session_metadata "$REPO_NAME" "$TICKET"
    
    # Remove the git worktree
    git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || git worktree prune
    
    # Display success message
    tmux display-message -d 2000 "✓ Deleted worktree: $TICKET"
else
    # Display cancellation message
    tmux display-message -d 1000 "Deletion cancelled"
fi