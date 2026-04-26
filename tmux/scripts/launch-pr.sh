#!/usr/bin/env bash
# Launch pull request in browser

# Get current directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Check if we're in a git repository
if ! git -C "$CURRENT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tmux display-message "Not in a git repository"
    exit 1
fi

# Check if gh CLI is available
if ! command -v gh >/dev/null 2>&1; then
    tmux display-message "GitHub CLI (gh) not found"
    exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git -C "$CURRENT_DIR" branch --show-current 2>/dev/null)

if [ -z "$CURRENT_BRANCH" ]; then
    tmux display-message "Not on a branch (detached HEAD)"
    exit 1
fi

# Try to find existing PR for current branch
PR_URL=$(cd "$CURRENT_DIR" && gh pr list --head "$CURRENT_BRANCH" --json url --jq '.[0].url' 2>/dev/null)

source ~/.config/tmux/scripts/os-utils.sh

if [ -n "$PR_URL" ] && [ "$PR_URL" != "null" ]; then
    if open_url "$PR_URL"; then
        tmux display-message "Opened PR for branch: $CURRENT_BRANCH"
    else
        tmux display-message "Cannot open browser on $(detect_os)"
    fi
else
    tmux display-message "No PR found for branch: $CURRENT_BRANCH"
fi