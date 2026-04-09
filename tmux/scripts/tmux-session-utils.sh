#!/usr/bin/env bash
# Shared utilities for tmux session group management
# Provides functions to support independent views (grouped sessions)
# for multiple clients on the same worktree.

# Resolve a session name to its master (group) name.
# If the session belongs to a group, returns the session_group value.
# Otherwise returns the session name as-is.
resolve_master_session() {
    local name="$1"
    if [ -z "$name" ]; then
        echo ""
        return
    fi
    local group
    group=$(tmux display-message -t "$name" -p '#{session_group}' 2>/dev/null)
    if [ -n "$group" ] && [ "$group" != "$name" ]; then
        echo "$group"
    else
        echo "$name"
    fi
}

# Generate the next available grouped child session name for a master.
# e.g., if ECH-123 and ECH-123_g2 exist, returns ECH-123_g3.
next_grouped_session_name() {
    local master="$1"
    local n=2
    while tmux has-session -t "${master}_g${n}" 2>/dev/null; do
        ((n++))
    done
    echo "${master}_g${n}"
}

# Check if a session name is a grouped child (matches _g[0-9]+$ suffix).
is_grouped_child() {
    local name="$1"
    [[ "$name" =~ _g[0-9]+$ ]]
}

# Kill an entire session group: the master and all its grouped children.
kill_session_group() {
    local master="$1"
    if [ -z "$master" ]; then
        return
    fi
    # List all sessions in this group and kill them
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name} #{session_group}' 2>/dev/null | \
        awk -v grp="$master" '$2 == grp { print $1 }')
    if [ -n "$sessions" ]; then
        while IFS= read -r sess; do
            tmux kill-session -t "$sess" 2>/dev/null
        done <<< "$sessions"
    else
        # Fallback: just try to kill the master directly
        tmux kill-session -t "$master" 2>/dev/null
    fi
}
