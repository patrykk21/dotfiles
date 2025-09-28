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

# The after-new-window hook won't trigger for these initial windows, so create bottom panes manually
# Create bottom panes with proper sizing for each window
for window in 1 2 3; do
    # Switch to the window
    tmux select-window -t "$TICKET:$window"
    
    # Log before creation
    echo "[DEBUG] Before creating bottom pane for window $window" >> /tmp/tmux-worktree-debug.log
    tmux list-panes -t "$TICKET:$window" -F "#{pane_index}:#{pane_height}" >> /tmp/tmux-worktree-debug.log
    
    # Create bottom pane exactly like the hook does - without initial size
    BOTTOM_PANE=$(tmux split-window -t "$TICKET:$window" -v -d -P -F "#{pane_id}" "~/.config/tmux/scripts/bottom-pane-display.sh")
    
    # Log after creation
    echo "[DEBUG] After creating bottom pane BOTTOM_PANE='$BOTTOM_PANE'" >> /tmp/tmux-worktree-debug.log
    tmux list-panes -t "$TICKET:$window" -F "#{pane_index}:#{pane_height}:#{pane_id}" >> /tmp/tmux-worktree-debug.log
    
    # Set the title
    tmux select-pane -t "$BOTTOM_PANE" -T "__tmux_status_bar__"
    
    # Small delay to ensure pane is ready
    sleep 0.1
    
    # Immediately resize to 1 line (like the hook does)
    if ! tmux resize-pane -t "$BOTTOM_PANE" -y 1 2>>/tmp/tmux-worktree-debug.log; then
        echo "[DEBUG] Resize failed for pane $BOTTOM_PANE" >> /tmp/tmux-worktree-debug.log
    fi
    
    # Log after resize
    echo "[DEBUG] After resize for window $window" >> /tmp/tmux-worktree-debug.log
    tmux list-panes -t "$TICKET:$window" -F "#{pane_index}:#{pane_height}:#{pane_id}" >> /tmp/tmux-worktree-debug.log
    
    # Return focus to main pane
    tmux select-pane -t "$TICKET:$window.1"
done

# Return to first window
tmux select-window -t "$TICKET:1"