#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# =============================================================================
# Autopilot Control Script (multi-project, cross-platform)
# Usage: autopilot <command> [args]
# =============================================================================

AUTOPILOT_DIR="$HOME/.config/autopilot"
PROJECTS_DIR="$AUTOPILOT_DIR/projects"
ENABLED_FILE="$AUTOPILOT_DIR/enabled"
SERVICE_NAME="autopilot-jira"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# --- Cross-platform scheduler ---
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

scheduler_load() {
    case "$(detect_os)" in
        macos)
            local plist="$HOME/Library/LaunchAgents/com.${SERVICE_NAME}.plist"
            [ -f "$plist" ] && launchctl load "$plist" 2>/dev/null || true
            ;;
        linux)
            systemctl --user enable --now "${SERVICE_NAME}.timer" 2>/dev/null || true
            ;;
    esac
}

scheduler_unload() {
    case "$(detect_os)" in
        macos)
            local plist="$HOME/Library/LaunchAgents/com.${SERVICE_NAME}.plist"
            [ -f "$plist" ] && launchctl unload "$plist" 2>/dev/null || true
            ;;
        linux)
            systemctl --user disable --now "${SERVICE_NAME}.timer" 2>/dev/null || true
            ;;
    esac
}

scheduler_status_line() {
    case "$(detect_os)" in
        macos)
            local plist="$HOME/Library/LaunchAgents/com.${SERVICE_NAME}.plist"
            if launchctl list "com.${SERVICE_NAME}" &>/dev/null; then
                local interval
                interval=$(/usr/libexec/PlistBuddy -c "Print :StartInterval" "$plist" 2>/dev/null || echo "300")
                if [ "$interval" -ge 60 ]; then
                    echo -e "  Schedule: ${GREEN}LOADED${NC} (launchd, every $((interval / 60))m)"
                else
                    echo -e "  Schedule: ${GREEN}LOADED${NC} (launchd, every ${interval}s)"
                fi
            else
                echo -e "  Schedule: ${YELLOW}NOT LOADED${NC} (run 'autopilot setup')"
            fi
            ;;
        linux)
            if systemctl --user is-active "${SERVICE_NAME}.timer" &>/dev/null; then
                local interval
                interval=$(systemctl --user show "${SERVICE_NAME}.timer" -p TriggerLimitIntervalSec --value 2>/dev/null || echo "300s")
                echo -e "  Schedule: ${GREEN}ACTIVE${NC} (systemd, every ${interval})"
            else
                echo -e "  Schedule: ${YELLOW}INACTIVE${NC} (run 'autopilot setup')"
            fi
            ;;
        *)  echo -e "  Schedule: ${YELLOW}UNKNOWN OS${NC}" ;;
    esac
}

# --- Project helpers ---
list_projects() {
    if [ -d "$PROJECTS_DIR" ]; then
        local files
        files=$(find "$PROJECTS_DIR" -maxdepth 1 -name "*.env" -type f 2>/dev/null | sort)
        if [ -n "$files" ]; then
            echo "$files" | while read -r f; do
                basename "$f" .env
            done
        fi
    fi
}

project_state() {
    local project="$1"
    local state_file="$AUTOPILOT_DIR/state/${project}.json"
    if [ -f "$state_file" ]; then
        cat "$state_file"
    else
        echo '{"status":"idle"}'
    fi
}

project_history_counts() {
    local project="$1"
    local hist_dir="$AUTOPILOT_DIR/history/${project}"
    local completed=0 failed=0
    if [ -d "$hist_dir" ] && [ "$(ls -A "$hist_dir" 2>/dev/null)" ]; then
        completed=$(find "$hist_dir" -name "*.json" -exec jq -r '.outcome' {} \; 2>/dev/null | grep -c "completed" || true)
        failed=$(find "$hist_dir" -name "*.json" -exec jq -r '.outcome' {} \; 2>/dev/null | grep -c "failed" || true)
    fi
    echo "$completed $failed"
}

# --- Commands ---
case "${1:-help}" in
    on)
        touch "$ENABLED_FILE"
        scheduler_load
        projects=$(list_projects)
        count=$(echo "$projects" | grep -c . || true)
        echo -e "${GREEN}Autopilot enabled.${NC} Polling every 5 minutes."
        echo -e "  Projects: ${BLUE}${count}${NC} configured"
        if [ -n "$projects" ]; then
            echo "$projects" | while read -r p; do
                echo -e "    - $p"
            done
        fi
        ;;

    off)
        rm -f "$ENABLED_FILE"
        scheduler_unload
        echo -e "${YELLOW}Autopilot disabled.${NC}"
        # Show any active work
        for state_file in "$AUTOPILOT_DIR/state/"*.json; do
            [ -f "$state_file" ] || continue
            s=$(jq -r '.status' "$state_file" 2>/dev/null || echo "")
            if [ "$s" = "working" ]; then
                t=$(jq -r '.ticket' "$state_file")
                p=$(jq -r '.project // "?"' "$state_file")
                echo -e "${BLUE}Note:${NC} $p is working on $t — active session continues, but no new tickets will be picked up."
            fi
        done
        ;;

    status)
        echo -e "${BLUE}=== Autopilot Status ===${NC}"
        echo ""

        if [ -f "$ENABLED_FILE" ]; then
            echo -e "  State:    ${GREEN}ENABLED${NC}"
        else
            echo -e "  State:    ${RED}DISABLED${NC}"
        fi
        scheduler_status_line
        echo ""

        projects=$(list_projects)
        if [ -z "$projects" ]; then
            echo -e "  ${YELLOW}No projects configured.${NC} Run 'autopilot add <name>' to add one."
        else
            echo -e "  ${BLUE}Projects:${NC}"
            echo ""
            echo "$projects" | while read -r project; do
                # Load project config for display
                jira_proj=""
                if [ -f "$PROJECTS_DIR/${project}.env" ]; then
                    jira_proj=$(grep '^JIRA_PROJECT=' "$PROJECTS_DIR/${project}.env" | sed 's/^JIRA_PROJECT=//' | tr -d '"' || true)
                fi

                state=$(project_state "$project")
                pstatus=$(echo "$state" | jq -r '.status')
                read -r completed failed <<< "$(project_history_counts "$project")"

                if [ "$pstatus" = "working" ]; then
                    ticket=$(echo "$state" | jq -r '.ticket')
                    worktree=$(echo "$state" | jq -r '.worktree_name')
                    port=$(echo "$state" | jq -r '.port')
                    started=$(echo "$state" | jq -r '.started_at')

                    echo -e "  ${CYAN}$project${NC} ${DIM}($jira_proj)${NC} — ${GREEN}WORKING${NC}"
                    echo "      Ticket:   $ticket"
                    echo "      Worktree: $worktree"
                    echo "      Port:     $port"
                    echo "      Started:  $started"
                    if tmux has-session -t "$worktree" 2>/dev/null; then
                        echo -e "      Session:  ${GREEN}ALIVE${NC}"
                    else
                        echo -e "      Session:  ${RED}DEAD${NC}"
                    fi
                else
                    echo -e "  ${CYAN}$project${NC} ${DIM}($jira_proj)${NC} — ${YELLOW}IDLE${NC}"
                fi
                if [ "$pstatus" = "working" ]; then
                    echo -e "      History:  ${CYAN}1${NC} in progress, ${GREEN}$completed${NC} done, ${RED}$failed${NC} failed"
                else
                    echo -e "      History:  ${GREEN}$completed${NC} done, ${RED}$failed${NC} failed"
                fi
                echo ""
            done
        fi
        ;;

    add)
        project_name="${2:-}"
        if [ -z "$project_name" ]; then
            echo "Usage: autopilot add <project-name>"
            echo ""
            echo "Creates a new project config from the template."
            echo "Example: autopilot add my-project"
            exit 1
        fi

        mkdir -p "$PROJECTS_DIR"
        target="$PROJECTS_DIR/${project_name}.env"

        if [ -f "$target" ]; then
            echo -e "${YELLOW}Project '$project_name' already exists:${NC} $target"
            exit 1
        fi

        cp "$AUTOPILOT_DIR/config.env.example" "$target"
        echo -e "${GREEN}Created project config:${NC} $target"
        echo ""
        echo "Edit it now:"
        echo "  \$EDITOR $target"
        echo ""
        echo "Required fields: PROJECT_DIR, JIRA_PROJECT, JIRA_LABEL"
        ;;

    remove)
        project_name="${2:-}"
        if [ -z "$project_name" ]; then
            echo "Usage: autopilot remove <project-name>"
            exit 1
        fi

        target="$PROJECTS_DIR/${project_name}.env"
        if [ ! -f "$target" ]; then
            echo -e "${RED}Project '$project_name' not found.${NC}"
            exit 1
        fi

        # Check if currently working
        state_file="$AUTOPILOT_DIR/state/${project_name}.json"
        if [ -f "$state_file" ]; then
            s=$(jq -r '.status' "$state_file" 2>/dev/null || echo "")
            if [ "$s" = "working" ]; then
                echo -e "${RED}Project '$project_name' is currently working on a ticket.${NC}"
                echo "Run 'autopilot reset $project_name' first, or wait for it to finish."
                exit 1
            fi
        fi

        rm -f "$target"
        echo -e "${GREEN}Removed project '$project_name'.${NC}"
        echo -e "${DIM}State and history preserved in $AUTOPILOT_DIR/state/ and $AUTOPILOT_DIR/history/${project_name}/${NC}"
        ;;

    list)
        projects=$(list_projects)
        if [ -z "$projects" ]; then
            echo "No projects configured. Run 'autopilot add <name>' to add one."
        else
            echo -e "${BLUE}Configured projects:${NC}"
            echo "$projects" | while read -r p; do
                jira_proj=$(grep '^JIRA_PROJECT=' "$PROJECTS_DIR/${p}.env" 2>/dev/null | sed 's/^JIRA_PROJECT=//' | tr -d '"' || true)
                state=$(project_state "$p")
                pstatus=$(echo "$state" | jq -r '.status')
                if [ "$pstatus" = "working" ]; then
                    ticket=$(echo "$state" | jq -r '.ticket')
                    echo -e "  ${CYAN}$p${NC} ${DIM}($jira_proj)${NC} — ${GREEN}working on $ticket${NC}"
                else
                    echo -e "  ${CYAN}$p${NC} ${DIM}($jira_proj)${NC} — ${YELLOW}idle${NC}"
                fi
            done
        fi
        ;;

    run)
        project_name="${2:-}"
        if [ -n "$project_name" ]; then
            config="$PROJECTS_DIR/${project_name}.env"
            if [ ! -f "$config" ]; then
                echo -e "${RED}Project '$project_name' not found.${NC}"
                exit 1
            fi
            echo -e "${BLUE}Running autopilot cycle for $project_name...${NC}"
            AUTOPILOT_CONF="$config" "$AUTOPILOT_DIR/autopilot.sh"
        else
            echo -e "${BLUE}Running autopilot cycle for all projects...${NC}"
            "$AUTOPILOT_DIR/autopilot-runner.sh"
        fi
        ;;

    logs)
        project_name="${2:-}"
        lines="${3:-50}"
        if [ -n "$project_name" ]; then
            log_file="$AUTOPILOT_DIR/logs/${project_name}.log"
        else
            # Show most recent log across all projects
            log_file=$(ls -t "$AUTOPILOT_DIR/logs/"*.log 2>/dev/null | head -1 || true)
        fi
        if [ -n "$log_file" ] && [ -f "$log_file" ]; then
            echo -e "${DIM}$(basename "$log_file" .log)${NC}"
            tail -"$lines" "$log_file"
        else
            echo "No log file found."
        fi
        ;;

    history)
        project_name="${2:-}"
        if [ -n "$project_name" ]; then
            hist_dir="$AUTOPILOT_DIR/history/${project_name}"
        else
            hist_dir="$AUTOPILOT_DIR/history"
        fi

        found=false
        for f in "$hist_dir"/*.json "$hist_dir"/**/*.json; do
            [ -f "$f" ] || continue
            found=true
            h_ticket=$(jq -r '.ticket' "$f")
            h_outcome=$(jq -r '.outcome' "$f")
            h_completed=$(jq -r '.completed_at' "$f")
            h_details=$(jq -r '.details // "N/A"' "$f")
            h_project=$(jq -r '.project // "?"' "$f")

            if [ "$h_outcome" = "completed" ]; then
                echo -e "  ${GREEN}$h_ticket${NC} ${DIM}($h_project)${NC} — completed ($h_completed)"
                echo "    PR: $h_details"
            else
                echo -e "  ${RED}$h_ticket${NC} ${DIM}($h_project)${NC} — failed ($h_completed)"
                echo "    Reason: $h_details"
            fi
            echo ""
        done
        if [ "$found" = false ]; then
            echo "No history yet."
        fi
        ;;

    reset)
        project_name="${2:-}"
        if [ -z "$project_name" ]; then
            echo "Usage: autopilot reset <project-name>"
            echo "  Or:  autopilot reset --all"
            exit 1
        fi

        if [ "$project_name" = "--all" ]; then
            echo -e "${YELLOW}Resetting ALL projects to idle...${NC}"
            for sf in "$AUTOPILOT_DIR/state/"*.json; do
                [ -f "$sf" ] && echo '{"status":"idle"}' > "$sf"
            done
            rm -f "$AUTOPILOT_DIR/markers/"*.done "$AUTOPILOT_DIR/markers/"*.failed "$AUTOPILOT_DIR/markers/"*.exit_code
            rm -f "$AUTOPILOT_DIR/state/"*.lock
        else
            echo -e "${YELLOW}Resetting $project_name to idle...${NC}"
            echo '{"status":"idle"}' > "$AUTOPILOT_DIR/state/${project_name}.json"
            rm -f "$AUTOPILOT_DIR/state/${project_name}.lock"
            # Clean markers for this project's worktrees
            if [ -f "$PROJECTS_DIR/${project_name}.env" ]; then
                # shellcheck source=/dev/null
                source "$PROJECTS_DIR/${project_name}.env" 2>/dev/null
                pn="${PROJECT_NAME:-$project_name}"
                rm -f "$AUTOPILOT_DIR/markers/${pn}-"*.done "$AUTOPILOT_DIR/markers/${pn}-"*.failed "$AUTOPILOT_DIR/markers/${pn}-"*.exit_code 2>/dev/null || true
            fi
        fi
        echo -e "${GREEN}Done.${NC}"
        ;;

    setup)
        "$AUTOPILOT_DIR/setup.sh"
        ;;

    help|*)
        echo "Usage: autopilot <command> [args]"
        echo ""
        echo "Global:"
        echo "  on                 Enable autopilot (starts polling all projects)"
        echo "  off                Disable autopilot"
        echo "  status             Show status of all projects"
        echo "  setup              Install scheduler for this OS"
        echo ""
        echo "Projects:"
        echo "  add <name>         Add a new project config"
        echo "  remove <name>      Remove a project config"
        echo "  list               List configured projects"
        echo ""
        echo "Execution:"
        echo "  run [project]      Run one cycle (all projects, or specific one)"
        echo "  logs [project] [N] Show last N log lines"
        echo "  history [project]  Show completed/failed tickets"
        echo "  reset <project>    Reset project state to idle"
        echo "  reset --all        Reset all projects"
        ;;
esac
