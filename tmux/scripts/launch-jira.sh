#!/usr/bin/env bash
# Launch Jira ticket in browser

# Get current session name
SESSION=$(tmux display-message -p '#S')

# Extract ticket ID from session name (e.g., ECH-128 from ECH-128-sub)
TICKET_ID=""
if [[ "$SESSION" =~ ([A-Z]+-[0-9]+) ]]; then
    TICKET_ID="${BASH_REMATCH[1]}"
else
    tmux display-message "No ticket ID found in session name: $SESSION"
    exit 1
fi

# Construct Jira URL
JIRA_URL="https://groupondev.atlassian.net/browse/$TICKET_ID"

# Open in browser
if command -v open >/dev/null 2>&1; then
    open "$JIRA_URL"
    tmux display-message "Opened Jira ticket: $TICKET_ID"
else
    tmux display-message "Cannot open browser: 'open' command not found"
    exit 1
fi