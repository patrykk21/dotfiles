#!/bin/bash
# Tab bar script for tmux - shows tabs at the top

# Get current window index
CURRENT_WINDOW=$(tmux display-message -p '#I')

# Get all windows
TABS=""
for window in $(tmux list-windows -F '#I:#W'); do
    INDEX=$(echo $window | cut -d: -f1)
    NAME=$(echo $window | cut -d: -f2)
    
    if [ "$INDEX" = "$CURRENT_WINDOW" ]; then
        # Current tab - highlighted
        TABS="${TABS}#[fg=#11111b,bg=#89b4fa,bold] Tab $INDEX: $NAME #[default] "
    else
        # Other tabs
        TABS="${TABS}#[fg=#7f849c,bg=#313244] Tab $INDEX: $NAME #[default] "
    fi
done

echo "$TABS"