#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Autopilot - Autonomous Jira-to-PR Pipeline (project-agnostic)
# =============================================================================
# Polls Jira for tickets with a configured label, picks the oldest one,
# creates a worktree, launches Claude Code, and monitors completion.
#
# All project-specific config lives in config.env (not committed to dotfiles).
# Project-specific setup logic lives in the project's .autopilot/ directory.
#
# Usage: Called by launchd/systemd every 5 minutes, or manually.
# Control: Use autopilot-ctl (on|off|status|run)
# =============================================================================

# --- Configuration ---
AUTOPILOT_DIR="$HOME/.config/autopilot"
CONFIG_FILE="${AUTOPILOT_CONF:-}"
ENABLED_FILE="$AUTOPILOT_DIR/enabled"
PROMPT_TEMPLATE="$AUTOPILOT_DIR/claude-prompt-template.md"

# Load project-specific config
if [ -z "$CONFIG_FILE" ]; then
    # Legacy: single config.env fallback
    if [ -f "$AUTOPILOT_DIR/config.env" ]; then
        CONFIG_FILE="$AUTOPILOT_DIR/config.env"
    else
        echo "ERROR: No config file specified. Set AUTOPILOT_CONF or use 'autopilot add <project>'"
        exit 1
    fi
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Validate required config vars
for var in PROJECT_DIR JIRA_PROJECT JIRA_LABEL; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Required config variable '$var' is not set in $CONFIG_FILE"
        exit 1
    fi
done

# Derived defaults
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
WORKTREES_BASE="${WORKTREES_BASE:-$HOME/worktrees/$PROJECT_NAME}"
BASE_BRANCH="${BASE_BRANCH:-main}"
JIRA_CREDENTIALS_FILE="${JIRA_CREDENTIALS_FILE:-$PROJECT_DIR/.env.local}"
TMUX_SCRIPTS="${TMUX_SCRIPTS:-$HOME/.config/tmux/scripts}"
DEV_SERVER_CMD="${DEV_SERVER_CMD:-}"
INSTALL_CMD="${INSTALL_CMD:-}"
WORKTREE_SETUP_HOOK="${WORKTREE_SETUP_HOOK:-}"

# Per-project paths (isolated state per project)
STATE_FILE="$AUTOPILOT_DIR/state/${PROJECT_NAME}.json"
LOCK_FILE="$AUTOPILOT_DIR/state/${PROJECT_NAME}.lock"
HISTORY_DIR="$AUTOPILOT_DIR/history/${PROJECT_NAME}"
LOG_FILE="$AUTOPILOT_DIR/logs/${PROJECT_NAME}.log"

# Resolve Claude binary: config override > claude-patched > claude
if [ -z "${CLAUDE_BIN:-}" ]; then
    CLAUDE_BIN=$(command -v claude-patched 2>/dev/null || command -v claude 2>/dev/null || echo "")
    if [ -z "$CLAUDE_BIN" ]; then
        echo "ERROR: Could not find 'claude' or 'claude-patched' in PATH"
        exit 1
    fi
fi

# Detect default shell
USER_SHELL="${SHELL:-/bin/bash}"

# --- Logging ---
log() {
    local level="$1"; shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $*" >> "$LOG_FILE"
    [[ -t 1 ]] && echo "[$timestamp] [$level] $*"
}

# --- Lock Management ---
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log "INFO" "Another autopilot instance is running (PID: $pid). Exiting."
            exit 0
        else
            log "WARN" "Stale lock file found (PID: $pid). Removing."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

trap release_lock EXIT

# --- Jira API ---
load_jira_credentials() {
    if [ ! -f "$JIRA_CREDENTIALS_FILE" ]; then
        log "ERROR" "Jira credentials file not found: $JIRA_CREDENTIALS_FILE"
        exit 1
    fi
    JIRA_BASE_URL=$(grep '^JIRA_BASE_URL=' "$JIRA_CREDENTIALS_FILE" | head -1 | sed 's/^JIRA_BASE_URL=//' | sed 's|/$||')
    JIRA_EMAIL=$(grep '^JIRA_EMAIL=' "$JIRA_CREDENTIALS_FILE" | head -1 | sed 's/^JIRA_EMAIL=//')
    JIRA_API_TOKEN=$(grep '^JIRA_API_TOKEN=' "$JIRA_CREDENTIALS_FILE" | head -1 | sed 's/^JIRA_API_TOKEN=//')

    if [ -z "$JIRA_BASE_URL" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_API_TOKEN" ]; then
        log "ERROR" "Missing Jira credentials (JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN) in $JIRA_CREDENTIALS_FILE"
        exit 1
    fi
}

jira_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local args=(-s -w "\n%{http_code}" -X "$method"
        -H "Content-Type: application/json"
        -u "$JIRA_EMAIL:$JIRA_API_TOKEN"
        "${JIRA_BASE_URL}/rest/api/3${endpoint}")

    if [ -n "$data" ]; then
        args+=(-d "$data")
    fi

    curl "${args[@]}" 2>/dev/null
}

find_autopilot_ticket() {
    local jql="project = $JIRA_PROJECT AND labels = \"$JIRA_LABEL\" AND status = \"To Do\" ORDER BY created ASC"

    local search_body
    search_body=$(jq -n --arg jql "$jql" '{
        jql: $jql,
        maxResults: 1,
        fields: ["summary", "description", "issuetype", "priority", "status"]
    }')

    local response
    response=$(jira_api POST "/search/jql" "$search_body")

    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log "ERROR" "Jira search failed (HTTP $http_code): $body"
        return 1
    fi

    local issue_count
    issue_count=$(echo "$body" | jq -r '.issues | length')
    if [ "$issue_count" = "0" ] || [ "$issue_count" = "null" ]; then
        log "INFO" "No tickets found with label '$JIRA_LABEL' in To Do status."
        return 1
    fi

    TICKET_KEY=$(echo "$body" | jq -r '.issues[0].key')
    TICKET_SUMMARY=$(echo "$body" | jq -r '.issues[0].fields.summary')
    TICKET_TYPE=$(echo "$body" | jq -r '.issues[0].fields.issuetype.name')
    TICKET_PRIORITY=$(echo "$body" | jq -r '.issues[0].fields.priority.name')

    log "INFO" "Found ticket: $TICKET_KEY - $TICKET_SUMMARY ($TICKET_TYPE, $TICKET_PRIORITY)"
    return 0
}

transition_to_in_progress() {
    local ticket_key="$1"

    local response
    response=$(jira_api GET "/issue/$ticket_key/transitions")
    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log "ERROR" "Failed to get transitions for $ticket_key (HTTP $http_code)"
        return 1
    fi

    local transition_id
    transition_id=$(echo "$body" | jq -r '.transitions[] | select(.name | test("In Progress"; "i")) | .id' | head -1)

    if [ -z "$transition_id" ] || [ "$transition_id" = "null" ]; then
        log "WARN" "No 'In Progress' transition found for $ticket_key. Available:"
        echo "$body" | jq -r '.transitions[].name' >> "$LOG_FILE"
        return 1
    fi

    response=$(jira_api POST "/issue/$ticket_key/transitions" "{\"transition\":{\"id\":\"$transition_id\"}}")
    http_code=$(echo "$response" | tail -1)

    if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        log "INFO" "Transitioned $ticket_key to In Progress"
        return 0
    else
        log "ERROR" "Failed to transition $ticket_key (HTTP $http_code)"
        return 1
    fi
}

jira_comment() {
    local ticket_key="$1"
    local message="$2"

    local adf_body
    adf_body=$(jq -n --arg msg "$message" '{
        body: {
            version: 1,
            type: "doc",
            content: [{
                type: "paragraph",
                content: [{
                    type: "text",
                    text: $msg
                }]
            }]
        }
    }')

    local response
    response=$(jira_api POST "/issue/$ticket_key/comment" "$adf_body")
    local http_code
    http_code=$(echo "$response" | tail -1)

    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        log "INFO" "Commented on $ticket_key"
    else
        log "WARN" "Failed to comment on $ticket_key (HTTP $http_code)"
    fi
}

# --- Worktree Management ---
create_worktree_name() {
    local ticket_key="$1"
    local summary="$2"

    local slug
    slug=$(echo "$summary" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-40)

    echo "${ticket_key}-${slug}"
}

setup_worktree() {
    local worktree_name="$1"
    local branch_name="$worktree_name"
    local worktree_path="$WORKTREES_BASE/$worktree_name"

    if [ -d "$worktree_path" ]; then
        log "INFO" "Worktree already exists: $worktree_path"
        return 0
    fi

    # Fetch latest from remote
    cd "$PROJECT_DIR"
    git fetch origin "$BASE_BRANCH" 2>/dev/null || true

    log "INFO" "Creating worktree: $worktree_path (branch: $branch_name, base: $BASE_BRANCH)"
    git worktree add -b "$branch_name" "$worktree_path" "origin/$BASE_BRANCH" 2>&1 | while read -r line; do
        log "INFO" "git: $line"
    done

    if [ ! -d "$worktree_path" ]; then
        log "ERROR" "Failed to create worktree at $worktree_path"
        return 1
    fi

    # Run project-specific setup hook if configured (e.g., copy .env, generate configs)
    if [ -n "$WORKTREE_SETUP_HOOK" ] && [ -x "$WORKTREE_SETUP_HOOK" ]; then
        log "INFO" "Running worktree setup hook: $WORKTREE_SETUP_HOOK"
        WORKTREE_PATH="$worktree_path" \
        PROJECT_DIR="$PROJECT_DIR" \
        WORKTREE_NAME="$worktree_name" \
            "$WORKTREE_SETUP_HOOK" 2>&1 | while read -r line; do
                log "INFO" "hook: $line"
            done
    fi

    # Install dependencies if configured
    if [ -n "$INSTALL_CMD" ]; then
        log "INFO" "Installing dependencies: $INSTALL_CMD"
        cd "$worktree_path" && eval "$INSTALL_CMD" 2>&1 | tail -5 | while read -r line; do
            log "INFO" "install: $line"
        done
    fi

    log "INFO" "Worktree setup complete: $worktree_path"
    return 0
}

# --- Tmux & Server ---
# Delegates to existing create-worktree-session.sh which handles:
#   - tmux session creation (3 tabs: claude, server, commands)
#   - port generation via worktree-metadata.sh
#   - metadata persistence
# Falls back to a simple tmux session if the script is not available.
setup_session() {
    local worktree_name="$1"
    local worktree_path="$WORKTREES_BASE/$worktree_name"

    if tmux has-session -t "$worktree_name" 2>/dev/null; then
        log "INFO" "Tmux session already exists: $worktree_name"
        return 0
    fi

    if [ -x "$TMUX_SCRIPTS/create-worktree-session.sh" ]; then
        log "INFO" "Creating tmux session via create-worktree-session.sh"
        "$TMUX_SCRIPTS/create-worktree-session.sh" "$worktree_name" "$worktree_path"
    else
        log "INFO" "Creating tmux session manually: $worktree_name"
        tmux new-session -s "$worktree_name" -n "claude" -c "$worktree_path" -d "cd '$worktree_path' && exec $USER_SHELL"
        tmux new-window -t "$worktree_name:2" -n "server" -c "$worktree_path" "cd '$worktree_path' && exec $USER_SHELL"
        tmux new-window -t "$worktree_name:3" -n "commands" -c "$worktree_path" "cd '$worktree_path' && exec $USER_SHELL"
        tmux select-window -t "$worktree_name:1"
    fi

    return 0
}

resolve_port() {
    local worktree_name="$1"

    # Try to get port from worktree metadata (set by create-worktree-session.sh)
    if [ -x "$TMUX_SCRIPTS/worktree-metadata.sh" ]; then
        source "$TMUX_SCRIPTS/worktree-metadata.sh" 2>/dev/null || true
        if type get_session_metadata &>/dev/null; then
            local port
            port=$(get_session_metadata "$PROJECT_NAME" "$worktree_name" "port")
            if [ -n "$port" ] && [ "$port" != "null" ]; then
                echo "$port"
                return 0
            fi
        fi
    fi

    # Fallback: derive from name hash
    local hash
    hash=$(echo -n "$worktree_name" | cksum | awk '{print $1 % 1001}')
    echo $((55000 + hash))
}

start_dev_server() {
    local worktree_name="$1"

    if [ -z "$DEV_SERVER_CMD" ]; then
        log "INFO" "No DEV_SERVER_CMD configured, skipping server start."
        return 0
    fi

    # Send command as-is to tmux — variables like $SERVER_PORT are
    # already set in the pane's env by create-worktree-session.sh
    log "INFO" "Starting dev server: $DEV_SERVER_CMD"
    tmux send-keys -t "$worktree_name:2" "$DEV_SERVER_CMD" Enter

    sleep 3
}

# --- Claude Launch ---
generate_prompt() {
    local ticket_key="$1"
    local worktree_name="$2"
    local worktree_path="$WORKTREES_BASE/$worktree_name"
    local port="${3:-3000}"
    local prompt_file="$AUTOPILOT_DIR/prompts/${worktree_name}.md"

    mkdir -p "$AUTOPILOT_DIR/prompts"

    if [ ! -f "$PROMPT_TEMPLATE" ]; then
        log "ERROR" "Prompt template not found: $PROMPT_TEMPLATE"
        return 1
    fi

    sed -e "s|{{TICKET_KEY}}|$ticket_key|g" \
        -e "s|{{TICKET_SUMMARY}}|$TICKET_SUMMARY|g" \
        -e "s|{{TICKET_TYPE}}|$TICKET_TYPE|g" \
        -e "s|{{TICKET_PRIORITY}}|$TICKET_PRIORITY|g" \
        -e "s|{{WORKTREE_NAME}}|$worktree_name|g" \
        -e "s|{{WORKTREE_PATH}}|$worktree_path|g" \
        -e "s|{{SERVER_PORT}}|$port|g" \
        -e "s|{{BASE_BRANCH}}|$BASE_BRANCH|g" \
        -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
        -e "s|{{JIRA_PROJECT}}|$JIRA_PROJECT|g" \
        -e "s|{{COMPLETION_MARKER}}|$AUTOPILOT_DIR/markers/${worktree_name}.done|g" \
        -e "s|{{FAILURE_MARKER}}|$AUTOPILOT_DIR/markers/${worktree_name}.failed|g" \
        "$PROMPT_TEMPLATE" > "$prompt_file"

    echo "$prompt_file"
}

launch_claude() {
    local worktree_name="$1"
    local prompt_file="$2"
    local worktree_path="$WORKTREES_BASE/$worktree_name"

    mkdir -p "$AUTOPILOT_DIR/markers"

    # Write a launcher script — avoids tmux send-keys length limits
    # Uses interactive mode so you get the full Claude TUI
    local launcher="$AUTOPILOT_DIR/prompts/${worktree_name}.sh"
    cat > "$launcher" << LAUNCHER
#!/usr/bin/env bash
cd '$worktree_path'
$CLAUDE_BIN --dangerously-skip-permissions "\$(cat '$prompt_file')"
echo \$? > '$AUTOPILOT_DIR/markers/${worktree_name}.exit_code'
LAUNCHER
    chmod +x "$launcher"

    log "INFO" "Launching Claude Code in tmux pane $worktree_name:1"
    tmux send-keys -t "$worktree_name:1" "$launcher" Enter

    log "INFO" "Claude launched. Monitoring via markers."
}

# --- State Management ---
read_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo '{"status":"idle"}'
    fi
}

write_state() {
    local status="$1"
    shift
    local json

    case "$status" in
        idle)
            json='{"status":"idle"}'
            ;;
        working)
            local ticket="$1" worktree_name="$2" worktree_path="$3" port="$4"
            json=$(jq -n \
                --arg status "working" \
                --arg ticket "$ticket" \
                --arg worktree_name "$worktree_name" \
                --arg worktree_path "$worktree_path" \
                --arg port "$port" \
                --arg project "$PROJECT_NAME" \
                --arg started_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                --arg pid "$$" \
                '{status: $status, ticket: $ticket, worktree_name: $worktree_name, worktree_path: $worktree_path, port: ($port | tonumber), project: $project, started_at: $started_at, pid: ($pid | tonumber)}')
            ;;
    esac

    echo "$json" > "$STATE_FILE"
}

save_history() {
    local ticket="$1"
    local outcome="$2"
    local details="${3:-}"
    local worktree_name="${4:-}"

    local state
    state=$(read_state)

    jq -n \
        --arg ticket "$ticket" \
        --arg outcome "$outcome" \
        --arg details "$details" \
        --arg worktree_name "$worktree_name" \
        --arg project "$PROJECT_NAME" \
        --arg completed_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson state "$state" \
        '{ticket: $ticket, outcome: $outcome, details: $details, worktree_name: $worktree_name, project: $project, completed_at: $completed_at, started_at: ($state.started_at // "unknown")}' \
        > "$HISTORY_DIR/${ticket}.json"
}

# --- Check Active Work ---
check_active_work() {
    local state
    state=$(read_state)
    local status
    status=$(echo "$state" | jq -r '.status')

    if [ "$status" != "working" ]; then
        return 1
    fi

    local ticket worktree_name
    ticket=$(echo "$state" | jq -r '.ticket')
    worktree_name=$(echo "$state" | jq -r '.worktree_name')

    log "INFO" "Checking active work: $ticket ($worktree_name)"

    # Check for completion marker
    if [ -f "$AUTOPILOT_DIR/markers/${worktree_name}.done" ]; then
        log "INFO" "$ticket completed successfully!"
        local result
        result=$(cat "$AUTOPILOT_DIR/markers/${worktree_name}.done")
        save_history "$ticket" "completed" "$result" "$worktree_name"
        rm -f "$AUTOPILOT_DIR/markers/${worktree_name}".{done,exit_code,failed}
        write_state "idle"
        log "INFO" "State reset to idle. Ready for next ticket."
        return 0
    fi

    # Check for failure marker
    if [ -f "$AUTOPILOT_DIR/markers/${worktree_name}.failed" ]; then
        local reason
        reason=$(cat "$AUTOPILOT_DIR/markers/${worktree_name}.failed")
        log "WARN" "$ticket failed: $reason"
        jira_comment "$ticket" "Autopilot encountered an issue and could not complete this ticket automatically. Keeping in progress for manual review. Reason: $reason"
        save_history "$ticket" "failed" "$reason" "$worktree_name"
        rm -f "$AUTOPILOT_DIR/markers/${worktree_name}".{done,exit_code,failed}
        write_state "idle"
        return 0
    fi

    # Check if exit code file exists (Claude process ended)
    if [ -f "$AUTOPILOT_DIR/markers/${worktree_name}.exit_code" ]; then
        local exit_code
        exit_code=$(cat "$AUTOPILOT_DIR/markers/${worktree_name}.exit_code")

        if [ "$exit_code" = "0" ]; then
            log "WARN" "$ticket: Claude exited (code 0) but no completion marker found"
            jira_comment "$ticket" "Autopilot: Claude process completed but no explicit completion marker was written. Please review the worktree at $WORKTREES_BASE/$worktree_name"
        else
            log "WARN" "$ticket: Claude exited with code $exit_code"
            jira_comment "$ticket" "Autopilot encountered an issue (exit code: $exit_code). Keeping in progress for manual review. Worktree: $WORKTREES_BASE/$worktree_name"
        fi
        save_history "$ticket" "failed" "Exit code: $exit_code" "$worktree_name"
        rm -f "$AUTOPILOT_DIR/markers/${worktree_name}.exit_code"
        write_state "idle"
        return 0
    fi

    # Check if tmux session is still alive
    if ! tmux has-session -t "$worktree_name" 2>/dev/null; then
        log "WARN" "Tmux session $worktree_name died unexpectedly"
        jira_comment "$ticket" "Autopilot: Session terminated unexpectedly. Keeping in progress for manual review."
        save_history "$ticket" "failed" "Tmux session died" "$worktree_name"
        write_state "idle"
        return 0
    fi

    # Check for timeout (4 hours max)
    local started_at now_epoch started_epoch elapsed max_seconds
    started_at=$(echo "$state" | jq -r '.started_at')
    # Cross-platform epoch conversion
    if date -j &>/dev/null; then
        # macOS
        started_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" "+%s" 2>/dev/null || echo "0")
    else
        # Linux
        started_epoch=$(date -d "$started_at" "+%s" 2>/dev/null || echo "0")
    fi
    now_epoch=$(date "+%s")
    elapsed=$(( now_epoch - started_epoch ))
    max_seconds=$((4 * 3600))

    if [ "$elapsed" -gt "$max_seconds" ]; then
        log "WARN" "$ticket: Timed out after $(( elapsed / 3600 ))h $(( (elapsed % 3600) / 60 ))m"
        jira_comment "$ticket" "Autopilot: Timed out after $(( elapsed / 3600 )) hours. Keeping in progress for manual review."
        save_history "$ticket" "failed" "Timeout after ${elapsed}s" "$worktree_name"
        write_state "idle"
        return 0
    fi

    log "INFO" "$ticket still in progress ($(( elapsed / 60 ))m elapsed)"
    return 0
}

# --- Main Flow ---
main() {
    mkdir -p "$AUTOPILOT_DIR/logs" "$AUTOPILOT_DIR/markers" "$AUTOPILOT_DIR/prompts" "$AUTOPILOT_DIR/state" "$HISTORY_DIR"

    if [ ! -f "$ENABLED_FILE" ]; then
        [[ -t 1 ]] && log "INFO" "Autopilot is disabled. Run 'autopilot on' to enable."
        exit 0
    fi

    acquire_lock
    load_jira_credentials

    log "INFO" "=== Autopilot cycle started ($PROJECT_NAME) ==="

    local state
    state=$(read_state)
    local status
    status=$(echo "$state" | jq -r '.status')

    if [ "$status" = "working" ]; then
        check_active_work
        log "INFO" "=== Autopilot cycle complete ==="
        exit 0
    fi

    if ! find_autopilot_ticket; then
        log "INFO" "=== Autopilot cycle complete (no work) ==="
        exit 0
    fi

    log "INFO" "=== Starting work on $TICKET_KEY ==="

    if ! transition_to_in_progress "$TICKET_KEY"; then
        log "ERROR" "Could not transition $TICKET_KEY. Skipping."
        exit 1
    fi

    local worktree_name
    worktree_name=$(create_worktree_name "$TICKET_KEY" "$TICKET_SUMMARY")

    if ! setup_worktree "$worktree_name"; then
        log "ERROR" "Failed to create worktree for $TICKET_KEY"
        jira_comment "$TICKET_KEY" "Autopilot: Failed to create worktree. Keeping in progress for manual intervention."
        save_history "$TICKET_KEY" "failed" "Worktree creation failed" "$worktree_name"
        exit 1
    fi

    if ! setup_session "$worktree_name"; then
        log "ERROR" "Failed to create tmux session for $TICKET_KEY"
        jira_comment "$TICKET_KEY" "Autopilot: Failed to create tmux session."
        save_history "$TICKET_KEY" "failed" "Tmux session creation failed" "$worktree_name"
        exit 1
    fi

    # Port is resolved from worktree metadata (set by create-worktree-session.sh)
    local port
    port=$(resolve_port "$worktree_name")

    start_dev_server "$worktree_name"

    local prompt_file
    prompt_file=$(generate_prompt "$TICKET_KEY" "$worktree_name" "$port")
    launch_claude "$worktree_name" "$prompt_file"

    write_state "working" "$TICKET_KEY" "$worktree_name" "$WORKTREES_BASE/$worktree_name" "$port"

    jira_comment "$TICKET_KEY" "Autopilot: Started working on this ticket. Worktree: $worktree_name, Port: $port"

    log "INFO" "=== $TICKET_KEY dispatched to Claude. Will check on next cycle. ==="
}

main "$@"
