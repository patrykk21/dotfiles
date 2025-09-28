#!/usr/bin/env bash
# Bottom bar daemon for tmux - draws directly to terminal

# Kill any existing daemon
pkill -f "bottom-bar-daemon.sh" 2>/dev/null || true
sleep 0.1

# Function to draw bottom bar
draw_bottom_bar() {
    local width=$(tput cols)
    local height=$(tput lines)
    
    # Get current tmux mode
    local mode=$(tmux display-message -p '#{client_key_table}' 2>/dev/null || echo "root")
    
    # Get status content
    local status=$(~/.config/tmux/scripts/status-bar.sh 2>/dev/null || echo "Loading...")
    
    # Strip tmux color codes
    local plain_status=$(echo "$status" | sed 's/#\[[^]]*\]//g')
    
    # Calculate centering
    local status_length=${#plain_status}
    local padding=$(( (width - status_length) / 2 ))
    
    # Draw to terminal
    {
        # Save cursor and attributes
        tput sc
        
        # Move to bottom line
        tput cup $((height - 1)) 0
        
        # Set background color (OneDark background)
        tput setab 235
        tput setaf 250
        
        # Clear line and draw status
        tput el
        printf "%*s%s%*s" $padding "" "$plain_status" $((width - status_length - padding)) ""
        
        # Restore cursor and attributes
        tput rc
        tput sgr0
    } 2>/dev/null
}

# Main daemon loop
while true; do
    draw_bottom_bar
    sleep 0.5
done &

echo "Bottom bar daemon started (PID: $!)"