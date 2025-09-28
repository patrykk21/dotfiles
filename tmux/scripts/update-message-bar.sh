#!/usr/bin/env bash
# Update message bar to act as bottom status

# Get the current mode status
STATUS=$(~/.config/tmux/scripts/status-bar.sh | sed 's/#\[[^]]*\]//g')

# Display in message bar with long duration
# Using a very long duration (999999 seconds) makes it effectively permanent
tmux display-message -d 999999 "$STATUS" 2>/dev/null || true