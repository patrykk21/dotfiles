#!/usr/bin/env bash
# Create a floating bottom pane for status display

# Configuration
PANE_HEIGHT=1
PANE_ID_FILE="/tmp/tmux-bottom-pane-${USER}-${TMUX_PANE:-$$}"

# Check if bottom pane already exists
if [[ -f "$PANE_ID_FILE" ]]; then
    EXISTING_PANE=$(cat "$PANE_ID_FILE" 2>/dev/null)
    if tmux list-panes -F "#{pane_id}" | grep -q "^${EXISTING_PANE}$"; then
        # Pane already exists
        exit 0
    fi
fi

# Save current pane
ORIGINAL_PANE=$(tmux display-message -p "#{pane_id}")

# Create bottom pane
# Split horizontally at the bottom with specific height
BOTTOM_PANE=$(tmux split-window -v -l $PANE_HEIGHT -d -P -F "#{pane_id}" \
    "~/.config/tmux/scripts/bottom-pane-display.sh")

# Save the pane ID
echo "$BOTTOM_PANE" > "$PANE_ID_FILE"

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

# Make sure we return to the original pane
tmux select-pane -t "$ORIGINAL_PANE" -e