#!/usr/bin/env bash
# Toggle Godot for the current pane's project (game by default, editor with `editor` arg).
# Usage: launch-godot.sh [editor]

source ~/.config/tmux/scripts/os-utils.sh

MODE="${1:-game}"  # game | editor
SESSION=$(tmux display-message -p '#S')
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Walk up from current dir to find project.godot
PROJECT_ROOT="$CURRENT_DIR"
while [ "$PROJECT_ROOT" != "/" ] && [ ! -f "$PROJECT_ROOT/project.godot" ]; do
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
if [ ! -f "$PROJECT_ROOT/project.godot" ]; then
    tmux display-message "No project.godot found above $CURRENT_DIR"
    exit 1
fi

GODOT_BIN="$(find_godot)"
if [ -z "$GODOT_BIN" ]; then
    tmux display-message "Godot binary not found on $(detect_os) (set \$GODOT or install)"
    exit 1
fi

WINDOW_NAME="godot-$MODE"
WINDOW_INDEX=$(tmux list-windows -t "$SESSION" -F '#{window_index} #{window_name}' \
    | awk -v n="$WINDOW_NAME" '$2 == n { print $1; exit }')

if [ -n "$WINDOW_INDEX" ]; then
    PANE_ID=$(tmux list-panes -t "$SESSION:$WINDOW_INDEX" -F '#{pane_id}' | head -1)
    PANE_PID=$(tmux list-panes -t "$SESSION:$WINDOW_INDEX" -F '#{pane_pid}' | head -1)
    GODOT_RUNNING=$(pgrep -P "$PANE_PID" -f "godot" 2>/dev/null | head -1)
    if [ -n "$GODOT_RUNNING" ]; then
        tmux send-keys -t "$PANE_ID" C-c
        tmux display-message "Stopped Godot ($MODE)"
        exit 0
    fi
    tmux select-window -t "$SESSION:$WINDOW_INDEX"
else
    tmux new-window -t "$SESSION:" -n "$WINDOW_NAME" -c "$PROJECT_ROOT"
    PANE_ID=$(tmux list-panes -t "$SESSION:$WINDOW_NAME" -F '#{pane_id}' | head -1)
fi

if [ "$MODE" = "editor" ]; then
    CMD="\"$GODOT_BIN\" --path \"$PROJECT_ROOT\" -e"
else
    CMD="\"$GODOT_BIN\" --path \"$PROJECT_ROOT\""
fi

tmux send-keys -t "$PANE_ID" "$CMD" Enter
tmux display-message "Launched Godot $MODE in $WINDOW_NAME"
