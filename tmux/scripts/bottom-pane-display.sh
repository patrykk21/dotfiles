#!/usr/bin/env bash
# Display loop for bottom status pane - optimized to prevent flickering

# Hide cursor
printf '\033[?25l'

# Trap to show cursor on exit
trap 'printf "\033[?25h"' EXIT

# Main display loop
LAST_MODE=""
LAST_WIDTH=""

while true; do
    # Get terminal width
    WIDTH=$(tput cols)
    
    # Get current mode from tmux
    MODE=$(tmux display-message -p '#{client_key_table}' 2>/dev/null || echo "root")
    
    # Only update if mode or width changed
    if [[ "$MODE" != "$LAST_MODE" ]] || [[ "$WIDTH" != "$LAST_WIDTH" ]]; then
        # Get the status content
        STATUS_RAW=$(~/.config/tmux/scripts/status-bar.sh 2>/dev/null || echo "Loading...")
        
        # Convert tmux color codes to ANSI
        STATUS=$(echo "$STATUS_RAW" | sed \
            -e 's/#\[bg=colour75,fg=colour235,bold\]/\\033[48;5;75m\\033[38;5;235m\\033[1m/g' \
            -e 's/#\[bg=colour114,fg=colour235,bold\]/\\033[48;5;114m\\033[38;5;235m\\033[1m/g' \
            -e 's/#\[bg=colour180,fg=colour235,bold\]/\\033[48;5;180m\\033[38;5;235m\\033[1m/g' \
            -e 's/#\[bg=colour168,fg=colour235,bold\]/\\033[48;5;168m\\033[38;5;235m\\033[1m/g' \
            -e 's/#\[bg=colour176,fg=colour235,bold\]/\\033[48;5;176m\\033[38;5;235m\\033[1m/g' \
            -e 's/#\[bg=colour73,fg=colour235,bold\]/\\033[48;5;73m\\033[38;5;235m\\033[1m/g' \
            -e 's/#\[bg=colour75,fg=colour235\]/\\033[48;5;75m\\033[38;5;235m/g' \
            -e 's/#\[bg=default,fg=colour75\]/\\033[49m\\033[38;5;75m/g' \
            -e 's/#\[bg=colour114,fg=colour235\]/\\033[48;5;114m\\033[38;5;235m/g' \
            -e 's/#\[bg=default,fg=colour114\]/\\033[49m\\033[38;5;114m/g' \
            -e 's/#\[bg=colour180,fg=colour235\]/\\033[48;5;180m\\033[38;5;235m/g' \
            -e 's/#\[bg=default,fg=colour180\]/\\033[49m\\033[38;5;180m/g' \
            -e 's/#\[bg=colour168,fg=colour235\]/\\033[48;5;168m\\033[38;5;235m/g' \
            -e 's/#\[bg=default,fg=colour168\]/\\033[49m\\033[38;5;168m/g' \
            -e 's/#\[bg=colour176,fg=colour235\]/\\033[48;5;176m\\033[38;5;235m/g' \
            -e 's/#\[bg=default,fg=colour176\]/\\033[49m\\033[38;5;176m/g' \
            -e 's/#\[bg=colour73,fg=colour235\]/\\033[48;5;73m\\033[38;5;235m/g' \
            -e 's/#\[bg=default,fg=colour73\]/\\033[49m\\033[38;5;73m/g' \
            -e 's/#\[bg=colour235,fg=colour\([0-9]*\)\]/\\033[48;5;235m\\033[38;5;\1m/g' \
            -e 's/#\[bg=colour240,fg=colour250\]/\\033[48;5;240m\\033[38;5;250m/g' \
            -e 's/#\[fg=colour\([0-9]*\)\]/\\033[38;5;\1m/g' \
            -e 's/#\[bold\]/\\033[1m/g' \
            -e 's/#\[bg=default\]/\\033[49m/g' \
            -e 's/#\[fg=default\]/\\033[39m/g' \
            -e 's/#\[[^]]*\]//g')
        
        # Get plain text length for padding calculation
        STATUS_PLAIN=$(echo "$STATUS_RAW" | sed 's/#\[[^]]*\]//g')
        STATUS_LENGTH=${#STATUS_PLAIN}
        
        # Don't clear - just position cursor at start and overwrite
        tput cup 0 0
        
        # Background color for the whole line
        printf '\033[48;5;235m'
        
        # Print status left-aligned with padding on the right
        printf "  "  # Small left margin
        printf "$STATUS"
        printf "%*s" $((WIDTH - STATUS_LENGTH - 2)) ""  # Fill rest of line
        
        # Reset colors
        printf '\033[0m'
        
        # Save last state
        LAST_MODE="$MODE"
        LAST_WIDTH="$WIDTH"
    fi
    
    # Short sleep to reduce CPU usage
    sleep 0.1
done