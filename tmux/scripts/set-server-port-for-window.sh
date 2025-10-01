#!/usr/bin/env bash
# Set SERVER_PORT environment variable for new tmux windows

WINDOW_TARGET="$1"
SESSION=$(echo "$WINDOW_TARGET" | cut -d':' -f1)

# Source metadata functions
source /Users/vigenerr/.config/tmux/scripts/worktree-metadata.sh

# Get current directory from the window
CURRENT_DIR=$(tmux display-message -t "$WINDOW_TARGET" -p '#{pane_current_path}' 2>/dev/null)

if [ -z "$CURRENT_DIR" ]; then
    exit 0
fi

SERVER_PORT=""

# Check if we're in a worktree
if [[ "$CURRENT_DIR" == "$WORKTREES_BASE/"* ]]; then
    # Extract repo and ticket from path
    WORKTREE_INFO=$(get_worktree_info_from_path "$CURRENT_DIR")
    if [ -n "$WORKTREE_INFO" ]; then
        REPO_NAME=$(echo "$WORKTREE_INFO" | cut -d'|' -f1)
        TICKET=$(echo "$WORKTREE_INFO" | cut -d'|' -f2)
        SERVER_PORT=$(get_session_metadata "$REPO_NAME" "$TICKET" "port")
    fi
else
    # Use session name to lookup metadata
    if ! [[ "$SESSION" =~ -base$ ]]; then
        # Try to find repo by checking git remote
        if git -C "$CURRENT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            REPO_URL=$(git -C "$CURRENT_DIR" remote get-url origin 2>/dev/null)
            REPO_NAME=$(basename "$REPO_URL" .git 2>/dev/null)
            
            if [ -n "$REPO_NAME" ]; then
                SERVER_PORT=$(get_session_metadata "$REPO_NAME" "$SESSION" "port")
            fi
        fi
    fi
fi

# Set SERVER_PORT in tmux environment (will be inherited by new shells)
if [ -n "$SERVER_PORT" ]; then
    tmux setenv -t "$SESSION" SERVER_PORT "$SERVER_PORT"
fi