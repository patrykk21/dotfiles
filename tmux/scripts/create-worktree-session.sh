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
# Wait for windows to be fully created
sleep 0.2

# Create bottom panes for each window
for window in 1 2 3; do
    ~/.config/tmux/scripts/create-bottom-pane-for-window.sh "$TICKET:$window"
done

# Force resize after creation
sleep 0.1
for window in 1 2 3; do
    STATUS_PANE=$(tmux list-panes -t "$TICKET:$window" -F "#{pane_id}:#{pane_title}" 2>/dev/null | grep "__tmux_status_bar__" | cut -d: -f1)
    if [ -n "$STATUS_PANE" ]; then
        tmux resize-pane -t "$STATUS_PANE" -y 1
    fi
done