#!/usr/bin/env bash
# Launch localhost with current SERVER_PORT in browser

# Source metadata functions
source ~/.config/tmux/scripts/worktree-metadata.sh

# Get current directory and session
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')
SESSION=$(tmux display-message -p '#S')

# Get SERVER_PORT using the unified function
SERVER_PORT=""

# First check if we're in a worktree by path
if [[ "$CURRENT_DIR" == "$WORKTREES_BASE/"* ]]; then
    # Extract repo and ticket from path
    WORKTREE_INFO=$(get_worktree_info_from_path "$CURRENT_DIR")
    if [ -n "$WORKTREE_INFO" ]; then
        REPO_NAME=$(echo "$WORKTREE_INFO" | cut -d'|' -f1)
        TICKET=$(echo "$WORKTREE_INFO" | cut -d'|' -f2)
        # Use unified function to ensure metadata exists and get port
        SERVER_PORT=$(ensure_and_get_server_port "$REPO_NAME" "$TICKET")
    fi
else
    # Not in worktree directory, but might still be a worktree session
    # Use session name to lookup metadata
    if [[ "$SESSION" =~ -base$ ]]; then
        # Base session - no SERVER_PORT, use default
        SERVER_PORT=""
    else
        # Try to find repo by checking git remote
        if git -C "$CURRENT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            REPO_URL=$(git -C "$CURRENT_DIR" remote get-url origin 2>/dev/null)
            REPO_NAME=$(basename "$REPO_URL" .git 2>/dev/null)
            
            if [ -n "$REPO_NAME" ]; then
                # Use unified function to ensure metadata exists and get port
                SERVER_PORT=$(ensure_and_get_server_port "$REPO_NAME" "$SESSION")
            fi
        fi
    fi
fi

# If no SERVER_PORT found, default to 3000
if [ -z "$SERVER_PORT" ]; then
    SERVER_PORT="3000"
    PORT_SOURCE="default"
else
    PORT_SOURCE="metadata"
fi

# Construct localhost URL
LOCALHOST_URL="http://localhost:$SERVER_PORT"

# Open in browser
if command -v open >/dev/null 2>&1; then
    open "$LOCALHOST_URL"
    if [ "$PORT_SOURCE" = "metadata" ]; then
        tmux display-message "Opened localhost:$SERVER_PORT (from $SESSION metadata)"
    else
        tmux display-message "Opened localhost:$SERVER_PORT (default port)"
    fi
else
    tmux display-message "Cannot open browser: 'open' command not found"
    exit 1
fi