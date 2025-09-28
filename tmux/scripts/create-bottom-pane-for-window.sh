#!/usr/bin/env bash
# Create a floating bottom pane for status display - window specific version

# Configuration
PANE_HEIGHT=1

# Get the target window (passed as argument or current)
TARGET_WINDOW="${1:-$(tmux display-message -p '#{session_name}:#{window_index}')}"

# Check if this window already has a bottom status pane by looking for the specific title
EXISTING_BOTTOM=$(tmux list-panes -t "$TARGET_WINDOW" -F "#{pane_id} #{pane_title}" | grep "__tmux_status_bar__" | awk '{print $1}')

if [ -n "$EXISTING_BOTTOM" ]; then
    # Bottom pane already exists for this window
    exit 0
fi

# Save current window
ORIGINAL_WINDOW=$(tmux display-message -p "#{session_name}:#{window_index}")

# Switch to the target window first
tmux select-window -t "$TARGET_WINDOW"

# Now create the bottom pane in the current (target) window
BOTTOM_PANE=$(tmux split-window -v -l $PANE_HEIGHT -d -P -F "#{pane_id}" \
    "~/.config/tmux/scripts/bottom-pane-display.sh")

# Set a unique pane title to identify it
tmux select-pane -t "$BOTTOM_PANE" -T "__tmux_status_bar__"

# Configure the bottom pane to be non-selectable
tmux set-option -t "$BOTTOM_PANE" -p window-style 'bg=colour235,fg=colour250'
tmux set-option -t "$BOTTOM_PANE" -p pane-border-style 'fg=colour235'

# Make the pane unselectable - it cannot receive focus
tmux select-pane -t "$BOTTOM_PANE" -d

# Set the pane as "dead" so it can't be selected with mouse or keyboard
tmux set-option -t "$BOTTOM_PANE" -p remain-on-exit on

# Disable all input to this pane
tmux set-option -t "$BOTTOM_PANE" -p synchronize-panes off

# Switch back to the original window if different
if [ "$ORIGINAL_WINDOW" != "$TARGET_WINDOW" ]; then
    tmux select-window -t "$ORIGINAL_WINDOW"
fi