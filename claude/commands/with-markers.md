---
name: with-markers
description: "Wrap any command with autopilot state marker tracking. Usage: /with-markers <command and args>"
argument-hint: "<command> [args]"
---

# State Marker Wrapper

Execute `$ARGUMENTS` but maintain the autopilot state marker throughout.

## Step 1: Set up the marker

```bash
if [ -z "$AUTOPILOT_STATE_MARKER" ]; then
    WORKTREE_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
    export AUTOPILOT_STATE_MARKER="$HOME/.config/autopilot/markers/${WORKTREE_NAME}.state"
    mkdir -p "$(dirname "$AUTOPILOT_STATE_MARKER")"
fi
```

## Step 2: Set working state

```bash
echo "working|running $ARGUMENTS" > "$AUTOPILOT_STATE_MARKER"
```

## Step 3: Execute the command

Run the command/prompt specified in `$ARGUMENTS`. This could be a slash command like `/fix-pr-comments` or any other instruction.

## Step 4: Update marker based on outcome

After the command completes, evaluate what happened and update the marker:

- **If you created or updated a PR** → `echo "awaiting_ci|PR_URL" > "$AUTOPILOT_STATE_MARKER"`, then monitor CI (poll `gh pr checks` every 30s, wait 60s after pass for CodeRabbit, check reviews, fix if needed, then set `awaiting_review`)
- **If you fixed review comments and pushed** → `echo "awaiting_ci|PR_URL" > "$AUTOPILOT_STATE_MARKER"`, then monitor CI as above
- **If you need user input** → `echo "needs_input|question" > "$AUTOPILOT_STATE_MARKER"`
- **If you failed** → `echo "failed|reason" > "$AUTOPILOT_STATE_MARKER"`
- **If the task is done but no PR involved** → `echo "working|completed $ARGUMENTS" > "$AUTOPILOT_STATE_MARKER"`

## Rules
- **Always** update the marker — never leave it stale
- The marker path is `$AUTOPILOT_STATE_MARKER` — write to it with `echo "state|details" > "$AUTOPILOT_STATE_MARKER"`
- After setting `awaiting_ci`, actively monitor CI and reviews (don't just stop)
