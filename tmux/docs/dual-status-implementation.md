# Implementing Dual Status Bars in Tmux (Top and Bottom)

## Quick Solution

Replace your current `pane-border-status bottom` approach with tmux's native multiple status bar feature:

```bash
# In your tmux.conf:

# Top bar - Window tabs
set -g status on
set -g status-position top
set -g status-justify centre

# Enable 2 status bars total
set -g status 2

# Bottom bar - Mode keybinds (this is status line index 1)
set -g status-format[1] '#[align=centre]#(~/.config/tmux/scripts/status-bar.sh)'

# CRITICAL: Disable pane-border-status to remove duplicates
set -g pane-border-status off
```

## How It Works

When you set `status-position top` and `status 2`:
- The primary status bar (window tabs) appears at the **top**
- `status-format[1]` creates a second bar at the **bottom**

This gives you exactly what you want:
```
┌─────────────────────────────────────────────┐
│  1 window1  2 window2* 3 window3           │ ← Top: Window tabs
├─────────────────┬───────────────────────────┤
│                 │                           │
│     Pane 1      │         Pane 2           │
│                 │                           │
│                 │                           │
├─────────────────┴───────────────────────────┤
│ C-S-p PANE  C-S-t TAB  C-S-r RESIZE ...    │ ← Bottom: Mode keybinds
└─────────────────────────────────────────────┘
```

## Migration Steps

1. **Backup your current config**:
   ```bash
   cp ~/.config/tmux/tmux.conf ~/.config/tmux/tmux.conf.backup
   ```

2. **Update the status bar configuration**:
   ```bash
   # Find these lines in your tmux.conf:
   set -g pane-border-status bottom
   set -g pane-border-format "#(~/.config/tmux/scripts/status-bar.sh)"
   
   # Replace with:
   set -g status 2
   set -g status-format[1] '#[align=centre]#(~/.config/tmux/scripts/status-bar.sh)'
   set -g pane-border-status off
   ```

3. **Reload tmux**:
   ```bash
   tmux source-file ~/.config/tmux/tmux.conf
   ```

## Complete Working Example

```bash
# =====================================
# COLORED PILL STATUS BAR (ZELLIJ RECREATION)
# =====================================

# Status bar colors (OneDark theme)
set -g status on
set -g status-bg "colour235"
set -g status-fg "colour250"

# Top bar for window tabs
set -g status-position top
set -g status-justify left
set -g status-left " "
set -g status-right "#[fg=colour243,bg=colour235] #S "
set -g status-left-length 30
set -g status-right-length 50

# Window/Tab list with OneDark colors
set -g window-status-format "#[fg=colour250,bg=colour236] #I #[fg=colour243]#W "
set -g window-status-current-format "#[fg=colour235,bg=colour114] #I #[fg=colour235,bold]#W "
set -g window-status-separator ""

# Enable second status bar at bottom
set -g status 2

# Bottom bar for mode keybinds
set -g status-format[1] '#[align=centre]#(~/.config/tmux/scripts/status-bar.sh)'

# Remove old pane border status (this was causing duplicates)
set -g pane-border-status off

# Clean pane borders
set -g pane-border-style "fg=colour235"
set -g pane-active-border-style "fg=colour235"
set -g pane-border-lines single
```

## Key Points

1. **`status 2`** tells tmux to display 2 status lines total
2. **`status-format[1]`** defines the content of the second status line
3. When `status-position` is `top`, additional status lines appear at the bottom
4. Your existing `status-bar.sh` script works without modification
5. No more duplicate bars when splitting panes!

## Testing

After applying the changes:
1. Split panes horizontally and vertically
2. Verify only ONE mode status bar appears at the bottom
3. Test all mode switches (C-S-p, C-S-t, etc.) to ensure the bottom bar updates correctly
4. Check that window tabs remain at the top

This is the clean, proper way to achieve the dual status bar layout you want.