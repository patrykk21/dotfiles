#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Conductor Runner - Iterates over all project configs
# =============================================================================
# Called by the scheduler (launchd/systemd) every 5 minutes.
# Runs conductor.sh once per project config in projects/*.env
# Each project runs independently with its own state, lock, and history.
# =============================================================================

CONDUCTOR_DIR="$HOME/.config/conductor"
PROJECTS_DIR="$CONDUCTOR_DIR/projects"
ENABLED_FILE="$CONDUCTOR_DIR/enabled"

# PATH is defined globally in ~/Library/LaunchAgents/com.conductor.plist so every
# tool this runner spawns (conductor.sh, summarize-dirty, claude, jq, ...) inherits
# it. Do not duplicate PATH exports in individual scripts — edit the plist instead.

# Check if enabled
if [ ! -f "$ENABLED_FILE" ]; then
    exit 0
fi

# Check if projects directory exists and has configs
if [ ! -d "$PROJECTS_DIR" ]; then
    exit 0
fi

configs=("$PROJECTS_DIR"/*.env)
if [ ! -f "${configs[0]}" ]; then
    exit 0
fi

# Run conductor for each project config
for config in "$PROJECTS_DIR"/*.env; do
    [ -f "$config" ] || continue

    project_name=$(basename "$config" .env)

    # Run in subshell so projects don't interfere with each other's env
    (
        CONDUCTOR_CONF="$config" "$CONDUCTOR_DIR/conductor.sh"
    ) &
done

# Wait for all background jobs to complete
wait

# =============================================================================
# Pass 2: Refresh dirty worktree summaries.
# Reads needs-summary-update flags set during Pass 1 (conductor-finished events)
# plus flags from Stop hook / post-commit / /pause-worktree.
# Each summarizer call is signal-hash gated so idle ticks are cheap.
# =============================================================================
if [ -x "$CONDUCTOR_DIR/bin/summarize-dirty" ]; then
    "$CONDUCTOR_DIR/bin/summarize-dirty" >/dev/null 2>&1
fi

# =============================================================================
# Pass 3: Probe PR state for all sessions (throttled).
# Walks every session, calls `gh pr view`, emits pr-state-changed when PR state
# changes. Throttled per-session via .last_pr_probe mtime (default 5 min).
# Terminal states (merged/closed) are never re-probed unless --force.
# Emitted events flip `needs-summary-update`, so Pass 2 on the *next* tick picks
# them up and regenerates summary.json / context.md with the fresh pr_state.
# =============================================================================
if [ -x "$CONDUCTOR_DIR/bin/probe-pr-state" ]; then
    "$CONDUCTOR_DIR/bin/probe-pr-state" >>"$CONDUCTOR_DIR/logs/pr-probe.log" 2>&1 || true
fi
