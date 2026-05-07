---
name: with-markers
description: "Wrap any command with conductor state marker tracking. Usage: /with-markers <command and args>"
argument-hint: "<command> [args]"
---

# State Marker Wrapper

Execute `$ARGUMENTS` but maintain the conductor state marker throughout.

## Step 1: Set up the marker

```bash
# Always derive WORKTREE_NAME so we can emit events even if CONDUCTOR_STATE_MARKER
# was inherited from a parent shell.
export WORKTREE_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")

if [ -z "$CONDUCTOR_STATE_MARKER" ]; then
    export CONDUCTOR_STATE_MARKER="$HOME/.config/conductor/markers/${WORKTREE_NAME}.state"
    mkdir -p "$(dirname "$CONDUCTOR_STATE_MARKER")"
fi

# Helper: write marker (compat for conductor.sh) AND emit event (instant picker refresh).
report_state() {
    local payload="$1"
    echo "$payload" > "$CONDUCTOR_STATE_MARKER"
    if [ -x "$HOME/.config/conductor/bin/worktree-event" ]; then
        "$HOME/.config/conductor/bin/worktree-event" conductor-state-reported \
            --ticket "$WORKTREE_NAME" --text "$payload" >/dev/null 2>&1 || true
    fi
}
```

## Step 2: Set working state

```bash
report_state "working|running $ARGUMENTS"
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

After the command completes, evaluate what happened and update the marker.

### Allowed state vocabulary (must match the picker's mapping)

Only these prefixes are recognized. Anything else falls through to `summary.json.status` or — worse — leaves the worktree showing a stale state.

| Prefix            | Picker label         | When to use                                                                 |
|-------------------|----------------------|-----------------------------------------------------------------------------|
| `working`         | `[AI WORKING]`       | Actively running — set in Step 2, should be replaced before exit             |
| `awaiting_ci`     | `[AWAITING CI]`      | PR pushed, CI running                                                        |
| `awaiting_review` | `[AWAITING REVIEW]`  | CI passed, waiting on human review                                           |
| `approved`        | `[APPROVED]`         | Review approved, not yet merged                                              |
| `merged`          | `[MERGED]`           | PR merged into base branch                                                   |
| `closed`          | `[CLOSED]`           | PR closed without merge, or task abandoned                                   |
| `needs_input`     | `[NEEDS INPUT]`      | Blocked on user decision/answer                                              |
| `blocked`         | `[BLOCKED]`          | Blocked on external system (CI infra, third-party, etc.)                     |
| `failed`          | `[FAILED]`           | Command errored out and cannot self-recover                                  |

**⚠️ Never emit `working|completed ...` as a "done" signal.** `working|*` maps to `[AI WORKING]` — it means in-flight, not finished. Actual session completion is recorded separately via the Stop hook's `.done` / `.exit_code` files; the marker is *only* for live picker status.

### Outcome → state

- **Created or updated a PR** → `report_state "awaiting_ci|PR_URL"`, then monitor CI (poll `gh pr checks` every 30s, wait 60s after pass for CodeRabbit, check reviews, fix if needed, then `report_state "awaiting_review|PR_URL"`)
- **Fixed review comments and pushed** → `report_state "awaiting_ci|PR_URL"`, then monitor CI as above
- **PR approved but not yet merged** → `report_state "approved|PR_URL"`
- **PR merged** → `report_state "merged|PR_URL"`
- **PR closed without merge / task abandoned** → `report_state "closed|reason"`
- **Need user input** → `report_state "needs_input|question"`
- **Blocked on external system** → `report_state "blocked|reason"`
- **Failed** → `report_state "failed|reason"`
- **Task is done with no PR involved** → do **not** overwrite with `working|*`. Leave the marker at its last meaningful state (e.g., `merged`, `closed`, or whatever terminal state applies). If the task genuinely has no terminal PR state (e.g., pure local investigation), emit `closed|completed: <one-line summary>` so the picker shows `[CLOSED]` instead of `[AI WORKING]`. The Stop hook's `.done` file is what signals true session end.

## Rules
- **Always** update the state — never leave it on `working|*` after the command finishes
- Use `report_state "state|details"` (defined in Step 1) — it writes the marker file AND emits a `worktree-event conductor-state-reported`, so the picker updates within seconds instead of waiting for the next scheduler tick
- After setting `awaiting_ci`, actively monitor CI and reviews (don't just stop)
- Prefix must be from the Allowed vocabulary table above — no free-form states
