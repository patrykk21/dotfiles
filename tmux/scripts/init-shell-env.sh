#!/usr/bin/env bash
# Initialize shell environment for new tmux windows/panes

# Source metadata functions
source /Users/vigenerr/.config/tmux/scripts/worktree-metadata.sh

# Get current directory
CURRENT_DIR="$PWD"

# Check if we're in a worktree
if [[ "$CURRENT_DIR" == "$WORKTREES_BASE/"* ]]; then
    # Extract worktree info
    WORKTREE_INFO=$(get_worktree_info_from_path "$CURRENT_DIR")
    if [ -n "$WORKTREE_INFO" ]; then
        REPO_NAME=$(echo "$WORKTREE_INFO" | cut -d'|' -f1)
        TICKET=$(echo "$WORKTREE_INFO" | cut -d'|' -f2)
        
        # Get SERVER_PORT from metadata
        SERVER_PORT=$(get_session_metadata "$REPO_NAME" "$TICKET" "port")
        
        if [ -n "$SERVER_PORT" ]; then
            export SERVER_PORT="$SERVER_PORT"
        fi
    fi
fi

# Execute the user's shell
exec "${SHELL}"