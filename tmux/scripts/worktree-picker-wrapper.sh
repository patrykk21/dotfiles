#!/usr/bin/env bash

# Wrapper script for worktree picker that handles deletion confirmations

while true; do
    # Run the picker
    ~/.config/tmux/scripts/worktree-picker-fzf.sh
    EXIT_CODE=$?
    
    # Check if deletion was requested (exit code 99 or pending file exists)
    if [ $EXIT_CODE -eq 99 ] || [ -f /tmp/tmux-worktree-delete-pending ]; then
        # Read deletion info
        if [ -f /tmp/tmux-worktree-delete-pending ]; then
            DELETE_INFO=$(cat /tmp/tmux-worktree-delete-pending)
            rm -f /tmp/tmux-worktree-delete-pending
            
            # Parse the info
            IFS='|' read -r TICKET WORKTREE_PATH REPO_NAME <<< "$DELETE_INFO"
            
            # Show confirmation dialog
            confirm=$(printf "NO - Cancel\nYES - Delete worktree '$TICKET'" | fzf-tmux -p 50%,30% \
                --prompt=" Delete worktree '$TICKET'? " \
                --header="This will permanently delete the worktree and its session" \
                --header-lines=0 \
                --no-sort \
                --color="fg:250,bg:235,hl:168,fg+:235,bg+:168,hl+:235,prompt:168,pointer:168,header:180" \
                --border=rounded \
                --border-label=" ⚠️  Confirm Deletion " \
                --no-multi)
            
            # Check if user confirmed deletion
            if [[ "$confirm" == "YES"* ]]; then
                # Source metadata functions
                source "$(dirname "$0")/worktree-metadata.sh"
                
                # Kill tmux session if it exists
                tmux has-session -t "$TICKET" 2>/dev/null && tmux kill-session -t "$TICKET" 2>/dev/null
                
                # Remove metadata if it exists
                remove_session_metadata "$REPO_NAME" "$TICKET"
                
                # Remove the git worktree
                git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || git worktree prune
                
                # Display success message
                tmux display-message -d 2000 "✓ Deleted worktree: $TICKET"
                
                # Show the picker again to see updated list
                continue
            else
                # Display cancellation message
                tmux display-message -d 1000 "Deletion cancelled"
                # Show the picker again
                continue
            fi
        fi
    fi
    
    # No deletion request, exit normally
    break
done