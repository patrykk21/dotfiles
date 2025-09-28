# Tmux Worktree Mode Documentation

## Overview
Worktree mode provides seamless git worktree management integrated with tmux sessions. Each worktree gets its own tmux session with a predefined layout, making it easy to work on multiple tickets in parallel.

## Entering Worktree Mode
Press `Ctrl+Shift+W` to enter worktree mode.

## Keybindings
- `w` - Open worktree picker (list, switch, or delete worktrees)
- `c` - Create new worktree (prompts for ticket name)
- `x` - Delete current worktree and its session
- `Escape` - Exit worktree mode

## Features

### Worktree Picker (`w`)
Shows all git worktrees in an fzf popup with:
- Active session indicator (● active, ○ inactive)
- Ticket/session name
- Branch name
- Full worktree path

Within the picker:
- `Enter` - Switch to worktree's tmux session
- `Ctrl+X` - Delete selected worktree and session
- `Ctrl+R` - Refresh the list
- `Escape` - Cancel

### Create Worktree (`c`)
1. Prompts for ticket name (e.g., "ECH-123")
2. Creates git worktree at `../repo-ECH-123`
3. Creates branch `feature/ECH-123`
4. Copies configuration files:
   - All `.env*` files
   - `.claude/` directory
   - `CLAUDE.local.md` file
5. Creates tmux session with 3 tabs:
   - `claude` - Main development tab
   - `server` - For running dev server
   - `commands` - For git and other commands
6. Runs package install in background
7. Switches to the new session

### Delete Worktree (`x`)
1. Confirms deletion
2. Switches to main session
3. Kills the worktree's tmux session
4. Removes the git worktree
5. Cleans up completely

## Naming Conventions
- **Worktree directory**: `../repo-TICKET-123`
- **Git branch**: `feature/TICKET-123`
- **Tmux session**: `TICKET-123`

## Example Workflow

1. **Start new ticket**:
   - `Ctrl+Shift+W` to enter worktree mode
   - `c` to create new worktree
   - Type `ECH-123` when prompted
   - Automatically switched to new session with 3 tabs

2. **Switch between tickets**:
   - `Ctrl+Shift+W` to enter worktree mode
   - `w` to open picker
   - Select worktree and press Enter

3. **Clean up completed ticket**:
   - While in the worktree session
   - `Ctrl+Shift+W` to enter worktree mode
   - `x` to delete (confirm with 'y')
   - Automatically switched to main session

## Tips
- The picker shows active sessions with a filled circle (●)
- Inactive sessions show an empty circle (○)
- Creating a worktree automatically installs dependencies
- Each worktree is completely isolated with its own dependencies
- Deleting a worktree removes both the git worktree and tmux session

## Troubleshooting

### "Not in a git repository" error
Make sure you're in a git repository before using worktree mode.

### "Worktree already exists" error
A worktree with that ticket name already exists. Use the picker to switch to it.

### Session not switching
The session might have been killed externally. The picker will create a new session automatically when you select the worktree.

### Dependencies not installing
Check the commands tab in the new session for any error messages. The install runs in the background and may take time for large projects.