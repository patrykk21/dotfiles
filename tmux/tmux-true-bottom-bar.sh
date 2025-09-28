#!/usr/bin/env bash
# True bottom bar for tmux using creative window management

# This script creates a secondary tmux session with a single window
# that acts as a bottom status bar

BOTTOM_BAR_SESSION="tmux-bottom-bar-$$"
BOTTOM_BAR_HEIGHT=1

start_bottom_bar() {
    # Kill any existing bottom bar sessions
    tmux kill-session -t "$BOTTOM_BAR_SESSION" 2>/dev/null || true
    
    # Create a new detached session for the bottom bar
    tmux new-session -d -s "$BOTTOM_BAR_SESSION" -n "status" \
        "while true; do clear; tput cup 0 0; ~/.config/tmux/scripts/status-bar.sh | sed 's/#\\[[^]]*\\]//g'; sleep 0.5; done"
    
    # Configure the bottom bar session
    tmux set-option -t "$BOTTOM_BAR_SESSION" status off
    tmux set-option -t "$BOTTOM_BAR_SESSION" pane-border-status off
    
    echo "Bottom bar started. To stop: $0 stop"
}

stop_bottom_bar() {
    tmux kill-session -t "$BOTTOM_BAR_SESSION" 2>/dev/null || echo "No bottom bar running"
}

case "${1:-start}" in
    start)
        start_bottom_bar
        ;;
    stop)
        stop_bottom_bar
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac