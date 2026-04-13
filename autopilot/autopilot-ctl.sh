#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# =============================================================================
# Autopilot Control Script (multi-project, cross-platform)
# Usage: autopilot <command> [args]
#
# State is stored in unified metadata files: projects/<project>.state.json
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

# --- Metadata helpers ---
meta_file_for() {
    local project="$1"
    echo "$PROJECTS_DIR/${project}.state.json"
}

meta_read_project() {
    local project="$1"
    local mf
    mf=$(meta_file_for "$project")
    if [ -f "$mf" ]; then
        cat "$mf"
    else
        echo '{"status":"idle","current":null,"history":[],"picker_decisions":[],"lock_pid":null}'
    fi
}

meta_write_project() {
    local project="$1"
    local json="$2"
    local mf
    mf=$(meta_file_for "$project")
    mkdir -p "$(dirname "$mf")"
    echo "$json" > "${mf}.tmp" && mv "${mf}.tmp" "$mf"
}

# Check if a session (tmux or background PID) is alive
session_is_alive() {
    local worktree="$1"
    if [ "$HAS_TMUX" = true ]; then
        tmux has-session -t "$worktree" 2>/dev/null && return 0
    fi
    # On Windows with WT tabs: if metadata still says "working", launcher hasn't
    # updated yet, meaning Claude is still running in the tab.
    local os
    os=$(detect_os)
    if [ "$os" = "windows" ]; then
        # The launcher script updates metadata when Claude exits.
        # If we're checking liveness, the caller already knows status is "working".
        return 0
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
    meta_read_project "$project"
}

project_history_counts() {
    local project="$1"
    local meta
    meta=$(meta_read_project "$project")
    local completed failed
    completed=$(echo "$meta" | jq '[.history[] | select(.outcome == "completed")] | length')
    failed=$(echo "$meta" | jq '[.history[] | select(.outcome == "failed")] | length')
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
        for meta_file in "$PROJECTS_DIR/"*.state.json; do
            [ -f "$meta_file" ] || continue
            s=$(jq -r '.status' "$meta_file" 2>/dev/null || echo "")
            if [ "$s" = "working" ]; then
                t=$(jq -r '.current.ticket' "$meta_file")
                p=$(basename "$meta_file" .state.json)
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
                    ticket=$(echo "$state" | jq -r '.current.ticket')
                    worktree=$(echo "$state" | jq -r '.current.worktree_name')
                    started=$(echo "$state" | jq -r '.current.started_at')

                    echo -e "  ${CYAN}$project${NC} ${DIM}($jira_proj)${NC} — ${GREEN}WORKING${NC}"
                    echo "      Ticket:   $ticket"
                    echo "      Worktree: $worktree"
                    echo "      Started:  $started"
                    if session_is_alive "$worktree"; then
                        echo -e "      Session:  ${GREEN}ALIVE${NC}"
                    else
                        echo -e "      Session:  ${RED}DEAD${NC}"
                    fi
                elif [ "$pstatus" = "pending_assignment" ]; then
                    ticket=$(echo "$state" | jq -r '.current.ticket')
                    pr_url=$(echo "$state" | jq -r '.current.pr_url // "?"')
                    echo -e "  ${CYAN}$project${NC} ${DIM}($jira_proj)${NC} — ${BLUE}AWAITING CI/REVIEW${NC}"
                    echo "      Ticket:   $ticket"
                    echo -e "      PR:       ${DIM}$pr_url${NC}"
                elif [ "$pstatus" = "failed" ]; then
                    last_ticket=$(echo "$state" | jq -r '.history[-1].ticket // "unknown"')
                    echo -e "  ${CYAN}$project${NC} ${DIM}($jira_proj)${NC} — ${RED}FAILED${NC} ($last_ticket)"
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
        meta=$(meta_read_project "$project_name")
        s=$(echo "$meta" | jq -r '.status')
        if [ "$s" = "working" ]; then
            echo -e "${RED}Project '$project_name' is currently working on a ticket.${NC}"
            echo "Run 'autopilot reset $project_name' first, or wait for it to finish."
            exit 1
        fi

        rm -f "$target"
        echo -e "${GREEN}Removed project '$project_name'.${NC}"
        echo -e "${DIM}State and history preserved in $(meta_file_for "$project_name")${NC}"
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
                    ticket=$(echo "$state" | jq -r '.current.ticket')
                    echo -e "  ${CYAN}$p${NC} ${DIM}($jira_proj)${NC} — ${GREEN}working on $ticket${NC}"
                else
                    echo -e "  ${CYAN}$p${NC} ${DIM}($jira_proj)${NC} — ${YELLOW}idle${NC}"
                fi
            done
        fi
        ;;

    run)
        project_name="${2:-}"
        force_flag=""
        # Check for --force in any position
        for arg in "$@"; do
            [ "$arg" = "--force" ] && force_flag="--force"
        done
        # Strip --force from project_name if it was $2
        [ "$project_name" = "--force" ] && project_name="${3:-}"

        if [ -n "$project_name" ]; then
            config="$PROJECTS_DIR/${project_name}.env"
            if [ ! -f "$config" ]; then
                echo -e "${RED}Project '$project_name' not found.${NC}"
                exit 1
            fi
            echo -e "${BLUE}Running autopilot cycle for $project_name...${NC}"
            AUTOPILOT_CONF="$config" "$AUTOPILOT_DIR/autopilot.sh" $force_flag
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
            projects_to_show="$project_name"
        else
            projects_to_show=$(list_projects)
        fi

        has_any=false
        while read -r p; do
            [ -z "$p" ] && continue
            meta=$(meta_read_project "$p")
            history_len=$(echo "$meta" | jq '.history | length')
            if [ "$history_len" -gt 0 ]; then
                has_any=true
                echo "$meta" | jq -r --arg proj "$p" '.history[] | "\(.outcome)\t\(.ticket)\t\($proj)\t\(.completed_at // "?")\t\(.details // "N/A")"' | \
                while IFS=$'\t' read -r h_outcome h_ticket h_project h_completed h_details; do
                    if [ "$h_outcome" = "completed" ]; then
                        echo -e "  ${GREEN}$h_ticket${NC} ${DIM}($h_project)${NC} — completed ($h_completed)"
                        echo "    PR: $h_details"
                    else
                        echo -e "  ${RED}$h_ticket${NC} ${DIM}($h_project)${NC} — failed ($h_completed)"
                        echo "    Reason: $h_details"
                    fi
                    echo ""
                done
            fi
        done <<< "$projects_to_show"
        if [ "$has_any" = false ]; then
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

        meta=$(meta_read_project "$project_name")
        pstatus=$(echo "$meta" | jq -r '.status')
        if [ "$pstatus" != "working" ]; then
            echo -e "${YELLOW}$project_name is not working on anything.${NC}"
            exit 0
        fi

        ticket=$(echo "$meta" | jq -r '.current.ticket')
        worktree=$(echo "$meta" | jq -r '.current.worktree_name')
        worktree_path=$(echo "$meta" | jq -r '.current.worktree_path')

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

        # Clean up any leftover prompt files
        rm -f "$AUTOPILOT_DIR/prompts/${worktree}".{sh,md} 2>/dev/null

        # Update metadata: add to history as stopped, set idle
        meta_write_project "$project_name" "$(echo "$meta" | jq \
            --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            '.status = "idle" | .history += [.current + {outcome: "failed", details: "Manually stopped", completed_at: $now}] | .current = null')"

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
            for mf in "$PROJECTS_DIR/"*.state.json; do
                [ -f "$mf" ] || continue
                p=$(basename "$mf" .state.json)
                meta=$(cat "$mf")
                # Preserve history, just reset status and current
                meta_write_project "$p" "$(echo "$meta" | jq '.status = "idle" | .current = null | .lock_pid = null')"
            done
        else
            echo -e "${YELLOW}Resetting $project_name to idle...${NC}"
            meta=$(meta_read_project "$project_name")
            meta_write_project "$project_name" "$(echo "$meta" | jq '.status = "idle" | .current = null | .lock_pid = null')"
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
        echo "  run [project] [--force]  Run one cycle (--force ignores worktree limit)"
        echo "  stop <project>     Stop active ticket (kill session, remove worktree, reset)"
        echo "  logs [project] [N] Show last N log lines"
        echo "  history [project]  Show completed/failed tickets"
        echo "  reset <project>    Reset state to idle (without cleanup)"
        echo "  reset --all        Reset all projects"
        ;;
esac
