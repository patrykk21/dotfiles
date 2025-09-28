#!/usr/bin/env bash

# Worktree picker using fzf-tmux
# Shows all git worktrees and allows switching or deleting

# Get the main repository path (parent of current worktree)
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
REPO_NAME=$(basename "$MAIN_REPO")
PARENT_DIR=$(dirname "$MAIN_REPO")

# Get current directory to identify current worktree
CURRENT_DIR=$(pwd)
CURRENT_WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null)

# Get list of worktrees with their info
get_worktrees() {
    git worktree list --porcelain | awk -v current="$CURRENT_WORKTREE" '
    /^worktree/ {
        path = $2
        # Extract just the directory name
        split(path, parts, "/")
        dirname = parts[length(parts)]
    }
    /^HEAD/ {
        commit = substr($2, 1, 7)
    }
    /^branch/ {
        branch = $2
        # Extract ticket number from branch if possible
        if (match(branch, /[A-Z]+-[0-9]+/)) {
            ticket = substr(branch, RSTART, RLENGTH)
        } else if (match(dirname, /[A-Z]+-[0-9]+/)) {
            ticket = substr(dirname, RSTART, RLENGTH)
        } else {
            ticket = dirname
        }
        
        # Check if tmux session exists
        cmd = "tmux has-session -t " ticket " 2>/dev/null && echo active || echo inactive"
        cmd | getline session_status
        close(cmd)
        
        # Format output
        if (path == current) {
            # Current worktree - show with arrow
            if (session_status == "active") {
                status_icon = "→ ● "
            } else {
                status_icon = "→ ○ "
            }
        } else {
            if (session_status == "active") {
                status_icon = "  ● "
            } else {
                status_icon = "  ○ "
            }
        }
        
        printf "%s%-15s %-30s %s\n", status_icon, ticket, branch, path
    }'
}


# Function to switch to worktree session
switch_to_worktree() {
    local selection="$1"
    # Extract the ticket/session name and path
    local ticket=$(echo "$selection" | awk '{print $2}')
    local worktree_path=$(echo "$selection" | awk '{print $NF}')
    
    # Check if this is the main repository
    if [ "$worktree_path" = "$MAIN_REPO" ]; then
        # For main repo, just change directory in current session
        tmux send-keys -t . "cd $worktree_path" Enter
        return
    fi
    
    # For actual worktrees, check if session exists
    if tmux has-session -t "$ticket" 2>/dev/null; then
        # Session exists, switch to it
        tmux switch-client -t "$ticket"
    else
        # Only create session with 3 tabs for actual worktrees (not main)
        tmux new-session -d -s "$ticket" -c "$worktree_path" -n "claude"
        tmux new-window -t "$ticket:2" -n "server" -c "$worktree_path"
        tmux new-window -t "$ticket:3" -n "commands" -c "$worktree_path"
        tmux select-window -t "$ticket:1"
        tmux switch-client -t "$ticket"
    fi
}

# Function to reload worktrees list
reload_worktrees() {
    get_worktrees
}

# Handle script being called with reload argument
if [ "$1" = "reload" ]; then
    reload_worktrees
    exit 0
fi

# Use fzf-tmux to select a worktree
selected=$(get_worktrees | fzf-tmux -p 70%,60% \
    --prompt=" Select worktree: " \
    --header="↵ switch | ctrl-x delete | ctrl-r reload | ^C cancel" \
    --header-lines=0 \
    --color="fg:250,bg:235,hl:114,fg+:235,bg+:114,hl+:235,prompt:114,pointer:114,header:243" \
    --border=rounded \
    --border-label=" Git Worktrees " \
    --bind "ctrl-x:execute-silent(~/.config/tmux/scripts/worktree-delete-from-picker.sh {})+reload(~/.config/tmux/scripts/worktree-picker-fzf.sh reload)" \
    --bind "ctrl-r:reload(~/.config/tmux/scripts/worktree-picker-fzf.sh reload)")

# If a worktree was selected (Enter pressed), switch to it
if [ -n "$selected" ]; then
    switch_to_worktree "$selected"
fi