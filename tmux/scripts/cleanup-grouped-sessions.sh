#!/usr/bin/env bash
# Auto-cleanup for unattached grouped child sessions.
# Called by tmux hooks (client-session-changed, client-detached).
# Kills sessions where session_group != session_name AND session_attached == 0.

tmux list-sessions -F '#{session_name} #{session_group} #{session_attached}' 2>/dev/null | \
while read -r name group attached; do
    if [ "$group" != "$name" ] && [ "$attached" = "0" ]; then
        tmux kill-session -t "$name" 2>/dev/null
    fi
done
