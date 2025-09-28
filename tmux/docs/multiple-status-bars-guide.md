# Complete Guide: Implementing Multiple Tmux Status Bars

## Table of Contents
1. [Problems with Current Approach](#problems-with-current-approach)
2. [Understanding Tmux Multiple Status Bars](#understanding-tmux-multiple-status-bars)
3. [Migration Strategy](#migration-strategy)
4. [Implementation Guide](#implementation-guide)
5. [Dynamic Content with Bash Scripts](#dynamic-content-with-bash-scripts)
6. [Working Examples](#working-examples)
7. [Performance Considerations](#performance-considerations)
8. [Troubleshooting](#troubleshooting)

## Problems with Current Approach

### Current Implementation Analysis
The current tmux configuration uses:
- `status-position top` for window tabs
- `pane-border-status bottom` for mode-specific keybinds
- A bash script (`~/.config/tmux/scripts/status-bar.sh`) for dynamic content

### Core Issues

#### 1. Duplicate Status Bars in Split Panes
```bash
# Current problematic behavior:
# When you split panes, each pane gets its own border with the status
┌─────────────────────────────────────┐
│ Window Tabs (status bar)           │
├─────────────────┬───────────────────┤
│ Pane 1          │ Pane 2            │
│                 │                   │
├─ Mode: PANE ────┼─ Mode: PANE ──────┤  ← Duplicate status bars!
│ Pane 3          │ Pane 4            │
│                 │                   │
└─ Mode: PANE ────┴─ Mode: PANE ──────┘  ← More duplicates!
```

#### 2. Inconsistent Visual Experience
- Status information appears multiple times
- Visual clutter increases with more panes
- Wastes screen real estate
- Breaks the clean Zellij-like aesthetic

#### 3. Performance Overhead
- Script runs for each pane border
- Multiple identical status updates
- Unnecessary resource usage

## Understanding Tmux Multiple Status Bars

### Native Multiple Status Bar Feature
Tmux supports multiple status lines through:
- `status` (primary status line)
- `status-format[0-4]` (additional status lines)
- Independent positioning and styling

### Key Configuration Options

```bash
# Primary status bar
set -g status on
set -g status-position top    # or bottom
set -g status-justify left    # left, centre, right

# Additional status lines (0-4 additional lines)
set -g status-format[0] "#[align=left]#{status-left}#[align=centre]#{window-status-format}#[align=right]#{status-right}"
set -g status-format[1] "Second status line content"
set -g status-format[2] "Third status line content"
```

### Positioning Logic
- `status-position top`: Main status at top, additional lines below it
- `status-position bottom`: Main status at bottom, additional lines above it
- Each format line is independent and doesn't duplicate per pane

## Migration Strategy

### Phase 1: Preserve Current Functionality
1. Keep existing window tabs at top
2. Replace pane-border-status with status-format[1]
3. Maintain all current keybind displays
4. Test thoroughly before removing old implementation

### Phase 2: Optimize and Enhance
1. Remove pane-border-status completely
2. Add additional status lines if needed
3. Optimize bash script performance
4. Fine-tune colors and spacing

### Phase 3: Advanced Features
1. Add contextual information (git branch, time, etc.)
2. Implement conditional status lines
3. Add integration with external tools

## Implementation Guide

### Step 1: Basic Multiple Status Bar Setup

```bash
# ~/.config/tmux/tmux.conf

# === MULTIPLE STATUS BARS CONFIGURATION ===

# Primary status bar (window tabs) - keep at top
set -g status on
set -g status-bg "colour235"
set -g status-fg "colour250"
set -g status-position top
set -g status-justify left
set -g status-left " "
set -g status-right "#[fg=colour243,bg=colour235] #S "
set -g status-left-length 30
set -g status-right-length 50

# Window/Tab styling (unchanged)
set -g window-status-format "#[fg=colour250,bg=colour236] #I #[fg=colour243]#W "
set -g window-status-current-format "#[fg=colour235,bg=colour114] #I #[fg=colour235,bold]#W "
set -g window-status-separator ""

# Second status line for mode-specific keybinds
set -g status-format[1] "#[align=centre]#(~/.config/tmux/scripts/status-bar.sh)"

# Remove pane border status (this was causing duplicates)
set -g pane-border-status off

# Clean pane borders
set -g pane-border-style "fg=colour235"
set -g pane-active-border-style "fg=colour235"
set -g pane-border-lines single
```

### Step 2: Enhanced Status Script

Create an optimized version of the status script:

```bash
#!/bin/bash
# ~/.config/tmux/scripts/enhanced-status-bar.sh
# Optimized status bar script with caching and improved performance

# Cache file for reducing tmux calls
CACHE_FILE="/tmp/tmux-status-cache-$$"
CACHE_TTL=1  # Cache for 1 second

# Function to get current mode efficiently
get_current_mode() {
    local current_time=$(date +%s)
    
    # Check if cache exists and is still valid
    if [[ -f "$CACHE_FILE" ]]; then
        local cache_time=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
        if (( current_time - cache_time < CACHE_TTL )); then
            cat "$CACHE_FILE"
            return
        fi
    fi
    
    # Get fresh mode and cache it
    local mode=$(tmux display-message -p '#{client_key_table}')
    echo "$mode" > "$CACHE_FILE"
    echo "$mode"
}

# Get current mode
MODE=$(get_current_mode)

# OneDark color palette (same as before)
# Blue: colour75, Green: colour114, Yellow: colour180
# Red: colour168, Purple: colour176, Cyan: colour73
# Background: colour235, Foreground: colour250

case "$MODE" in
    "root")
        echo "  #[bg=colour75,fg=colour235] C-S-p #[bg=default,fg=colour75] PANE  #[bg=colour114,fg=colour235] C-S-t #[bg=default,fg=colour114] TAB  #[bg=colour180,fg=colour235] C-S-r #[bg=default,fg=colour180] RESIZE  #[bg=colour168,fg=colour235] C-S-o #[bg=default,fg=colour168] SESSION  #[bg=colour176,fg=colour235] C-S-m #[bg=default,fg=colour176] SCROLL"
        ;;
    "pane-mode")
        echo "#[bg=colour75,fg=colour235,bold] ◆ PANE #[bg=colour235,fg=colour75]  #[fg=colour250]navigate #[fg=colour75]h/j/k/l  #[fg=colour250]new #[fg=colour75]n  #[fg=colour250]split #[fg=colour75]s/v  #[fg=colour250]close #[fg=colour75]x  #[fg=colour250]fullscreen #[fg=colour75]f  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "tab-mode")
        echo "#[bg=colour114,fg=colour235,bold] ◆ TAB #[bg=colour235,fg=colour114]  #[fg=colour250]navigate #[fg=colour114]h/l  #[fg=colour250]new #[fg=colour114]n  #[fg=colour250]rename #[fg=colour114]r  #[fg=colour250]close #[fg=colour114]x  #[fg=colour250]goto #[fg=colour114]1-9  #[fg=colour250]toggle #[fg=colour114]Tab  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "resize-mode")
        echo "#[bg=colour180,fg=colour235,bold] ◆ RESIZE #[bg=colour235,fg=colour180]  #[fg=colour250]resize #[fg=colour180]h/j/k/l  #[fg=colour250]fine #[fg=colour180]H/J/K/L  #[fg=colour250]adjust #[fg=colour180]+/-  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "session-mode")
        echo "#[bg=colour168,fg=colour235,bold] ◆ SESSION #[bg=colour235,fg=colour168]  #[fg=colour250]detach #[fg=colour168]d  #[fg=colour250]choose #[fg=colour168]w  #[fg=colour250]create #[fg=colour168]c  #[fg=colour250]new-auto #[fg=colour168]n  #[fg=colour250]kill #[fg=colour168]x  #[fg=colour250]list #[fg=colour168]l  #[fg=colour250]rename #[fg=colour168]r  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "scroll-mode")
        echo "#[bg=colour176,fg=colour235,bold] ◆ SCROLL #[bg=colour235,fg=colour176]  #[fg=colour250]search #[fg=colour176]s  #[fg=colour250]edit #[fg=colour176]e  #[fg=colour250]exit #[fg=colour176]C-c  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "tmux-mode")
        echo "#[bg=colour73,fg=colour235,bold] ◆ TMUX #[bg=colour235,fg=colour73]  #[fg=colour250]new window #[fg=colour73]c  #[fg=colour250]kill #[fg=colour73]x  #[fg=colour250]split-h #[fg=colour73]%  #[fg=colour250]split-v #[fg=colour73]\"  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
    "locked-mode")
        echo "#[bg=colour240,fg=colour250,bold] ◆ LOCKED #[bg=colour235,fg=colour240]  #[fg=colour250]Press #[fg=colour240]C-S-g #[fg=colour250]to unlock"
        ;;
    *)
        echo "#[bg=colour240,fg=colour250] MODE: $MODE #[bg=colour235,fg=colour243] Unknown mode - press ESC to return to normal"
        ;;
esac

# Cleanup old cache files (older than 1 hour)
find /tmp -name "tmux-status-cache-*" -mtime +1h -delete 2>/dev/null || true
```

### Step 3: Advanced Multi-Line Implementation

For even more information, you can add additional status lines:

```bash
# Three status lines example
set -g status-format[0] "#[align=left] #{session_name} #[align=centre]#{window_status_current_format}#{window_status_format} #[align=right]%Y-%m-%d %H:%M "
set -g status-format[1] "#[align=centre]#(~/.config/tmux/scripts/enhanced-status-bar.sh)"
set -g status-format[2] "#[align=centre,fg=colour243]#(~/.config/tmux/scripts/system-info.sh)"
```

## Dynamic Content with Bash Scripts

### System Information Script
```bash
#!/bin/bash
# ~/.config/tmux/scripts/system-info.sh
# Additional system information for third status line

# Only show if in specific modes or conditions
MODE=$(tmux display-message -p '#{client_key_table}')

case "$MODE" in
    "root"|"session-mode")
        # Show useful system info
        LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        MEM=$(ps -A -o %mem | awk '{s+=$1} END {printf "%.1f%%", s}')
        
        echo "#[fg=colour243]Load: #[fg=colour250]$LOAD #[fg=colour243]Mem: #[fg=colour250]$MEM #[fg=colour243]Panes: #[fg=colour250]#{session_panes}"
        ;;
    *)
        # Don't show extra info in other modes to reduce clutter
        echo ""
        ;;
esac
```

### Git Information Script
```bash
#!/bin/bash
# ~/.config/tmux/scripts/git-info.sh
# Show git branch and status if in a git repository

# Only run in root mode and if current pane is in a git repo
MODE=$(tmux display-message -p '#{client_key_table}')
PANE_PID=$(tmux display-message -p '#{pane_pid}')

if [[ "$MODE" == "root" ]]; then
    # Get the working directory of the current pane
    PANE_DIR=$(lsof -p $PANE_PID | grep cwd | awk '{print $NF}' | head -1)
    
    if [[ -n "$PANE_DIR" ]] && cd "$PANE_DIR" 2>/dev/null; then
        if git rev-parse --git-dir >/dev/null 2>&1; then
            BRANCH=$(git branch --show-current 2>/dev/null)
            STATUS=$(git status --porcelain 2>/dev/null | wc -l | xargs)
            
            if [[ -n "$BRANCH" ]]; then
                if [[ "$STATUS" -gt 0 ]]; then
                    echo "#[fg=colour168] $BRANCH #[fg=colour180]($STATUS)"
                else
                    echo "#[fg=colour114] $BRANCH"
                fi
            fi
        fi
    fi
fi
```

## Working Examples

### Example 1: Basic Two-Line Setup
```bash
# Top line: Window tabs
# Bottom line: Mode keybinds

set -g status on
set -g status-position top
set -g status-justify left
set -g status-left " "
set -g status-right "#[fg=colour243] #S "

# Main status format (windows)
set -g window-status-format "#[fg=colour250,bg=colour236] #I #W "
set -g window-status-current-format "#[fg=colour235,bg=colour114] #I #W "

# Second line for keybinds
set -g status-format[1] "#[align=centre]#(~/.config/tmux/scripts/enhanced-status-bar.sh)"

# Clean borders
set -g pane-border-status off
set -g pane-border-style "fg=colour235"
```

### Example 2: Three-Line Advanced Setup
```bash
# Top line: Session info and time
# Middle line: Window tabs  
# Bottom line: Mode keybinds

set -g status on
set -g status-position top

# First line: Session and system info
set -g status-format[0] "#[align=left,fg=colour250] #{session_name} #[align=centre,fg=colour243]tmux #[align=right,fg=colour250]%H:%M "

# Second line: Window tabs (main status)
set -g status-left ""
set -g status-right ""
set -g window-status-format "#[fg=colour250,bg=colour236] #I #W "
set -g window-status-current-format "#[fg=colour235,bg=colour114] #I #W "

# Third line: Mode keybinds
set -g status-format[1] "#[align=centre]#(~/.config/tmux/scripts/enhanced-status-bar.sh)"
```

### Example 3: Bottom Position Setup
```bash
# For bottom positioning (lines appear bottom-up)
set -g status-position bottom

# Bottom line: Mode keybinds
set -g status-left ""
set -g status-right ""
set -g window-status-format "#[fg=colour250,bg=colour236] #I #W "
set -g window-status-current-format "#[fg=colour235,bg=colour114] #I #W "

# Line above: Additional info
set -g status-format[0] "#[align=centre]#(~/.config/tmux/scripts/enhanced-status-bar.sh)"

# Top line: Session info
set -g status-format[1] "#[align=left] #{session_name} #[align=right]%H:%M "
```

## Performance Considerations

### Script Optimization
1. **Caching**: Implement caching to reduce tmux display-message calls
2. **Conditional Execution**: Only run expensive operations when needed
3. **Background Processing**: Use background jobs for slow operations

### Tmux Configuration
```bash
# Optimize status updates
set -g status-interval 1          # Update every second (default: 15)
set -g status-left-length 50      # Reasonable length limits
set -g status-right-length 50

# Reduce unnecessary refreshes
set -g focus-events on             # Enable focus events
set -g escape-time 0               # No escape delay
```

### Memory Management
```bash
# In your status scripts, clean up temp files
trap 'rm -f /tmp/tmux-status-cache-$$' EXIT

# Use efficient commands
# Good: tmux display-message -p '#{client_key_table}'
# Bad: tmux list-clients | grep $(tmux display-message -p '#{client_tty}') | ...
```

## Troubleshooting

### Common Issues

#### 1. Status Lines Not Appearing
```bash
# Check if status is enabled
tmux show-options -g status

# Verify status-format settings
tmux show-options -g status-format

# Test script directly
~/.config/tmux/scripts/enhanced-status-bar.sh
```

#### 2. Performance Problems
```bash
# Check script execution time
time ~/.config/tmux/scripts/enhanced-status-bar.sh

# Monitor tmux process
top -p $(pgrep tmux)

# Reduce status-interval if needed
set -g status-interval 5  # Update every 5 seconds instead of 1
```

#### 3. Color Issues
```bash
# Test color support
tmux display-message -p '#{client_termname}'

# List available colors
for i in {0..255}; do printf "\e[38;5;${i}mcolour${i}\e[0m\n"; done
```

#### 4. Script Not Updating
```bash
# Force refresh
tmux refresh-client -S

# Check script permissions
chmod +x ~/.config/tmux/scripts/enhanced-status-bar.sh

# Debug mode execution
bash -x ~/.config/tmux/scripts/enhanced-status-bar.sh
```

### Migration Checklist

- [ ] Backup current tmux configuration
- [ ] Test new status-format configuration
- [ ] Verify all modes display correctly
- [ ] Check performance with multiple panes
- [ ] Remove pane-border-status settings
- [ ] Update status script paths
- [ ] Test with different terminal emulators
- [ ] Verify colors match OneDark theme
- [ ] Test keybind functionality
- [ ] Document any custom modifications

### Complete Migration Script

```bash
#!/bin/bash
# ~/.config/tmux/scripts/migrate-to-multiple-status.sh
# Script to migrate from pane-border-status to multiple status bars

echo "Migrating tmux configuration to multiple status bars..."

# Backup current config
cp ~/.config/tmux/tmux.conf ~/.config/tmux/tmux.conf.backup.$(date +%s)

# Create enhanced status script
cat > ~/.config/tmux/scripts/enhanced-status-bar.sh << 'EOF'
[Insert the enhanced script from above here]
EOF

chmod +x ~/.config/tmux/scripts/enhanced-status-bar.sh

# Update tmux configuration
cat >> ~/.config/tmux/tmux.conf << 'EOF'

# === MULTIPLE STATUS BARS MIGRATION ===
# Replace pane-border-status with status-format[1]

# Second status line for mode-specific keybinds
set -g status-format[1] "#[align=centre]#(~/.config/tmux/scripts/enhanced-status-bar.sh)"

# Disable pane border status (removes duplicates)
set -g pane-border-status off

EOF

echo "Migration complete! Please reload tmux config:"
echo "tmux source-file ~/.config/tmux/tmux.conf"
echo ""
echo "To test, split some panes and verify no duplicate status bars appear."
```

This comprehensive guide provides everything needed to migrate from the problematic pane-border-status approach to tmux's native multiple status bar functionality, eliminating duplicate status bars while maintaining all current functionality and visual styling.