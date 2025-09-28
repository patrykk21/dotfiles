#!/usr/bin/env bash

# Auto save/restore functionality for tmux
# Makes tmux behave like Zellij with automatic session persistence

TMUX_RESURRECT_DIR="$HOME/.tmux/resurrect"

# Function to save current tmux state
save_tmux_state() {
    # Only save if we're inside tmux
    if [ -n "$TMUX" ]; then
        # Run resurrect save script directly
        ~/.tmux/plugins/tmux-resurrect/scripts/save.sh quiet
    fi
}

# Function to restore tmux state
restore_tmux_state() {
    # Check if there's a last saved state
    if [ -f "$TMUX_RESURRECT_DIR/last" ]; then
        # Run resurrect restore script
        ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh
        return 0
    fi
    return 1
}

# Handle the command
case "$1" in
    save)
        save_tmux_state
        ;;
    restore)
        restore_tmux_state
        ;;
    *)
        echo "Usage: $0 {save|restore}"
        exit 1
        ;;
esac