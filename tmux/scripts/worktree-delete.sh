#!/usr/bin/env bash

# Delete current worktree and its associated tmux session
# This script is called from within a tmux session

# Get current session name
CURRENT_SESSION=$(tmux display-message -p '#S')

# Get the main repository info
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
if [ -z "$MAIN_REPO" ]; then
    tmux display-message -d 2000 "Error: Not in a git repository"
    exit 1
fi

REPO_NAME=$(basename "$MAIN_REPO")
PARENT_DIR=$(dirname "$MAIN_REPO")

# Try to find the worktree path for this session
# First, check if we're in a worktree directory
CURRENT_PATH=$(pwd)
IS_WORKTREE=false
WORKTREE_PATH=""

# Check if current path is a worktree
if git worktree list | grep -q "$CURRENT_PATH"; then
    IS_WORKTREE=true
    WORKTREE_PATH="$CURRENT_PATH"
else
    # Try to find worktree by session name pattern
    EXPECTED_WORKTREE="$PARENT_DIR/$REPO_NAME-$CURRENT_SESSION"
    if [ -d "$EXPECTED_WORKTREE" ] && git worktree list | grep -q "$EXPECTED_WORKTREE"; then
        IS_WORKTREE=true
        WORKTREE_PATH="$EXPECTED_WORKTREE"
    fi
fi

# If not in a worktree, check if session name matches a ticket pattern
if [ "$IS_WORKTREE" = false ]; then
    # Check all worktrees to find one that matches the session name
    while IFS= read -r line; do
        worktree_dir=$(echo "$line" | awk '{print $1}')
        if [[ "$worktree_dir" == *"-$CURRENT_SESSION" ]]; then
            IS_WORKTREE=true
            WORKTREE_PATH="$worktree_dir"
            break
        fi
    done < <(git worktree list | tail -n +2)
fi

# If we still haven't found a worktree, this session might not be associated with one
if [ "$IS_WORKTREE" = false ]; then
    tmux display-message -d 2000 "Error: Current session '$CURRENT_SESSION' is not associated with a git worktree"
    exit 1
fi

# Confirm we're not trying to delete the main worktree
if [ "$WORKTREE_PATH" = "$MAIN_REPO" ]; then
    tmux display-message -d 2000 "Error: Cannot delete the main worktree"
    exit 1
fi

# Get the branch name for the worktree
BRANCH_NAME=$(git worktree list --porcelain | grep -A2 "^worktree $WORKTREE_PATH" | grep "^branch" | cut -d' ' -f2)

# Store the main session name (usually the first session or one named after the repo)
MAIN_SESSION=$(tmux list-sessions -F "#{session_name}" | grep -E "^${REPO_NAME}$|^main$" | head -1)
if [ -z "$MAIN_SESSION" ]; then
    # Fallback to first available session that isn't the current one
    MAIN_SESSION=$(tmux list-sessions -F "#{session_name}" | grep -v "^${CURRENT_SESSION}$" | head -1)
fi

# Switch to main session first (so we're not in the session we're about to kill)
if [ -n "$MAIN_SESSION" ]; then
    tmux switch-client -t "$MAIN_SESSION"
else
    # Create a new session if no other exists
    tmux new-session -d -s "main" -c "$MAIN_REPO"
    tmux switch-client -t "main"
fi

# Kill the worktree session
tmux kill-session -t "$CURRENT_SESSION" 2>/dev/null

# Remove the git worktree
tmux display-message -d 1000 "Removing worktree at $WORKTREE_PATH..."

# Force remove the worktree
if ! git worktree remove "$WORKTREE_PATH" --force 2>/dev/null; then
    # If remove fails, try pruning first
    git worktree prune
    git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || {
        tmux display-message -d 2000 "Warning: Could not remove worktree. It may need manual cleanup."
    }
fi

# Display success message
tmux display-message -d 2000 "✓ Deleted worktree and session: $CURRENT_SESSION"