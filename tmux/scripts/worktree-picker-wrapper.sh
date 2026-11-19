#!/usr/bin/env bash

# Wrapper script for worktree picker that handles deletion confirmations

# Source session group utilities
source "$(dirname "$0")/tmux-session-utils.sh"
# Source worktree process cleanup (kills reparented dev servers like conductor does)
source "$(dirname "$0")/worktree-proc-utils.sh"

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
            confirm=$(printf "NO - Cancel\nYES - Delete worktree '$TICKET'" | fzf \
                --prompt=" Delete worktree '$TICKET'? " \
                --header="This will permanently delete the worktree and its session" \
                --header-lines=0 \
                --no-sort \
                --color="fg:250,bg:235,hl:168,fg+:235,bg+:168,hl+:235,prompt:168,pointer:168,header:180,border:168" \
                --border=rounded \
                --border-label=" ⚠️  Confirm Deletion " \
                --no-multi)
            
            # Check if user confirmed deletion
            if [[ "$confirm" == "YES"* ]]; then
                # Source metadata functions
                SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                source "$SCRIPT_DIR/worktree-metadata.sh"
                
                # ORDERING INVARIANT: remove the worktree BEFORE killing its
                # session/metadata. If the session is killed first and removal then
                # fails, the worktree is stranded with no session to retry from
                # (the orphan bug). So below: kill procs → remove worktree (abort on
                # failure, session kept) → drop metadata → kill session LAST.

                # Kill lingering dev servers / watchers that reparented away from
                # the tmux session (bun → node → next-server holding port 3000).
                # Run BEFORE removal so cwd matching works and busy files don't
                # block `git worktree remove`. Must be a plain statement (not a
                # command substitution) — see worktree-proc-utils.sh; result comes
                # back in $WT_KILLED_PROCS.
                kill_worktree_procs "$WORKTREE_PATH"
                if [ "${WT_KILLED_PROCS:-0}" -gt 0 ]; then
                    KILL_MSG="killed $WT_KILLED_PROCS process(es)"
                else
                    KILL_MSG=""
                fi

                # Remove the git worktree — capture stderr so real failures
                # don't get swallowed into a bogus success toast.
                REMOVE_ERR=$(git worktree remove "$WORKTREE_PATH" --force 2>&1 >/dev/null)
                REMOVE_RC=$?
                if [ $REMOVE_RC -ne 0 ]; then
                    # Try prune-then-retry for stale worktree refs
                    git worktree prune
                    REMOVE_ERR=$(git worktree remove "$WORKTREE_PATH" --force 2>&1 >/dev/null)
                    REMOVE_RC=$?
                fi

                if [ $REMOVE_RC -ne 0 ]; then
                    # Removal failed — abort WITHOUT killing the session, so nothing
                    # is orphaned and the user can retry. Surface the real git error.
                    SHORT_ERR=$(echo "$REMOVE_ERR" | head -1)
                    tmux display-message -d 4000 "✗ Failed to delete $TICKET (session kept): $SHORT_ERR"
                    continue
                fi

                # Worktree is gone — now finish the irreversible teardown.
                remove_session_metadata "$REPO_NAME" "$TICKET"
                kill_session_group "$TICKET"
                tmux display-message -d 2000 "✓ Deleted worktree: $TICKET${KILL_MSG:+ ($KILL_MSG)}"

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