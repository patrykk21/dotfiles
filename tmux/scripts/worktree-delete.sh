#!/usr/bin/env bash

# Delete current worktree and its associated tmux session
# This script is called from within a tmux session

# Source metadata functions
source "$(dirname "$0")/worktree-metadata.sh"
source "$(dirname "$0")/tmux-session-utils.sh"
# Kills reparented dev servers (bun → node → next-server) the tmux session can't reach
source "$(dirname "$0")/worktree-proc-utils.sh"

# Get current session name (resolve grouped child to master)
CURRENT_SESSION=$(resolve_master_session "$(tmux display-message -p '#S')")

# Get the main repository info
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
if [ -z "$MAIN_REPO" ]; then
    tmux display-message -d 2000 "Error: Not in a git repository"
    exit 1
fi

REPO_NAME=$(basename "$MAIN_REPO")

# Get current path
CURRENT_PATH=$(pwd)
IS_WORKTREE=false
WORKTREE_PATH=""
TICKET=""

# First check if we can get info from metadata
if [ -f "$GLOBAL_METADATA_DIR/repos.json" ]; then
    # Check if current session matches a known worktree
    for repo_sessions_dir in "$WORKTREES_BASE"/*/.worktree-meta/sessions; do
        if [ -d "$repo_sessions_dir" ]; then
            for metadata_file in "$repo_sessions_dir"/*.json; do
                if [ -f "$metadata_file" ]; then
                    session_name=$(jq -r '.session_name // empty' "$metadata_file" 2>/dev/null)
                    if [ "$session_name" = "$CURRENT_SESSION" ]; then
                        WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$metadata_file" 2>/dev/null)
                        TICKET=$(jq -r '.ticket // empty' "$metadata_file" 2>/dev/null)
                        IS_WORKTREE=true
                        break 2
                    fi
                fi
            done
        fi
    done
fi

# If not found in metadata, try traditional detection
if [ "$IS_WORKTREE" = false ]; then
    # Check if current path is a worktree
    if git worktree list | grep -q "$CURRENT_PATH"; then
        IS_WORKTREE=true
        WORKTREE_PATH="$CURRENT_PATH"
        # Try to extract ticket from path
        if [[ "$CURRENT_PATH" =~ .*\/([A-Z]+-[0-9]+)$ ]]; then
            TICKET="${BASH_REMATCH[1]}"
        else
            TICKET="$CURRENT_SESSION"
        fi
    else
        # Try to find worktree in new structure
        EXPECTED_PATH="$WORKTREES_BASE/$REPO_NAME/$CURRENT_SESSION"
        if [ -d "$EXPECTED_PATH" ] && git worktree list | grep -q "$EXPECTED_PATH"; then
            IS_WORKTREE=true
            WORKTREE_PATH="$EXPECTED_PATH"
            TICKET="$CURRENT_SESSION"
        fi
    fi
fi

# Validate we found a worktree
if [ "$IS_WORKTREE" = false ] || [ -z "$WORKTREE_PATH" ]; then
    tmux display-message -d 2000 "Error: Current session '$CURRENT_SESSION' is not associated with a git worktree"
    exit 1
fi

# Confirm we're not trying to delete the main worktree
if [ "$WORKTREE_PATH" = "$MAIN_REPO" ]; then
    tmux display-message -d 2000 "Error: Cannot delete the main worktree"
    exit 1
fi

# Get the branch name for the worktree
BRANCH_NAME=$(git worktree list --porcelain | grep -A2 "^worktree $WORKTREE_PATH" | grep "^branch" | cut -d' ' -f2)

# Show fzf confirmation dialog
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
if [[ "$confirm" != "YES"* ]]; then
    tmux display-message -d 1000 "Deletion cancelled"
    exit 0
fi

# ORDERING INVARIANT: the irreversible session-kill MUST run LAST, only after the
# worktree is confirmed removed. Killing the session FIRST is what previously left
# orphaned worktrees: kill_session_group can terminate this very run-shell job
# (it was launched from the session being killed), so the worktree removal never
# ran — session gone, worktree + reparented dev servers stranded. So we now:
#   1. move the client off the doomed session (non-destructive),
#   2. kill the worktree's processes,
#   3. remove the worktree — abort here on failure, leaving the session intact,
#   4. only then kill the session.

# Move the attached client to another session so it doesn't detach when we tear
# the worktree's session down (exclude grouped children and the current session).
MAIN_SESSION=$(tmux list-sessions -F "#{session_name}" | grep -v '_g[0-9]\+$' | grep -v "^${CURRENT_SESSION}$" | head -1)
if [ -n "$MAIN_SESSION" ]; then
    tmux switch-client -t "$MAIN_SESSION"
else
    # Create a new session if no other exists
    tmux new-session -d -s "main" -c "$MAIN_REPO"
    tmux switch-client -t "main"
    MAIN_SESSION="main"
fi

# Kill lingering dev servers / watchers (and the worktree's shells) that would
# otherwise keep holding files/ports. Run BEFORE removal so cwd matching works and
# busy files don't block removal. Plain statement, not $(...) — result comes back
# in $WT_KILLED_PROCS. $$ and its ancestors are protected inside the function.
kill_worktree_procs "$WORKTREE_PATH"

# Remove the git worktree from the MAIN repo's context (never from inside the dir
# we're deleting). This is the critical step — it must succeed before we kill the
# session, otherwise the user loses the only handle to retry the deletion.
tmux display-message -d 1000 "Removing worktree at $WORKTREE_PATH..."
cd "$MAIN_REPO" 2>/dev/null || cd / 2>/dev/null

if ! git -C "$MAIN_REPO" worktree remove "$WORKTREE_PATH" --force 2>/dev/null; then
    # If remove fails, try pruning first, then once more.
    git -C "$MAIN_REPO" worktree prune 2>/dev/null
    if ! git -C "$MAIN_REPO" worktree remove "$WORKTREE_PATH" --force 2>/dev/null; then
        # Abort WITHOUT killing the session, so nothing is orphaned and the user
        # can re-run the deletion after dealing with whatever is holding the tree.
        tmux display-message -d 3000 "✗ Could not remove worktree '$TICKET' — session kept. Check for processes holding $WORKTREE_PATH"
        exit 1
    fi
fi

# Worktree is gone — now finish the irreversible teardown.
# Remove metadata if it exists
if [ -n "$TICKET" ]; then
    remove_session_metadata "$REPO_NAME" "$TICKET"
fi

# Kill the worktree session and all grouped children (LAST — see ordering invariant).
kill_session_group "$CURRENT_SESSION"

# Display success message
if [ "${WT_KILLED_PROCS:-0}" -gt 0 ]; then
    tmux display-message -d 2000 "✓ Deleted worktree and session: $CURRENT_SESSION (killed $WT_KILLED_PROCS process(es))"
else
    tmux display-message -d 2000 "✓ Deleted worktree and session: $CURRENT_SESSION"
fi