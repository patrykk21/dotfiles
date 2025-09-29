#!/usr/bin/env bash

# Ignore SIGPIPE
trap '' PIPE

# Update all top status bars
for f in /tmp/tmux-top-status-*; do
    if [ -p "$f" ]; then
        # Non-blocking write with timeout
        timeout 0.1 bash -c "echo update > '$f'" 2>/dev/null || true
    fi
done

exit 0