#!/bin/bash
# Dynamic status bar script for tmux - shows keybinds based on current mode

# Force immediate update by running in foreground
MODE=$(tmux display-message -p '#{client_key_table}')

# OneDark color palette using tmux 256 colors
# Blue: colour75 (#61afef)
# Green: colour114 (#98c379) 
# Yellow: colour180 (#d19a66)
# Red: colour168 (#e06c75)
# Purple: colour176 (#c678dd)
# Cyan: colour73 (#56b6c2)
# Background: colour235 (#1e2127)
# Foreground: colour250 (#abb2bf)

case "$MODE" in
    "root")
        # Main menu with OneDark colored pills and matching text
        echo "  #[bg=colour75,fg=colour235] C-S-p #[bg=default,fg=colour75] PANE  #[bg=colour114,fg=colour235] C-S-t #[bg=default,fg=colour114] TAB  #[bg=colour180,fg=colour235] C-S-r #[bg=default,fg=colour180] RESIZE  #[bg=colour168,fg=colour235] C-S-o #[bg=default,fg=colour168] SESSION  #[bg=colour176,fg=colour235] C-S-m #[bg=default,fg=colour176] SCROLL  #[bg=colour73,fg=colour235] C-S-w #[bg=default,fg=colour73] WORKTREE"
        ;;
    "pane-mode")
        # Pane submenu with organized keybinds
        echo "#[bg=colour75,fg=colour235,bold] ◆ PANE #[bg=colour235,fg=colour75]  #[fg=colour250]navigate #[fg=colour75]h/j/k/l  #[fg=colour250]new #[fg=colour75]n  #[fg=colour250]split #[fg=colour75]s/v  #[fg=colour250]close #[fg=colour75]x  #[fg=colour250]fullscreen #[fg=colour75]f  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "tab-mode")
        # Tab submenu with organized keybinds
        echo "#[bg=colour114,fg=colour235,bold] ◆ TAB #[bg=colour235,fg=colour114]  #[fg=colour250]navigate #[fg=colour114]h/l  #[fg=colour250]new #[fg=colour114]n  #[fg=colour250]rename #[fg=colour114]r  #[fg=colour250]close #[fg=colour114]x  #[fg=colour250]goto #[fg=colour114]1-9  #[fg=colour250]toggle #[fg=colour114]Tab  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "resize-mode")
        # Resize submenu with organized keybinds
        echo "#[bg=colour180,fg=colour235,bold] ◆ RESIZE #[bg=colour235,fg=colour180]  #[fg=colour250]resize #[fg=colour180]h/j/k/l  #[fg=colour250]fine #[fg=colour180]H/J/K/L  #[fg=colour250]adjust #[fg=colour180]+/-  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "session-mode")
        # Enhanced session submenu with all new keybinds
        echo "#[bg=colour168,fg=colour235,bold] ◆ SESSION #[bg=colour235,fg=colour168]  #[fg=colour250]detach #[fg=colour168]d  #[fg=colour250]choose #[fg=colour168]w  #[fg=colour250]create #[fg=colour168]c  #[fg=colour250]new-auto #[fg=colour168]n  #[fg=colour250]kill #[fg=colour168]x  #[fg=colour250]list #[fg=colour168]l  #[fg=colour250]rename #[fg=colour168]r  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "scroll-mode")
        # Scroll submenu with organized keybinds
        echo "#[bg=colour176,fg=colour235,bold] ◆ SCROLL #[bg=colour235,fg=colour176]  #[fg=colour250]search #[fg=colour176]s  #[fg=colour250]edit #[fg=colour176]e  #[fg=colour250]exit #[fg=colour176]C-c  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "tmux-mode")
        # Tmux submenu with organized keybinds
        echo "#[bg=colour73,fg=colour235,bold] ◆ TMUX #[bg=colour235,fg=colour73]  #[fg=colour250]new window #[fg=colour73]c  #[fg=colour250]kill #[fg=colour73]x  #[fg=colour250]split-h #[fg=colour73]%  #[fg=colour250]split-v #[fg=colour73]\"  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "worktree-mode")
        # Worktree submenu with organized keybinds
        echo "#[bg=colour73,fg=colour235,bold] ◆ WORKTREE #[bg=colour235,fg=colour73]  #[fg=colour250]list/switch #[fg=colour73]w  #[fg=colour250]create #[fg=colour73]c  #[fg=colour250]delete #[fg=colour73]x  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    *)
        echo "#[bg=colour240,fg=colour250] MODE: $MODE"
        ;;
esac