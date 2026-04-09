#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Autopilot Runner - Iterates over all project configs
# =============================================================================
# Called by the scheduler (launchd/systemd) every 5 minutes.
# Runs autopilot.sh once per project config in projects/*.env
# Each project runs independently with its own state, lock, and history.
# =============================================================================

AUTOPILOT_DIR="$HOME/.config/autopilot"
PROJECTS_DIR="$AUTOPILOT_DIR/projects"
ENABLED_FILE="$AUTOPILOT_DIR/enabled"

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

# Run autopilot for each project config
for config in "$PROJECTS_DIR"/*.env; do
    [ -f "$config" ] || continue

    project_name=$(basename "$config" .env)

    # Run in subshell so projects don't interfere with each other's env
    (
        AUTOPILOT_CONF="$config" "$AUTOPILOT_DIR/autopilot.sh"
    ) &
done

# Wait for all background jobs to complete
wait
