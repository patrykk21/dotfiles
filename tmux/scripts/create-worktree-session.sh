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

# Create new session attached (not detached) with first window
tmux new-session -s "$TICKET" -n "claude" -c "$WORKTREE_PATH" -d "cd '$WORKTREE_PATH' && exec $SHELL"

# Now we're in the session context, create the other windows
# This should trigger the same hooks as manual tab creation
tmux new-window -t "$TICKET:2" -n "server" -c "$WORKTREE_PATH"
tmux new-window -t "$TICKET:3" -n "commands" -c "$WORKTREE_PATH"

# Go back to first window
tmux select-window -t "$TICKET:1"

# Now manually create bottom panes for windows that don't have them
for window in 1 2 3; do
    echo "[DEBUG] Checking window $TICKET:$window" >> /tmp/tmux-worktree-debug.log
    
    # Check if window already has a bottom pane by looking for the special title
    HAS_STATUS_BAR=$(tmux list-panes -t "$TICKET:$window" -F "#{pane_title}" 2>/dev/null | grep -c "__tmux_status_bar__" || echo 0)
    echo "[DEBUG] Window $TICKET:$window has $HAS_STATUS_BAR status bar panes" >> /tmp/tmux-worktree-debug.log
    
    if [ "$HAS_STATUS_BAR" -eq 0 ]; then
        echo "[DEBUG] Creating bottom pane for window $TICKET:$window" >> /tmp/tmux-worktree-debug.log
        # Create bottom pane for this specific window
        tmux split-window -t "$TICKET:$window.1" -v -l 1 -d "~/.config/tmux/scripts/bottom-pane-display.sh" 2>&1 | tee -a /tmp/tmux-worktree-debug.log
        
        # Get the new pane ID and set its title
        BOTTOM_PANE=$(tmux list-panes -t "$TICKET:$window" -F "#{pane_id}" | tail -1)
        echo "[DEBUG] Setting title for pane $BOTTOM_PANE" >> /tmp/tmux-worktree-debug.log
        tmux select-pane -t "$BOTTOM_PANE" -T "__tmux_status_bar__"
    fi
done

# Select first window
tmux select-window -t "$TICKET:1"