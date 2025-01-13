# Homebrew
export HOMEBREW_NO_ANALYTICS=1

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# NVIM
# export NVIM_APPNAME="NvChad"
# export EDITOR=nvim

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/vigenerr/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/vigenerr/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/vigenerr/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/vigenerr/google-cloud-sdk/completion.zsh.inc'; fi

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# PKCFG
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/opt/libffi/lib/pkgconfig"

# Toptal infra tools
export PATH=/opt/homebrew/bin:$PATH

# Add RVM to PATH for scripting. Make sure this is the last PATH variable change.
export PATH="$PATH:$HOME/.rvm/bin"
source ~/.rvm/scripts/rvm
rvm use default

