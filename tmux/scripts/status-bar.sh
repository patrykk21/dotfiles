#!/bin/bash
# Dynamic status bar script for tmux - shows keybinds based on current mode

# Force immediate update by running in foreground
MODE=$(tmux display-message -p '#{client_key_table}')

# Pastel color definitions using tmux 256 colors
# Blues: colour117 (light blue), colour153 (soft blue)
# Greens: colour120 (light green), colour156 (soft green)  
# Yellows: colour228 (light yellow), colour229 (soft yellow)
# Pinks: colour218 (light pink), colour225 (soft pink)
# Purples: colour183 (light purple), colour189 (soft purple)
# Oranges: colour216 (light orange), colour223 (soft orange)

case "$MODE" in
    "root")
        # Main menu with pastel colored pills and matching text
        echo "#[bg=colour117,fg=colour232] C-S-p #[bg=default,fg=colour117] PANE  #[bg=colour120,fg=colour232] C-S-t #[bg=default,fg=colour120] TAB  #[bg=colour228,fg=colour232] C-S-r #[bg=default,fg=colour228] RESIZE  #[bg=colour183,fg=colour232] C-S-o #[bg=default,fg=colour183] SESSION  #[bg=colour216,fg=colour232] C-S-m #[bg=default,fg=colour216] SCROLL"
        ;;
    "pane-mode")
        # Pane submenu with organized keybinds
        echo "#[bg=colour117,fg=colour232,bold] ◆ PANE #[bg=colour236,fg=colour117]  #[fg=colour250]navigate #[fg=colour117]h/j/k/l  #[fg=colour250]new #[fg=colour117]n  #[fg=colour250]split #[fg=colour117]s/v  #[fg=colour250]close #[fg=colour117]x  #[fg=colour250]fullscreen #[fg=colour117]f  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "tab-mode")
        # Tab submenu with organized keybinds
        echo "#[bg=colour120,fg=colour232,bold] ◆ TAB #[bg=colour236,fg=colour120]  #[fg=colour250]navigate #[fg=colour120]h/l  #[fg=colour250]new #[fg=colour120]n  #[fg=colour250]rename #[fg=colour120]r  #[fg=colour250]close #[fg=colour120]x  #[fg=colour250]goto #[fg=colour120]1-9  #[fg=colour250]toggle #[fg=colour120]Tab  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "resize-mode")
        # Resize submenu with organized keybinds
        echo "#[bg=colour228,fg=colour232,bold] ◆ RESIZE #[bg=colour236,fg=colour228]  #[fg=colour250]resize #[fg=colour228]h/j/k/l  #[fg=colour250]fine #[fg=colour228]H/J/K/L  #[fg=colour250]adjust #[fg=colour228]+/-  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "session-mode")
        # Session submenu with organized keybinds
        echo "#[bg=colour183,fg=colour232,bold] ◆ SESSION #[bg=colour236,fg=colour183]  #[fg=colour250]detach #[fg=colour183]d  #[fg=colour250]choose #[fg=colour183]w  #[fg=colour250]create #[fg=colour183]c  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "scroll-mode")
        # Scroll submenu with organized keybinds
        echo "#[bg=colour216,fg=colour232,bold] ◆ SCROLL #[bg=colour236,fg=colour216]  #[fg=colour250]search #[fg=colour216]s  #[fg=colour250]edit #[fg=colour216]e  #[fg=colour250]exit #[fg=colour216]C-c  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "tmux-mode")
        # Tmux submenu with organized keybinds
        echo "#[bg=colour218,fg=colour232,bold] ◆ TMUX #[bg=colour236,fg=colour218]  #[fg=colour250]new window #[fg=colour218]c  #[fg=colour250]kill #[fg=colour218]x  #[fg=colour250]split-h #[fg=colour218]%  #[fg=colour250]split-v #[fg=colour218]\"  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    *)
        echo "#[bg=colour240,fg=colour250] MODE: $MODE"
        ;;
esac