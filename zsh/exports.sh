# Homebrew (sets up environment and adds /opt/homebrew/bin to PATH)
eval "$(/opt/homebrew/bin/brew shellenv)"
export HOMEBREW_NO_ANALYTICS=1

# Volta - Node.js version manager (prepends to PATH, taking precedence over Homebrew)
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"

# Local binaries (prepends to PATH, taking precedence over everything)
export PATH="$HOME/.local/bin:$PATH"

# NVM - Node Version Manager (keeping for compatibility, though you're using Volta)
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

# PKG_CONFIG
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/opt/libffi/lib/pkgconfig"

# RVM - Ruby Version Manager (append to PATH - should be last PATH modification)
export PATH="$PATH:$HOME/.rvm/bin"
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM as a function

# Google Cloud SDK
if [ -f '/Users/vigenerr/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/vigenerr/Downloads/google-cloud-sdk/path.zsh.inc'; fi
if [ -f '/Users/vigenerr/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/vigenerr/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

# Claude Code Notifications (ntfy.sh)
export CLAUDE_NOTIFY_TOPIC="pat-claude-alerts"
export CLAUDE_NOTIFY_SERVER="https://ntfy.sh"
export CLAUDE_NOTIFY_PRIORITY="default"

# CCLSP (Claude Code Language Server Protocol)
export CCLSP_CONFIG_PATH="$HOME/.claude/cclsp.json"

# OpenSSL (uncomment if needed)
# export LDFLAGS="-L/opt/homebrew/opt/openssl@3/lib"
# export CPPFLAGS="-I/opt/homebrew/opt/openssl@3/include"
