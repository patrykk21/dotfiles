# Tmux-Zellij Configuration Fix Guide

This document provides comprehensive solutions for three critical issues with the current tmux configuration that's attempting to replicate zellij behavior.

## Issues Overview

1. **Pane mode spawns new tabs instead of new panes** (line 73)
2. **Session mode "choose session" acts like tab chooser** (line 143)
3. **Missing session management features** (create, delete, switch sessions)

## Understanding Zellij vs Tmux Sessions

### Zellij Session Model
- **Sessions** = Separate processes/workspaces
- **Tabs** = Windows within a session
- **Panes** = Splits within a tab
- Session switching means connecting to different processes

### Tmux Session Model
- **Sessions** = Separate tmux server instances with independent window sets
- **Windows** = Equivalent to zellij tabs
- **Panes** = Splits within a window
- Session switching connects to different server instances

## Problem Analysis & Solutions

### Issue 1: Pane Mode Creating Tabs Instead of Panes

**Current problematic code (line 73):**
```bash
bind-key -T pane-mode n new-window -c "#{pane_current_path}"
```

**Root Cause:** 
The `new-window` command creates a new tmux window (equivalent to a zellij tab), not a new pane.

**Solution:**
```bash
# Replace line 73 with:
bind-key -T pane-mode n split-window -h -c "#{pane_current_path}"

# Or for vertical split (more zellij-like):
bind-key -T pane-mode n split-window -v -c "#{pane_current_path}"

# Alternative: Add both options
bind-key -T pane-mode n split-window -v -c "#{pane_current_path}"  # New pane below
bind-key -T pane-mode N split-window -h -c "#{pane_current_path}"  # New pane right
```

**Complete updated pane-mode section:**
```bash
# =====================================
# PANE MODE (exact zellij pane bindings) - FIXED
# =====================================
bind-key -T pane-mode Left select-pane -L
bind-key -T pane-mode Down select-pane -D
bind-key -T pane-mode Up select-pane -U
bind-key -T pane-mode Right select-pane -R
bind-key -T pane-mode h select-pane -L
bind-key -T pane-mode j select-pane -D
bind-key -T pane-mode k select-pane -U
bind-key -T pane-mode l select-pane -R
bind-key -T pane-mode n split-window -v -c "#{pane_current_path}"  # FIXED: Creates new pane, not tab
bind-key -T pane-mode p select-pane -l
bind-key -T pane-mode s split-window -h -c "#{pane_current_path}"
bind-key -T pane-mode v split-window -v -c "#{pane_current_path}"
bind-key -T pane-mode x kill-pane
bind-key -T pane-mode f resize-pane -Z
bind-key -T pane-mode w run-shell "echo 'Floating panes not available in tmux'"
bind-key -T pane-mode e run-shell "echo 'Embed/Float not available in tmux'"
bind-key -T pane-mode z run-shell 'tmux set pane-border-status #{?#{==:#{pane-border-status},off},top,off}'
bind-key -T pane-mode c command-prompt "select-pane -T '%%'"
bind-key -T pane-mode Escape switch-client -T root \; refresh-client -S
```

### Issue 2: Session Mode Choose Command Problems

**Current problematic code (line 143):**
```bash
bind-key -T session-mode w choose-session
```

**Root Cause:** 
While `choose-session` is correct, the tmux session model doesn't match zellij's session concept directly.

**Analysis:**
- `choose-session` in tmux IS correct for choosing between different tmux sessions
- However, the user likely doesn't have multiple tmux sessions running
- In zellij, this would show different workspace processes

**Solutions:**

#### Option A: Enhanced Session Chooser (Recommended)
```bash
# Replace line 143 with enhanced session management:
bind-key -T session-mode w run-shell '
    if [ $(tmux list-sessions | wc -l) -gt 1 ]; then
        tmux choose-session
    else
        tmux display-message "Only one session active. Use '\''c'\'' to create new session."
    fi
'
```

#### Option B: List Sessions with Information
```bash
# Alternative: Show session list with more information
bind-key -T session-mode w run-shell 'tmux list-sessions | tmux display-message -d 3000'
```

#### Option C: Interactive Session Manager
```bash
# Most zellij-like: Custom session picker
bind-key -T session-mode w run-shell '~/.config/tmux/scripts/session-picker.sh'
```

### Issue 3: Missing Session Management Features

**Current session-mode section (lines 139-147) is incomplete:**
```bash
# Current incomplete section:
bind-key -T session-mode C-o switch-client -T root
bind-key -T session-mode C-s switch-client -T scroll-mode
bind-key -T session-mode d detach-client
bind-key -T session-mode w choose-session
bind-key -T session-mode c command-prompt "new-session -s '%%'"
bind-key -T session-mode p run-shell "echo 'Plugin manager not available in tmux'"
bind-key -T session-mode a display-message "tmux #{version}"
bind-key -T session-mode Escape switch-client -T root \; refresh-client -S
```

**Complete Enhanced Session Mode:**
```bash
# =====================================
# SESSION MODE (enhanced zellij-like session bindings) - FIXED
# =====================================
bind-key -T session-mode C-o switch-client -T root
bind-key -T session-mode C-s switch-client -T scroll-mode
bind-key -T session-mode d detach-client

# Enhanced session chooser with fallback
bind-key -T session-mode w run-shell '
    if [ $(tmux list-sessions | wc -l) -gt 1 ]; then
        tmux choose-session
    else
        tmux display-message "Only one session: $(tmux display-message -p \"#S\"). Use c to create new session."
    fi
'

# Create new session (prompts for name)
bind-key -T session-mode c command-prompt -p "New session name:" "new-session -d -s '%%' ; switch-client -t '%%'"

# Create new session with auto-generated name
bind-key -T session-mode C command-prompt -p "New session name:" "new-session -d -s '%%'"
bind-key -T session-mode n new-session -d -s "session-$(date +%s)" \; switch-client -t "session-$(date +%s)"

# Delete/kill session (with confirmation)
bind-key -T session-mode x confirm-before -p "Kill session #S? (y/n)" kill-session
bind-key -T session-mode X kill-session  # Force kill without confirmation

# List all sessions
bind-key -T session-mode l run-shell 'tmux list-sessions | tmux display-message -d 5000'

# Rename current session
bind-key -T session-mode r command-prompt -p "Rename session:" "rename-session '%%'"

# Switch to previous session
bind-key -T session-mode p switch-client -l

# Session navigation shortcuts
bind-key -T session-mode 1 run-shell 'tmux switch-client -t $(tmux list-sessions -F "#{session_name}" | sed -n "1p") 2>/dev/null || tmux display-message "Session 1 not found"'
bind-key -T session-mode 2 run-shell 'tmux switch-client -t $(tmux list-sessions -F "#{session_name}" | sed -n "2p") 2>/dev/null || tmux display-message "Session 2 not found"'
bind-key -T session-mode 3 run-shell 'tmux switch-client -t $(tmux list-sessions -F "#{session_name}" | sed -n "3p") 2>/dev/null || tmux display-message "Session 3 not found"'

# Show session info
bind-key -T session-mode a display-message "Session: #S | Windows: #{session_windows} | Created: #{session_created}"

bind-key -T session-mode Escape switch-client -T root \; refresh-client -S
```

## Additional Required Scripts

### Session Picker Script
Create `~/.config/tmux/scripts/session-picker.sh`:

```bash
#!/bin/bash
# Advanced session picker for tmux

SESSIONS=$(tmux list-sessions -F "#{session_name}: #{session_windows} windows, created #{session_created}")

if [ $(echo "$SESSIONS" | wc -l) -eq 1 ]; then
    tmux display-message "Only one session active: $(echo "$SESSIONS" | cut -d: -f1)"
else
    # Use tmux's built-in chooser with enhanced format
    tmux choose-session -F "#{session_name}: #{session_windows} windows, #{?session_attached,attached,not attached}"
fi
```

Make it executable:
```bash
chmod +x ~/.config/tmux/scripts/session-picker.sh
```

### Updated Status Bar Script
Update the session-mode section in `~/.config/tmux/scripts/status-bar.sh` (line 34-37):

```bash
    "session-mode")
        # Enhanced session submenu with all new keybinds
        echo "#[bg=colour168,fg=colour235,bold] ◆ SESSION #[bg=colour235,fg=colour168]  #[fg=colour250]detach #[fg=colour168]d  #[fg=colour250]choose #[fg=colour168]w  #[fg=colour250]create #[fg=colour168]c  #[fg=colour250]new-auto #[fg=colour168]n  #[fg=colour250]kill #[fg=colour168]x  #[fg=colour250]list #[fg=colour168]l  #[fg=colour250]rename #[fg=colour168]r  #[bg=colour235,fg=colour243] ESC to exit"
        ;;
```

## Fundamental Limitations & Differences

### What CAN be achieved:
1. ✅ Multiple tmux sessions (separate workspaces)
2. ✅ Session switching and management 
3. ✅ Session creation/deletion
4. ✅ Per-session window/pane state

### What CANNOT be perfectly replicated:
1. ❌ **True process isolation**: Tmux sessions share the same server process
2. ❌ **Independent configuration**: All sessions use the same tmux.conf
3. ❌ **Separate plugin states**: Plugins are server-wide, not per-session
4. ❌ **Layout persistence**: Zellij's layout system is more advanced

### Working Around Limitations:

#### Multiple Session Workflow:
```bash
# Create multiple sessions for different projects
tmux new-session -d -s "work-project"
tmux new-session -d -s "personal-dev" 
tmux new-session -d -s "system-admin"

# Attach to specific session
tmux attach-session -t "work-project"

# List all sessions
tmux list-sessions
```

#### Session Templates:
Create different starting configurations by using different attach scripts:

```bash
# ~/.config/tmux/sessions/work-setup.sh
tmux new-session -d -s "work"
tmux new-window -t "work" -n "editor" 
tmux new-window -t "work" -n "terminal"
tmux new-window -t "work" -n "logs"
tmux select-window -t "work:editor"
tmux attach-session -t "work"
```

## Implementation Steps

1. **Backup current configuration:**
   ```bash
   cp ~/.config/tmux/tmux.conf ~/.config/tmux/tmux.conf.backup
   ```

2. **Apply the fixes:**
   - Update line 73 to use `split-window` instead of `new-window`
   - Replace session-mode section with enhanced version
   - Update status bar script

3. **Create additional scripts:**
   ```bash
   mkdir -p ~/.config/tmux/scripts
   # Create session-picker.sh as shown above
   ```

4. **Test the fixes:**
   ```bash
   tmux source-file ~/.config/tmux/tmux.conf
   ```

5. **Create multiple test sessions:**
   ```bash
   tmux new-session -d -s "test1"
   tmux new-session -d -s "test2" 
   tmux list-sessions
   ```

## Usage Guide After Fixes

### Pane Mode (Ctrl+Shift+P):
- `n` = Create new pane (vertical split) ✅ FIXED
- `s` = Horizontal split
- `v` = Vertical split  
- `h/j/k/l` = Navigate panes
- `x` = Close pane

### Session Mode (Ctrl+Shift+O):
- `w` = Choose session (enhanced with fallback) ✅ FIXED
- `c` = Create new session (with name prompt) ✅ NEW
- `n` = Create new session (auto-named) ✅ NEW
- `x` = Kill current session ✅ NEW
- `l` = List all sessions ✅ NEW
- `r` = Rename current session ✅ NEW
- `p` = Switch to previous session ✅ NEW
- `1/2/3` = Switch to session by number ✅ NEW
- `d` = Detach from session

This comprehensive guide addresses all three issues while providing additional session management features that bring tmux closer to zellij's session model, within the constraints of tmux's architecture.