#!/usr/bin/env bash

# Ensure all panes in a session are in the correct worktree directory
# This is called when switching to a worktree session

SESSION="$1"
WORKTREE_PATH="$2"

if [ -z "$SESSION" ] || [ -z "$WORKTREE_PATH" ]; then
    echo "Usage: $0 <session> <worktree_path>"
    exit 1
fi

# Get all windows and panes
tmux list-panes -s -t "$SESSION" -F '#{window_index}.#{pane_index} #{pane_current_command} #{pane_current_path}' | while read -r pane_info; do
    pane_id=$(echo "$pane_info" | awk '{print $1}')
    pane_cmd=$(echo "$pane_info" | awk '{print $2}')
    current_path=$(echo "$pane_info" | awk '{print $3}')
    
    # Only update if it's a shell and not already in the correct path
    if [[ "$pane_cmd" =~ ^(zsh|bash|sh)$ ]] && [ "$current_path" != "$WORKTREE_PATH" ]; then
        # First try to clear any current command
        tmux send-keys -t "$SESSION:$pane_id" C-c
        sleep 0.1
        
        # Clear the line and change directory
        tmux send-keys -t "$SESSION:$pane_id" C-u
        tmux send-keys -t "$SESSION:$pane_id" "cd $WORKTREE_PATH" Enter
        
        # Clear screen for a clean view
        tmux send-keys -t "$SESSION:$pane_id" C-l
    fi
done