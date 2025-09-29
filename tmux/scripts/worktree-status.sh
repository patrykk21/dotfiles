#!/usr/bin/env bash

# Get current session name
SESSION=$(tmux display-message -p '#S')

# Get current directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Get SERVER_PORT from the active pane's environment
SERVER_PORT=$(tmux show-environment -t "$SESSION" SERVER_PORT 2>/dev/null | cut -d= -f2)

# If not found in session, try global environment
if [ -z "$SERVER_PORT" ] || [ "$SERVER_PORT" = "-SERVER_PORT" ]; then
    SERVER_PORT=$(tmux show-environment -g SERVER_PORT 2>/dev/null | cut -d= -f2)
fi

# Clear if we got the unset marker
if [ "$SERVER_PORT" = "-SERVER_PORT" ]; then
    SERVER_PORT=""
fi

# Check if we're in a git repository
if ! git -C "$CURRENT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Not in a git repo, just show session name
    OUTPUT="#[fg=colour243,bg=colour235] $SESSION"
    
    # Add SERVER_PORT if it exists
    if [ -n "$SERVER_PORT" ]; then
        OUTPUT="$OUTPUT #[fg=colour239] • #[fg=colour214] $SERVER_PORT"
    fi
    
    echo "$OUTPUT  "
    exit 0
fi

# Get the worktree path
WORKTREE_PATH=$(git -C "$CURRENT_DIR" rev-parse --show-toplevel 2>/dev/null)

# Get the main repository path
MAIN_REPO=$(git -C "$CURRENT_DIR" worktree list | head -1 | awk '{print $1}')

# Check if we're in the main repository or a worktree
if [ "$WORKTREE_PATH" = "$MAIN_REPO" ]; then
    # In main repository
    BRANCH=$(git -C "$CURRENT_DIR" branch --show-current 2>/dev/null || echo "detached")
    OUTPUT="#[fg=colour243,bg=colour235] main:$BRANCH"
    
    # Add SERVER_PORT if it exists
    if [ -n "$SERVER_PORT" ]; then
        OUTPUT="$OUTPUT #[fg=colour239] • #[fg=colour214] $SERVER_PORT"
    fi
    
    echo "$OUTPUT  "
else
    # In a worktree - extract ticket name from path or session
    WORKTREE_NAME=$(basename "$WORKTREE_PATH")
    
    # Try to extract ticket pattern (e.g., ECH-123)
    if [[ "$WORKTREE_NAME" =~ ([A-Z]+-[0-9]+) ]]; then
        TICKET="${BASH_REMATCH[1]}"
    elif [[ "$SESSION" =~ ([A-Z]+-[0-9]+) ]]; then
        TICKET="${BASH_REMATCH[1]}"
    else
        TICKET="$SESSION"
    fi
    
    # Get current branch
    BRANCH=$(git -C "$CURRENT_DIR" branch --show-current 2>/dev/null || echo "detached")
    
    # Show worktree indicator with ticket
    OUTPUT="#[fg=colour73,bg=colour235] ⎇ $TICKET #[fg=colour243]($BRANCH)"
    
    # Add SERVER_PORT if it exists
    if [ -n "$SERVER_PORT" ]; then
        OUTPUT="$OUTPUT #[fg=colour239] • #[fg=colour214] $SERVER_PORT"
    fi
    
    echo "$OUTPUT  "
fi