#!/usr/bin/env bash
# tmux-bottom-bar: A plugin to create a persistent bottom status bar

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the bottom bar manager
tmux run-shell "$CURRENT_DIR/scripts/bottom-bar-manager.sh &"

# Set up hooks to update the bottom bar on mode changes
tmux set-hook -g client-session-changed "run-shell '$CURRENT_DIR/scripts/update-bottom-bar.sh'"
tmux set-hook -g after-select-pane "run-shell '$CURRENT_DIR/scripts/update-bottom-bar.sh'"
tmux set-hook -g after-select-window "run-shell '$CURRENT_DIR/scripts/update-bottom-bar.sh'"

# Adjust terminal dimensions to reserve space for bottom bar
tmux set-environment -g TMUX_BOTTOM_BAR_HEIGHT 1