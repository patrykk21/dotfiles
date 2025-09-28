#!/usr/bin/env bash

# Session switcher using fzf-tmux

# Get list of sessions
sessions=$(tmux list-sessions -F "#{session_name}: #{session_windows} windows#{?session_attached, (attached),}")

# Use fzf-tmux to select a session with kill functionality
selected=$(echo "$sessions" | fzf-tmux -p 60%,60% \
    --prompt=" Select session: " \
    --header="↵ switch | ctrl-x kill | ^C cancel" \
    --color="fg:250,bg:235,hl:114,fg+:235,bg+:114,hl+:235,prompt:114,pointer:114,header:243" \
    --border=rounded \
    --border-label=" Sessions " \
    --bind "ctrl-x:execute-silent(~/.config/tmux/scripts/kill-session.sh {})+reload(~/.config/tmux/scripts/reload-sessions.sh)")

# If a session was selected (Enter pressed), switch to it
if [ -n "$selected" ]; then
    session_name=$(echo "$selected" | cut -d: -f1)
    tmux switch-client -t "$session_name"
fi