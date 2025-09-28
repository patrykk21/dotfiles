#!/usr/bin/env bash
# Display status at bottom while in fullscreen mode

while true; do
    # Check if still zoomed
    ZOOMED=$(tmux display-message -p '#{window_zoomed_flag}' 2>/dev/null || echo "0")
    if [[ "$ZOOMED" != "1" ]]; then
        # No longer zoomed, exit
        exit 0
    fi
    
    # Get status and display it
    STATUS=$(~/.config/tmux/scripts/status-bar.sh 2>/dev/null | sed 's/#\[[^]]*\]//g')
    tmux display-message -d 0 "$STATUS"
    
    sleep 0.5
done