#!/usr/bin/env bash
# Simple bottom bar implementation using tmux's message bar

# Function to display bottom bar
display_bottom_bar() {
    local mode=$(tmux display-message -p '#{client_key_table}')
    local content=$(~/.config/tmux/scripts/status-bar.sh)
    
    # Use tmux's message display as a persistent bottom bar
    # This requires continuous refresh
    tmux display-message -d 0 "$content"
}

# Set up refresh loop
tmux run-shell -b "while true; do
    mode=\$(tmux display-message -p '#{client_key_table}' 2>/dev/null)
    if [ -n \"\$mode\" ]; then
        content=\$(~/.config/tmux/scripts/status-bar.sh 2>/dev/null)
        tmux display-message -d 0 \"\$content\" 2>/dev/null
    fi
    sleep 0.5
done &"