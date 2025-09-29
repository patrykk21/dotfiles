#!/usr/bin/env bash

# Debug version of worktree picker
echo "[DEBUG] Starting worktree picker debug" >> /tmp/worktree-picker-debug.log

# Test 1: Basic environment
echo "[DEBUG] Testing basic environment" >> /tmp/worktree-picker-debug.log
echo "TMUX: $TMUX" >> /tmp/worktree-picker-debug.log
echo "TMUX_PANE: $TMUX_PANE" >> /tmp/worktree-picker-debug.log
echo "PWD: $PWD" >> /tmp/worktree-picker-debug.log

# Test 2: Simple fzf-tmux
echo "[DEBUG] Testing simple fzf-tmux" >> /tmp/worktree-picker-debug.log
echo -e "option1\noption2\noption3" | fzf-tmux -p 50%,50%

echo "[DEBUG] Simple fzf-tmux completed" >> /tmp/worktree-picker-debug.log