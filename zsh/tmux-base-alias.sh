#!/usr/bin/env zsh

# Integration with tmux-auto for base repository handling
# This prevents creating multiple numeric sessions for base repositories

# First unalias tmux if it exists
unalias tmux 2>/dev/null || true

# Create new tmux function that integrates with our base wrapper
tmux() {
    # Check if we're in a base repository and no args given
    if [ $# -eq 0 ] && git rev-parse --git-dir > /dev/null 2>&1; then
        local MAIN_REPO=$(git worktree list 2>/dev/null | head -1 | awk '{print $1}')
        local CURRENT_DIR=$(pwd)
        
        # Check if we're in the base repository (not a worktree)
        if [ "$CURRENT_DIR" = "$MAIN_REPO" ] || [[ "$CURRENT_DIR" == "$MAIN_REPO"/* && ! "$CURRENT_DIR" =~ /worktrees/ ]]; then
            # Use our base wrapper
            ~/.config/tmux/scripts/tmux-base-wrapper.sh
            return
        fi
    fi
    
    # Otherwise use regular tmux directly (bypassing tmux-auto)
    command tmux "$@"
}