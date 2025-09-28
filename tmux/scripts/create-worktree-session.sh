#!/usr/bin/env bash

# Create a worktree session with proper window setup
# This mimics manual tab creation

# Source metadata functions
source "$(dirname "$0")/worktree-metadata.sh"

TICKET="$1"
WORKTREE_PATH="$2"

# Get user's default shell - use /bin/zsh directly since $SHELL might not be available in script context
USER_SHELL="/bin/zsh"

if [ -z "$TICKET" ] || [ -z "$WORKTREE_PATH" ]; then
    echo "Usage: $0 <ticket> <worktree_path>"
    exit 1
fi

# Get repository name from worktree path
MAIN_REPO=$(cd "$WORKTREE_PATH" 2>/dev/null && git worktree list | head -1 | awk '{print $1}')
REPO_NAME=$(basename "$MAIN_REPO")

# Get port from metadata if this is a worktree (not base)
SERVER_PORT=""
PORT_GENERATED=false
if [[ ! "$TICKET" =~ -base$ ]]; then
    # Try to get existing port from metadata
    SERVER_PORT=$(get_session_metadata "$REPO_NAME" "$TICKET" "port")
    
    # If no port exists, generate one and update metadata
    if [ -z "$SERVER_PORT" ]; then
        SERVER_PORT=$(generate_worktree_port)
        PORT_GENERATED=true
    fi
fi

# Create new session with explicit size (90 lines to accommodate 89+1 split)
# Set SERVER_PORT environment variable if we have one
if [ -n "$SERVER_PORT" ]; then
    tmux new-session -s "$TICKET" -n "claude" -c "$WORKTREE_PATH" -d -x 120 -y 90 \
        "export SERVER_PORT=$SERVER_PORT && cd '$WORKTREE_PATH' && exec $USER_SHELL"
    tmux new-window -t "$TICKET:2" -n "server" -c "$WORKTREE_PATH" \
        "export SERVER_PORT=$SERVER_PORT && cd '$WORKTREE_PATH' && exec $USER_SHELL"
    tmux new-window -t "$TICKET:3" -n "commands" -c "$WORKTREE_PATH" \
        "export SERVER_PORT=$SERVER_PORT && cd '$WORKTREE_PATH' && exec $USER_SHELL"
else
    tmux new-session -s "$TICKET" -n "claude" -c "$WORKTREE_PATH" -d -x 120 -y 90 "cd '$WORKTREE_PATH' && exec $USER_SHELL"
    tmux new-window -t "$TICKET:2" -n "server" -c "$WORKTREE_PATH" "cd '$WORKTREE_PATH' && exec $USER_SHELL"
    tmux new-window -t "$TICKET:3" -n "commands" -c "$WORKTREE_PATH" "cd '$WORKTREE_PATH' && exec $USER_SHELL"
fi

# Go back to first window
tmux select-window -t "$TICKET:1"

# Wait a moment for hooks to complete
sleep 0.5

# Clean up any extra panes and ensure correct sizing
for window in 1 2 3; do
    # Switch to the window
    tmux select-window -t "$TICKET:$window"
    
    # Find all status bar panes
    STATUS_PANES=$(tmux list-panes -t "$TICKET:$window" -F "#{pane_id} #{pane_title}" | grep "__tmux_status_bar__" | awk '{print $1}')
    if [ -z "$STATUS_PANES" ]; then
        STATUS_COUNT=0
    else
        STATUS_COUNT=$(echo "$STATUS_PANES" | wc -l | tr -d ' ')
    fi
    
    if [ "$STATUS_COUNT" -eq 0 ]; then
        # No status pane exists, create one
        if [ -n "$SERVER_PORT" ]; then
            BOTTOM_PANE=$(tmux split-window -t "$TICKET:$window" -v -d -l 1 -P -F "#{pane_id}" "export SERVER_PORT=$SERVER_PORT && exec ~/.config/tmux/scripts/bottom-pane-display.sh")
        else
            BOTTOM_PANE=$(tmux split-window -t "$TICKET:$window" -v -d -l 1 -P -F "#{pane_id}" "exec ~/.config/tmux/scripts/bottom-pane-display.sh")
        fi
        tmux select-pane -t "$BOTTOM_PANE" -T "__tmux_status_bar__"
        # Force correct sizes - bottom pane is already 1 line from split -l 1
        # Main pane will auto-adjust
    elif [ "$STATUS_COUNT" -gt 1 ]; then
        # Multiple status panes exist, keep only the last one and kill others
        KEEP_PANE=$(echo "$STATUS_PANES" | tail -1)
        echo "$STATUS_PANES" | head -n -1 | while read PANE; do
            tmux kill-pane -t "$PANE" 2>/dev/null || true
        done
        # Resize the kept pane
        tmux resize-pane -t "$KEEP_PANE" -y 1
    else
        # Exactly one status pane exists, just resize it  
        tmux resize-pane -t "$STATUS_PANES" -y 1
    fi
    
    # Return focus to main pane
    tmux select-pane -t "$TICKET:$window.1"
done

# Return to first window
tmux select-window -t "$TICKET:1"

# If we generated a new port, update the metadata
if [ "$PORT_GENERATED" = "true" ] && [ -n "$SERVER_PORT" ]; then
    # Check if metadata file exists
    METADATA_FILE="$WORKTREES_BASE/$REPO_NAME/.worktree-meta/sessions/${TICKET}.json"
    if [ -f "$METADATA_FILE" ]; then
        # Update existing metadata with port
        TEMP_FILE=$(mktemp)
        jq --arg port "$SERVER_PORT" '.port = ($port | tonumber)' "$METADATA_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$METADATA_FILE"
    fi
fi
