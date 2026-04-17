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

**CRITICAL**: You MUST invoke the Skill tool to run `$ARGUMENTS`. Do NOT attempt to perform the command's logic yourself — always delegate to the skill. For example, if `$ARGUMENTS` is `/fix-pr-comments`, you MUST call the Skill tool with skill="fix-pr-comments". Never short-circuit by checking comments or CI yourself — that is the inner skill's job.

## Step 3.5: Self-review before pushing

If the command produced code changes that will be pushed (e.g., `/fix-pr-comments` fixed issues), run `/review --fix` before pushing. This spawns a review team to catch bugs, security issues, and architecture violations in your changes. Apply any CRITICAL/IMPORTANT fixes.

Skip this step if:
- The command was read-only (no files changed)
- The command was `/review` itself (avoid recursion)
- The command was `/merge-base` (merge commits don't need review)

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
