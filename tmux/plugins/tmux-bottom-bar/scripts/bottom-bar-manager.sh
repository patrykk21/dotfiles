#!/usr/bin/env bash
# Bottom bar manager - Creates and maintains a persistent bottom status bar

# Function to get terminal dimensions
get_terminal_size() {
    local size=$(tmux display-message -p "#{window_width}x#{window_height}")
    echo "$size"
}

# Function to draw the bottom bar using ANSI escape sequences
draw_bottom_bar() {
    local width=$(tmux display-message -p "#{window_width}")
    local height=$(tmux display-message -p "#{window_height}")
    local mode=$(tmux display-message -p '#{client_key_table}')
    
    # Get the status content from the original status-bar.sh
    local content=$(~/.config/tmux/scripts/status-bar.sh)
    
    # Save cursor position
    printf '\033[s'
    
    # Move to bottom line
    printf '\033[%d;1H' "$height"
    
    # Clear the line
    printf '\033[K'
    
    # Set background color to match OneDark theme
    printf '\033[48;5;235m'
    
    # Center the content
    local content_plain=$(echo "$content" | sed 's/#\[[^]]*\]//g')
    local content_length=${#content_plain}
    local padding=$(( (width - content_length) / 2 ))
    
    # Print padding
    printf '%*s' "$padding" ''
    
    # Print the content (converting tmux format codes to ANSI)
    echo -n "$content" | sed -e 's/#\[bg=colour75,fg=colour235\]/\\033[48;5;75m\\033[38;5;235m/g' \
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
                              -e 's/#\[bg=colour235,fg=colour/\\033[48;5;235m\\033[38;5;/g' \
                              -e 's/#\[bg=colour240,fg=colour250\]/\\033[48;5;240m\\033[38;5;250m/g' \
                              -e 's/#\[fg=colour250\]/\\033[38;5;250m/g' \
                              -e 's/#\[fg=colour243\]/\\033[38;5;243m/g' \
                              -e 's/#\[bold\]/\\033[1m/g' \
                              -e 's/#\[[^]]*\]//g' | xargs -0 printf
    
    # Fill the rest of the line
    printf '\033[48;5;235m%*s' "$((width - padding - content_length))" ''
    
    # Reset colors
    printf '\033[0m'
    
    # Restore cursor position
    printf '\033[u'
}

# Function to setup the bottom margin
setup_bottom_margin() {
    local height=$(tmux display-message -p "#{window_height}")
    # Set scrolling region to exclude bottom line
    printf '\033[1;%dr' "$((height - 1))"
}

# Main loop
while true; do
    # Check if tmux is still running
    if ! tmux info &>/dev/null; then
        break
    fi
    
    # Draw the bottom bar
    draw_bottom_bar
    
    # Sleep for a short interval
    sleep 0.5
done