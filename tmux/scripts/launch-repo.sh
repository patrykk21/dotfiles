#!/usr/bin/env bash
# Launch repository in browser

# Get current directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Check if we're in a git repository
if ! git -C "$CURRENT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tmux display-message "Not in a git repository"
    exit 1
fi

# Try to get repository URL using gh CLI first
if command -v gh >/dev/null 2>&1; then
    REPO_URL=$(cd "$CURRENT_DIR" && gh repo view --json url --jq '.url' 2>/dev/null)
    
    if [ -n "$REPO_URL" ] && [ "$REPO_URL" != "null" ]; then
        if command -v open >/dev/null 2>&1; then
            open "$REPO_URL"
            tmux display-message "Opened repository in browser"
            exit 0
        else
            tmux display-message "Cannot open browser: 'open' command not found"
            exit 1
        fi
    fi
fi

# Fallback: try to construct URL from git remote
REMOTE_URL=$(git -C "$CURRENT_DIR" remote get-url origin 2>/dev/null)

if [ -z "$REMOTE_URL" ]; then
    tmux display-message "No remote origin found"
    exit 1
fi

# Convert SSH URL to HTTPS if needed
if [[ "$REMOTE_URL" =~ ^git@ ]]; then
    # Convert git@github.com:owner/repo.git to https://github.com/owner/repo
    REPO_URL=$(echo "$REMOTE_URL" | sed 's/git@\([^:]*\):/https:\/\/\1\//' | sed 's/\.git$//')
elif [[ "$REMOTE_URL" =~ ^https:// ]]; then
    # Remove .git suffix if present
    REPO_URL=$(echo "$REMOTE_URL" | sed 's/\.git$//')
else
    tmux display-message "Unsupported remote URL format: $REMOTE_URL"
    exit 1
fi

# Open in browser
if command -v open >/dev/null 2>&1; then
    open "$REPO_URL"
    tmux display-message "Opened repository in browser"
else
    tmux display-message "Cannot open browser: 'open' command not found"
    exit 1
fi