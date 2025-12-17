# Zed Editor Configuration

This directory contains configuration for the [Zed editor](https://zed.dev/).

## Setup on a New Machine

1. **Backup existing config** (if you have one):
   ```bash
   mv ~/.config/zed ~/.config/zed.backup
   ```

2. **Create symlink** to dotfiles:
   ```bash
   # Assuming your dotfiles are in ~/.config
   ln -sf ~/.config/zed ~/.config/zed

   # OR if your dotfiles are elsewhere (e.g., ~/dotfiles):
   # ln -sf ~/dotfiles/zed ~/.config/zed
   ```

3. **Install required extensions** in Zed:
   - Open Zed
   - Press `Cmd+Shift+P` (or `Ctrl+Shift+P` on Linux)
   - Type "zed: extensions"
   - Install the following:
     - **Tokyo Night** (theme)
     - Add other extensions you use here...

4. **Restart Zed** for all settings to take effect

## Configuration Files

- `settings.json` - Main Zed settings (Vim mode, theme, editor preferences)
- `keymap.json` - Custom keybindings
- `*_backup.json` - Backup versions of configs

## Features Configured

- ✅ Vim mode enabled
- ✅ Tokyo Night theme
- ✅ Relative line numbers
- ✅ No tab bar (minimal UI like Neovim)
- ✅ Git gutter enabled
- ✅ Inline git blame **disabled**
- ✅ Claude AI integration configured
- ✅ Indent guides enabled
- ✅ Ligatures disabled

## Troubleshooting

**Settings not applying?**
- Ensure the symlink is correct: `ls -la ~/.config/zed`
- Should show: `zed -> /path/to/your/dotfiles/zed`

**Theme not working?**
- Install Tokyo Night extension from Zed's extension marketplace
- Restart Zed after installation

**Inline git blame showing despite being disabled?**
- Make sure you're reading from the correct config
- Check: `zed: open settings` should show your settings.json content
