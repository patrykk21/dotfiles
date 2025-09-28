#!/usr/bin/env bash

# Create a worktree session with proper window setup
# This mimics manual tab creation

# Debug logging
echo "[DEBUG] create-worktree-session.sh called with: $1 $2" >> /tmp/tmux-worktree-debug.log

TICKET="$1"
WORKTREE_PATH="$2"

if [ -z "$TICKET" ] || [ -z "$WORKTREE_PATH" ]; then
    echo "Usage: $0 <ticket> <worktree_path>"
    exit 1
fi

# Don't try to unset hook - it gets reinstalled by tmux.conf
# Instead, we'll check for existing panes before creating new ones
echo "[DEBUG] Creating session with hook check" >> /tmp/tmux-worktree-debug.log

# Create new session and windows one by one (compound command seems to still trigger hooks)
tmux new-session -s "$TICKET" -n "claude" -c "$WORKTREE_PATH" -d "cd '$WORKTREE_PATH' && exec $SHELL"
tmux new-window -t "$TICKET:2" -n "server" -c "$WORKTREE_PATH"
tmux new-window -t "$TICKET:3" -n "commands" -c "$WORKTREE_PATH"

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
        BOTTOM_PANE=$(tmux split-window -t "$TICKET:$window" -v -d -l 1 -P -F "#{pane_id}" "~/.config/tmux/scripts/bottom-pane-display.sh")
        tmux select-pane -t "$BOTTOM_PANE" -T "__tmux_status_bar__"
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

# Log final state (simplified)
echo "[DEBUG] Final pane heights for session $TICKET:" >> /tmp/tmux-worktree-debug.log
for window in 1 2 3; do
    HEIGHTS=$(tmux list-panes -t "$TICKET:$window" -F "#{pane_height}" | tr '\n' ',' | sed 's/,$//')
    echo "  Window $window: $HEIGHTS" >> /tmp/tmux-worktree-debug.log
done

# Hook is already set by tmux.conf, no need to restore
echo "[DEBUG] Session creation complete" >> /tmp/tmux-worktree-debug.log