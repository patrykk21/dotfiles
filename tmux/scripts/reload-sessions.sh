#!/usr/bin/env bash
# Reload tmux sessions for fzf (filter out grouped child sessions)
tmux list-sessions -F "#{session_name}: #{session_windows} windows#{?session_attached, (attached),}" | grep -v '^[^:]*_g[0-9]\+:'