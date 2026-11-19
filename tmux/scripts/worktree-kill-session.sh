#!/usr/bin/env bash

# Kill a tmux session from the worktree picker
# This only kills the session, not the worktree itself

# Source session group utilities
source "$(dirname "$0")/tmux-session-utils.sh"

# Get the full selection line
SELECTION="$*"

# Extract the ticket/session name and type
TICKET=$(echo "$SELECTION" | sed 's/^[[:space:]]*[→○●[:space:]]*//' | awk '{print $1}')
TYPE=$(echo "$SELECTION" | sed 's/^[[:space:]]*[→○●[:space:]]*//' | awk '{print $2}')

# Validate inputs
if [ -z "$TICKET" ]; then
    exit 1
fi

# $TICKET came off the rendered row, which truncates the name to 48 chars for
# column alignment. Restore it from the live session list, because the guard
# below is a string compare and a truncated name never equals the full one.
# Only an unambiguous match is accepted; an exact hit always wins.
resolved=()
while IFS= read -r candidate; do
    if [ "$candidate" = "$TICKET" ]; then
        resolved=("$candidate")
        break
    fi
    case "$candidate" in
        "$TICKET"*) resolved+=("$candidate") ;;
    esac
done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
[ ${#resolved[@]} -eq 1 ] && TICKET="${resolved[0]}"

# Ask tmux whether a session exists rather than reading a status column. The
# previous check tested $3 against "[SESSION]", a token the picker never emits —
# its STATUS column holds values like "[AI WORKING]", so this path always fired
# and ctrl-k could never kill anything.
if ! tmux has-session -t "$TICKET" 2>/dev/null; then
    tmux display-message -d 1000 "No active session to kill"
    exit 0
fi

# Compare group masters on both sides: killing a grouped child of the session
# you are sitting in would take yours down with it.
CURRENT_SESSION=$(resolve_master_session "$(tmux display-message -p '#S')")
TARGET_MASTER=$(resolve_master_session "$TICKET")

if [ "$TARGET_MASTER" = "$CURRENT_SESSION" ]; then
    tmux display-message -d 1000 "Cannot kill current session"
    exit 0
fi

# Kill the session and all grouped children
if tmux has-session -t "$TICKET" 2>/dev/null; then
    kill_session_group "$TICKET"
    tmux display-message -d 1000 "✓ Killed session: $TICKET"
else
    tmux display-message -d 1000 "Session not found: $TICKET"
fi