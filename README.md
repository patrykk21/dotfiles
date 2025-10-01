# Personal Dotfiles Configuration

A comprehensive collection of terminal, editor, and development tool configurations optimized for modern development workflows.

## 🚀 Quick Start

```bash
git clone https://github.com/patrykk21/dotfiles.git ~/.config
```

## 📁 Configuration Overview

### Terminal & Shell
- **[Tmux](./tmux/)** - Advanced terminal multiplexer with Zellij-style keybindings
- **[Zsh](./zsh/)** - Shell configuration with transient prompts and deferred loading
- **[Starship](./starship.toml)** - Minimal, fast terminal prompt
- **[Kitty](./kitty/)** - GPU-accelerated terminal emulator
- **[Ghostty](./ghostty/)** - Modern terminal emulator configuration
- **[Fish](./fish/)** - User-friendly shell alternative

### Development Tools
- **[Neovim](./nvim/)** - Highly customized Lua-based editor with LSP, completion, and modern plugin ecosystem
- **[Zed](./zed/)** - Modern code editor configuration
- **[Git](./git/)** - Version control configuration and aliases
- **[GitHub CLI](./gh/)** - GitHub command-line tool settings

### System & Productivity
- **[Aerospace](./aerospace/)** - Tiling window manager for macOS
- **[Karabiner](./karabiner/)** - Keyboard customization for macOS
- **[Zellij](./zellij/)** - Terminal workspace manager

### Package Management
- **[Yarn](./yarn/)** - JavaScript package manager configuration
- **[UV](./uv/)** - Python package installer and resolver
- **[Helm](./helm/)** - Kubernetes package manager

## 🎯 Key Features

### Tmux Configuration
- **Zellij-style keybindings** for familiar navigation
- **Borderless panes** with seamless transitions
- **Dual status bars** (top and bottom) with contextual information
- **Smart session management** with auto-save/restore
- **Integrated development server** port management
- **Custom launch scripts** for common workflows:
  - `launch-cursor.sh` - Open Cursor editor
  - `launch-jira.sh` - Quick JIRA access
  - `launch-pr.sh` - GitHub PR workflows
  - `launch-repo.sh` - Repository navigation
  - `launch-server-toggle.sh` - Development server management

### Neovim Setup
- **Lazy.nvim plugin manager** for fast startup
- **LSP integration** with completion and diagnostics
- **Modern plugin ecosystem** with Telescope, Treesitter, and more
- **Lua-based configuration** for performance and maintainability
- **Modular structure** for easy customization

### Shell Environment
- **Starship prompt** with minimal, informative design
- **Zsh transient prompts** for clean terminal history
- **Deferred loading** for optimal startup performance
- **Environment variable management** with proper inheritance

## 🛠 Installation & Setup

### Prerequisites
- macOS (primary target platform)
- Homebrew package manager
- Git version control

### Essential Dependencies
```bash
# Core tools
brew install tmux neovim zsh starship
brew install --cask kitty

# Development tools
brew install gh git yarn helm
brew install --cask aerospace karabiner-elements
```

### Terminal Setup
1. Set Zsh as default shell: `chsh -s /bin/zsh`
2. Install tmux plugins: `<prefix> + I` (default prefix: Ctrl-a)
3. Configure terminal emulator to use appropriate font and color scheme

### Editor Setup
1. Launch Neovim: `nvim`
2. Lazy.nvim will automatically install configured plugins
3. Run `:checkhealth` to verify setup

## 🔧 Customization

### Adding New Configurations
1. Create directory for new tool: `mkdir ~/.config/[tool-name]`
2. Add configuration files following existing patterns
3. Update this README with new tool documentation

### Tmux Customization
- Modify `tmux/tmux.conf` for core settings
- Add new scripts to `tmux/scripts/` directory
- Update status bar configuration in dedicated script files

### Neovim Plugins
- Add new plugins to `nvim/lua/plugins/` directory
- Follow existing plugin configuration patterns
- Test changes incrementally to avoid conflicts

## 📚 Documentation

### Tmux
- [Dual Status Implementation](./tmux/docs/dual-status-implementation.md)
- [Multiple Status Bars Guide](./tmux/docs/multiple-status-bars-guide.md)
- [Zellij Fixes Guide](./tmux/ZELLIJ_FIXES_GUIDE.md)

### Neovim
- [Development Guide](./nvim/CLAUDE.md)
- [Current Issues](./nvim/ISSUES.md)
- [Development Plans](./nvim/plans/)

## 🎨 Visual Configuration

### Terminal Appearance
- **256-color support** with true color (Tc) capability
- **Thin beam cursor** for consistent visual feedback
- **Mouse support** enabled across all terminal applications
- **Borderless design** for seamless pane transitions

### Prompt Design
- **Minimal starship prompt** with essential information only
- **Command duration** display for performance awareness
- **Time display** in HH:MM format
- **Git status integration** with branch and change indicators

## 🔄 Workflow Integration

### Development Server Management
- Automatic port detection and display in status bar
- Server toggle functionality for quick start/stop operations
- Environment variable inheritance across tmux sessions

### Git Integration
- Custom aliases and shortcuts in Git configuration
- GitHub CLI integration for PR and issue management
- Automated worktree management for feature development

### Session Management
- Auto-save and restore tmux sessions
- Workspace organization with consistent naming
- Quick access to frequently used projects and repositories

## 🚨 Troubleshooting

### Common Issues
- **Tmux not starting**: Check shell configuration and environment variables
- **Colors not displaying**: Verify terminal true color support
- **Plugins not loading**: Ensure package managers are properly installed
- **Keybindings not working**: Check for conflicts with system shortcuts

### Debug Commands
```bash
# Check tmux configuration
tmux show-options -g

# Verify Neovim health
nvim +checkhealth

# Test shell configuration
zsh -n ~/.zshrc
```

## 📞 Support

This is a personal configuration repository. Feel free to:
- Fork and adapt for your own use
- Submit issues for bugs or suggestions
- Contribute improvements via pull requests

## 📄 License

Personal dotfiles configuration. Use and modify as needed for your own setup.