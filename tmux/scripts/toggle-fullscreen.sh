#!/usr/bin/env bash
# Toggle custom fullscreen that preserves status bar

LAYOUT_FILE="/tmp/tmux-fullscreen-layout-${TMUX_PANE}"
PANES_FILE="/tmp/tmux-fullscreen-panes-${TMUX_PANE}"

if [[ -f "$PANES_FILE" ]]; then
    # Exit fullscreen - restore layout
    if [[ -f "$LAYOUT_FILE" ]]; then
        # Restore the original layout
        LAYOUT=$(cat "$LAYOUT_FILE")
        tmux select-layout "$LAYOUT"
        
        # Clean up
        rm -f "$LAYOUT_FILE" "$PANES_FILE"
        tmux display-message "Exited fullscreen"
    fi
else
    # Enter fullscreen
    # Save current layout
    tmux list-windows -F '#{window_layout}' > "$LAYOUT_FILE"
    
    # Save pane information
    tmux list-panes -F "#{pane_id}:#{pane_width}:#{pane_height}" > "$PANES_FILE"
    
    # Get current pane and status pane
    CURRENT_PANE=$(tmux display-message -p "#{pane_id}")
    STATUS_PANE=$(tmux list-panes -F "#{pane_id}:#{pane_title}" | grep ":__tmux_status_bar__$" | cut -d: -f1)
    
    # Get window dimensions
    WINDOW_WIDTH=$(tmux display-message -p '#{window_width}')
    WINDOW_HEIGHT=$(tmux display-message -p '#{window_height}')
    
    # First, use even-vertical to stack all panes
    tmux select-layout even-vertical
    
    # Now resize panes
    if [[ -n "$STATUS_PANE" ]]; then
        # Calculate heights
        MAIN_HEIGHT=$((WINDOW_HEIGHT - 1))
        
        # Make current pane take most of the space
        tmux resize-pane -t "$CURRENT_PANE" -y "$MAIN_HEIGHT"
        
        # Make status bar 1 line
        tmux resize-pane -t "$STATUS_PANE" -y 1
        
        # Hide all other panes by making them 0 height
        for pane in $(tmux list-panes -F "#{pane_id}"); do
            if [[ "$pane" != "$CURRENT_PANE" ]] && [[ "$pane" != "$STATUS_PANE" ]]; then
                tmux resize-pane -t "$pane" -y 0
            fi
        done
    else
        # No status bar, just maximize current pane
        tmux resize-pane -t "$CURRENT_PANE" -y "$WINDOW_HEIGHT"
        
        # Hide all other panes
        for pane in $(tmux list-panes -F "#{pane_id}"); do
            if [[ "$pane" != "$CURRENT_PANE" ]]; then
                tmux resize-pane -t "$pane" -y 0
            fi
        done
    fi
    
    tmux display-message "Entered fullscreen (press 'f' to exit)"
fi