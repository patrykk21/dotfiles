#!/usr/bin/env bash

# Create a new git worktree with associated tmux session
# Usage: worktree-create.sh <ticket-name>

TICKET="$1"

# Validate input
if [ -z "$TICKET" ]; then
    tmux display-message -d 2000 "Error: No ticket name provided"
    exit 1
fi

# Validate ticket format (should contain letters and numbers, typically ECH-123 format)
if ! echo "$TICKET" | grep -qE '^[A-Za-z]+-[0-9]+$|^[A-Za-z0-9_-]+$'; then
    tmux display-message -d 2000 "Error: Invalid ticket format. Use format like ECH-123"
    exit 1
fi

# Get the main repository info
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
if [ -z "$MAIN_REPO" ]; then
    tmux display-message -d 2000 "Error: Not in a git repository"
    exit 1
fi

REPO_NAME=$(basename "$MAIN_REPO")
PARENT_DIR=$(dirname "$MAIN_REPO")

# Define paths
WORKTREE_PATH="$PARENT_DIR/$REPO_NAME-$TICKET"
BRANCH_NAME="feature/$TICKET"

# Check if worktree already exists
if [ -d "$WORKTREE_PATH" ]; then
    tmux display-message -d 2000 "Error: Worktree $TICKET already exists"
    exit 1
fi

# Check if tmux session already exists
if tmux has-session -t "$TICKET" 2>/dev/null; then
    tmux display-message -d 2000 "Error: Tmux session $TICKET already exists"
    exit 1
fi

# Create the worktree
tmux display-message -d 1000 "Creating worktree for $TICKET..."

# Create worktree with new branch
if ! git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" 2>/dev/null; then
    # If branch already exists, just check it out
    git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>/dev/null || {
        tmux display-message -d 2000 "Error: Failed to create worktree"
        exit 1
    }
fi

# Function to copy files if they exist
copy_if_exists() {
    local source="$1"
    local dest="$2"
    if [ -e "$source" ]; then
        cp -r "$source" "$dest"
    fi
}

# Copy environment and configuration files
tmux display-message -d 1000 "Copying configuration files..."

# Copy .env files
for env_file in "$MAIN_REPO"/.env*; do
    [ -f "$env_file" ] && copy_if_exists "$env_file" "$WORKTREE_PATH/"
done

# Copy .claude directory
copy_if_exists "$MAIN_REPO/.claude" "$WORKTREE_PATH/"

# Copy CLAUDE.local.md if it exists
copy_if_exists "$MAIN_REPO/CLAUDE.local.md" "$WORKTREE_PATH/"

# Detect package manager and install dependencies
tmux display-message -d 1000 "Installing dependencies..."

cd "$WORKTREE_PATH"

# Function to run package install in background
install_dependencies() {
    if [ -f "bun.lockb" ] || [ -f "package.json" ] && command -v bun &> /dev/null; then
        bun install > /dev/null 2>&1 &
    elif [ -f "yarn.lock" ]; then
        yarn install > /dev/null 2>&1 &
    elif [ -f "pnpm-lock.yaml" ]; then
        pnpm install > /dev/null 2>&1 &
    elif [ -f "package-lock.json" ] || [ -f "package.json" ]; then
        npm install > /dev/null 2>&1 &
    fi
}

# Create tmux session with 3 tabs
tmux new-session -d -s "$TICKET" -c "$WORKTREE_PATH" -n "claude"
tmux new-window -t "$TICKET:2" -n "server" -c "$WORKTREE_PATH"
tmux new-window -t "$TICKET:3" -n "commands" -c "$WORKTREE_PATH"

# Select first window
tmux select-window -t "$TICKET:1"

# Run dependency installation in the background
install_dependencies

# Switch to the new session
tmux switch-client -t "$TICKET"

# Display success message
tmux display-message -d 2000 "✓ Created worktree $TICKET with session"