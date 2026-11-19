#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# =============================================================================
# Conductor Control Script (multi-project, cross-platform)
# Usage: conductor <command> [args]
#
# State is stored in unified metadata files: projects/<project>.state.json
# =============================================================================

CONDUCTOR_DIR="$HOME/.config/conductor"
PROJECTS_DIR="$CONDUCTOR_DIR/projects"
ENABLED_FILE="$CONDUCTOR_DIR/enabled"
SERVICE_NAME="conductor"

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
PIDS_DIR="$CONDUCTOR_DIR/pids"

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

# Collect a PID and all of its descendants (depth-first). Echoes one PID per line.
# Needed because a dev server is a tree: bun → node → next-server. Only the node's
# argv embeds the worktree path; the next-server child (the actual CPU hog) shows
# argv "next-server (vX)" with no path, so it must be reached via the parent.
_descendant_pids() {
    local root="$1"
    echo "$root"
    local child
    for child in $(pgrep -P "$root" 2>/dev/null || true); do
        _descendant_pids "$child"
    done
}

# Kill any lingering processes tied to a worktree (dev servers, file watchers, etc.)
# that aren't tracked by tmux or PID files. Dev servers started with `bun run dev`
# reparent to launchd/init (PPID 1), so killing the tmux session never reaches them.
#
# Finds "seed" processes two ways, then kills each seed's entire subtree:
#   1. Command line referencing the worktree path — catches the node process whose
#      argv embeds the absolute worktree path. Survives even after the worktree
#      directory has been deleted (the orphan case).
#   2. Current working directory at/under the worktree — catches bun/next-server
#      that don't name the path in argv (only while the directory still exists).
# Subtree expansion then reaches the next-server child in the orphan case where its
# directory is gone and only its node parent could be matched by argv.
# Safe under `set -euo pipefail`: every step is guarded with `|| true`.
kill_worktree_procs() {
    local wt_path="$1"
    [ -n "$wt_path" ] || return 0

    # Resolve the real path too, so cwd matching survives symlinked parents
    # (e.g. macOS /var -> /private/var).
    local wt_real="$wt_path"
    if [ -d "$wt_path" ]; then
        wt_real=$(cd "$wt_path" 2>/dev/null && pwd -P 2>/dev/null || echo "$wt_path")
    fi

    local seeds=""

    # 1. By command line (works post-deletion).
    seeds=$(pgrep -f "$wt_path" 2>/dev/null || true)

    # 2. By cwd (only meaningful while the directory exists), matching either the
    #    given path or its resolved real path.
    if [ -d "$wt_path" ]; then
        local cwd_pids
        cwd_pids=$(lsof -a -d cwd -F pn 2>/dev/null | awk -v d1="$wt_path" -v d2="$wt_real" '
            /^p/{ pid=substr($0,2) }
            /^n/{ p=substr($0,2);
                  if (p==d1 || index(p, d1"/")==1 || p==d2 || index(p, d2"/")==1) print pid }' || true)
        seeds=$(printf '%s\n%s\n' "$seeds" "$cwd_pids")
    fi

    # Normalize seeds: numeric, unique, excluding this script's own PID.
    seeds=$(echo "$seeds" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u | grep -v "^$$\$" || true)
    [ -z "$seeds" ] && return 0

    # Expand each seed to its full subtree (reaches next-server children), then
    # re-dedupe and drop our own PID again.
    local pids="" s
    for s in $seeds; do
        pids="$pids
$(_descendant_pids "$s")"
    done
    pids=$(echo "$pids" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u | grep -v "^$$\$" || true)
    [ -z "$pids" ] && return 0

    # Graceful TERM first, then SIGKILL any straggler (next-server can ignore TERM
    # while mid-compile under turbopack).
    echo "$pids" | xargs kill 2>/dev/null || true
    sleep 1
    local p
    for p in $pids; do
        kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null || true
    done

    local n
    n=$(echo "$pids" | grep -c . || true)
    echo "    killed $n lingering worktree process(es)"
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
            local task_name="Conductor-${SERVICE_NAME}"
            local vbs_path="$CONDUCTOR_DIR/conductor-runner.vbs"
            if [ ! -f "$vbs_path" ]; then
                local runner_win
                runner_win=$(cygpath -w "$CONDUCTOR_DIR/conductor-runner.sh" 2>/dev/null)
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
            local task_name="Conductor-${SERVICE_NAME}"
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
                echo -e "  Schedule: ${YELLOW}NOT LOADED${NC} (run 'conductor setup')"
            fi
            ;;
        linux)
            if systemctl --user is-active "${SERVICE_NAME}.timer" &>/dev/null; then
                local interval
                interval=$(systemctl --user show "${SERVICE_NAME}.timer" -p TriggerLimitIntervalSec --value 2>/dev/null || echo "300s")
                echo -e "  Schedule: ${GREEN}ACTIVE${NC} (systemd, every ${interval})"
            else
                echo -e "  Schedule: ${YELLOW}INACTIVE${NC} (run 'conductor setup')"
            fi
            ;;
        windows)
            local task_name="Conductor-${SERVICE_NAME}"
            if schtasks.exe //Query //TN "$task_name" &>/dev/null; then
                echo -e "  Schedule: ${GREEN}ACTIVE${NC} (Task Scheduler, every 1m)"
            else
                echo -e "  Schedule: ${YELLOW}NOT CONFIGURED${NC} (run 'conductor setup')"
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
        echo -e "${GREEN}Conductor enabled.${NC} Polling every 1 minute."
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
        echo -e "${YELLOW}Conductor disabled.${NC}"
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
        echo -e "${BLUE}=== Conductor Status ===${NC}"
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
            echo -e "  ${YELLOW}No projects configured.${NC} Run 'conductor add <name>' to add one."
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
                    echo -e "      Run: ${DIM}conductor reset $project${NC} to retry"
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
            echo "Usage: conductor add <project-name>"
            echo ""
            echo "Creates a new project config from the template."
            echo "Example: conductor add my-project"
            exit 1
        fi

        mkdir -p "$PROJECTS_DIR"
        target="$PROJECTS_DIR/${project_name}.env"

        if [ -f "$target" ]; then
            echo -e "${YELLOW}Project '$project_name' already exists:${NC} $target"
            exit 1
        fi

        cp "$CONDUCTOR_DIR/config.env.example" "$target"
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
            echo "Usage: conductor remove <project-name>"
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
            echo "Run 'conductor reset $project_name' first, or wait for it to finish."
            exit 1
        fi

        rm -f "$target"
        echo -e "${GREEN}Removed project '$project_name'.${NC}"
        echo -e "${DIM}State and history preserved in $(meta_file_for "$project_name")${NC}"
        ;;

    list)
        projects=$(list_projects)
        if [ -z "$projects" ]; then
            echo "No projects configured. Run 'conductor add <name>' to add one."
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
        ticket_url=""
        # Check for --force and ticket URL in any position
        for arg in "${@:2}"; do
            [ "$arg" = "--force" ] && force_flag="--force" && continue
            [[ "$arg" == http* ]] && ticket_url="$arg" && continue
        done
        # Strip flags from project_name if it was $2
        [ "$project_name" = "--force" ] && project_name="${3:-}"
        [[ "$project_name" == http* ]] && ticket_url="$project_name" && project_name="${3:-}"

        if [ -n "$project_name" ]; then
            config="$PROJECTS_DIR/${project_name}.env"
            if [ ! -f "$config" ]; then
                echo -e "${RED}Project '$project_name' not found.${NC}"
                exit 1
            fi
            if [ -n "$ticket_url" ]; then
                echo -e "${BLUE}Running conductor for $project_name with ticket: $ticket_url${NC}"
                CONDUCTOR_CONF="$config" "$CONDUCTOR_DIR/conductor.sh" $force_flag --ticket "$ticket_url"
            else
                echo -e "${BLUE}Running conductor cycle for $project_name...${NC}"
                CONDUCTOR_CONF="$config" "$CONDUCTOR_DIR/conductor.sh" $force_flag
            fi
        else
            echo -e "${BLUE}Running conductor cycle for all projects...${NC}"
            "$CONDUCTOR_DIR/conductor-runner.sh"
        fi
        ;;

    logs)
        project_name="${2:-}"
        lines="${3:-50}"
        if [ -n "$project_name" ]; then
            log_file="$CONDUCTOR_DIR/logs/${project_name}.log"
        else
            # Show most recent log across all projects
            log_file=$(ls -t "$CONDUCTOR_DIR/logs/"*.log 2>/dev/null | head -1 || true)
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
            echo "Usage: conductor stop <project-name>"
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

        # Kill lingering worktree processes (dev servers, watchers) untracked above.
        kill_worktree_procs "$worktree_path"

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
        rm -f "$CONDUCTOR_DIR/prompts/${worktree}".{sh,md} 2>/dev/null

        # Update metadata: add to history as stopped, set idle
        meta_write_project "$project_name" "$(echo "$meta" | jq \
            --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            '.status = "idle" | .history += [.current + {outcome: "failed", details: "Manually stopped", completed_at: $now}] | .current = null')"

        echo -e "${GREEN}Stopped. $project_name is idle.${NC}"
        ;;

    reset)
        project_name="${2:-}"
        if [ -z "$project_name" ]; then
            echo "Usage: conductor reset <project-name>"
            echo "  Or:  conductor reset --all"
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

    prune)
        # Bulk-clean finished worktrees + orphan session dirs.
        #   conductor prune                  — all projects, interactive
        #   conductor prune <project>        — single project, interactive
        #   conductor prune [--yes|-y]       — skip confirmation
        #   conductor prune [--dry-run|-n]   — preview only
        #   conductor prune [--include-failed] — also prune state=failed (default: skip)
        project_filter=""
        auto_yes=false
        dry_run=false
        include_failed=false
        shift
        while [ $# -gt 0 ]; do
            case "$1" in
                --yes|-y)        auto_yes=true ;;
                --dry-run|-n)    dry_run=true ;;
                --include-failed) include_failed=true ;;
                --*)             echo "Unknown flag: $1" >&2; exit 1 ;;
                *)               project_filter="$1" ;;
            esac
            shift
        done

        # Build list of projects to scan
        projects_to_scan=()
        if [ -n "$project_filter" ]; then
            if [ ! -f "$PROJECTS_DIR/${project_filter}.env" ]; then
                echo -e "${RED}Unknown project: $project_filter${NC}" >&2
                exit 1
            fi
            projects_to_scan+=("$project_filter")
        else
            for envf in "$PROJECTS_DIR/"*.env; do
                [ -f "$envf" ] || continue
                projects_to_scan+=("$(basename "$envf" .env)")
            done
        fi

        # Collect prune candidates: lines of "project|ticket|state|reason|worktree_path|sessions_dir"
        candidates=()
        kept_count=0
        active_ticket_for=""  # "<project>:<ticket>" pairs we must skip

        for project in "${projects_to_scan[@]}"; do
            # shellcheck source=/dev/null
            ( : ); unset PROJECT_DIR WORKTREES_BASE BASE_BRANCH
            # shellcheck source=/dev/null
            source "$PROJECTS_DIR/${project}.env" 2>/dev/null || continue
            [ -n "${WORKTREES_BASE:-}" ] || continue

            # Determine the currently-active ticket (if any) so we never prune it
            meta=$(meta_read_project "$project")
            pstatus=$(echo "$meta" | jq -r '.status')
            active_ticket=""
            if [ "$pstatus" = "working" ]; then
                active_ticket=$(echo "$meta" | jq -r '.current.worktree_name // empty')
            fi

            sessions_root="$WORKTREES_BASE/.worktree-meta/sessions"
            [ -d "$sessions_root" ] || continue

            for sd in "$sessions_root"/*; do
                [ -d "$sd" ] || continue
                ticket=$(basename "$sd")

                # Never touch the live ticket
                if [ -n "$active_ticket" ] && [ "$ticket" = "$active_ticket" ]; then
                    kept_count=$((kept_count + 1))
                    continue
                fi

                # Skip base session dirs — they track the main repo, not a worktree.
                # Detected by meta.json:.worktree_path being outside $WORKTREES_BASE.
                if [ -f "$sd/meta.json" ]; then
                    meta_wt_path=$(jq -r '.worktree_path // empty' "$sd/meta.json" 2>/dev/null)
                    if [ -n "$meta_wt_path" ]; then
                        case "$meta_wt_path" in
                            "$WORKTREES_BASE"/*) ;;  # under WORKTREES_BASE → real worktree
                            *)
                                kept_count=$((kept_count + 1))
                                continue
                                ;;
                        esac
                    fi
                fi

                wt_path="$WORKTREES_BASE/$ticket"
                state=""
                if [ -f "$sd/conductor.json" ]; then
                    state=$(jq -r '.state // empty' "$sd/conductor.json" 2>/dev/null || echo "")
                fi

                reason=""
                if [ ! -d "$wt_path" ]; then
                    reason="orphan (no worktree dir)"
                else
                    case "$state" in
                        merged|closed)
                            reason="state=$state"
                            ;;
                        failed)
                            if [ "$include_failed" = true ]; then
                                reason="state=failed"
                            else
                                kept_count=$((kept_count + 1))
                                continue
                            fi
                            ;;
                        ""|null)
                            # No state recorded — orphan-ish if no live tmux session and no working flag
                            if [ "$HAS_TMUX" = true ] && tmux has-session -t "$ticket" 2>/dev/null; then
                                kept_count=$((kept_count + 1))
                                continue
                            fi
                            reason="no state recorded"
                            ;;
                        *)
                            kept_count=$((kept_count + 1))
                            continue
                            ;;
                    esac
                fi

                candidates+=("$project|$ticket|${state:-none}|$reason|$wt_path|$sd")
            done
        done

        if [ ${#candidates[@]} -eq 0 ]; then
            echo -e "${GREEN}Nothing to prune.${NC} ($kept_count kept)"
            exit 0
        fi

        # Show what we'd prune
        echo -e "${CYAN}Prune candidates:${NC}"
        printf "  %-12s %-50s %-10s %s\n" "PROJECT" "TICKET" "STATE" "REASON"
        for line in "${candidates[@]}"; do
            IFS='|' read -r p t s r _ _ <<< "$line"
            printf "  %-12s %-50s %-10s %s\n" "$p" "$t" "$s" "$r"
        done
        echo ""
        echo -e "${DIM}($kept_count kept · ${#candidates[@]} to prune)${NC}"

        if [ "$dry_run" = true ]; then
            echo -e "${YELLOW}--dry-run: not deleting anything.${NC}"
            exit 0
        fi

        if [ "$auto_yes" != true ]; then
            echo ""
            read -r -p "Proceed with deletion? [y/N] " confirm
            case "$confirm" in
                y|Y|yes|YES) ;;
                *) echo "Aborted."; exit 0 ;;
            esac
        fi

        # Execute prune
        pruned=0
        failed=0
        for line in "${candidates[@]}"; do
            IFS='|' read -r project ticket state reason wt_path sd <<< "$line"
            echo -e "${YELLOW}→ $project/$ticket${NC} ($reason)"

            # Re-source env to get PROJECT_DIR for this project
            unset PROJECT_DIR WORKTREES_BASE
            # shellcheck source=/dev/null
            source "$PROJECTS_DIR/${project}.env" 2>/dev/null || true

            # 1. Kill tmux session if any
            if [ "$HAS_TMUX" = true ] && tmux has-session -t "$ticket" 2>/dev/null; then
                tmux kill-session -t "$ticket" 2>/dev/null && echo "    killed tmux session"
            fi

            # 2. Kill PID files
            for pidfile in "$PIDS_DIR/${ticket}"-*.pid; do
                [ -f "$pidfile" ] || continue
                pid=$(cat "$pidfile" 2>/dev/null || echo "")
                if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                    kill "$pid" 2>/dev/null && echo "    killed pid $pid"
                fi
                rm -f "$pidfile"
            done

            # 2b. Kill lingering worktree processes (dev servers, watchers) that are
            #     untracked by tmux/PID files. Run BEFORE removing the dir so cwd
            #     matching works and git worktree remove isn't blocked by busy files.
            kill_worktree_procs "$wt_path"

            # 3. Remove worktree (if exists)
            if [ -d "$wt_path" ]; then
                if [ -n "${PROJECT_DIR:-}" ] && [ -d "$PROJECT_DIR" ]; then
                    git -C "$PROJECT_DIR" worktree remove "$wt_path" --force 2>/dev/null \
                        && echo "    removed worktree" \
                        || { rm -rf "$wt_path" 2>/dev/null && echo "    rm -rf'd worktree (worktree remove failed)"; }
                else
                    rm -rf "$wt_path" 2>/dev/null && echo "    rm -rf'd worktree"
                fi
            fi

            # 4. Delete branch
            if [ -n "${PROJECT_DIR:-}" ] && [ -d "$PROJECT_DIR" ]; then
                git -C "$PROJECT_DIR" branch -D "$ticket" 2>/dev/null && echo "    deleted branch" || true
                git -C "$PROJECT_DIR" worktree prune 2>/dev/null
            fi

            # 5. Remove session dir
            if [ -d "$sd" ]; then
                rm -rf "$sd" && echo "    removed session dir"
            fi

            # 6. Clean prompt files
            rm -f "$CONDUCTOR_DIR/prompts/${ticket}".{sh,md} 2>/dev/null

            pruned=$((pruned + 1))
        done

        echo ""
        echo -e "${GREEN}Pruned $pruned · kept $kept_count${NC}"
        [ $failed -gt 0 ] && echo -e "${RED}$failed failed${NC}"
        ;;

    setup)
        "$CONDUCTOR_DIR/setup.sh"
        ;;

    help|*)
        echo "Usage: conductor <command> [args]"
        echo ""
        echo "Global:"
        echo "  on                 Enable conductor (starts polling all projects)"
        echo "  off                Disable conductor"
        echo "  status             Show status of all projects"
        echo "  setup              Install scheduler for this OS"
        echo ""
        echo "Projects:"
        echo "  add <name>         Add a new project config"
        echo "  remove <name>      Remove a project config"
        echo "  list               List configured projects"
        echo ""
        echo "Execution:"
        echo "  run [project] [url] [--force]  Run cycle, optionally with a specific ticket URL"
        echo "  stop <project>     Stop active ticket (kill session, remove worktree, reset)"
        echo "  logs [project] [N] Show last N log lines"
        echo "  history [project]  Show completed/failed tickets"
        echo "  reset <project>    Reset state to idle (without cleanup)"
        echo "  reset --all        Reset all projects"
        echo "  prune [project]    Bulk-clean finished worktrees + orphan session dirs"
        echo "                     Flags: --yes, --dry-run, --include-failed"
        ;;
esac
