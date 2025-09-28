#!/bin/bash
# Smart status bar script that minimizes duplication in split panes

# Get current pane info
PANE_ID=$(tmux display-message -p '#{pane_id}')
ACTIVE_PANE=$(tmux display-message -p '#{pane_active}')
PANE_COUNT=$(tmux display-message -p '#{window_panes}')

# Only show full status on active pane or if only one pane
if [[ "$ACTIVE_PANE" == "1" ]] || [[ "$PANE_COUNT" == "1" ]]; then
    # Run the original status bar script
    exec ~/.config/tmux/scripts/status-bar.sh
else
    # For inactive panes, show a minimal indicator or nothing
    echo ""
fi