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
SERVICE_NAME="autopilot"

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
        Darwin)               echo "macos" ;;
        Linux)                echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)                    echo "unknown" ;;
    esac
}

HAS_TMUX=false
command -v tmux &>/dev/null && HAS_TMUX=true
PIDS_DIR="$AUTOPILOT_DIR/pids"

# Check if a session (tmux or background PID) is alive
session_is_alive() {
    local worktree="$1"
    if [ "$HAS_TMUX" = true ]; then
        tmux has-session -t "$worktree" 2>/dev/null && return 0
    fi
    # Fallback: check PID file
    local pid_file="$PIDS_DIR/${worktree}-claude.pid"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || echo "")
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && return 0
    fi
    return 1
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
        windows)
            # Windows Task Scheduler — use VBS wrapper for invisible polling
            local task_name="Autopilot-${SERVICE_NAME}"
            local vbs_path="$AUTOPILOT_DIR/autopilot-runner.vbs"
            if [ ! -f "$vbs_path" ]; then
                local runner_win
                runner_win=$(cygpath -w "$AUTOPILOT_DIR/autopilot-runner.sh" 2>/dev/null)
                local bash_win
                bash_win=$(cygpath -w "$(command -v bash)" 2>/dev/null || echo "C:\\Program Files\\Git\\usr\\bin\\bash.exe")
                cat > "$vbs_path" << VBSEOF
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """${bash_win}"" ""${runner_win}""", 0, False
VBSEOF
            fi
            local vbs_win
            vbs_win=$(cygpath -w "$vbs_path" 2>/dev/null || echo "$vbs_path")
            schtasks.exe //Create //F //TN "$task_name" //SC MINUTE //MO 1 \
                //TR "wscript.exe \"$vbs_win\"" 2>/dev/null || true
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
        windows)
            local task_name="Autopilot-${SERVICE_NAME}"
            schtasks.exe //Delete //TN "$task_name" //F 2>/dev/null || true
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
        windows)
            local task_name="Autopilot-${SERVICE_NAME}"
            if schtasks.exe //Query //TN "$task_name" &>/dev/null; then
                echo -e "  Schedule: ${GREEN}ACTIVE${NC} (Task Scheduler, every 1m)"
            else
                echo -e "  Schedule: ${YELLOW}NOT CONFIGURED${NC} (run 'autopilot setup')"
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
        echo -e "${GREEN}Autopilot enabled.${NC} Polling every 1 minute."
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
                    if session_is_alive "$worktree"; then
                        waiting_marker="$AUTOPILOT_DIR/markers/${worktree}.waiting"
                        if [ -f "$waiting_marker" ]; then
                            if [ "$HAS_TMUX" = true ]; then
                                echo -e "      Session:  ${YELLOW}NEEDS INPUT${NC}  ← tmux a -t $worktree"
                            else
                                echo -e "      Session:  ${YELLOW}NEEDS INPUT${NC}  (check logs/${worktree}-claude.log)"
                            fi
                            echo -e "      Question: $(cat "$waiting_marker" | head -1)"
                        else
                            echo -e "      Session:  ${GREEN}ALIVE${NC}"
                        fi
                    else
                        echo -e "      Session:  ${RED}DEAD${NC}"
                    fi
                elif [ "$pstatus" = "failed" ]; then
                    ticket=$(echo "$state" | jq -r '.ticket')
                    echo -e "  ${CYAN}$project${NC} ${DIM}($jira_proj)${NC} — ${RED}FAILED${NC} ($ticket)"
                    echo -e "      Run: ${DIM}autopilot reset $project${NC} to retry"
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

    stop)
        project_name="${2:-}"
        if [ -z "$project_name" ]; then
            echo "Usage: autopilot stop <project-name>"
            echo ""
            echo "Stops the active ticket: kills Claude session, removes worktree + branch, resets state."
            exit 1
        fi

        state_file="$AUTOPILOT_DIR/state/${project_name}.json"
        if [ ! -f "$state_file" ] || [ "$(jq -r '.status' "$state_file" 2>/dev/null)" != "working" ]; then
            echo -e "${YELLOW}$project_name is not working on anything.${NC}"
            exit 0
        fi

        ticket=$(jq -r '.ticket' "$state_file")
        worktree=$(jq -r '.worktree_name' "$state_file")
        worktree_path=$(jq -r '.worktree_path' "$state_file")

        echo -e "${YELLOW}Stopping $ticket ($worktree)...${NC}"

        if [ "$HAS_TMUX" = true ]; then
            # Kill Claude in tmux pane
            tmux send-keys -t "$worktree:1" C-c 2>/dev/null
            sleep 1
            # Kill tmux session
            tmux kill-session -t "$worktree" 2>/dev/null && echo "  Killed tmux session" || echo "  No tmux session found"
        else
            # Kill background processes via PID files
            for pidfile in "$PIDS_DIR/${worktree}"-*.pid; do
                [ -f "$pidfile" ] || continue
                local pid
                pid=$(cat "$pidfile" 2>/dev/null || echo "")
                if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                    kill "$pid" 2>/dev/null && echo "  Killed process $pid ($(basename "$pidfile" .pid))"
                fi
                rm -f "$pidfile"
            done
        fi

        # Remove worktree and branch
        if [ -d "$worktree_path" ]; then
            git -C "$worktree_path" worktree remove "$worktree_path" --force 2>/dev/null || \
                rm -rf "$worktree_path" 2>/dev/null
            echo "  Removed worktree"
        fi

        # Load project config for the main repo path
        if [ -f "$PROJECTS_DIR/${project_name}.env" ]; then
            # shellcheck source=/dev/null
            source "$PROJECTS_DIR/${project_name}.env" 2>/dev/null
            git -C "${PROJECT_DIR:-}" branch -D "$worktree" 2>/dev/null && echo "  Deleted branch" || true
            git -C "${PROJECT_DIR:-}" worktree prune 2>/dev/null
        fi

        # Clean markers
        rm -f "$AUTOPILOT_DIR/markers/${worktree}".{done,failed,exit_code} 2>/dev/null
        rm -f "$AUTOPILOT_DIR/prompts/${worktree}".{sh,md} 2>/dev/null

        # Reset state
        echo '{"status":"idle"}' > "$state_file"
        rm -f "$AUTOPILOT_DIR/state/${project_name}.lock"

        echo -e "${GREEN}Stopped. $project_name is idle.${NC}"
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
        echo "  stop <project>     Stop active ticket (kill session, remove worktree, reset)"
        echo "  logs [project] [N] Show last N log lines"
        echo "  history [project]  Show completed/failed tickets"
        echo "  reset <project>    Reset state to idle (without cleanup)"
        echo "  reset --all        Reset all projects"
        ;;
esac
