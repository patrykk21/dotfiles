#!/usr/bin/env bash
# Toggle server in "server" tab

# Source metadata functions to get SERVER_PORT
source /Users/vigenerr/.config/tmux/scripts/worktree-metadata.sh

# Get current session
SESSION=$(tmux display-message -p '#S')

# Find the "server" window
SERVER_WINDOW=$(tmux list-windows -t "$SESSION" -F '#{window_index} #{window_name}' | grep -E '\bserver\b' | awk '{print $1}' | head -1)

if [ -z "$SERVER_WINDOW" ]; then
    tmux display-message "No 'server' window found in session $SESSION"
    exit 1
fi

# Get the first pane in the server window
SERVER_PANE=$(tmux list-panes -t "$SESSION:$SERVER_WINDOW" -F '#{pane_id}' | head -1)

# Check if there's a server process running (bun, node, npm, etc.)
SERVER_RUNNING=$(tmux list-panes -t "$SESSION:$SERVER_WINDOW" -F '#{pane_pid}' | \
    xargs -I {} pgrep -P {} -f 'bun.*dev|npm.*dev|yarn.*dev|node.*dev' 2>/dev/null | head -1)

if [ -n "$SERVER_RUNNING" ]; then
    # Server is running - kill it
    tmux send-keys -t "$SERVER_PANE" C-c
    tmux display-message "Stopped server in window $SERVER_WINDOW"
else
    # Server is not running - start it
    # Get SERVER_PORT from metadata
    CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')
    
    SERVER_PORT=""
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
    
    if [ -n "$SERVER_PORT" ]; then
        # Start server with PORT environment variable
        tmux send-keys -t "$SERVER_PANE" "PORT=$SERVER_PORT bun dev" Enter
        tmux display-message "Started server on port $SERVER_PORT in window $SERVER_WINDOW"
    else
        # Start server without specific port
        tmux send-keys -t "$SERVER_PANE" "bun dev" Enter
        tmux display-message "Started server in window $SERVER_WINDOW"
    fi
fi