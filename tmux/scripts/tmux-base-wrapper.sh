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
        
        # Create a unique base session name for this repository
        REPO_NAME=$(basename "$MAIN_REPO")
        # Sanitize repo name - replace dots and other special chars with underscores
        SAFE_REPO_NAME=$(echo "$REPO_NAME" | sed 's/[^a-zA-Z0-9-]/_/g')
        BASE_SESSION_NAME="${SAFE_REPO_NAME}-base"
        
        # Check if this repo's base session exists
        if tmux has-session -t "$BASE_SESSION_NAME" 2>/dev/null; then
            # Attach to existing base session for this repository
            exec tmux attach-session -t "$BASE_SESSION_NAME"
        else
            # Create new base session in detached mode first
            ~/.config/tmux/scripts/create-worktree-session.sh "$BASE_SESSION_NAME" "$MAIN_REPO"
            
            # Save metadata for the base session
            source ~/.config/tmux/scripts/worktree-metadata.sh
            # Get the current branch name
            CURRENT_BRANCH=$(git -C "$MAIN_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")
            save_session_metadata "$REPO_NAME" "$BASE_SESSION_NAME" "$MAIN_REPO" "$CURRENT_BRANCH" "$BASE_SESSION_NAME"
            
            
            # Now attach to the already-configured session
            exec tmux attach-session -t "$BASE_SESSION_NAME"
        fi
    fi
fi

# Not in base repo, use regular tmux command directly
exec command tmux "$@"