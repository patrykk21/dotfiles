#!/usr/bin/env bash
# Floating bottom bar implementation for tmux
# This creates a dedicated pane at the bottom that acts as a status bar

# Configuration
BOTTOM_BAR_HEIGHT=1
BOTTOM_BAR_ID_FILE="/tmp/tmux-bottom-bar-${USER}-${TMUX_PANE}"

# Function to create bottom bar pane
create_bottom_bar() {
    # Get current window dimensions
    local window_height=$(tmux display-message -p "#{window_height}")
    local target_height=$((window_height - BOTTOM_BAR_HEIGHT - 1))
    
    # Create a horizontal split at the bottom
    local bottom_pane=$(tmux split-window -v -l $BOTTOM_BAR_HEIGHT -P -F "#{pane_id}")
    echo "$bottom_pane" > "$BOTTOM_BAR_ID_FILE"
    
    # Configure the bottom pane
    tmux select-pane -t "$bottom_pane"
    tmux send-keys -t "$bottom_pane" "clear" C-m
    tmux send-keys -t "$bottom_pane" "while true; do clear; ~/.config/tmux/scripts/status-bar.sh | sed 's/#\\[[^]]*\\]//g'; sleep 0.5; done" C-m
    
    # Make the bottom pane non-selectable and style it
    tmux set-option -t "$bottom_pane" -p remain-on-exit on
    tmux set-option -t "$bottom_pane" -p window-style 'bg=colour235'
    
    # Return to the main pane
    tmux select-pane -t "{top}"
}

# Function to remove bottom bar
remove_bottom_bar() {
    if [ -f "$BOTTOM_BAR_ID_FILE" ]; then
        local bottom_pane=$(cat "$BOTTOM_BAR_ID_FILE")
        tmux kill-pane -t "$bottom_pane" 2>/dev/null
        rm -f "$BOTTOM_BAR_ID_FILE"
    fi
}

# Main logic
case "${1:-create}" in
    create)
        remove_bottom_bar  # Remove any existing bottom bar first
        create_bottom_bar
        ;;
    remove)
        remove_bottom_bar
        ;;
    toggle)
        if [ -f "$BOTTOM_BAR_ID_FILE" ]; then
            remove_bottom_bar
        else
            create_bottom_bar
        fi
        ;;
    *)
        echo "Usage: $0 {create|remove|toggle}"
        exit 1
        ;;
esac