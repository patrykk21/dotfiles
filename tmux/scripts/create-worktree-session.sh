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

# Temporarily set a no-op hook to prevent conflicts
echo "[DEBUG] Setting no-op after-new-window hook" >> /tmp/tmux-worktree-debug.log
tmux set-hook -g after-new-window ''

# Create new session with all windows at once to avoid hook triggers
tmux new-session -s "$TICKET" -n "claude" -c "$WORKTREE_PATH" -d "cd '$WORKTREE_PATH' && exec $SHELL" \; \
    new-window -t "$TICKET:2" -n "server" -c "$WORKTREE_PATH" \; \
    new-window -t "$TICKET:3" -n "commands" -c "$WORKTREE_PATH"

# Go back to first window
tmux select-window -t "$TICKET:1"

# The after-new-window hook won't trigger for these initial windows, so create bottom panes manually
# Create bottom panes with proper sizing for each window
for window in 1 2 3; do
    # Switch to the window
    tmux select-window -t "$TICKET:$window"
    
    # Create bottom pane exactly like the hook does - without initial size
    BOTTOM_PANE=$(tmux split-window -t "$TICKET:$window" -v -d -P -F "#{pane_id}" "~/.config/tmux/scripts/bottom-pane-display.sh")
    
    # Set the title
    tmux select-pane -t "$BOTTOM_PANE" -T "__tmux_status_bar__"
    
    # Small delay to ensure pane is ready
    sleep 0.1
    
    # Immediately resize to 1 line (like the hook does)
    tmux resize-pane -t "$BOTTOM_PANE" -y 1
    
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