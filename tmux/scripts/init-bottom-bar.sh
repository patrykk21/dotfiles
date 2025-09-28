#!/usr/bin/env bash
# Initialize terminal for bottom status bar

# This sets up the terminal to reserve the bottom line
# by adjusting the scrolling region

# Get terminal dimensions
HEIGHT=$(tmux display-message -p "#{client_height}")

# Set scrolling region to exclude bottom line
# This prevents tmux content from overwriting our bottom bar
printf '\033[?1049h' # Use alternate screen buffer
printf '\033[1;%dr' "$((HEIGHT-1))" # Set scroll region
printf '\033[?1049l' # Return to normal screen buffer

# Initial draw of bottom bar
~/.config/tmux/scripts/draw-bottom-bar.sh