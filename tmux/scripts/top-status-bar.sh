#!/usr/bin/env bash

# Source session group utilities
source ~/.config/tmux/scripts/tmux-session-utils.sh

# Clear the terminal and set up the environment
export TERM=xterm-256color

# Initial clear
printf '\033[2J\033[H'

# Function to get window name with formatting
get_window_tabs() {
    local current_window="$1"
    local tabs=""
    local window_list=$(tmux list-windows -F '#I:#W' 2>/dev/null)
    
    while IFS= read -r win; do
        local index=$(echo "$win" | cut -d: -f1)
        local name=$(echo "$win" | cut -d: -f2-)
        
        if [ "$index" = "$current_window" ]; then
            # Active tab with bright color and marker
            tabs="${tabs}$(printf '\033[48;5;114m\033[38;5;235m\033[1m %s \033[0m\033[38;5;114m\033[48;5;235m█\033[0m ' "$name")"
        else
            # Inactive tab with subtle background
            tabs="${tabs}$(printf '\033[48;5;237m\033[38;5;243m %s \033[0m ' "$name")"
        fi
    done <<< "$window_list"
    
    echo "$tabs"
}

# Function to get worktree status (right side)
get_worktree_status() {
    local session="$1"
    local current_path="$2"
    local server_port="$3"
    local output=""
    
    # Check if we're in a git repository
    if ! git -C "$current_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # Not in a git repo, just show session name
        output="$(printf '\033[38;5;243m%s\033[0m' "$session")"
    else
        # Get the worktree path
        local worktree_path=$(git -C "$current_path" rev-parse --show-toplevel 2>/dev/null)
        local main_repo=$(git -C "$current_path" worktree list | head -1 | awk '{print $1}')
        
        if [ "$worktree_path" = "$main_repo" ]; then
            # In main repository
            local branch=$(git -C "$current_path" branch --show-current 2>/dev/null || echo "detached")
            output="$(printf '\033[38;5;243mmain:%s\033[0m' "$branch")"
        else
            # In a worktree
            local worktree_name=$(basename "$worktree_path")
            local ticket=""
            
            if [[ "$worktree_name" =~ ([A-Z]+-[0-9]+) ]]; then
                ticket="${BASH_REMATCH[1]}"
            elif [[ "$session" =~ ([A-Z]+-[0-9]+) ]]; then
                ticket="${BASH_REMATCH[1]}"
            else
                ticket="$session"
            fi
            
            local branch=$(git -C "$current_path" branch --show-current 2>/dev/null || echo "detached")
            output="$(printf '\033[38;5;73m⎇ %s \033[38;5;243m(%s)\033[0m' "$ticket" "$branch")"
        fi
    fi
    
    # Add SERVER_PORT if it exists
    if [ -n "$server_port" ] && [ "$server_port" != "-SERVER_PORT" ]; then
        output="${output}$(printf '\033[38;5;239m • \033[38;5;214m%s\033[0m' "$server_port")"
    fi
    
    echo "$output"
}

# Function to get the main work pane's current path (not the status pane's own path)
get_work_pane_path() {
    local session="$1"
    local window="$2"
    # Find the active pane in this window that isn't a 1-line status bar
    # The work pane is the large pane (height > 1)
    local path
    path=$(tmux list-panes -t "${session}:${window}" -F '#{pane_height} #{pane_current_path} #{pane_active}' 2>/dev/null | \
        awk '$1 > 1 && $3 == 1 { print $2; exit }')
    if [ -z "$path" ]; then
        # Fallback: just get the largest pane's path
        path=$(tmux list-panes -t "${session}:${window}" -F '#{pane_height} #{pane_current_path}' 2>/dev/null | \
            sort -rn | head -1 | awk '{ print $2 }')
    fi
    echo "$path"
}

# Function to draw status line
draw_status() {
    # Get session, window, and width from the status pane's own context
    local info=$(tmux display-message -p '#S|#I|#{pane_width}')
    IFS='|' read -r raw_session current_window width <<< "$info"
    # Resolve grouped child to master for metadata lookups
    local session
    session=$(resolve_master_session "$raw_session")
    # Get the current path from the WORK pane, not the status pane
    local current_path
    current_path=$(get_work_pane_path "$raw_session" "$current_window")

    # Get SERVER_PORT (check the raw session first, then the master)
    local server_port=$(tmux show-environment -t "$raw_session" SERVER_PORT 2>/dev/null | cut -d= -f2)
    if [ -z "$server_port" ] || [ "$server_port" = "-SERVER_PORT" ]; then
        server_port=$(tmux show-environment -g SERVER_PORT 2>/dev/null | cut -d= -f2)
    fi
    
    # Build the status line
    local tabs=$(get_window_tabs "$current_window")
    local right_status=$(get_worktree_status "$session" "$current_path" "$server_port")
    
    # Calculate padding for right alignment
    # Remove ANSI codes for length calculation
    local tabs_plain=$(echo -e "$tabs" | sed 's/\x1b\[[0-9;]*m//g')
    local right_plain=$(echo -e "$right_status" | sed 's/\x1b\[[0-9;]*m//g')
    local tabs_len=${#tabs_plain}
    local right_len=${#right_plain}
    local padding=$((width - tabs_len - right_len - 2))
    
    # Move to top and clear line
    printf '\033[H\033[K'
    printf '\033[48;5;235m'  # Set background color
    
    # Left side (tabs)
    printf ' %s' "$tabs"
    
    # Padding
    [ $padding -gt 0 ] && printf '%*s' $padding ""
    
    # Right side (worktree status)
    printf '%s ' "$right_status"
    
    # Fill the rest of the line
    printf '\033[K'
    
    # Reset formatting
    printf '\033[0m'
}

# Cache variables
LAST_WINDOW=""
LAST_WINDOWS=""
LAST_PATH=""
UPDATE_COUNT=0

# Main loop - monitor tmux state directly
while true; do
    # Get current state
    CURRENT_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
    CURRENT_WINDOW=$(tmux display-message -p '#I' 2>/dev/null || echo "")
    CURRENT_WINDOWS=$(tmux list-windows -F '#I' 2>/dev/null | tr '\n' ' ')
    CURRENT_PATH=$(get_work_pane_path "$CURRENT_SESSION" "$CURRENT_WINDOW")
    
    # Check if we need to update (window changed, windows list changed, path changed, or periodic)
    if [ "$CURRENT_WINDOW" != "$LAST_WINDOW" ] || \
       [ "$CURRENT_WINDOWS" != "$LAST_WINDOWS" ] || \
       [ "$CURRENT_PATH" != "$LAST_PATH" ] || \
       [ $((UPDATE_COUNT % 20)) -eq 0 ]; then
        
        draw_status
        
        LAST_WINDOW="$CURRENT_WINDOW"
        LAST_WINDOWS="$CURRENT_WINDOWS"
        LAST_PATH="$CURRENT_PATH"
    fi
    
    ((UPDATE_COUNT++))
    
    # Short sleep for responsiveness
    sleep 0.1
done