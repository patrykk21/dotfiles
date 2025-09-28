#!/usr/bin/env bash

# Get current session name
SESSION=$(tmux display-message -p '#S')

# Get current directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Check if we're in a git repository
if ! git -C "$CURRENT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Not in a git repo, just show session name
    echo "#[fg=colour243,bg=colour235] $SESSION "
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
    echo "#[fg=colour243,bg=colour235] main:$BRANCH "
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
    echo "#[fg=colour73,bg=colour235] ⎇ $TICKET #[fg=colour243]($BRANCH) "
fi