#!/usr/bin/env bash

# Delete a worktree from the picker
# This is a helper script to avoid recursion issues with fzf

# Source metadata functions
source "$(dirname "$0")/worktree-metadata.sh"

# Get the full selection line
SELECTION="$*"

# Extract the ticket/session name (first field after status icon).
# NOTE: do NOT use $NF to get a path — the last picker column is the branch
# name, which is not a filesystem path and differs from the worktree dir name
# for any ticket whose branch was renamed (e.g. ECH-706 dir vs branch mismatch).
TICKET=$(echo "$SELECTION" | sed 's/^[[:space:]]*[→○●[:space:]]*//' | awk '{print $1}')

if [ -z "$TICKET" ]; then
    exit 1
fi

# Get repository name from worktree path
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
REPO_NAME=$(basename "$MAIN_REPO")

# Derive worktree path the same way the picker does on selection
# (worktree-picker-fzf.sh:474). Prefer metadata if available, falling back
# to the conventional $WORKTREES_BASE/$REPO_NAME/$TICKET location.
WORKTREE_PATH=""
META_NEW="$WORKTREES_BASE/$REPO_NAME/.worktree-meta/sessions/$TICKET/meta.json"
META_OLD="$WORKTREES_BASE/$REPO_NAME/.worktree-meta/sessions/$TICKET.json"
if [ -f "$META_NEW" ]; then
    WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$META_NEW" 2>/dev/null)
elif [ -f "$META_OLD" ]; then
    WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$META_OLD" 2>/dev/null)
fi
if [ -z "$WORKTREE_PATH" ]; then
    WORKTREE_PATH="$WORKTREES_BASE/$REPO_NAME/$TICKET"
fi

# Write deletion info to a temp file for confirmation
TEMP_DELETE_FILE="/tmp/tmux-worktree-delete-pending"
echo "$TICKET|$WORKTREE_PATH|$REPO_NAME" > "$TEMP_DELETE_FILE"

# Create a marker that we want to delete something
touch /tmp/tmux-worktree-delete-requested