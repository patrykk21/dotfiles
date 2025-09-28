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

# Unset the hook completely to prevent conflicts
echo "[DEBUG] Unsetting after-new-window hook" >> /tmp/tmux-worktree-debug.log
tmux set-hook -gu after-new-window

# Create new session and windows one by one (compound command seems to still trigger hooks)
tmux new-session -s "$TICKET" -n "claude" -c "$WORKTREE_PATH" -d "cd '$WORKTREE_PATH' && exec $SHELL"
tmux new-window -t "$TICKET:2" -n "server" -c "$WORKTREE_PATH"
tmux new-window -t "$TICKET:3" -n "commands" -c "$WORKTREE_PATH"

# Go back to first window
tmux select-window -t "$TICKET:1"

# The after-new-window hook won't trigger for these initial windows, so create bottom panes manually
# Create bottom panes with proper sizing for each window
for window in 1 2 3; do
    # Switch to the window
    tmux select-window -t "$TICKET:$window"
    
    # Check if bottom pane already exists (in case hook ran)
    EXISTING_BOTTOM=$(tmux list-panes -t "$TICKET:$window" -F "#{pane_id} #{pane_title}" | grep "__tmux_status_bar__" | awk '{print $1}')
    
    if [ -z "$EXISTING_BOTTOM" ]; then
        # Create bottom pane only if it doesn't exist
        BOTTOM_PANE=$(tmux split-window -t "$TICKET:$window" -v -d -P -F "#{pane_id}" "~/.config/tmux/scripts/bottom-pane-display.sh")
        
        # Set the title
        tmux select-pane -t "$BOTTOM_PANE" -T "__tmux_status_bar__"
        
        # Small delay to ensure pane is ready
        sleep 0.1
        
        # Immediately resize to 1 line (like the hook does)
        tmux resize-pane -t "$BOTTOM_PANE" -y 1
    else
        # Just resize existing pane
        tmux resize-pane -t "$EXISTING_BOTTOM" -y 1
    fi
    
    # Return focus to main pane
    tmux select-pane -t "$TICKET:$window.1"
done

# Return to first window
tmux select-window -t "$TICKET:1"

# Log final state
echo "[DEBUG] Final pane state for session $TICKET:" >> /tmp/tmux-worktree-debug.log
for window in 1 2 3; do
    echo "  Window $window:" >> /tmp/tmux-worktree-debug.log
    tmux list-panes -t "$TICKET:$window" -F "    Pane #{pane_index}: Height #{pane_height}, Title: #{pane_title}" >> /tmp/tmux-worktree-debug.log
done

# Restore the after-new-window hook
tmux set-hook -g after-new-window 'run-shell -b "~/.config/tmux/scripts/create-bottom-pane-for-window.sh #{session_name}:#{window_index}"'
echo "[DEBUG] Hook restored" >> /tmp/tmux-worktree-debug.log