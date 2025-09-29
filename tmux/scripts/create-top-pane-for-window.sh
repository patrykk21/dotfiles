#!/usr/bin/env bash

WINDOW="${1:-}"

if [ -z "$WINDOW" ]; then
    echo "Usage: $0 <session:window>"
    exit 1
fi

# Check if top pane already exists
TOP_PANE=$(tmux list-panes -t "$WINDOW" -F '#{pane_index}:#{pane_id}:#{pane_current_command}' | grep ':top-status-bar' | head -1)

if [ -z "$TOP_PANE" ]; then
    # Get the first regular pane (not status bar)
    FIRST_PANE=$(tmux list-panes -t "$WINDOW" -F '#{pane_index}:#{pane_id}:#{pane_current_command}' | grep -v -E ':(bottom-prompt|top-status-bar)' | head -1 | cut -d: -f2)
    
    if [ -n "$FIRST_PANE" ]; then
        # Create top pane by splitting from the first regular pane
        tmux split-window -t "$FIRST_PANE" -v -b -l 1 "~/.config/tmux/scripts/top-status-bar.sh"
        
        # Get the new pane ID (should be index 1)
        TOP_PANE_ID=$(tmux list-panes -t "$WINDOW" -F '#{pane_index}:#{pane_id}:#{pane_current_command}' | grep ':top-status-bar' | cut -d: -f2)
        
        # Ensure top pane can't be selected
        if [ -n "$TOP_PANE_ID" ]; then
            tmux set-option -t "$TOP_PANE_ID" @ignore-pane "true"
        fi
    fi
fi