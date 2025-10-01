# Tmux Configuration - Complete Setup Guide

A modern tmux configuration featuring Zellij-style keybindings, borderless panes, dual status bars, and advanced session management.

## 🚀 Quick Start

```bash
# Install tmux
brew install tmux

# Clone just the tmux configuration
git clone --no-checkout https://github.com/patrykk21/dotfiles.git temp-dotfiles
cd temp-dotfiles
git sparse-checkout init --cone
git sparse-checkout set tmux
git checkout
mkdir -p ~/.config
mv tmux ~/.config/
cd .. && rm -rf temp-dotfiles

# Install TPM (Tmux Plugin Manager)
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Start tmux and install plugins
tmux
# Press Ctrl-Space + I to install plugins
```

## 📦 Installation from Scratch

### Step 1: Install Dependencies

#### macOS (Homebrew)
```bash
brew install tmux
brew install fzf              # For session/worktree pickers
brew install jq               # For JSON processing in scripts
```

#### Ubuntu/Debian
```bash
sudo apt update
sudo apt install tmux fzf jq
```

#### CentOS/RHEL
```bash
sudo yum install tmux fzf jq
# or for newer versions:
sudo dnf install tmux fzf jq
```

### Step 2: Install Tmux Plugin Manager (TPM)
```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

### Step 3: Copy Configuration Files
```bash
# Clone just the tmux configuration using sparse-checkout
git clone --no-checkout https://github.com/patrykk21/dotfiles.git temp-dotfiles
cd temp-dotfiles
git sparse-checkout init --cone
git sparse-checkout set tmux
git checkout
mkdir -p ~/.config
mv tmux ~/.config/
cd .. && rm -rf temp-dotfiles

# Alternative: Download specific files manually
# mkdir -p ~/.config/tmux/scripts
# curl -o ~/.config/tmux/tmux.conf https://raw.githubusercontent.com/patrykk21/dotfiles/master/tmux/tmux.conf
# curl -o ~/.config/tmux/scripts/init-shell-env.sh https://raw.githubusercontent.com/patrykk21/dotfiles/master/tmux/scripts/init-shell-env.sh
# ... (continue for other needed files)
```

### Step 4: Make Scripts Executable
```bash
chmod +x ~/.config/tmux/scripts/*.sh
chmod +x ~/.config/tmux/plugins/tmux-bottom-bar/scripts/*.sh
```

### Step 5: Set Up Environment (Optional)
```bash
# Set up worktree base directory for git worktree integration
mkdir -p ~/worktrees

# Add to your shell rc file (~/.zshrc, ~/.bashrc) for worktree features
echo 'export WORKTREES_BASE="$HOME/worktrees"' >> ~/.zshrc
# or for bash:
# echo 'export WORKTREES_BASE="$HOME/worktrees"' >> ~/.bashrc
```

### Step 6: Start Tmux and Install Plugins
```bash
tmux
# Inside tmux, press: Ctrl-Space + I
# Wait for plugins to install
```

## 🎯 Configuration Features

### Zellij-Style Keybindings
- **Prefix Key**: `Ctrl-Space` (instead of default Ctrl-b)
- **Normal Mode Navigation**: `Ctrl-Shift-hjkl` for pane/window switching
- **Pane Management**: `Ctrl-Shift-pn` for new panes
- **Tab Management**: `Ctrl-Shift-tn` for new tabs/windows

### Visual Design
- **Borderless Panes**: Seamless transitions between panes
- **Dual Status Bars**: Top and bottom status information
- **256-Color Support**: True color terminal capability
- **Thin Beam Cursor**: Consistent cursor styling

### Advanced Features
- **Smart Session Management**: Auto-save and restore sessions
- **Development Server Integration**: Port tracking and display
- **Git Worktree Support**: Automatic worktree session creation
- **Custom Launch Scripts**: Quick access to development tools

## 🛠 Core Configuration Structure

```
~/.config/tmux/
├── tmux.conf                 # Main configuration file
├── scripts/                  # Custom utility scripts
│   ├── init-shell-env.sh    # Shell environment initialization
│   ├── status-bar.sh        # Status bar management
│   ├── worktree-*.sh        # Git worktree utilities
│   ├── launch-*.sh          # Application launchers
│   └── session-*.sh         # Session management
├── plugins/                  # Custom tmux plugins
│   └── tmux-bottom-bar/     # Bottom status bar plugin
└── docs/                    # Documentation
```

## ⚙️ Key Configuration Settings

### Basic Settings
```bash
# Modern terminal support
set -g default-terminal "screen-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

# Mouse support
set -g mouse on

# Start indexing from 1
set -g base-index 1
set -g pane-base-index 1

# Faster command sequences
set -g escape-time 0
```

### Borderless Design
```bash
# Invisible borders
set -g pane-border-style "fg=colour235"
set -g pane-active-border-style "fg=colour235"
```

### Environment Variables
```bash
# Inherit important environment variables
set -g update-environment "DISPLAY SSH_ASKPASS SSH_AUTH_SOCK SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY SERVER_PORT"
```

## 🔧 Customization Guide

### Modifying Keybindings
Edit `tmux.conf` in the "EXACT ZELLIJ KEYBINDS" section:
```bash
# Example: Change prefix key
set -g prefix C-a
bind C-a send-prefix
```

### Adding Custom Scripts
1. Create script in `scripts/` directory
2. Make it executable: `chmod +x scripts/your-script.sh`
3. Reference in `tmux.conf`: `bind-key x run-shell "~/.config/tmux/scripts/your-script.sh"`

### Status Bar Customization
- **Bottom Status**: Modify `scripts/status-bar.sh`
- **Top Status**: Edit status bar configuration in `tmux.conf`
- **Colors**: Update color codes in status bar scripts

## 🚀 Launch Scripts

### Available Launchers
- `launch-cursor.sh` - Open Cursor editor in current directory
- `launch-jira.sh` - Quick JIRA ticket access
- `launch-pr.sh` - GitHub pull request workflows
- `launch-repo.sh` - Repository navigation
- `launch-server-toggle.sh` - Development server management

### Using Launch Scripts
```bash
# From within tmux
Ctrl-Space + Ctrl-c    # Launch Cursor
Ctrl-Space + Ctrl-j    # Launch JIRA
Ctrl-Space + Ctrl-p    # Launch PR tools
Ctrl-Space + Ctrl-r    # Launch repo navigation
Ctrl-Space + Ctrl-s    # Toggle server
```

## 🔄 Session Management

### Auto-Save/Restore
Sessions are automatically saved and restored using the tmux-resurrect plugin:
```bash
# Save session manually
Ctrl-Space + Ctrl-s

# Restore session manually
Ctrl-Space + Ctrl-r
```

### Worktree Integration
Automatic session creation for git worktrees:
```bash
# Sessions are created automatically when entering worktree directories
cd /path/to/worktree
# Tmux session "repo-TICKET-123" is created automatically
```

## 🐛 Troubleshooting

### Common Issues

#### Colors Not Displaying Correctly
```bash
# Check terminal capabilities
echo $TERM
# Should be "screen-256color" inside tmux

# Test true color support
curl -s https://gist.githubusercontent.com/lifepillar/09a44b8cf0f9397465614e622979107f/raw/24-bit-color.sh | bash
```

#### Scripts Not Executing
```bash
# Make scripts executable
chmod +x ~/.config/tmux/scripts/*.sh

# Check script permissions
ls -la ~/.config/tmux/scripts/
```

#### Plugins Not Loading
```bash
# Verify TPM installation
ls ~/.tmux/plugins/tpm/

# Reload tmux configuration
tmux source ~/.config/tmux/tmux.conf

# Reinstall plugins
# In tmux: Ctrl-Space + I
```

#### Keybindings Not Working
```bash
# Check for conflicts
tmux list-keys | grep "C-Space"

# Verify prefix key
tmux show-options -g prefix
```

### Debug Commands
```bash
# Show all tmux options
tmux show-options -g

# List all key bindings
tmux list-keys

# Check tmux info
tmux info

# Validate configuration
tmux source ~/.config/tmux/tmux.conf
```

## 📁 Directory Structure Requirements

### Required Directories
```bash
mkdir -p ~/.config/tmux/scripts
mkdir -p ~/.config/tmux/plugins
mkdir -p ~/.tmux/plugins
```

### Environment Variables
The configuration expects these environment variables:
- `WORKTREES_BASE` - Base directory for git worktrees
- `SERVER_PORT` - Development server port (auto-detected)

### Shell Integration
Add to your shell rc file (`~/.zshrc`, `~/.bashrc`):
```bash
# Tmux auto-start (optional)
if command -v tmux &> /dev/null && [ -z "$TMUX" ]; then
    tmux attach-session -t default || tmux new-session -s default
fi
```

## 🔄 Updating Configuration

### Pull Latest Changes
```bash
# Re-download tmux configuration
git clone --no-checkout https://github.com/patrykk21/dotfiles.git temp-dotfiles
cd temp-dotfiles
git sparse-checkout init --cone
git sparse-checkout set tmux
git checkout
rm -rf ~/.config/tmux
mv tmux ~/.config/
cd .. && rm -rf temp-dotfiles
```

### Reload Configuration
```bash
# In tmux
Ctrl-Space + r

# Or manually
tmux source ~/.config/tmux/tmux.conf
```

### Update Plugins
```bash
# In tmux
Ctrl-Space + U
```

## 📚 Additional Resources

- [Official Tmux Documentation](https://github.com/tmux/tmux/wiki)
- [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm)
- [Zellij Keybinding Reference](https://zellij.dev/documentation/keybindings.html)

## 🆘 Getting Help

### Configuration Issues
1. Check tmux logs: `tmux show-messages`
2. Validate config: `tmux source ~/.config/tmux/tmux.conf`
3. Reset to defaults: Backup and remove `~/.config/tmux/tmux.conf`

### Script Issues
1. Check script permissions: `ls -la ~/.config/tmux/scripts/`
2. Test scripts manually: `bash ~/.config/tmux/scripts/script-name.sh`
3. Check for missing dependencies: `which fzf jq`

### Plugin Issues
1. Reinstall TPM: Remove `~/.tmux/plugins/tpm` and reinstall
2. Clear plugin cache: Remove `~/.tmux/plugins/` except `tpm`
3. Manual plugin install: `Ctrl-Space + I`

## 🎨 Customization Examples

### Change Color Scheme
```bash
# Edit status bar colors in scripts/status-bar.sh
STATUS_BG="#1e1e2e"    # Background color
STATUS_FG="#cdd6f4"    # Foreground color
```

### Add Custom Status Items
```bash
# In scripts/status-bar.sh, add:
CUSTOM_STATUS="#(date +%H:%M)"
echo "#{?window_zoomed_flag,🔍 ,}$CUSTOM_STATUS"
```

### Create Custom Keybinding
```bash
# In tmux.conf, add:
bind-key m run-shell "echo 'Custom command executed!'"
```

This configuration provides a powerful, modern tmux setup with advanced features while maintaining compatibility and ease of use.