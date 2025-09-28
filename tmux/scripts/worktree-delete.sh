#!/usr/bin/env bash

# Delete current worktree and its associated tmux session
# This script is called from within a tmux session

# Source metadata functions
source "$(dirname "$0")/worktree-metadata.sh"

# Get current session name
CURRENT_SESSION=$(tmux display-message -p '#S')

# Get the main repository info
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
if [ -z "$MAIN_REPO" ]; then
    tmux display-message -d 2000 "Error: Not in a git repository"
    exit 1
fi

REPO_NAME=$(basename "$MAIN_REPO")

# Get current path
CURRENT_PATH=$(pwd)
IS_WORKTREE=false
WORKTREE_PATH=""
TICKET=""

# First check if we can get info from metadata
if [ -f "$GLOBAL_METADATA_DIR/repos.json" ]; then
    # Check if current session matches a known worktree
    for repo_sessions_dir in "$WORKTREES_BASE"/*/.worktree-meta/sessions; do
        if [ -d "$repo_sessions_dir" ]; then
            for metadata_file in "$repo_sessions_dir"/*.json; do
                if [ -f "$metadata_file" ]; then
                    session_name=$(jq -r '.session_name // empty' "$metadata_file" 2>/dev/null)
                    if [ "$session_name" = "$CURRENT_SESSION" ]; then
                        WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$metadata_file" 2>/dev/null)
                        TICKET=$(jq -r '.ticket // empty' "$metadata_file" 2>/dev/null)
                        IS_WORKTREE=true
                        break 2
                    fi
                fi
            done
        fi
    done
fi

# If not found in metadata, try traditional detection
if [ "$IS_WORKTREE" = false ]; then
    # Check if current path is a worktree
    if git worktree list | grep -q "$CURRENT_PATH"; then
        IS_WORKTREE=true
        WORKTREE_PATH="$CURRENT_PATH"
        # Try to extract ticket from path
        if [[ "$CURRENT_PATH" =~ .*\/([A-Z]+-[0-9]+)$ ]]; then
            TICKET="${BASH_REMATCH[1]}"
        else
            TICKET="$CURRENT_SESSION"
        fi
    else
        # Try to find worktree in new structure
        EXPECTED_PATH="$WORKTREES_BASE/$REPO_NAME/$CURRENT_SESSION"
        if [ -d "$EXPECTED_PATH" ] && git worktree list | grep -q "$EXPECTED_PATH"; then
            IS_WORKTREE=true
            WORKTREE_PATH="$EXPECTED_PATH"
            TICKET="$CURRENT_SESSION"
        fi
    fi
fi

# Validate we found a worktree
if [ "$IS_WORKTREE" = false ] || [ -z "$WORKTREE_PATH" ]; then
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
if [[ "$confirm" != "YES"* ]]; then
    tmux display-message -d 1000 "Deletion cancelled"
    exit 0
fi

# Find a session to switch to
MAIN_SESSION=$(tmux list-sessions -F "#{session_name}" | grep -v "^${CURRENT_SESSION}$" | head -1)

# Switch to another session or create one if needed
if [ -n "$MAIN_SESSION" ]; then
    tmux switch-client -t "$MAIN_SESSION"
else
    # Create a new session if no other exists
    tmux new-session -d -s "main" -c "$MAIN_REPO"
    tmux switch-client -t "main"
fi

# Kill the worktree session
tmux kill-session -t "$CURRENT_SESSION" 2>/dev/null

# Remove metadata if it exists
if [ -n "$TICKET" ]; then
    remove_session_metadata "$REPO_NAME" "$TICKET"
fi

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