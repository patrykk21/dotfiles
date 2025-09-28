#!/usr/bin/env bash
# Update bottom bar - Forces a redraw when mode changes

# Send a signal to the bottom bar manager to update
pkill -USR1 -f "bottom-bar-manager.sh" 2>/dev/null || true