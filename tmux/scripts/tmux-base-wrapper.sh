#!/usr/bin/env bash

# Wrapper for tmux command that handles base repository sessions
# This prevents creating multiple numeric sessions for the base repo

# Check if we're in a git repository
if git rev-parse --git-dir > /dev/null 2>&1; then
    # Get the main repository path (not worktree)
    MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
    CURRENT_DIR=$(pwd)
    
    # Check if we're in the base repository (not a worktree)
    if [ "$CURRENT_DIR" = "$MAIN_REPO" ] || [[ "$CURRENT_DIR" == "$MAIN_REPO"/* && ! "$CURRENT_DIR" =~ /worktrees/ ]]; then
        # We're in the base repository
        
        # Check if base session exists
        if tmux has-session -t "base" 2>/dev/null; then
            # Attach to existing base session
            exec tmux attach-session -t "base"
        else
            # Create new base session with proper setup
            ~/.config/tmux/scripts/create-worktree-session.sh "base" "$MAIN_REPO"
            
            # Save metadata for the base session
            REPO_NAME=$(basename "$MAIN_REPO")
            source ~/.config/tmux/scripts/worktree-metadata.sh
            save_session_metadata "$REPO_NAME" "base" "$MAIN_REPO" "master" "base"
            
            # Ensure bottom panes are properly sized
            for window in 1 2 3; do
                tmux resize-pane -t "base:$window.2" -y 1 2>/dev/null
            done
            
            # Attach to the new session
            exec tmux attach-session -t "base"
        fi
    fi
fi

# Not in base repo, use regular tmux command directly
exec command tmux "$@"