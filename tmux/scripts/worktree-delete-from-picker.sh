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
# for any ticket whose branch was renamed (e.g. PROJ-706 dir vs branch mismatch).
TICKET=$(echo "$SELECTION" | sed 's/^[[:space:]]*[→○●[:space:]]*//' | awk '{print $1}')

if [ -z "$TICKET" ]; then
    exit 1
fi

# Ignore the section divider (line without a real worktree type token)
TYPE=$(echo "$SELECTION" | sed 's/^[[:space:]]*[→○●[:space:]]*//' | awk '{print $2}')
case "$TYPE" in
    "[WORKTREE]"|"[BASE]"|"[AUTO]") ;;
    *) exit 0 ;;
esac

# Get repository name from worktree path
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
REPO_NAME=$(basename "$MAIN_REPO")

# $TICKET came off the rendered row, which is truncated to 48 chars for column
# alignment. The metadata lookup and the fallback path below both key off the
# untruncated name, so restore it from disk first. Without this, deleting any
# worktree with a name longer than 48 chars targets a path that does not exist:
# `git worktree remove` fails and the deletion aborts. Only an unambiguous single
# match is accepted; anything else keeps the parsed value.
if [ "$TYPE" != "[BASE]" ] && [ ! -d "$WORKTREES_BASE/$REPO_NAME/$TICKET" ]; then
    resolved=()
    for candidate in "$WORKTREES_BASE/$REPO_NAME/$TICKET"*/; do
        [ -d "$candidate" ] && resolved+=("$candidate")
    done
    [ ${#resolved[@]} -eq 1 ] && TICKET="$(basename "${resolved[0]}")"
fi

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