#!/usr/bin/env bash
# Toggle fullscreen while preserving status bar

# Check if we have a saved layout
if [[ -f "/tmp/tmux-layout-${TMUX_PANE}" ]]; then
    # Restore layout
    LAYOUT=$(cat "/tmp/tmux-layout-${TMUX_PANE}")
    tmux select-layout "$LAYOUT"
    rm -f "/tmp/tmux-layout-${TMUX_PANE}"
    tmux display-message "Exited fullscreen"
else
    # Save current layout
    tmux list-windows -F '#{window_layout}' > "/tmp/tmux-layout-${TMUX_PANE}"
    
    # Get current pane and status bar
    CURRENT_PANE=$(tmux display-message -p "#{pane_id}")
    STATUS_PANE=$(tmux list-panes -F "#{pane_id}:#{pane_title}" | grep ":__tmux_status_bar__$" | cut -d: -f1)
    
    # Hide all panes except current and status bar
    for pane in $(tmux list-panes -F "#{pane_id}"); do
        if [[ "$pane" != "$CURRENT_PANE" ]] && [[ "$pane" != "$STATUS_PANE" ]]; then
            tmux resize-pane -t "$pane" -x 0 -y 0
        fi
    done
    
    # Maximize current pane (leaving room for status)
    if [[ -n "$STATUS_PANE" ]]; then
        # Leave 1 line for status bar
        HEIGHT=$(($(tmux display-message -p '#{window_height}') - 1))
        tmux resize-pane -t "$CURRENT_PANE" -x "100%" -y "$HEIGHT"
    else
        tmux resize-pane -t "$CURRENT_PANE" -x "100%" -y "100%"
    fi
    
    tmux display-message "Entered fullscreen"
fi