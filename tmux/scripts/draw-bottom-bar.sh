#!/usr/bin/env bash
# Draw bottom status bar using direct terminal control

# Get terminal info
WIDTH=$(tmux display-message -p "#{client_width}")
HEIGHT=$(tmux display-message -p "#{client_height}")

# Get current mode
MODE=$(tmux display-message -p '#{client_key_table}')

# Get status content
STATUS=$(~/.config/tmux/scripts/status-bar.sh)

# Convert tmux color codes to ANSI escape sequences
convert_colors() {
    echo "$1" | sed \
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
        -e 's/#\[bg=colour235,fg=colour73\]/\\033[48;5;235m\\033[38;5;73m/g' \
        -e 's/#\[bg=colour235,fg=colour/\\033[48;5;235m\\033[38;5;/g' \
        -e 's/#\[bg=colour240,fg=colour250\]/\\033[48;5;240m\\033[38;5;250m/g' \
        -e 's/#\[fg=colour250\]/\\033[38;5;250m/g' \
        -e 's/#\[fg=colour243\]/\\033[38;5;243m/g' \
        -e 's/#\[bold\]/\\033[1m/g' \
        -e 's/#\[[^]]*\]//g'
}

# Function to center text
center_text() {
    local text="$1"
    local width="$2"
    local text_length=$(echo -n "$text" | sed 's/\x1b\[[0-9;]*m//g' | wc -c)
    local padding=$(( (width - text_length) / 2 ))
    printf "%*s%s%*s" $padding "" "$text" $((width - text_length - padding)) ""
}

# Draw the bottom bar
{
    # Save cursor position
    printf '\033[s'
    
    # Move to bottom line
    printf '\033[%d;1H' "$HEIGHT"
    
    # Set background color
    printf '\033[48;5;235m'
    
    # Clear line
    printf '\033[K'
    
    # Convert and display status
    CONVERTED_STATUS=$(convert_colors "$STATUS")
    center_text "$CONVERTED_STATUS" "$WIDTH"
    
    # Reset attributes
    printf '\033[0m'
    
    # Restore cursor position
    printf '\033[u'
} > /dev/tty