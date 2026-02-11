#!/usr/bin/env bash
# Smart pane selection that skips the top and bottom status panes

DIRECTION=$1

# Get the target pane ID in the requested direction BEFORE moving
TARGET_PANE=$(tmux display-message -p "#{pane_id}")

# Try to move in the direction to see what the target would be
case "$DIRECTION" in
    L) TARGET_PANE=$(tmux display-message -p -t "{left-of}" "#{pane_id}" 2>/dev/null) ;;
    R) TARGET_PANE=$(tmux display-message -p -t "{right-of}" "#{pane_id}" 2>/dev/null) ;;
    U) TARGET_PANE=$(tmux display-message -p -t "{up-of}" "#{pane_id}" 2>/dev/null) ;;
    D) TARGET_PANE=$(tmux display-message -p -t "{down-of}" "#{pane_id}" 2>/dev/null) ;;
esac

# If no target pane in that direction, do nothing
if [[ -z "$TARGET_PANE" ]]; then
    exit 0
fi

# Check if target pane is a status bar
TARGET_TITLE=$(tmux display-message -p -t "$TARGET_PANE" "#{pane_title}")
TARGET_CMD=$(tmux display-message -p -t "$TARGET_PANE" "#{pane_current_command}")
TARGET_HEIGHT=$(tmux display-message -p -t "$TARGET_PANE" "#{pane_height}")

# Don't move if target is a status bar (check title, command, or if it's only 1 line tall)
if [[ "$TARGET_TITLE" == "__tmux_status_bar__" ]] || \
   [[ "$TARGET_CMD" == *"bottom-prompt"* ]] || \
   [[ "$TARGET_CMD" == *"status-bar"* ]] || \
   [[ "$TARGET_HEIGHT" == "1" ]]; then
    # Don't move - just stay in current pane
    exit 0
fi

# Safe to move - select the target pane
tmux select-pane -$DIRECTION