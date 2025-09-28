#!/bin/bash
# Dynamic status bar script for tmux - shows keybinds based on current mode

# Force immediate update by running in foreground
MODE=$(tmux display-message -p '#{client_key_table}')

# Very muted pastel color definitions using tmux 256 colors
# Blues: colour67 (muted blue), colour60 (dark blue)
# Greens: colour65 (muted green), colour22 (dark green)
# Yellows: colour144 (muted yellow), colour94 (brown-yellow)
# Pinks: colour132 (muted pink), colour125 (dark pink)
# Purples: colour96 (muted purple), colour54 (dark purple)
# Oranges: colour131 (muted orange), colour88 (dark orange)

case "$MODE" in
    "root")
        # Main menu with pastel colored pills and matching text
        echo "  #[bg=colour67,fg=colour255] C-S-p #[bg=default,fg=colour67] PANE  #[bg=colour65,fg=colour255] C-S-t #[bg=default,fg=colour65] TAB  #[bg=colour144,fg=colour235] C-S-r #[bg=default,fg=colour144] RESIZE  #[bg=colour96,fg=colour255] C-S-o #[bg=default,fg=colour96] SESSION  #[bg=colour131,fg=colour255] C-S-m #[bg=default,fg=colour131] SCROLL"
        ;;
    "pane-mode")
        # Pane submenu with organized keybinds
        echo "#[bg=colour67,fg=colour255,bold] ◆ PANE #[bg=colour236,fg=colour67]  #[fg=colour250]navigate #[fg=colour67]h/j/k/l  #[fg=colour250]new #[fg=colour67]n  #[fg=colour250]split #[fg=colour67]s/v  #[fg=colour250]close #[fg=colour67]x  #[fg=colour250]fullscreen #[fg=colour67]f  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "tab-mode")
        # Tab submenu with organized keybinds
        echo "#[bg=colour65,fg=colour255,bold] ◆ TAB #[bg=colour236,fg=colour65]  #[fg=colour250]navigate #[fg=colour65]h/l  #[fg=colour250]new #[fg=colour65]n  #[fg=colour250]rename #[fg=colour65]r  #[fg=colour250]close #[fg=colour65]x  #[fg=colour250]goto #[fg=colour65]1-9  #[fg=colour250]toggle #[fg=colour65]Tab  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "resize-mode")
        # Resize submenu with organized keybinds
        echo "#[bg=colour144,fg=colour235,bold] ◆ RESIZE #[bg=colour236,fg=colour144]  #[fg=colour250]resize #[fg=colour144]h/j/k/l  #[fg=colour250]fine #[fg=colour144]H/J/K/L  #[fg=colour250]adjust #[fg=colour144]+/-  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "session-mode")
        # Session submenu with organized keybinds
        echo "#[bg=colour96,fg=colour255,bold] ◆ SESSION #[bg=colour236,fg=colour96]  #[fg=colour250]detach #[fg=colour96]d  #[fg=colour250]choose #[fg=colour96]w  #[fg=colour250]create #[fg=colour96]c  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "scroll-mode")
        # Scroll submenu with organized keybinds
        echo "#[bg=colour131,fg=colour255,bold] ◆ SCROLL #[bg=colour236,fg=colour131]  #[fg=colour250]search #[fg=colour131]s  #[fg=colour250]edit #[fg=colour131]e  #[fg=colour250]exit #[fg=colour131]C-c  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "tmux-mode")
        # Tmux submenu with organized keybinds
        echo "#[bg=colour218,fg=colour232,bold] ◆ TMUX #[bg=colour236,fg=colour218]  #[fg=colour250]new window #[fg=colour218]c  #[fg=colour250]kill #[fg=colour218]x  #[fg=colour250]split-h #[fg=colour218]%  #[fg=colour250]split-v #[fg=colour218]\"  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    *)
        echo "#[bg=colour240,fg=colour250] MODE: $MODE"
        ;;
esac