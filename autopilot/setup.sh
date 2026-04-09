#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Autopilot Setup - Cross-platform scheduler installation
# Supports: macOS (launchd), Linux (systemd user timers)
# =============================================================================

AUTOPILOT_DIR="$HOME/.config/autopilot"
SCRIPT_PATH="$AUTOPILOT_DIR/autopilot-runner.sh"
SERVICE_NAME="autopilot-jira"

detect_os() {
    case "$(uname -s)" in
        Darwin)               echo "macos" ;;
        Linux)                echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)                    echo "unknown" ;;
    esac
}

# --- macOS: launchd ---
install_launchd() {
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist_path="$plist_dir/com.${SERVICE_NAME}.plist"

    mkdir -p "$plist_dir"

    local path_value="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.${SERVICE_NAME}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${SCRIPT_PATH}</string>
    </array>

    <key>StartInterval</key>
    <integer>300</integer>

    <key>RunAtLoad</key>
    <false/>

    <key>StandardOutPath</key>
    <string>${AUTOPILOT_DIR}/launchd-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>${AUTOPILOT_DIR}/launchd-stderr.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>PATH</key>
        <string>${path_value}</string>
        <key>LANG</key>
        <string>en_US.UTF-8</string>
    </dict>
</dict>
</plist>
EOF

    echo "Installed launchd plist: $plist_path"
    echo "  To load:   launchctl load $plist_path"
    echo "  To unload: launchctl unload $plist_path"
    echo "  Or just use: autopilot on / autopilot off"
}

# --- Linux: systemd user timer ---
install_systemd() {
    local systemd_dir="$HOME/.config/systemd/user"
    mkdir -p "$systemd_dir"

    cat > "$systemd_dir/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Autopilot - Autonomous Jira-to-PR Pipeline

[Service]
Type=oneshot
ExecStart=/bin/bash ${SCRIPT_PATH}
Environment=HOME=${HOME}
Environment=PATH=${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=LANG=en_US.UTF-8
EOF

    cat > "$systemd_dir/${SERVICE_NAME}.timer" << EOF
[Unit]
Description=Autopilot Timer (every 5 min)

[Timer]
OnBootSec=60
OnUnitActiveSec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload 2>/dev/null || true

    echo "Installed systemd user timer:"
    echo "  Service: $systemd_dir/${SERVICE_NAME}.service"
    echo "  Timer:   $systemd_dir/${SERVICE_NAME}.timer"
    echo "  To enable: systemctl --user enable --now ${SERVICE_NAME}.timer"
    echo "  To disable: systemctl --user disable --now ${SERVICE_NAME}.timer"
    echo "  Or just use: autopilot on / autopilot off"
}

# --- Windows: Task Scheduler ---
install_task_scheduler() {
    local task_name="Autopilot-${SERVICE_NAME}"
    local runner_path
    runner_path=$(cygpath -w "$SCRIPT_PATH" 2>/dev/null || echo "$SCRIPT_PATH")
    local bash_path
    bash_path=$(cygpath -w "$(command -v bash)" 2>/dev/null || echo "bash")

    schtasks.exe //Create //F //TN "$task_name" //SC MINUTE //MO 5 \
        //TR "\"$bash_path\" \"$runner_path\"" 2>&1

    if [ $? -eq 0 ]; then
        echo "Installed Windows Task Scheduler task: $task_name"
        echo "  Runs every 5 minutes"
        echo "  To manage: autopilot on / autopilot off"
    else
        echo "WARNING: Failed to create scheduled task."
        echo "You may need to run this as Administrator, or create it manually."
        echo "You can still run autopilot manually: autopilot run"
    fi
}

setup_config() {
    if [ -f "$AUTOPILOT_DIR/config.env" ]; then
        echo "Config file already exists: $AUTOPILOT_DIR/config.env"
        return 0
    fi

    if [ -f "$AUTOPILOT_DIR/config.env.example" ]; then
        cp "$AUTOPILOT_DIR/config.env.example" "$AUTOPILOT_DIR/config.env"
        echo "Created config.env from example. Edit it with your project paths:"
        echo "  $AUTOPILOT_DIR/config.env"
    else
        echo "WARNING: No config.env.example found. Create $AUTOPILOT_DIR/config.env manually."
    fi
}

setup_dirs() {
    mkdir -p "$AUTOPILOT_DIR/history" "$AUTOPILOT_DIR/logs" "$AUTOPILOT_DIR/markers" "$AUTOPILOT_DIR/prompts"
    chmod +x "$AUTOPILOT_DIR/autopilot.sh" 2>/dev/null || true
    chmod +x "$AUTOPILOT_DIR/autopilot-ctl.sh" 2>/dev/null || true
}

main() {
    echo "=== Autopilot Setup ==="
    echo ""

    local os
    os=$(detect_os)
    echo "Detected OS: $os"
    echo ""

    echo "[1/3] Creating directories..."
    setup_dirs

    echo "[2/3] Checking config..."
    setup_config

    echo "[3/3] Installing scheduler..."
    case "$os" in
        macos)   install_launchd ;;
        linux)   install_systemd ;;
        windows) install_task_scheduler ;;
        *)
            echo "WARNING: Unsupported OS '$os'. No scheduler installed."
            echo "You can still run autopilot manually: autopilot run"
            ;;
    esac

    echo ""
    echo "=== Setup complete ==="
    echo ""
    echo "Next steps:"
    echo "  1. Edit config:  \$EDITOR $AUTOPILOT_DIR/config.env"
    echo "  2. Enable:       autopilot on"
    echo "  3. Test:         autopilot run"
    echo "  4. Monitor:      autopilot status"
}

main "$@"
