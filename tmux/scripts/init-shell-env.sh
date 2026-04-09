#!/usr/bin/env bash
# Initialize shell environment for new tmux windows/panes

# Source metadata functions safely
if [ -f ~/.config/tmux/scripts/worktree-metadata.sh ]; then
    source ~/.config/tmux/scripts/worktree-metadata.sh 2>/dev/null || true
fi
if [ -f ~/.config/tmux/scripts/tmux-session-utils.sh ]; then
    source ~/.config/tmux/scripts/tmux-session-utils.sh 2>/dev/null || true
fi

# Get current directory
CURRENT_DIR="$PWD"

# Only try to set SERVER_PORT if we have the metadata functions
if command -v get_worktree_info_from_path >/dev/null 2>&1 && command -v ensure_and_get_server_port >/dev/null 2>&1; then
    # Check if we're in a worktree
    if [[ "$CURRENT_DIR" == "$WORKTREES_BASE/"* ]]; then
        # Extract worktree info
        WORKTREE_INFO=$(get_worktree_info_from_path "$CURRENT_DIR" 2>/dev/null)
        if [ -n "$WORKTREE_INFO" ]; then
            REPO_NAME=$(echo "$WORKTREE_INFO" | cut -d'|' -f1)
            TICKET=$(echo "$WORKTREE_INFO" | cut -d'|' -f2)
            
            # Get SERVER_PORT using unified function (ensures metadata exists)
            SERVER_PORT=$(ensure_and_get_server_port "$REPO_NAME" "$TICKET" 2>/dev/null)
            
            if [ -n "$SERVER_PORT" ]; then
                export SERVER_PORT="$SERVER_PORT"
            fi
        fi
    else
        # Try to get from session name for non-worktree paths
        if [ -n "$TMUX" ]; then
            RAW_SESSION=$(tmux display-message -p '#S' 2>/dev/null)
            # Resolve grouped child to master for metadata lookups
            if command -v resolve_master_session >/dev/null 2>&1; then
                SESSION=$(resolve_master_session "$RAW_SESSION")
            else
                SESSION="$RAW_SESSION"
            fi
            if [ -n "$SESSION" ] && ! [[ "$SESSION" =~ -base$ ]]; then
                # Try to find repo by checking git remote
                if git -C "$CURRENT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    REPO_URL=$(git -C "$CURRENT_DIR" remote get-url origin 2>/dev/null)
                    REPO_NAME=$(basename "$REPO_URL" .git 2>/dev/null)
                    
                    if [ -n "$REPO_NAME" ]; then
                        # Use unified function for consistency
                        SERVER_PORT=$(ensure_and_get_server_port "$REPO_NAME" "$SESSION" 2>/dev/null)
                        if [ -n "$SERVER_PORT" ]; then
                            export SERVER_PORT="$SERVER_PORT"
                        fi
                    fi
                fi
            fi
        fi
    fi
fi

# Execute the user's shell
exec "${SHELL:-/bin/zsh}"