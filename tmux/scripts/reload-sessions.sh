#!/usr/bin/env bash
# Reload tmux sessions for fzf
tmux list-sessions -F "#{session_name}: #{session_windows} windows#{?session_attached, (attached),}"