#!/usr/bin/env zsh
# Transient prompt configuration for Starship

# Configure transient prompt variables
TRANSIENT_PROMPT_PROMPT='$(starship prompt)'
TRANSIENT_PROMPT_RPROMPT=''
TRANSIENT_PROMPT_TRANSIENT_PROMPT='❯ '
TRANSIENT_PROMPT_TRANSIENT_RPROMPT=''

# Source the plugin - it will auto-initialize
source /Users/vigenerr/.config/zsh/zsh-transient-prompt/transient-prompt.plugin.zsh