#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Conductor - Autonomous Jira-to-PR Pipeline (project-agnostic)
# =============================================================================
# Polls Jira for tickets with a configured label, picks the oldest one,
# creates a worktree, launches Claude Code, and monitors completion.
#
# All project-specific config lives in config.env (not committed to dotfiles).
# Project-specific setup logic lives in the project's .conductor/ directory.
#
# State is stored in a single metadata JSON file per project:
#   projects/<project>.state.json
#
# Usage: Called by launchd/systemd every 5 minutes, or manually.
# Control: Use conductor-ctl (on|off|status|run)
# =============================================================================

# --- Configuration ---
CONDUCTOR_DIR="$HOME/.config/conductor"
CONFIG_FILE="${CONDUCTOR_CONF:-}"
ENABLED_FILE="$CONDUCTOR_DIR/enabled"
PROMPT_TEMPLATE="$CONDUCTOR_DIR/claude-prompt-template.md"

# Load project-specific config
if [ -z "$CONFIG_FILE" ]; then
    # Legacy: single config.env fallback
    if [ -f "$CONDUCTOR_DIR/config.env" ]; then
        CONFIG_FILE="$CONDUCTOR_DIR/config.env"
    else
        echo "ERROR: No config file specified. Set CONDUCTOR_CONF or use 'conductor add <project>'"
        exit 1
    fi
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Tracker type: "jira" (default) or "clickup"
TRACKER="${TRACKER:-jira}"

# Validate required config vars based on tracker
if [ "$TRACKER" = "clickup" ]; then
    for var in PROJECT_DIR CLICKUP_API_TOKEN CLICKUP_TEAM_ID CLICKUP_TAG; do
        if [ -z "${!var:-}" ]; then
            echo "ERROR: Required config variable '$var' is not set in $CONFIG_FILE"
            exit 1
        fi
    done
else
    for var in PROJECT_DIR JIRA_PROJECT JIRA_LABEL; do
        if [ -z "${!var:-}" ]; then
            echo "ERROR: Required config variable '$var' is not set in $CONFIG_FILE"
            exit 1
        fi
    done
fi

# Derived defaults
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
WORKTREES_BASE="${WORKTREES_BASE:-$HOME/worktrees/$PROJECT_NAME}"
BASE_BRANCH="${BASE_BRANCH:-main}"
JIRA_CREDENTIALS_FILE="${JIRA_CREDENTIALS_FILE:-$PROJECT_DIR/.env.local}"
TMUX_SCRIPTS="${TMUX_SCRIPTS:-$HOME/.config/tmux/scripts}"
DEV_SERVER_CMD="${DEV_SERVER_CMD:-}"
INSTALL_CMD="${INSTALL_CMD:-}"
WORKTREE_SETUP_HOOK="${WORKTREE_SETUP_HOOK:-}"

# ClickUp defaults
CLICKUP_SPACE_IDS="${CLICKUP_SPACE_IDS:-}"
CLICKUP_TAG="${CLICKUP_TAG:-claude-conductor}"

# AI Picker defaults
AI_PICKER_ENABLED="${AI_PICKER_ENABLED:-true}"
PICKER_MODEL="${PICKER_MODEL:-sonnet}"

# Concurrency: max tickets worked on simultaneously
MAX_CONCURRENT_TICKETS="${MAX_CONCURRENT_TICKETS:-1}"

# Max worktrees per project — won't pick new tickets if this limit is reached
MAX_WORKTREES="${MAX_WORKTREES:-8}"

# Unified metadata file (single source of truth per project)
META_FILE="$CONDUCTOR_DIR/projects/${PROJECT_NAME}.state.json"
LOG_FILE="$CONDUCTOR_DIR/logs/${PROJECT_NAME}.log"

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

# --- Platform Detection ---
detect_platform() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Darwin)               echo "macos" ;;
        Linux)                echo "linux" ;;
        *)                    echo "unknown" ;;
    esac
}
PLATFORM=$(detect_platform)
HAS_TMUX=false
command -v tmux &>/dev/null && HAS_TMUX=true

# --- Logging ---
log() {
    local level="$1"; shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $*" >> "$LOG_FILE"
    [[ -t 1 ]] && echo "[$timestamp] [$level] $*"
}

# --- Unified Metadata Management ---
meta_read() {
    if [ -f "$META_FILE" ]; then
        cat "$META_FILE"
    else
        echo '{"status":"idle","current":null,"history":[],"picker_decisions":[],"lock_pid":null}'
    fi
}

meta_write() {
    local json="$1"
    mkdir -p "$(dirname "$META_FILE")"
    echo "$json" > "${META_FILE}.tmp" && mv "${META_FILE}.tmp" "$META_FILE"
}

meta_set_working() {
    local ticket="$1" ticket_url="$2" worktree_name="$3" worktree_path="$4" base_branch="$5"
    local meta
    meta=$(meta_read)
    meta_write "$(echo "$meta" | jq \
        --arg ticket "$ticket" \
        --arg ticket_url "$ticket_url" \
        --arg wt_name "$worktree_name" \
        --arg wt_path "$worktree_path" \
        --arg base "$base_branch" \
        --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '.status = "working" | .current = {ticket: $ticket, ticket_url: $ticket_url, worktree_name: $wt_name, worktree_path: $wt_path, base_branch: $base, started_at: $now}')"
}

meta_set_idle_from_completion() {
    local details="$1"
    local meta
    meta=$(meta_read)

    # Write /track entry before clearing current
    local ticket started_at
    ticket=$(echo "$meta" | jq -r '.current.ticket // empty')
    started_at=$(echo "$meta" | jq -r '.current.started_at // empty')
    if [ -n "$ticket" ] && [ -n "$started_at" ]; then
        track_time_entry "$ticket" "$started_at" "$details"
    fi

    meta_write "$(echo "$meta" | jq \
        --arg details "$details" \
        --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '.status = "idle" | .history += [.current + {outcome: "completed", details: $details, completed_at: $now}] | .current = null')"
}

# Write an entry to ~/.claude/time-track.md
# Duration = from started_at to now (includes working + CI/review + feedback loops)
track_time_entry() {
    local ticket="$1" started_at="$2" details="$3"
    local track_file="$HOME/.claude/time-track.md"
    local now_epoch started_epoch

    # Cross-platform epoch conversion
    if date -j &>/dev/null; then
        started_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" "+%s" 2>/dev/null || echo "0")
    else
        started_epoch=$(date -d "$started_at" "+%s" 2>/dev/null || echo "0")
    fi
    now_epoch=$(date "+%s")

    local elapsed_secs=$(( now_epoch - started_epoch ))
    local elapsed_hours=$(( elapsed_secs / 3600 ))
    local elapsed_mins=$(( (elapsed_secs % 3600) / 60 ))

    # Format duration
    local duration
    if [ "$elapsed_hours" -eq 0 ]; then
        duration="${elapsed_mins}m"
    elif [ "$elapsed_mins" -eq 0 ]; then
        duration="${elapsed_hours}h"
    else
        duration="${elapsed_hours}h${elapsed_mins}m"
    fi

    local today today_header time_now day_name
    today=$(date '+%Y-%m-%d')
    day_name=$(date '+%A')
    today_header="## $today ($day_name)"
    time_now=$(date '+%H:%M')

    # Extract PR number from details if it's a URL
    local activity="Conductor: $ticket"
    local pr_num
    pr_num=$(echo "$details" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+')
    [ -n "$pr_num" ] && activity="Conductor: $ticket -> PR #$pr_num"

    # Create file if it doesn't exist
    if [ ! -f "$track_file" ]; then
        cat > "$track_file" << 'EOF'
# Time Track

A running log of daily work activities.

---

EOF
    fi

    # Check if today's section exists
    if grep -q "^## $today" "$track_file" 2>/dev/null; then
        # Append to existing day section
        local tmp
        tmp=$(mktemp)
        awk -v header="$today_header" -v entry="| $time_now | \`$ticket\` | $activity | $duration |" '
            $0 == header { found=1 }
            found && /^$/ && !added { print entry; added=1 }
            { print }
            END { if (found && !added) print entry }
        ' "$track_file" > "$tmp" && mv "$tmp" "$track_file"
    else
        # Add new day section at the end
        cat >> "$track_file" << EOF

$today_header

| Time | Category | Activity | Duration |
|------|----------|----------|----------|
| $time_now | \`$ticket\` | $activity | $duration |
EOF
    fi

    log "INFO" "Tracked $ticket: $duration to time-track.md"
}

meta_set_failed() {
    local details="$1"
    local meta
    meta=$(meta_read)
    meta_write "$(echo "$meta" | jq \
        --arg details "$details" \
        --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '.status = "failed" | .history += [.current + {outcome: "failed", details: $details, completed_at: $now}] | .current = null')"
}

meta_add_picker_decision() {
    local decision_json="$1"
    local meta
    meta=$(meta_read)
    meta_write "$(echo "$meta" | jq --argjson d "$decision_json" '.picker_decisions = (.picker_decisions + [$d])[-50:]')"
}

# --- Lock Management (via metadata) ---
acquire_lock() {
    local meta
    meta=$(meta_read)
    local lock_pid
    lock_pid=$(echo "$meta" | jq -r '.lock_pid // empty')
    if [ -n "$lock_pid" ] && [ "$lock_pid" != "null" ] && kill -0 "$lock_pid" 2>/dev/null; then
        log "INFO" "Another conductor instance is running (PID: $lock_pid). Exiting."
        exit 0
    fi
    meta_write "$(echo "$meta" | jq --arg pid "$$" '.lock_pid = ($pid | tonumber)')"
}

release_lock() {
    if [ -f "$META_FILE" ]; then
        meta_write "$(meta_read | jq '.lock_pid = null')"
    fi
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

find_conductor_ticket() {
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

    # Match by target status category (key=indeterminate, name="In Progress") — robust
    # against workflow transition-name casing like "In progress" vs "In Progress".
    # Prefer a transition whose target status is literally named "In Progress".
    local transition_id
    transition_id=$(echo "$body" | jq -r '
        .transitions[]
        | select((.to.name // "" | ascii_downcase) == "in progress")
        | .id
    ' | head -1)

    # Fallback: match by transition name (case-insensitive).
    if [ -z "$transition_id" ] || [ "$transition_id" = "null" ]; then
        transition_id=$(echo "$body" | jq -r '
            .transitions[]
            | select((.name // "" | ascii_downcase) == "in progress")
            | .id
        ' | head -1)
    fi

    if [ -z "$transition_id" ] || [ "$transition_id" = "null" ]; then
        log "WARN" "No 'In Progress' transition found for $ticket_key. Available:"
        echo "$body" | jq -r '.transitions[] | "  - \(.name) -> \(.to.name)"' >> "$LOG_FILE"
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

transition_to_code_review() {
    local ticket_key="$1"
    [ "$TRACKER" != "jira" ] && return 0

    local response
    response=$(jira_api GET "/issue/$ticket_key/transitions")
    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    [ "$http_code" != "200" ] && return 1

    # Case-insensitive match: "Code Review" first, then "Review", then "In Review"
    local transition_id=""
    for name in "code review" "review" "in review"; do
        transition_id=$(echo "$body" | jq -r --arg n "$name" '
            .transitions[]
            | select((.name // "" | ascii_downcase) == $n)
            | .id
        ' | head -1)
        [ -n "$transition_id" ] && [ "$transition_id" != "null" ] && break
    done

    [ -z "$transition_id" ] || [ "$transition_id" = "null" ] && return 1

    response=$(jira_api POST "/issue/$ticket_key/transitions" "{\"transition\":{\"id\":\"$transition_id\"}}")
    http_code=$(echo "$response" | tail -1)

    if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        log "INFO" "Transitioned $ticket_key to Code Review"
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

# --- ClickUp API ---
clickup_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local args=(-s -w "\n%{http_code}" -X "$method"
        -H "Content-Type: application/json"
        -H "Authorization: $CLICKUP_API_TOKEN"
        "https://api.clickup.com/api/v2${endpoint}")

    if [ -n "$data" ]; then
        args+=(-d "$data")
    fi

    curl "${args[@]}" 2>/dev/null
}

find_conductor_ticket_clickup() {
    # Build query params
    local params="tags[]=${CLICKUP_TAG}&statuses[]=to%20do&order_by=created&reverse=true&subtasks=true&include_closed=false"

    # Filter by space if configured
    if [ -n "$CLICKUP_SPACE_IDS" ]; then
        for sid in $(echo "$CLICKUP_SPACE_IDS" | tr ',' ' '); do
            params+="&space_ids[]=$sid"
        done
    fi

    local response
    response=$(clickup_api GET "/team/${CLICKUP_TEAM_ID}/task?${params}&page=0")

    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log "ERROR" "ClickUp search failed (HTTP $http_code): $body"
        return 1
    fi

    local task_count
    task_count=$(echo "$body" | jq -r '.tasks | length')
    if [ "$task_count" = "0" ] || [ "$task_count" = "null" ]; then
        log "INFO" "No tasks found with tag '$CLICKUP_TAG' in To Do status."
        return 1
    fi

    # Pick the oldest task (last in reverse-created list, or first if API returns oldest first)
    TICKET_KEY=$(echo "$body" | jq -r '.tasks[0].id')
    TICKET_SUMMARY=$(echo "$body" | jq -r '.tasks[0].name')
    TICKET_TYPE=$(echo "$body" | jq -r '.tasks[0].type // "task"')
    TICKET_PRIORITY=$(echo "$body" | jq -r '.tasks[0].priority.priority // "normal"')
    CLICKUP_TASK_URL=$(echo "$body" | jq -r '.tasks[0].url')
    CLICKUP_TASK_CUSTOM_ID=$(echo "$body" | jq -r '.tasks[0].custom_id // empty')

    # Use custom ID for branch names if available, otherwise task ID
    if [ -n "$CLICKUP_TASK_CUSTOM_ID" ] && [ "$CLICKUP_TASK_CUSTOM_ID" != "null" ]; then
        TICKET_KEY="$CLICKUP_TASK_CUSTOM_ID"
    fi

    log "INFO" "Found task: $TICKET_KEY - $TICKET_SUMMARY ($TICKET_TYPE, $TICKET_PRIORITY)"
    return 0
}

transition_to_in_progress_clickup() {
    local task_id="$1"

    local response
    response=$(clickup_api PUT "/task/$task_id" '{"status":"in progress"}')
    local http_code
    http_code=$(echo "$response" | tail -1)

    if [ "$http_code" = "200" ]; then
        log "INFO" "Transitioned $task_id to In Progress"
        return 0
    else
        log "ERROR" "Failed to transition $task_id (HTTP $http_code)"
        return 1
    fi
}

# Move a ClickUp task to its terminal/done status when the PR merges.
# Status name is configurable per-project via CLICKUP_DONE_STATUS (default: "complete",
# which matches ClickUp's default closed-type status). For custom workflows, set
# CLICKUP_DONE_STATUS in the project env file.
transition_to_done_clickup() {
    local task_id="$1"
    local status="${CLICKUP_DONE_STATUS:-complete}"

    local body
    body=$(jq -n --arg s "$status" '{status: $s}')

    local response
    response=$(clickup_api PUT "/task/$task_id" "$body")
    local http_code
    http_code=$(echo "$response" | tail -1)

    if [ "$http_code" = "200" ]; then
        log "INFO" "Transitioned $task_id to '$status' (PR merged)"
        return 0
    else
        local err_body
        err_body=$(echo "$response" | sed '$d')
        log "ERROR" "Failed to transition $task_id to '$status' (HTTP $http_code): $err_body"
        return 1
    fi
}

# Extract the ClickUp task id from a worktree name. Worktree names are
# `${TICKET_KEY}-${slug}` where TICKET_KEY is either the raw ClickUp id
# (e.g. "869d27pza") or a custom_id (e.g. "CONVOY-42"). Custom IDs contain
# uppercase letters which never appear in raw IDs, so we use that to disambiguate.
task_id_from_worktree_name_clickup() {
    local wt_name="$1"
    # Custom id: starts with uppercase letters then digits (e.g. CONVOY-42-…)
    if [[ "$wt_name" =~ ^([A-Z][A-Z0-9]*-[0-9]+)- ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    # Raw id: take everything before the first hyphen (lowercase alphanumeric)
    echo "${wt_name%%-*}"
}

clickup_comment() {
    local task_id="$1"
    local message="$2"

    local body
    body=$(jq -n --arg msg "$message" '{comment_text: $msg}')

    local response
    response=$(clickup_api POST "/task/$task_id/comment" "$body")
    local http_code
    http_code=$(echo "$response" | tail -1)

    if [ "$http_code" = "200" ]; then
        log "INFO" "Commented on $task_id"
    else
        log "WARN" "Failed to comment on $task_id (HTTP $http_code)"
    fi
}

# --- Tracker-agnostic wrappers ---
find_ticket() {
    if [ "${AI_PICKER_ENABLED:-true}" = "true" ]; then
        if ai_pick_ticket; then return 0; fi
        log "WARN" "AI picker failed — not falling back to oldest-first (could pick wrong ticket)"
        return 1
    fi
    if [ "$TRACKER" = "clickup" ]; then
        find_conductor_ticket_clickup
    else
        find_conductor_ticket
    fi
}

transition_ticket() {
    local key="$1"
    if [ "$TRACKER" = "clickup" ]; then
        transition_to_in_progress_clickup "$key"
    else
        transition_to_in_progress "$key"
    fi
}

comment_on_ticket() {
    local key="$1"
    local msg="$2"
    if [ "$TRACKER" = "clickup" ]; then
        clickup_comment "$key" "$msg"
    else
        jira_comment "$key" "$msg"
    fi
}

build_ticket_url() {
    local key="$1"
    if [ "$TRACKER" = "clickup" ]; then
        echo "${CLICKUP_TASK_URL:-https://app.clickup.com/t/$key}"
    elif [ -n "${TICKET_URL_PATTERN:-}" ]; then
        echo "$TICKET_URL_PATTERN" | sed "s|{{KEY}}|$key|g"
    else
        echo "${JIRA_BASE_URL}/browse/${key}"
    fi
}

# --- AI Ticket Picker ---

fetch_all_candidates_clickup() {
    local params="tags[]=${CLICKUP_TAG}&statuses[]=to%20do&order_by=created&reverse=true&subtasks=true&include_closed=false"

    if [ -n "$CLICKUP_SPACE_IDS" ]; then
        for sid in $(echo "$CLICKUP_SPACE_IDS" | tr ',' ' '); do
            params+="&space_ids[]=$sid"
        done
    fi

    local response
    response=$(clickup_api GET "/team/${CLICKUP_TEAM_ID}/task?${params}&page=0")

    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log "ERROR" "ClickUp fetch failed (HTTP $http_code)"
        return 1
    fi

    local task_count
    task_count=$(echo "$body" | jq -r '.tasks | length')
    if [ "$task_count" = "0" ] || [ "$task_count" = "null" ]; then
        log "INFO" "No tasks found with tag '$CLICKUP_TAG' in To Do status."
        return 1
    fi

    # Extract relevant fields, truncate descriptions to 300 chars
    CANDIDATE_TASKS_JSON=$(echo "$body" | jq '[.tasks[] | {
        id, custom_id, name,
        description: (.description // "" | .[0:300]),
        priority: (.priority.orderindex // null),
        priority_label: (.priority.priority // "none"),
        tags: [.tags[].name],
        dependencies, linked_tasks,
        url, date_created
    }]')

    log "INFO" "Found $task_count candidate tasks"
    return 0
}

gather_local_context() {
    local history_json="[]"
    local branches_json="[]"
    local worktrees_json="[]"

    # Completed history from metadata
    history_json=$(meta_read | jq '.history')

    # Existing branches
    if [ -d "$PROJECT_DIR/.git" ] || [ -f "$PROJECT_DIR/.git" ]; then
        branches_json=$(git -C "$PROJECT_DIR" branch --list --format='%(refname:short)' 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo "[]")
    fi

    # Existing worktrees
    if [ -d "$PROJECT_DIR/.git" ] || [ -f "$PROJECT_DIR/.git" ]; then
        worktrees_json=$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null | awk '
            /^worktree / { path=$2 }
            /^branch /   { branch=$2; sub(/refs\/heads\//, "", branch); print path "|" branch }
        ' | jq -R -s 'split("\n") | map(select(length > 0)) | map(split("|") | {path: .[0], branch: .[1]})' 2>/dev/null || echo "[]")
    fi

    LOCAL_CONTEXT_JSON=$(jq -n \
        --argjson history "$history_json" \
        --argjson branches "$branches_json" \
        --argjson worktrees "$worktrees_json" \
        --arg base_branch "$BASE_BRANCH" \
        '{completed_history: $history, existing_branches: $branches, existing_worktrees: $worktrees, base_branch: $base_branch}')
}

fetch_all_candidates_jira() {
    local jql="project = $JIRA_PROJECT AND labels = \"$JIRA_LABEL\" AND status = \"To Do\" ORDER BY priority ASC, created ASC"
    local search_body
    search_body=$(jq -n --arg jql "$jql" '{
        jql: $jql,
        maxResults: 20,
        fields: ["summary", "description", "issuetype", "priority", "status", "parent", "issuelinks"]
    }')

    local response
    response=$(jira_api POST "/search/jql" "$search_body")
    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log "ERROR" "Jira candidate fetch failed (HTTP $http_code)"
        return 1
    fi

    local issue_count
    issue_count=$(echo "$body" | jq -r '.issues | length')
    if [ "$issue_count" = "0" ]; then
        log "INFO" "No candidate tickets found"
        return 1
    fi

    # Format candidates as JSON array for the picker
    CANDIDATE_TASKS_JSON=$(echo "$body" | jq '[.issues[] | {
        id: .key,
        task_id: .key,
        name: .fields.summary,
        description: (.fields.description // ""),
        priority: (.fields.priority.name // "Medium"),
        priority_label: (.fields.priority.name // "Medium"),
        type: (.fields.issuetype.name // "Task"),
        parent: (.fields.parent.key // null),
        url: ("https://groupondev.atlassian.net/browse/" + .key),
        dependencies: [.fields.issuelinks[]? | select(.type.name == "Blocks" or .type.name == "is blocked by") | .inwardIssue.key // .outwardIssue.key]
    }]')

    log "INFO" "Fetched $issue_count Jira candidates for AI picker"
    return 0
}

ai_pick_ticket() {
    log "INFO" "Running AI ticket picker (model: $PICKER_MODEL)"

    if [ "$TRACKER" = "clickup" ]; then
        if ! fetch_all_candidates_clickup; then return 1; fi
    else
        if ! fetch_all_candidates_jira; then return 1; fi
    fi

    gather_local_context

    # Build picker prompt
    local prompt_file="$CONDUCTOR_DIR/prompts/_picker_prompt.md"
    mkdir -p "$CONDUCTOR_DIR/prompts"
    cat > "$prompt_file" << 'PICKER_HEADER'
You are choosing the next task for an autonomous coding agent to implement.

## Instructions
- Pick the task that should be done NEXT considering dependencies and priority.
- **Priority is king.** Pick the highest priority task that is NOT blocked. Priority ordering: Blocker > Critical > High > Medium > Low > none.
- **Dependency check:** If a task depends on another task (via explicit dependencies, sequential numbering under the same parent/epic, or description references), the dependency must be completed first. Check completed_history AND existing branches/worktrees. If the dependency is not completed and has no branch, the task is BLOCKED — skip it.
- **Sequential tickets:** Tickets under the same parent (e.g., ECH-672, ECH-673, ECH-674, ECH-675) are almost always sequential. Pick the lowest number that isn't completed yet. If ECH-672 isn't done, don't pick ECH-673.
- If ALL high-priority tasks are blocked by unmet dependencies, pick the highest priority unblocked task regardless of priority tier.
- Consider task descriptions and tags for context about what makes sense to do first.

## Branch Selection (CRITICAL)
Determine which branch the new worktree should be based on:

1. **Check existing branches for related work.** Look at "Existing Branches" and "Existing Worktrees" for branches that match the same epic, story, or feature area as the picked task. Indicators of related work:
   - Branches with the same parent ticket key (e.g., ECH-571, ECH-572, ECH-573 are siblings under the same epic)
   - Branches with similar names suggesting the same feature area (e.g., "biome-linting-phase-1" and a task for "biome-linting-phase-2")
   - Tasks that are sequential phases of the same work (Phase 1, Phase 2, etc.)

2. **If a related branch exists**, set base_branch to that branch name. The new work should build on top of existing changes rather than starting fresh from the default branch.

3. **If multiple related branches exist**, prefer the most recently completed one (check completed_history), or the one whose ticket number is closest and highest (e.g., for ECH-575, prefer ECH-574 over ECH-571).

4. **If no related branches exist**, use the default base branch.

- If NO task can be picked (all blocked by unmet dependencies), return {"pick": null, "reasoning": "..."}.

Return ONLY valid JSON with no markdown fences:
{"pick": {"task_id": "...", "name": "...", "base_branch": "...", "url": "..."}, "reasoning": "one sentence explaining your choice"}
PICKER_HEADER

    # Append data sections
    {
        echo ""
        echo "## Default Base Branch"
        echo "$BASE_BRANCH"
        echo ""
        echo "## Candidate Tasks"
        echo "$CANDIDATE_TASKS_JSON"
        echo ""
        echo "## Local Context"
        echo "$LOCAL_CONTEXT_JSON"
    } >> "$prompt_file"

    # Invoke Claude
    local picker_response
    picker_response=$("$CLAUDE_BIN" -p --model "$PICKER_MODEL" --output-format json < "$prompt_file" 2>/dev/null)
    local exit_code=$?

    if [ $exit_code -ne 0 ] || [ -z "$picker_response" ]; then
        log "ERROR" "Claude picker call failed (exit $exit_code)"
        return 1
    fi

    # Parse outer JSON wrapper
    local inner
    inner=$(echo "$picker_response" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$inner" ]; then
        log "ERROR" "Picker response missing .result field"
        return 1
    fi

    # Parse inner picker JSON
    local task_id
    task_id=$(echo "$inner" | jq -r '.pick.task_id // empty' 2>/dev/null)

    if [ -z "$task_id" ] || [ "$task_id" = "null" ]; then
        local reasoning
        reasoning=$(echo "$inner" | jq -r '.reasoning // "no reason given"' 2>/dev/null)
        log "INFO" "Picker chose nothing: $reasoning"
        return 1
    fi

    # Extract pick details
    TICKET_KEY="$task_id"
    TICKET_SUMMARY=$(echo "$inner" | jq -r '.pick.name // empty' 2>/dev/null)
    CLICKUP_TASK_URL=$(echo "$inner" | jq -r '.pick.url // empty' 2>/dev/null)
    PICKER_BASE_BRANCH=$(echo "$inner" | jq -r '.pick.base_branch // empty' 2>/dev/null)
    PICKER_REASONING=$(echo "$inner" | jq -r '.reasoning // empty' 2>/dev/null)

    # Fill in missing fields from candidate data
    if [ -z "$TICKET_SUMMARY" ]; then
        TICKET_SUMMARY=$(echo "$CANDIDATE_TASKS_JSON" | jq -r --arg id "$task_id" '.[] | select(.id == $id) | .name // empty')
    fi
    if [ -z "$CLICKUP_TASK_URL" ]; then
        CLICKUP_TASK_URL=$(echo "$CANDIDATE_TASKS_JSON" | jq -r --arg id "$task_id" '.[] | select(.id == $id) | .url // empty')
    fi

    # Look for custom_id from candidates
    CLICKUP_TASK_CUSTOM_ID=$(echo "$CANDIDATE_TASKS_JSON" | jq -r --arg id "$task_id" '.[] | select(.id == $id) | .custom_id // empty')
    if [ -n "$CLICKUP_TASK_CUSTOM_ID" ] && [ "$CLICKUP_TASK_CUSTOM_ID" != "null" ]; then
        TICKET_KEY="$CLICKUP_TASK_CUSTOM_ID"
    fi

    TICKET_TYPE="task"
    TICKET_PRIORITY=$(echo "$CANDIDATE_TASKS_JSON" | jq -r --arg id "$task_id" '.[] | select(.id == $id) | .priority_label // "normal"')

    # Validate task_id exists in candidates
    local valid
    valid=$(echo "$CANDIDATE_TASKS_JSON" | jq -r --arg id "$task_id" '[.[] | select(.id == $id)] | length')
    if [ "$valid" = "0" ]; then
        log "ERROR" "Picker chose task_id '$task_id' which is not in candidate list"
        return 1
    fi

    # Validate base branch exists (fall back to BASE_BRANCH if not)
    if [ -n "$PICKER_BASE_BRANCH" ] && [ "$PICKER_BASE_BRANCH" != "$BASE_BRANCH" ]; then
        if ! git -C "$PROJECT_DIR" rev-parse --verify "$PICKER_BASE_BRANCH" &>/dev/null && \
           ! git -C "$PROJECT_DIR" rev-parse --verify "origin/$PICKER_BASE_BRANCH" &>/dev/null; then
            log "WARN" "Picker suggested base '$PICKER_BASE_BRANCH' but it doesn't exist. Using $BASE_BRANCH."
            PICKER_BASE_BRANCH="$BASE_BRANCH"
        fi
    fi
    PICKER_BASE_BRANCH="${PICKER_BASE_BRANCH:-$BASE_BRANCH}"

    # Save picker decision to metadata
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local decision
    decision=$(jq -n \
        --arg ts "$timestamp" \
        --arg task_id "$task_id" \
        --arg name "$TICKET_SUMMARY" \
        --arg base "$PICKER_BASE_BRANCH" \
        --arg url "$CLICKUP_TASK_URL" \
        --arg reasoning "$PICKER_REASONING" \
        --arg model "$PICKER_MODEL" \
        --argjson candidates_count "$(echo "$CANDIDATE_TASKS_JSON" | jq 'length')" \
        '{timestamp: $ts, picked: {task_id: $task_id, name: $name, base_branch: $base, url: $url}, reasoning: $reasoning, model: $model, candidates_count: $candidates_count}')
    meta_add_picker_decision "$decision"

    log "INFO" "Picker chose: $TICKET_KEY - $TICKET_SUMMARY (base: $PICKER_BASE_BRANCH)"
    log "INFO" "Reasoning: $PICKER_REASONING"
    return 0
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
    local base_override="${2:-$BASE_BRANCH}"
    local branch_name="$worktree_name"
    local worktree_path="$WORKTREES_BASE/$worktree_name"

    # Check worktrunk path pattern first (project.branch). Validate that the
    # directory is an actual git worktree before reusing it — a leftover empty
    # directory (e.g. from a previously-removed worktree) will pass `-d` but
    # can't be used as a worktree, and silently dispatching Claude into it
    # produces "fatal: not a git repository" with no clear failure path.
    local wt_path="$(dirname "$PROJECT_DIR")/$(basename "$PROJECT_DIR").${worktree_name}"
    if [ -d "$wt_path" ]; then
        if git -C "$wt_path" rev-parse --git-dir >/dev/null 2>&1; then
            log "INFO" "Worktree already exists: $wt_path"
            RESOLVED_WORKTREE_PATH="$wt_path"
            return 0
        fi
        log "ERROR" "Path exists but is not a git worktree (no .git): $wt_path — remove this directory manually before retrying"
        return 1
    fi
    if [ -d "$worktree_path" ]; then
        if git -C "$worktree_path" rev-parse --git-dir >/dev/null 2>&1; then
            log "INFO" "Worktree already exists: $worktree_path"
            RESOLVED_WORKTREE_PATH="$worktree_path"
            return 0
        fi
        log "ERROR" "Path exists but is not a git worktree (no .git): $worktree_path — remove this directory manually before retrying"
        return 1
    fi

    # Fetch latest from remote
    cd "$PROJECT_DIR"
    git fetch origin "$base_override" 2>/dev/null || true

    # Prefer worktrunk (git-wt) if available — runs pre-start hooks (copy-ignored etc.)
    if command -v git-wt &>/dev/null && [ -f "$PROJECT_DIR/.config/wt.toml" ]; then
        log "INFO" "Creating worktree via worktrunk: $branch_name (base: $base_override)"
        git-wt switch --create "$branch_name" --base "$base_override" --no-cd 2>&1 | while read -r line; do
            log "INFO" "wt: $line"
        done
        # worktrunk places worktrees relative to the project dir — find the actual path
        worktree_path=$(git worktree list --porcelain | grep -A0 "worktree.*${branch_name}" | head -1 | sed 's/^worktree //')
        if [ -z "$worktree_path" ] || [ ! -d "$worktree_path" ]; then
            log "ERROR" "Worktrunk created branch but worktree path not found"
            return 1
        fi
        log "INFO" "Worktree created at: $worktree_path"
    else
        log "INFO" "Creating worktree: $worktree_path (branch: $branch_name, base: $base_override)"
        git worktree add -b "$branch_name" "$worktree_path" "origin/$base_override" 2>&1 | while read -r line; do
            log "INFO" "git: $line"
        done

        if [ ! -d "$worktree_path" ]; then
            log "ERROR" "Failed to create worktree at $worktree_path"
            return 1
        fi

        # Copy env and settings from main repo to worktree
        cp "$PROJECT_DIR/.env.local" "$worktree_path/.env.local" 2>/dev/null && log "INFO" "Copied .env.local" || true
        mkdir -p "$worktree_path/.claude"
        cp "$PROJECT_DIR/.claude/settings.local.json" "$worktree_path/.claude/settings.local.json" 2>/dev/null && log "INFO" "Copied settings.local.json" || true

        # Run project-specific setup hook if configured
        if [ -n "$WORKTREE_SETUP_HOOK" ] && [ -x "$WORKTREE_SETUP_HOOK" ]; then
            log "INFO" "Running worktree setup hook: $WORKTREE_SETUP_HOOK"
            WORKTREE_PATH="$worktree_path" \
            PROJECT_DIR="$PROJECT_DIR" \
            WORKTREE_NAME="$worktree_name" \
                "$WORKTREE_SETUP_HOOK" 2>&1 | while read -r line; do
                    log "INFO" "hook: $line"
                done
        fi
    fi

    # Install dependencies if configured
    if [ -n "$INSTALL_CMD" ]; then
        log "INFO" "Installing dependencies: $INSTALL_CMD"
        # Source npm registry tokens so .npmrc env-var refs (e.g.
        # ${GROUPON_PACKAGES_TOKEN}) resolve. Resolution order:
        #   1. shared conductor secrets.env
        #   2. project-specific conductor secrets
        #   3. the worktree's own .env.local (committed by `wt setup` from the
        #      base repo) — this is where echelon devs keep the token in practice
        # Then bridge name mismatches: echelon's .npmrc expects GROUPON_PACKAGES_TOKEN
        # but .env.local / .env.example use GITHUB_PACKAGES_TOKEN. Map one to the
        # other if only one is set so install doesn't 401 on @groupon/* deps.
        # Sub-shell isolates exports from the rest of the cycle.
        (
            set -a
            [ -f "$CONDUCTOR_DIR/secrets.env" ] && source "$CONDUCTOR_DIR/secrets.env"
            [ -f "$CONDUCTOR_DIR/projects/${PROJECT_NAME}.secrets.env" ] && source "$CONDUCTOR_DIR/projects/${PROJECT_NAME}.secrets.env"
            [ -f "$worktree_path/.env.local" ] && source "$worktree_path/.env.local"
            set +a
            # Bridge GITHUB_PACKAGES_TOKEN <-> GROUPON_PACKAGES_TOKEN
            if [ -z "${GROUPON_PACKAGES_TOKEN:-}" ] && [ -n "${GITHUB_PACKAGES_TOKEN:-}" ]; then
                export GROUPON_PACKAGES_TOKEN="$GITHUB_PACKAGES_TOKEN"
            fi
            if [ -z "${GITHUB_PACKAGES_TOKEN:-}" ] && [ -n "${GROUPON_PACKAGES_TOKEN:-}" ]; then
                export GITHUB_PACKAGES_TOKEN="$GROUPON_PACKAGES_TOKEN"
            fi
            cd "$worktree_path" && eval "$INSTALL_CMD"
        ) 2>&1 | tail -5 | while read -r line; do
            log "INFO" "install: $line"
        done
    fi

    RESOLVED_WORKTREE_PATH="$worktree_path"
    log "INFO" "Worktree setup complete: $worktree_path"
    return 0
}

# --- Session Management (cross-platform) ---
# On macOS/Linux with tmux: creates tmux sessions with multiple windows.
# On Windows (or no tmux): runs processes in background with PID tracking.

PIDS_DIR="$CONDUCTOR_DIR/pids"

setup_session() {
    local worktree_name="$1"
    local worktree_path="$WORKTREES_BASE/$worktree_name"

    if [ "$HAS_TMUX" = true ]; then
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
    else
        # No tmux: just ensure PID directory exists for background process tracking
        mkdir -p "$PIDS_DIR"
        log "INFO" "No tmux available — will run processes in background (PID-tracked)"
    fi

    # Tag worktree metadata with conductor=true
    local meta_session_file="$WORKTREES_BASE/.worktree-meta/sessions/${worktree_name}.json"
    if [ -f "$meta_session_file" ]; then
        jq '.conductor = true' "$meta_session_file" > "${meta_session_file}.tmp" && mv "${meta_session_file}.tmp" "$meta_session_file"
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
    local worktree_path="$WORKTREES_BASE/$worktree_name"

    if [ -z "$DEV_SERVER_CMD" ]; then
        log "INFO" "No DEV_SERVER_CMD configured, skipping server start."
        return 0
    fi

    log "INFO" "Starting dev server: $DEV_SERVER_CMD"

    if [ "$HAS_TMUX" = true ]; then
        # Send command to tmux pane — $SERVER_PORT is set in pane env
        # Tee output to log so Claude can read server errors
        local server_log="$CONDUCTOR_DIR/logs/${worktree_name}-server.log"
        tmux send-keys -t "$worktree_name:2" "$DEV_SERVER_CMD 2>&1 | tee $server_log" Enter
    else
        # Run dev server as background process with PID tracking
        local port
        port=$(resolve_port "$worktree_name")
        local server_log="$CONDUCTOR_DIR/logs/${worktree_name}-server.log"
        (
            cd "$worktree_path"
            export SERVER_PORT="$port"
            eval "$DEV_SERVER_CMD" >> "$server_log" 2>&1
        ) &
        local server_pid=$!
        mkdir -p "$PIDS_DIR"
        echo "$server_pid" > "$PIDS_DIR/${worktree_name}-server.pid"
        log "INFO" "Dev server started in background (PID: $server_pid, port: $port)"
    fi

    sleep 3
}

# --- Claude Launch ---
generate_prompt() {
    local ticket_key="$1"
    local worktree_name="$2"
    local worktree_path="$WORKTREES_BASE/$worktree_name"
    local port="${3:-3000}"
    local prompt_file="$CONDUCTOR_DIR/prompts/${worktree_name}.md"

    mkdir -p "$CONDUCTOR_DIR/prompts"

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
        "$PROMPT_TEMPLATE" > "$prompt_file"

    echo "$prompt_file"
}

launch_claude() {
    local worktree_name="$1"
    local ticket_key="$2"
    local port="${3:-}"
    local worktree_path="${RESOLVED_WORKTREE_PATH:-$WORKTREES_BASE/$worktree_name}"
    local server_log="$CONDUCTOR_DIR/logs/${worktree_name}-server.log"

    # Build ticket URL (tracker-agnostic)
    local ticket_url
    ticket_url=$(build_ticket_url "$ticket_key")

    # Build a readable tab title
    local tab_title="🤖 ${ticket_key} — ${TICKET_SUMMARY:-$worktree_name}"

    # Convert META_FILE to a Windows path for jq inside the launcher if needed
    local meta_file_path="$META_FILE"

    # Resolve session dir for this worktree (where conductor.json lives).
    # WORKTREES_BASE is per-project, so the session lives directly under
    # $WORKTREES_BASE/.worktree-meta/sessions/<wt>/ — no extra <proj> layer.
    local session_dir="$WORKTREES_BASE/.worktree-meta/sessions/$worktree_name"

    # Write a launcher script — starts Claude interactively with /conductor command.
    # Claude reports state via the `state` shell function (calls worktree-event,
    # which patches conductor.json). The launcher reads .state from conductor.json
    # after Claude exits and updates project-level metadata.
    local launcher="$CONDUCTOR_DIR/prompts/${worktree_name}.sh"
    cat > "$launcher" << LAUNCHER
#!/usr/bin/env bash
# Set terminal tab title
echo -ne "\\033]0;${tab_title}\\007"
cd '$worktree_path'

# Resolve gh auth from per-repo metadata so the worker's \`gh pr view\` and
# \`gh pr checks\` calls hit the right account. Without this, an org-owned
# repo (e.g. groupon/echelon) silently 404s when the active gh account is
# a personal one (patrykk21), which causes CI polling to loop forever on
# states='' because gh returned an error the worker didn't see.
# Mirrors gh_pr() in conductor.sh — keep the two in sync.
__ap_remote_url=\$(git -C '$worktree_path' remote get-url origin 2>/dev/null)
__ap_gh_host="github.com"
case "\$__ap_remote_url" in
    *github.groupondev.com*) __ap_gh_host="github.groupondev.com" ;;
esac
__ap_gh_token=""
__ap_repos_json="\$HOME/worktrees/.metadata/repos.json"
if [ -f "\$__ap_repos_json" ] && command -v jq >/dev/null 2>&1; then
    __ap_meta_repo=\$(jq -r --arg cwd '$worktree_path' --arg wbase "\$HOME/worktrees" '
        .repositories | to_entries
        | map(. as \$e | select(
            (\$cwd | startswith(\$e.value.main_path)) or
            (\$cwd | startswith(\$wbase + "/" + \$e.key + "/"))
          ))
        | .[0].key // empty
    ' "\$__ap_repos_json" 2>/dev/null)
    if [ -n "\$__ap_meta_repo" ]; then
        __ap_meta_host=\$(jq -r --arg k "\$__ap_meta_repo" '.repositories[\$k].gh_host // empty' "\$__ap_repos_json" 2>/dev/null)
        __ap_meta_account=\$(jq -r --arg k "\$__ap_meta_repo" '.repositories[\$k].gh_account // empty' "\$__ap_repos_json" 2>/dev/null)
        [ -n "\$__ap_meta_host" ] && __ap_gh_host="\$__ap_meta_host"
        if [ -n "\$__ap_meta_account" ]; then
            __ap_gh_token=\$(gh auth token --hostname "\$__ap_gh_host" --user "\$__ap_meta_account" 2>/dev/null)
        fi
    fi
fi
if [ -n "\$__ap_gh_token" ]; then
    export GH_HOST="\$__ap_gh_host"
    export GH_TOKEN="\$__ap_gh_token"
fi
unset __ap_remote_url __ap_gh_host __ap_gh_token __ap_repos_json __ap_meta_repo __ap_meta_host __ap_meta_account

export CONDUCTOR_PR_ASSIGNEE="${PR_ASSIGNEE:-}"
export CONDUCTOR_WORKTREE_NAME="${worktree_name}"
export CONDUCTOR_SESSION_DIR="${session_dir}"

# state — single source of state transitions for conductor. Calls worktree-event
# which patches the per-worktree conductor.json (.state, .state_detail, .state_updated).
# Usage: state STATE [DETAIL]   e.g. state working "implementing changes"
state() {
    local s="\$1"; local d="\${2:-}"
    local text="\$s"
    [ -n "\$d" ] && text="\$s|\$d"
    "$CONDUCTOR_DIR/bin/worktree-event" conductor-state-reported \\
        --ticket "$worktree_name" --text "\$text" >/dev/null 2>&1 || true
}
export -f state

# Run Claude
SYSTEM_PROMPT="YOU ARE RUNNING IN AN CONDUCTOR SESSION.

State is reported via the shell function \\\`state\\\` (already exported into your shell).
Call it whenever your state changes: \\\`state STATE \"details\"\\\`. The function patches
the per-worktree conductor.json which the picker and scheduler read.

STATES (call exactly these):
  state working \"description\"          — you are actively coding, testing, committing
  state awaiting_ci PR_URL                — you created/updated a PR, CI is running
  state awaiting_review PR_URL            — CI passed, waiting for human review (assignee)
  state approved PR_URL                   — reviewer approved, ready to merge
  state merged PR_URL                     — PR merged to base (terminal; usually set by scheduler)
  state closed \"PR_URL or reason\"        — PR closed without merging (abandoned/superseded/rejected), terminal
  state blocked \"reason\"                 — waiting on external dependency (other ticket, team, decision) — not user input
  state needs_input \"your question\"      — you need the user to answer something
  state failed \"reason\"                  — you cannot complete the task

WHEN TO TRANSITION:
  Session starts                → state working \"reading ticket and planning\"
  Actively implementing         → state working \"implementing changes\"
  Created or updated a PR       → state awaiting_ci \"PR_URL\", then MONITOR CI (poll gh pr checks every 30s, wait 60s after pass for CodeRabbit, check reviews, fix if needed, then transition per the CI-passed rule below)
  CI passed                     → BEFORE writing awaiting_review, query \\\`gh pr view <num> --json reviewDecision -q '.reviewDecision'\\\`. Map: APPROVED → state approved \"PR_URL\"; CHANGES_REQUESTED → fix comments first; REVIEW_REQUIRED/null/empty → state awaiting_review \"PR_URL\". NEVER blindly write awaiting_review — a prior approval may already exist (e.g. after merging base or pushing a non-dismissing commit).
  Review requested changes      → state working \"fixing review comments\", fix, push, then state awaiting_ci \"PR_URL\"
  Need user input               → state needs_input \"your question\"
  User responded                → state working \"addressing feedback\"
  PR abandoned/superseded       → state closed \"PR_URL or reason\" (terminal — do not resume)
  Blocked by external factor    → state blocked \"waiting for ECH-XXX to merge\" (pauses session; user or scheduler unblocks)
  Cannot complete               → state failed \"reason\"

CRITICAL: After calling \\\`state awaiting_ci\\\`, DO NOT STOP. Poll CI, wait for CodeRabbit, address review comments, THEN check \\\`reviewDecision\\\` and emit \\\`approved\\\` or \\\`awaiting_review\\\` accordingly.
CRITICAL: NEVER overwrite if current state is 'merged', 'closed', or 'approved' — those are terminal states set by the scheduler.
CRITICAL: When merging the base branch or pushing any commit to an open PR, re-check \\\`reviewDecision\\\` afterwards. If it is still APPROVED (no dismissal), the state stays \\\`approved\\\` — do not regress to \\\`awaiting_review\\\`.
CRITICAL: Before EVERY git push, re-read AGENTS.md/CLAUDE.md and self-review your diff against all project rules. Check architecture, code standards, naming, imports, file/directory layout, no console.logs, no commented-out code. Fix violations BEFORE pushing — this applies to initial PRs AND subsequent fixes. The self-review must be explicit: enumerate each rule in AGENTS.md/CLAUDE.md that touches the files you changed, then verify the diff against it. Do not skip rules because lint/typecheck/build pass — convention violations are silent to those tools.
CRITICAL: AGENTS.md/CLAUDE.md is the source of truth — NOT existing code. Existing files in the repo may themselves violate the conventions (legacy code, prior worker mistakes). When you see \"the existing X does it this way,\" that is NOT evidence the convention permits it. Anchor on the documented rule and its example; if the convention says types live in their own \\\`types.ts\\\` for multi-file domains, do that even if a similar nearby file inlines them. If you find an existing file violates the convention, do not propagate the violation; flag it in the PR description if it's adjacent to your work.

IMPORTANT: Call \\\`state\\\` EVERY time your state changes. The tmux worktree picker and conductor scheduler read conductor.json to show your current status.

ENVIRONMENT:
  - Dev server running on port \$SERVER_PORT
  - Server logs: $server_log
  - Do NOT assign the PR — the scheduler handles that after CI and reviews pass"

$CLAUDE_BIN --dangerously-skip-permissions --disallowedTools AskUserQuestion --name "${tab_title}" \\
  --append-system-prompt "\$SYSTEM_PROMPT" \\
  "/conductor $ticket_url"
EXIT_CODE=\$?

# Read final state from conductor.json and update project-level metadata.
META_FILE="$meta_file_path"
NOW=\$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CONDUCTOR_JSON="\$CONDUCTOR_SESSION_DIR/conductor.json"

FINAL_STATE=""
FINAL_DETAIL=""
if [ -f "\$CONDUCTOR_JSON" ]; then
    FINAL_STATE=\$(jq -r '.state // ""' "\$CONDUCTOR_JSON" 2>/dev/null)
    FINAL_DETAIL=\$(jq -r '.state_detail // ""' "\$CONDUCTOR_JSON" 2>/dev/null)
fi

case "\$FINAL_STATE" in
    awaiting_ci|awaiting_review|approved|merged)
        if [ -n "\$CONDUCTOR_PR_ASSIGNEE" ] && [ "\$FINAL_STATE" != "merged" ]; then
            # PR needs CI/review before assignment — stay in pending_assignment
            jq --arg details "\$FINAL_DETAIL" --arg now "\$NOW" \\
              '.status = "pending_assignment" | .current.pr_url = \$details | .current.completed_at = \$now' \\
              "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
        else
            # No assignee configured (or already merged) — go straight to idle
            jq --arg details "\$FINAL_DETAIL" --arg now "\$NOW" \\
              '.status = "idle" | .history += [.current + {outcome: "completed", details: \$details, completed_at: \$now}] | .current = null' \\
              "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
        fi
        ;;
    closed)
        # PR closed without merge — record as completed-with-note, free the slot
        jq --arg details "closed: \$FINAL_DETAIL" --arg now "\$NOW" \\
          '.status = "idle" | .history += [.current + {outcome: "completed", details: \$details, completed_at: \$now}] | .current = null' \\
          "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
        ;;
    failed)
        jq --arg reason "\$FINAL_DETAIL" --arg now "\$NOW" \\
          '.status = "failed" | .history += [.current + {outcome: "failed", details: \$reason, completed_at: \$now}] | .current = null' \\
          "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
        ;;
    blocked)
        # Free the slot but record as blocked, not failed
        jq --arg reason "blocked: \$FINAL_DETAIL" --arg now "\$NOW" \\
          '.status = "idle" | .history += [.current + {outcome: "blocked", details: \$reason, completed_at: \$now}] | .current = null' \\
          "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
        ;;
    needs_input|working|"")
        # No terminal state reached — treat as failure if exit was 0
        if [ "\$EXIT_CODE" -eq 0 ]; then
            jq --arg now "\$NOW" \\
              '.status = "failed" | .history += [.current + {outcome: "failed", details: "Exit 0 with no terminal state", completed_at: \$now}] | .current = null' \\
              "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
        else
            jq --arg code "\$EXIT_CODE" --arg now "\$NOW" \\
              '.status = "failed" | .history += [.current + {outcome: "failed", details: ("Exit code: " + \$code), completed_at: \$now}] | .current = null' \\
              "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
        fi
        ;;
    *)
        # Unknown FINAL_STATE — record as failed and free the slot. Without
        # this arm, an unrecognized state silently no-ops, leaving .current
        # populated and wedging the project (was the root cause of convoy
        # worktrees stuck without a history entry).
        jq --arg state "\$FINAL_STATE" --arg detail "\$FINAL_DETAIL" --arg now "\$NOW" \\
          '.status = "failed" | .history += [.current + {outcome: "failed", details: ("Unknown FINAL_STATE \"" + \$state + "\": " + \$detail), completed_at: \$now}] | .current = null' \\
          "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
        ;;
esac

# Mark tab as done
echo -ne "\\033]0;✅ ${ticket_key} — done\\007"
LAUNCHER
    chmod +x "$launcher"

    if [ "$HAS_TMUX" = true ]; then
        log "INFO" "Launching Claude Code in tmux pane $worktree_name:1"
        tmux send-keys -t "$worktree_name:1" "$launcher" Enter
    elif [ "$PLATFORM" = "windows" ] && command -v wt.exe &>/dev/null; then
        # Launch in a new Windows Terminal tab using Git Bash profile (interactive)
        local wt_bin
        wt_bin="$(cygpath -w "$HOME/AppData/Local/Microsoft/WindowsApps/wt.exe" 2>/dev/null || echo "wt.exe")"
        local launcher_win
        launcher_win="$(cygpath -w "$launcher" 2>/dev/null || echo "$launcher")"
        local bash_win
        bash_win="$(cygpath -w "$(command -v bash)" 2>/dev/null || echo "C:\\Program Files\\Git\\usr\\bin\\bash.exe")"
        log "INFO" "Launching Claude Code in Windows Terminal tab: $tab_title"
        "$wt_bin" -w 0 nt --title "$tab_title" "$bash_win" "$launcher_win" &
        local claude_pid=$!
        mkdir -p "$PIDS_DIR"
        echo "$claude_pid" > "$PIDS_DIR/${worktree_name}-claude.pid"
        log "INFO" "Claude launched in Windows Terminal tab (PID: $claude_pid)"
    else
        log "INFO" "Launching Claude Code in background"
        mkdir -p "$PIDS_DIR"
        bash "$launcher" >> "$CONDUCTOR_DIR/logs/${worktree_name}-claude.log" 2>&1 &
        local claude_pid=$!
        echo "$claude_pid" > "$PIDS_DIR/${worktree_name}-claude.pid"
        log "INFO" "Claude launched in background (PID: $claude_pid)"
    fi

    log "INFO" "Claude launched. Metadata will be updated by launcher on exit."
}

# --- Session-state helpers ---
# Phase 3: marker files are gone. State lives in per-worktree conductor.json
# under $WORKTREES_BASE/.worktree-meta/sessions/<ticket>/conductor.json.
# WORKTREES_BASE is per-project (e.g. ~/worktrees/echelon) — it already includes
# the project, so do NOT add another `<proj>` path component.
# These helpers wrap the lookup + read + write so monitors stay tidy.

# Resolve session dir for a worktree name. Echos full path or empty.
session_dir_for_worktree() {
    local wt="$1"
    local sd="$WORKTREES_BASE/.worktree-meta/sessions/$wt"
    [ -d "$sd" ] && echo "$sd"
    return 0
}

# List worktree names that have an conductor.json (i.e. conductor has touched them).
list_session_worktrees() {
    for f in "$WORKTREES_BASE"/.worktree-meta/sessions/*/conductor.json; do
        [ -f "$f" ] || continue
        basename "$(dirname "$f")"
    done
}

# Read .state from a worktree's conductor.json. Echos empty if unset.
read_session_state() {
    local wt="$1"
    local sd
    sd=$(session_dir_for_worktree "$wt")
    [ -z "$sd" ] && return 0
    [ -f "$sd/conductor.json" ] || return 0
    jq -r '.state // ""' "$sd/conductor.json" 2>/dev/null
}

# Read .state_detail from a worktree's conductor.json. Echos empty if unset.
read_session_detail() {
    local wt="$1"
    local sd
    sd=$(session_dir_for_worktree "$wt")
    [ -z "$sd" ] && return 0
    [ -f "$sd/conductor.json" ] || return 0
    jq -r '.state_detail // ""' "$sd/conductor.json" 2>/dev/null
}

# Resolve PR number + URL for a worktree, even when state_detail is empty.
# Echos "<pr_number> <pr_url>" on success; nothing on failure.
#
# State_detail can be empty when the worker invoked `state awaiting_ci` without
# the PR_URL (or with a non-URL detail). Without a fallback the reconciler
# silently skips the worktree and it sticks in awaiting_ci/awaiting_review
# forever — the convoy 3-4 / 4-3 / ECH-715 regression. Fallback path: ask
# GitHub directly via `gh pr list --head <branch>`. Branch == worktree name
# in our convention. As a side-effect, when we resolve via fallback we patch
# conductor.json so subsequent cycles can use the fast path.
resolve_pr_for_worktree() {
    local wt_name="$1" wt_path="$2" details="$3"
    local pr_number pr_url

    # Fast path: state_detail already contains a PR URL.
    pr_number=$(echo "$details" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+')
    if [ -n "$pr_number" ]; then
        pr_url=$(echo "$details" | grep -oE 'https://[^ ]+/pull/[0-9]+' | head -1)
        [ -z "$pr_url" ] && pr_url="$details"
        echo "$pr_number $pr_url"
        return 0
    fi

    # Fallback: ask GitHub for the PR whose head branch == worktree name.
    [ -d "$wt_path" ] || return 0
    local branch
    branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
    [ -z "$branch" ] || [ "$branch" = "HEAD" ] && return 0

    local pr_json
    pr_json=$(gh_pr "$wt_path" pr list --head "$branch" --state all \
        --json number,url --limit 1 2>/dev/null)
    [ -z "$pr_json" ] || [ "$pr_json" = "[]" ] && return 0

    pr_number=$(echo "$pr_json" | jq -r '.[0].number // empty' 2>/dev/null)
    pr_url=$(echo "$pr_json" | jq -r '.[0].url // empty' 2>/dev/null)
    [ -z "$pr_number" ] && return 0

    # Persist the URL back to conductor.json so future cycles take fast path.
    local sd
    sd=$(session_dir_for_worktree "$wt_name")
    if [ -n "$sd" ] && [ -f "$sd/conductor.json" ]; then
        jq --arg url "$pr_url" '.state_detail = $url' "$sd/conductor.json" \
            > "$sd/conductor.json.tmp" 2>/dev/null \
            && mv "$sd/conductor.json.tmp" "$sd/conductor.json"
        log "INFO" "$wt_name: backfilled state_detail=$pr_url (was empty)"
    fi

    echo "$pr_number $pr_url"
}

# Emit conductor-state-reported event. Best-effort; never fails the cycle.
# Also keeps the legacy marker file at $CONDUCTOR_DIR/markers/<wt>.state in
# sync with conductor.json, so any consumer reading the marker (including the
# tmux picker) sees the same truth as the reconciler. Without this sync,
# reconcile_pr_states_with_github would update conductor.json to "merged" but
# leave the marker stale at "awaiting_review" — the bug that left convoy
# worktrees displayed as awaiting_review long after their PRs merged.
emit_state() {
    local wt="$1" s="$2" d="${3:-}"
    [ -x "$CONDUCTOR_DIR/bin/worktree-event" ] || return 0
    local text="$s"
    [ -n "$d" ] && text="$s|$d"
    "$CONDUCTOR_DIR/bin/worktree-event" conductor-state-reported \
        --ticket "$wt" --text "$text" >/dev/null 2>&1 || true
    # Mirror to legacy marker file (best-effort).
    local markers_dir="$CONDUCTOR_DIR/markers"
    mkdir -p "$markers_dir" 2>/dev/null || true
    printf '%s' "$text" > "$markers_dir/$wt.state" 2>/dev/null || true
}

# Resolve the worktree path for a session_dir. Returns empty if the worktree
# directory is gone (cleanup needed elsewhere). session_dir layout:
#   $WORKTREES_BASE/<project>/.worktree-meta/sessions/<wt>
worktree_path_for_session() {
    local sd="$1"
    [ -n "$sd" ] || return 0
    local wt
    wt=$(basename "$sd")
    # WORKTREES_BASE is per-project — worktrees live directly under it.
    local path="$WORKTREES_BASE/$wt"
    [ -d "$path" ] || return 0
    echo "$path"
}

# Run `gh <args>` against a specific worktree's git remote. Picks the gh host
# from the remote URL (github.com vs github.groupondev.com) and, when the
# remote owner matches a logged-in gh username, uses that account's token.
# This unblocks reconciliation for personal repos (e.g. patrykk21/convoy)
# while keeping work-org repos using the active account.
gh_pr() {
    local wt_path="$1"; shift
    [ -d "$wt_path" ] || return 1
    local remote_url host="github.com" owner token
    remote_url=$(git -C "$wt_path" remote get-url origin 2>/dev/null)
    case "$remote_url" in
        *github.groupondev.com*) host="github.groupondev.com" ;;
    esac
    owner=$(printf '%s' "$remote_url" | sed -nE 's#.*[:/]([^/:]+)/[^/]+(\.git)?$#\1#p')

    # Resolution order (must match launch-pr.sh):
    #   1. ~/worktrees/.metadata/repos.json — explicit gh_account per repo,
    #      keyed by main_path or $WORKTREES_BASE/<repo>/ prefix. Required for
    #      org-owned repos (groupon/echelon) where OWNER doesn't match a gh
    #      username; without this, gh falls back to the active account which
    #      may not have access and the reconciler gets empty pr_state.
    #   2. OWNER as username (correct for personal patrykk21/* repos).
    #   3. Active account (gh default).
    token=""
    local repos_json="$HOME/worktrees/.metadata/repos.json"
    if [ -f "$repos_json" ] && command -v jq >/dev/null 2>&1; then
        local meta_repo meta_account meta_host
        meta_repo=$(jq -r --arg cwd "$wt_path" --arg wbase "$HOME/worktrees" '
            .repositories | to_entries
            | map(. as $e | select(
                ($cwd | startswith($e.value.main_path)) or
                ($cwd | startswith($wbase + "/" + $e.key + "/"))
              ))
            | .[0].key // empty
        ' "$repos_json" 2>/dev/null)
        if [ -n "$meta_repo" ]; then
            meta_host=$(jq -r --arg k "$meta_repo" '.repositories[$k].gh_host // empty' "$repos_json" 2>/dev/null)
            meta_account=$(jq -r --arg k "$meta_repo" '.repositories[$k].gh_account // empty' "$repos_json" 2>/dev/null)
            [ -n "$meta_host" ] && host="$meta_host"
            if [ -n "$meta_account" ]; then
                token=$(gh auth token --hostname "$host" --user "$meta_account" 2>/dev/null)
            fi
        fi
    fi
    if [ -z "$token" ] && [ -n "$owner" ]; then
        token=$(gh auth token --hostname "$host" --user "$owner" 2>/dev/null)
    fi

    if [ -n "$token" ]; then
        ( cd "$wt_path" && GH_HOST="$host" GH_TOKEN="$token" gh "$@" )
    else
        ( cd "$wt_path" && GH_HOST="$host" gh "$@" )
    fi
}

# Run `gh <args>` against the host/repo derived from a PR URL. Used during
# reconciliation when a worker opened the PR in a different repo than the
# conductor worktree (e.g. an echelon worktree whose actual change landed on
# github.groupondev.com/Mobile-Next/next-pwa-app#15697). The worktree's own
# `origin` is irrelevant here — we trust the URL the worker emitted via
# `state awaiting_ci PR_URL` and route the gh call to that host/repo.
#
# For `gh pr ...` subcommands, --repo OWNER/REPO is injected so the call
# lands on the right repository even though our cwd's git remote points
# elsewhere. Non-`pr` commands (e.g. `api user`) only need GH_HOST.
#
# Returns 1 if the URL doesn't parse — caller should fall back to gh_pr.
gh_pr_url() {
    local pr_url="$1"; shift
    [ -n "$pr_url" ] || return 1

    # Parse https://HOST/OWNER/REPO/pull/NUMBER
    local host owner repo
    host=$(printf '%s'  "$pr_url" | sed -nE 's#^https?://([^/]+)/.*#\1#p')
    owner=$(printf '%s' "$pr_url" | sed -nE 's#^https?://[^/]+/([^/]+)/[^/]+/pull/[0-9]+.*#\1#p')
    repo=$(printf '%s'  "$pr_url" | sed -nE 's#^https?://[^/]+/[^/]+/([^/]+)/pull/[0-9]+.*#\1#p')
    if [ -z "$host" ] || [ -z "$owner" ] || [ -z "$repo" ]; then
        return 1
    fi

    # Token resolution mirrors gh_pr but keys off the URL's host instead of
    # the worktree's remote. Order: repos.json entry whose gh_host matches
    # → OWNER as a gh username on that host → active account.
    local token=""
    local repos_json="$HOME/worktrees/.metadata/repos.json"
    if [ -f "$repos_json" ] && command -v jq >/dev/null 2>&1; then
        local acct
        acct=$(jq -r --arg host "$host" '
            .repositories | to_entries
            | map(select((.value.gh_host // "github.com") == $host))
            | .[0].value.gh_account // empty
        ' "$repos_json" 2>/dev/null)
        if [ -n "$acct" ]; then
            token=$(gh auth token --hostname "$host" --user "$acct" 2>/dev/null)
        fi
    fi
    if [ -z "$token" ]; then
        token=$(gh auth token --hostname "$host" --user "$owner" 2>/dev/null)
    fi

    local extra=()
    if [ "${1:-}" = "pr" ]; then
        extra=(--repo "$owner/$repo")
    fi

    if [ -n "$token" ]; then
        GH_HOST="$host" GH_TOKEN="$token" gh "$@" "${extra[@]}"
    else
        GH_HOST="$host" gh "$@" "${extra[@]}"
    fi
}

# --- Check Active Work ---
check_active_work() {
    local meta
    meta=$(meta_read)
    local status
    status=$(echo "$meta" | jq -r '.status')

    if [ "$status" = "idle" ]; then
        # Launcher already updated metadata to idle (completed successfully)
        log "INFO" "Previous task completed (launcher updated metadata)."
        return 0
    fi

    if [ "$status" = "failed" ]; then
        # Launcher already updated metadata to failed
        local last_ticket
        last_ticket=$(echo "$meta" | jq -r '.history[-1].ticket // "unknown"')
        local last_reason
        last_reason=$(echo "$meta" | jq -r '.history[-1].details // "unknown"')
        log "WARN" "$last_ticket failed: $last_reason"
        comment_on_ticket "$last_ticket" "Conductor encountered an issue and could not complete this ticket automatically. Reason: $last_reason"
        log "WARN" "State is FAILED. Run 'conductor reset $PROJECT_NAME' to retry."
        return 0
    fi

    if [ "$status" != "working" ]; then
        return 1
    fi

    # Status is "working" — check Claude's reported state in conductor.json
    local ticket worktree_name
    ticket=$(echo "$meta" | jq -r '.current.ticket')
    worktree_name=$(echo "$meta" | jq -r '.current.worktree_name')

    log "INFO" "Checking active work: $ticket ($worktree_name)"

    local cur_state cur_detail
    cur_state=$(read_session_state "$worktree_name")
    cur_detail=$(read_session_detail "$worktree_name")

    if [ -n "$cur_state" ]; then
        case "$cur_state" in
            awaiting_ci|awaiting_review)
                log "INFO" "$ticket: $cur_state. PR: $cur_detail"
                # Transition Jira ticket to Code Review (if not already)
                transition_to_code_review "$ticket"
                if [ -n "${PR_ASSIGNEE:-}" ]; then
                    meta_write "$(echo "$meta" | jq \
                        --arg pr "$cur_detail" \
                        --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                        '.status = "pending_assignment" | .current.pr_url = $pr | .current.completed_at = $now')"
                    log "INFO" "State: pending_assignment (waiting for CI/reviews)"
                else
                    meta_set_idle_from_completion "$cur_detail"
                    log "INFO" "State: idle"
                fi
                return 0
                ;;
            failed)
                log "WARN" "$ticket failed: $cur_detail"
                comment_on_ticket "$ticket" "Conductor encountered an issue. Reason: $cur_detail"
                meta_set_failed "$cur_detail"
                return 0
                ;;
            needs_input)
                log "INFO" "$ticket: Claude needs input — $cur_detail"
                # Don't transition — just log. User will attach to tmux.
                ;;
            blocked)
                log "INFO" "$ticket: blocked — $cur_detail"
                # Free the concurrency slot; user/scheduler unblocks via /with-markers.
                meta_set_idle_from_completion "blocked: $cur_detail"
                return 0
                ;;
            working)
                log "INFO" "$ticket: Claude is working — $cur_detail"
                ;;
        esac
    fi

    # On tmux: check if session is still alive as secondary signal
    if [ "$HAS_TMUX" = true ]; then
        if ! tmux has-session -t "$worktree_name" 2>/dev/null; then
            log "WARN" "Session $worktree_name died unexpectedly (tmux session gone)"
            comment_on_ticket "$ticket" "Conductor: Session terminated unexpectedly. Keeping in progress for manual review."
            meta_set_failed "Session died (tmux session gone)"
            log "WARN" "State set to FAILED. Run 'conductor reset $PROJECT_NAME' to retry."
            return 0
        fi
    elif [ "$PLATFORM" != "windows" ]; then
        # Background process: check PID file
        local pid_file="$PIDS_DIR/${worktree_name}-claude.pid"
        if [ -f "$pid_file" ]; then
            local claude_pid
            claude_pid=$(cat "$pid_file" 2>/dev/null || echo "")
            if [ -n "$claude_pid" ] && ! kill -0 "$claude_pid" 2>/dev/null; then
                log "WARN" "Session $worktree_name died unexpectedly (PID $claude_pid gone)"
                comment_on_ticket "$ticket" "Conductor: Session terminated unexpectedly. Keeping in progress for manual review."
                meta_set_failed "Session died (PID gone)"
                log "WARN" "State set to FAILED. Run 'conductor reset $PROJECT_NAME' to retry."
                return 0
            fi
        fi
    fi
    # On Windows: launcher updates metadata when done, so if still "working", Claude is running.

    # Check for timeout (4 hours max)
    local started_at now_epoch started_epoch elapsed max_seconds
    started_at=$(echo "$meta" | jq -r '.current.started_at')
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
        comment_on_ticket "$ticket" "Conductor: Timed out after $(( elapsed / 3600 )) hours. Keeping in progress for manual review."
        meta_set_failed "Timeout after ${elapsed}s"
        log "WARN" "State set to FAILED. Run 'conductor reset $PROJECT_NAME' to retry."
        return 0
    fi

    log "INFO" "$ticket still in progress ($(( elapsed / 60 ))m elapsed)"
    return 0
}

# --- Post-Completion PR Monitor ---
# When status is "pending_assignment": check if CI passed + reviews done, then assign PR
check_pending_assignment() {
    [ -z "${PR_ASSIGNEE:-}" ] && return 1

    local meta
    meta=$(meta_read)
    local status
    status=$(echo "$meta" | jq -r '.status')
    [ "$status" != "pending_assignment" ] && return 1

    local pr_url ticket pr_number
    pr_url=$(echo "$meta" | jq -r '.current.pr_url // empty')
    ticket=$(echo "$meta" | jq -r '.current.ticket // empty')
    pr_number=$(echo "$pr_url" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+')

    if [ -z "$pr_number" ]; then
        log "WARN" "pending_assignment but no PR number found — moving to idle"
        meta_set_idle_from_completion "$pr_url"
        return 0
    fi

    # Use the URL's host/repo (handles cross-repo PRs); PROJECT_DIR's remote
    # is no longer trusted as the source of host/repo for these queries.
    # Check CI status
    local ci_states
    ci_states=$(gh_pr_url "$pr_url" pr checks "$pr_number" --json 'state' -q '.[].state' 2>/dev/null)
    if [ -z "$ci_states" ]; then
        ( cd "$PROJECT_DIR" 2>/dev/null && gh pr checks "$pr_number" --json 'state' -q '.[].state' 2>/dev/null ) > /tmp/ap_ci_states.$$ 2>/dev/null
        ci_states=$(cat /tmp/ap_ci_states.$$ 2>/dev/null); rm -f /tmp/ap_ci_states.$$
    fi

    if echo "$ci_states" | grep -q "FAILURE"; then
        log "WARN" "PR #$pr_number ($ticket): CI failed — assigning anyway for review"
        # Assign even on CI failure so someone can fix it
    elif echo "$ci_states" | grep -q "PENDING\|QUEUED"; then
        log "INFO" "PR #$pr_number ($ticket): CI still running"
        return 0
    fi

    # Check review status — wait for at least one review to be submitted
    local review_count
    review_count=$(gh_pr_url "$pr_url" pr view "$pr_number" --json 'reviews' -q '.reviews | length' 2>/dev/null)
    [ -z "$review_count" ] && review_count=$( ( cd "$PROJECT_DIR" 2>/dev/null && gh pr view "$pr_number" --json 'reviews' -q '.reviews | length' 2>/dev/null ) || echo "0" )
    [ -z "$review_count" ] && review_count="0"

    if [ "$review_count" = "0" ]; then
        log "INFO" "PR #$pr_number ($ticket): no reviews submitted yet — waiting"
        return 0
    fi

    local review_state
    review_state=$(gh_pr_url "$pr_url" pr view "$pr_number" --json 'reviewDecision' -q '.reviewDecision' 2>/dev/null)
    [ -z "$review_state" ] && review_state=$( ( cd "$PROJECT_DIR" 2>/dev/null && gh pr view "$pr_number" --json 'reviewDecision' -q '.reviewDecision' 2>/dev/null ) || echo "" )
    log "INFO" "PR #$pr_number ($ticket): $review_count review(s), decision: ${review_state:-pending}"

    # CI done + reviews done (or submitted) — assign and move to idle
    log "INFO" "PR #$pr_number ($ticket): ready — assigning to $PR_ASSIGNEE"
    local current_user
    current_user=$(gh_pr_url "$pr_url" api user -q '.login' 2>/dev/null || echo "")
    [ -z "$current_user" ] && current_user=$(gh api user -q '.login' 2>/dev/null || echo "")

    if gh_pr_url "$pr_url" pr edit "$pr_number" --add-assignee "$PR_ASSIGNEE" ${current_user:+--remove-assignee "$current_user"} 2>/dev/null \
       || ( cd "$PROJECT_DIR" 2>/dev/null && gh pr edit "$pr_number" --add-assignee "$PR_ASSIGNEE" ${current_user:+--remove-assignee "$current_user"} 2>/dev/null ); then
        log "INFO" "PR #$pr_number assigned to $PR_ASSIGNEE${current_user:+, unassigned $current_user}"
    else
        log "WARN" "Failed to assign PR #$pr_number (continuing anyway)"
    fi

    # Move to idle + record in history
    meta_set_idle_from_completion "$pr_url"
    return 0
}

# --- GitHub State Reconciliation ---
# Single source of truth: query GH for every session that references a PR and
# patch the per-worktree conductor.json so the picker can never display a stale
# state. Runs first in the cycle.
#
# Mapping:
#   PR state MERGED                              -> merged
#   PR state CLOSED                              -> closed
#   PR state OPEN, reviewDecision APPROVED       -> approved
#   PR state OPEN, reviewDecision CHANGES_REQ.   -> (skip; let monitor_awaiting_reviews handle)
#   PR state OPEN, otherwise                     -> awaiting_review
#
# Skip: working (Claude actively editing — don't clobber), failed, needs_input, blocked.
reconcile_pr_states_with_github() {
    local wt_name
    while IFS= read -r wt_name; do
        [ -n "$wt_name" ] || continue
        local state details pr_number
        state=$(read_session_state "$wt_name")
        details=$(read_session_detail "$wt_name")

        case "$state" in
            awaiting_ci|awaiting_review|approved|merged|closed) ;;
            *) continue ;;
        esac

        # Resolve worktree path first — needed for both state_detail fallback
        # AND the gh_pr calls below.
        local sd wt_path
        sd=$(session_dir_for_worktree "$wt_name")
        wt_path=$(worktree_path_for_session "$sd")
        [ -z "$wt_path" ] && continue

        # Resolve pr_number/url with branch-name fallback when state_detail is empty.
        local pr_url resolved
        resolved=$(resolve_pr_for_worktree "$wt_name" "$wt_path" "$details")
        pr_number="${resolved%% *}"
        pr_url="${resolved#* }"
        [ -z "$pr_number" ] && continue
        # Use the resolved URL going forward (covers backfilled case).
        details="$pr_url"

        # Prefer URL-derived host/repo (handles cross-repo PRs); fall back to
        # the worktree's own remote when the URL doesn't parse cleanly.
        local pr_state pr_decision
        pr_state=$(gh_pr_url "$pr_url" pr view "$pr_number" --json state -q '.state' 2>/dev/null)
        [ -z "$pr_state" ] && pr_state=$(gh_pr "$wt_path" pr view "$pr_number" --json state -q '.state' 2>/dev/null)
        [ -z "$pr_state" ] && continue
        pr_decision=$(gh_pr_url "$pr_url" pr view "$pr_number" --json reviewDecision -q '.reviewDecision' 2>/dev/null)
        [ -z "$pr_decision" ] && pr_decision=$(gh_pr "$wt_path" pr view "$pr_number" --json reviewDecision -q '.reviewDecision' 2>/dev/null)

        local truth=""
        case "$pr_state" in
            MERGED) truth="merged" ;;
            CLOSED) truth="closed" ;;
            OPEN)
                case "$pr_decision" in
                    APPROVED) truth="approved" ;;
                    CHANGES_REQUESTED) truth="" ;;  # let monitor_awaiting_reviews drive
                    *) truth="awaiting_review" ;;
                esac
                ;;
        esac

        [ -z "$truth" ] && continue
        [ "$truth" = "$state" ] && continue

        log "INFO" "PR #$pr_number ($wt_name): reconciling state $state -> $truth"
        emit_state "$wt_name" "$truth" "$details"

        # Terminal transitions: clear review-tracking sidecar and release the slot.
        if [ "$truth" = "merged" ] || [ "$truth" = "closed" ]; then
            local sd
            sd=$(session_dir_for_worktree "$wt_name")
            [ -n "$sd" ] && rm -f "$sd/last_review_at"
            meta_set_idle_from_completion "$details"

            # Move the upstream tracker ticket to its terminal status on merge.
            # Without this, monitor_pr_merges would handle it — but reconcile runs
            # first and consumes the state transition (awaiting_review -> merged),
            # leaving monitor_pr_merges' awaiting_* filter empty. Sentinel guards
            # against double-calls if this block re-enters.
            # Only fires on merged: closed-without-merge is intentional cancellation
            # and should not auto-mark the tracker ticket as done.
            if [ "$truth" = "merged" ] && [ -n "$sd" ] && [ ! -f "$sd/tracker_done_at" ]; then
                if [ "$TRACKER" = "clickup" ]; then
                    local cu_task_id
                    cu_task_id=$(task_id_from_worktree_name_clickup "$wt_name")
                    if [ -n "$cu_task_id" ] && transition_to_done_clickup "$cu_task_id"; then
                        date -u +"%Y-%m-%dT%H:%M:%SZ" > "$sd/tracker_done_at"
                    fi
                fi
                # Jira: typically driven by PR-merge webhooks server-side; no-op here.
            fi
        fi
    done < <(list_session_worktrees)
}

# --- Review Monitor ---
# Check all worktrees in awaiting_review or approved state. If new review with
# changes requested → send /fix-pr-comments to the Claude session automatically.
# If approved → mark approved + assign.
monitor_awaiting_reviews() {
    local wt_name
    while IFS= read -r wt_name; do
        [ -n "$wt_name" ] || continue
        local state details
        state=$(read_session_state "$wt_name")
        details=$(read_session_detail "$wt_name")

        # Monitor both awaiting_review and approved states — approval can be revoked
        [ "$state" = "awaiting_review" ] || [ "$state" = "approved" ] || continue

        # Run gh in the worktree's own project context (not daemon's PROJECT_DIR)
        local sd wt_path
        sd=$(session_dir_for_worktree "$wt_name")
        [ -z "$sd" ] && continue
        wt_path=$(worktree_path_for_session "$sd")
        [ -z "$wt_path" ] && continue

        # Resolve pr_number with branch-name fallback when state_detail is empty.
        local pr_number pr_url resolved
        resolved=$(resolve_pr_for_worktree "$wt_name" "$wt_path" "$details")
        pr_number="${resolved%% *}"
        pr_url="${resolved#* }"
        [ -z "$pr_number" ] && continue

        # Check latest review timestamp — only act if new review arrived.
        # Prefer URL-derived host/repo (handles cross-repo PRs).
        local latest_review_at last_seen_file last_seen
        latest_review_at=$(gh_pr_url "$pr_url" pr view "$pr_number" --json reviews -q '[.reviews[-1].submittedAt // ""] | .[0]' 2>/dev/null || echo "")
        [ -z "$latest_review_at" ] && latest_review_at=$(gh_pr "$wt_path" pr view "$pr_number" --json reviews -q '[.reviews[-1].submittedAt // ""] | .[0]' 2>/dev/null || echo "")
        last_seen_file="$sd/last_review_at"
        last_seen=$(cat "$last_seen_file" 2>/dev/null || echo "")

        if [ "$latest_review_at" = "$last_seen" ] || [ -z "$latest_review_at" ]; then
            # No new reviews — skip
            continue
        fi

        # New review detected — update tracker
        echo "$latest_review_at" > "$last_seen_file"

        # Check review decision (URL-host first, worktree-host fallback)
        local review_decision
        review_decision=$(gh_pr_url "$pr_url" pr view "$pr_number" --json reviewDecision -q '.reviewDecision' 2>/dev/null)
        [ -z "$review_decision" ] && review_decision=$(gh_pr "$wt_path" pr view "$pr_number" --json reviewDecision -q '.reviewDecision' 2>/dev/null)

        # Check latest review state (not just decision — handles COMMENTED reviews)
        local latest_review_state
        latest_review_state=$(gh_pr_url "$pr_url" pr view "$pr_number" --json reviews -q '.reviews[-1].state // ""' 2>/dev/null || echo "")
        [ -z "$latest_review_state" ] && latest_review_state=$(gh_pr "$wt_path" pr view "$pr_number" --json reviews -q '.reviews[-1].state // ""' 2>/dev/null || echo "")

        case "$review_decision" in
            CHANGES_REQUESTED)
                log "INFO" "PR #$pr_number ($wt_name): changes requested — sending /with-markers /fix-pr-comments"
                emit_state "$wt_name" "working" "fixing review comments"
                if [ "$HAS_TMUX" = true ] && tmux has-session -t "$wt_name" 2>/dev/null; then
                    tmux send-keys -t "$wt_name:1" "/with-markers /fix-pr-comments" Enter
                fi
                ;;
            COMMENTED|"")
                # No formal decision — check if the latest review left comments
                if [ "$latest_review_state" = "COMMENTED" ] || [ "$latest_review_state" = "CHANGES_REQUESTED" ]; then
                    log "INFO" "PR #$pr_number ($wt_name): review with comments (state: $latest_review_state) — sending /with-markers /fix-pr-comments"
                    emit_state "$wt_name" "working" "fixing review comments"
                    if [ "$HAS_TMUX" = true ] && tmux has-session -t "$wt_name" 2>/dev/null; then
                        tmux send-keys -t "$wt_name:1" "/with-markers /fix-pr-comments" Enter
                    fi
                else
                    log "INFO" "PR #$pr_number ($wt_name): no actionable review — waiting"
                fi
                ;;
            APPROVED)
                log "INFO" "PR #$pr_number ($wt_name): approved — ready to merge!"
                # Assign to reviewer (URL-derived host first, worktree fallback)
                if [ -n "${PR_ASSIGNEE:-}" ]; then
                    local current_user
                    current_user=$(gh_pr_url "$pr_url" api user -q '.login' 2>/dev/null || echo "")
                    [ -z "$current_user" ] && current_user=$(gh_pr "$wt_path" api user -q '.login' 2>/dev/null || echo "")
                    gh_pr_url "$pr_url" pr edit "$pr_number" --add-assignee "$PR_ASSIGNEE" ${current_user:+--remove-assignee "$current_user"} 2>/dev/null \
                        || gh_pr "$wt_path" pr edit "$pr_number" --add-assignee "$PR_ASSIGNEE" ${current_user:+--remove-assignee "$current_user"} 2>/dev/null
                    log "INFO" "PR #$pr_number assigned to $PR_ASSIGNEE"
                fi
                # Set approved state — stays here until manually merged
                emit_state "$wt_name" "approved" "$details"
                ;;
            *)
                # No decision yet or review pending — do nothing
                ;;
        esac
    done < <(list_session_worktrees)
}

# --- Approved PR Monitor ---
# Check sessions with PR-bearing states — once PR is merged, transition to idle.
monitor_pr_merges() {
    local wt_name
    while IFS= read -r wt_name; do
        [ -n "$wt_name" ] || continue
        local state details
        state=$(read_session_state "$wt_name")
        details=$(read_session_detail "$wt_name")

        # Check any state that has a PR URL (awaiting_ci, awaiting_review, approved)
        case "$state" in
            awaiting_ci|awaiting_review|approved) ;;
            *) continue ;;
        esac

        local sd wt_path
        sd=$(session_dir_for_worktree "$wt_name")
        wt_path=$(worktree_path_for_session "$sd")
        [ -z "$wt_path" ] && continue

        local pr_number resolved
        resolved=$(resolve_pr_for_worktree "$wt_name" "$wt_path" "$details")
        pr_number="${resolved%% *}"
        [ -z "$pr_number" ] && continue
        details="${resolved#* }"

        # URL-derived host first (cross-repo safe), worktree remote as fallback.
        local pr_state
        pr_state=$(gh_pr_url "$details" pr view "$pr_number" --json state -q '.state' 2>/dev/null)
        [ -z "$pr_state" ] && pr_state=$(gh_pr "$wt_path" pr view "$pr_number" --json state -q '.state' 2>/dev/null)

        if [ "$pr_state" = "MERGED" ]; then
            log "INFO" "PR #$pr_number ($wt_name): merged!"
            emit_state "$wt_name" "merged" "$details"
            [ -n "$sd" ] && rm -f "$sd/last_review_at"
            meta_set_idle_from_completion "$details"
            # Move the upstream tracker ticket to its terminal status so the
            # board reflects reality. Currently only ClickUp — Jira typically
            # has its own automation rules tied to PR-merge webhooks.
            if [ "$TRACKER" = "clickup" ]; then
                local cu_task_id
                cu_task_id=$(task_id_from_worktree_name_clickup "$wt_name")
                [ -n "$cu_task_id" ] && transition_to_done_clickup "$cu_task_id" || true
            fi
        elif [ "$pr_state" = "CLOSED" ]; then
            log "INFO" "PR #$pr_number ($wt_name): closed without merge — marking terminal"
            emit_state "$wt_name" "closed" "$details"
            [ -n "$sd" ] && rm -f "$sd/last_review_at"
            meta_set_idle_from_completion "$details"
        elif [ "$pr_state" = "OPEN" ] && [ "$state" != "approved" ]; then
            # Check if review decision changed to APPROVED
            local decision
            decision=$(gh_pr_url "$details" pr view "$pr_number" --json reviewDecision -q '.reviewDecision' 2>/dev/null)
            [ -z "$decision" ] && decision=$(gh_pr "$wt_path" pr view "$pr_number" --json reviewDecision -q '.reviewDecision' 2>/dev/null)
            if [ "$decision" = "APPROVED" ]; then
                log "INFO" "PR #$pr_number ($wt_name): approved — ready to merge!"
                emit_state "$wt_name" "approved" "$details"
                if [ -n "${PR_ASSIGNEE:-}" ]; then
                    local current_user
                    current_user=$(gh_pr_url "$details" api user -q '.login' 2>/dev/null || echo "")
                    [ -z "$current_user" ] && current_user=$(gh_pr "$wt_path" api user -q '.login' 2>/dev/null || echo "")
                    gh_pr_url "$details" pr edit "$pr_number" --add-assignee "$PR_ASSIGNEE" ${current_user:+--remove-assignee "$current_user"} 2>/dev/null \
                        || gh_pr "$wt_path" pr edit "$pr_number" --add-assignee "$PR_ASSIGNEE" ${current_user:+--remove-assignee "$current_user"} 2>/dev/null
                    log "INFO" "PR #$pr_number assigned to $PR_ASSIGNEE"
                fi
            fi
        fi
    done < <(list_session_worktrees)
}

# --- Conflict Monitor ---
# Check idle worktrees (awaiting_review, approved) for merge conflicts with base branch.
# If conflicts detected and Claude isn't actively working, send /with-markers /merge-base.
check_pr_conflicts() {
    local wt_name
    while IFS= read -r wt_name; do
        [ -n "$wt_name" ] || continue
        local state details
        state=$(read_session_state "$wt_name")
        details=$(read_session_detail "$wt_name")

        # Only check idle states — not working, not awaiting_ci
        case "$state" in
            awaiting_review|approved) ;;
            *) continue ;;
        esac

        local sd wt_path
        sd=$(session_dir_for_worktree "$wt_name")
        wt_path=$(worktree_path_for_session "$sd")
        [ -z "$wt_path" ] && continue

        local pr_number resolved
        resolved=$(resolve_pr_for_worktree "$wt_name" "$wt_path" "$details")
        pr_number="${resolved%% *}"
        [ -z "$pr_number" ] && continue

        # Check if PR is mergeable
        local mergeable
        mergeable=$(gh_pr "$wt_path" pr view "$pr_number" --json mergeable -q '.mergeable' 2>/dev/null)

        if [ "$mergeable" = "CONFLICTING" ]; then
            log "INFO" "PR #$pr_number ($wt_name): has conflicts — sending /with-markers /merge-base"
            emit_state "$wt_name" "working" "resolving merge conflicts"
            if [ "$HAS_TMUX" = true ] && tmux has-session -t "$wt_name" 2>/dev/null; then
                tmux send-keys -t "$wt_name:1" "/with-markers /merge-base" Enter
            fi
        fi
    done < <(list_session_worktrees)
}

# --- Stale Session Cleanup ---
# For sessions in non-terminal "working" state where the tmux session is gone
# and the PID is dead, mark them failed so the picker stops showing them as
# active. We never delete conductor.json — it's the audit log.
cleanup_stale_sessions() {
    local wt
    while IFS= read -r wt; do
        [ -n "$wt" ] || continue
        local state
        state=$(read_session_state "$wt")
        # Only clean up active states; terminal/idle states are already correct
        case "$state" in
            working|awaiting_ci|needs_input) ;;
            *) continue ;;
        esac

        # Live tmux session — keep
        if [ "$HAS_TMUX" = true ] && tmux has-session -t "$wt" 2>/dev/null; then
            continue
        fi
        # Live PID — keep
        if [ -f "$PIDS_DIR/${wt}-claude.pid" ]; then
            local pid
            pid=$(cat "$PIDS_DIR/${wt}-claude.pid" 2>/dev/null || echo "")
            [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && continue
        fi

        # No live session — mark failed (best effort; admin can resume manually)
        log "INFO" "Stale session $wt (state=$state): no tmux/PID — marking failed"
        emit_state "$wt" "failed" "Session terminated unexpectedly"
    done < <(list_session_worktrees)
}

# --- Main Flow ---
main() {
    # Parse flags
    local ticket_override=""
    local prev=""
    for arg in "$@"; do
        [ "$arg" = "--force" ] && export CONDUCTOR_FORCE=true
        [ "$prev" = "--ticket" ] && ticket_override="$arg"
        prev="$arg"
    done

    mkdir -p "$CONDUCTOR_DIR/logs" "$CONDUCTOR_DIR/prompts" "$CONDUCTOR_DIR/projects"

    if [ ! -f "$ENABLED_FILE" ]; then
        [[ -t 1 ]] && log "INFO" "Conductor is disabled. Run 'conductor on' to enable."
        exit 0
    fi

    acquire_lock
    if [ "$TRACKER" = "jira" ]; then
        load_jira_credentials
    fi

    log "INFO" "=== Conductor cycle started ($PROJECT_NAME, tracker: $TRACKER) ==="

    # Clean up sessions for dead processes
    cleanup_stale_sessions

    # Reconcile every PR-bearing session against GitHub truth before any other
    # monitor runs. Fixes drift between per-worktree conductor.json and actual
    # PR state (e.g. picker showing [AWAITING REVIEW] for an APPROVED PR).
    reconcile_pr_states_with_github

    # Check worktrees awaiting review — auto-fix if changes requested
    monitor_awaiting_reviews
    monitor_pr_merges
    check_pr_conflicts

    local meta
    meta=$(meta_read)
    local status
    status=$(echo "$meta" | jq -r '.status')

    # Check if we're waiting for CI/reviews before assigning PR
    if [ "$status" = "pending_assignment" ]; then
        check_pending_assignment
        meta=$(meta_read)
        status=$(echo "$meta" | jq -r '.status')
        if [ "$status" = "pending_assignment" ]; then
            # Per-worktree PR monitoring (reconcile_pr_states_with_github,
            # monitor_pr_merges, monitor_awaiting_reviews) already ran above and
            # tracks each session's PR independently, so the project-level slot
            # is only meaningful for serial single-ticket projects. Allow
            # bypass when concurrency permits or --force is set.
            if [ "${CONDUCTOR_FORCE:-}" = "true" ] || [ "$MAX_CONCURRENT_TICKETS" -gt 1 ]; then
                log "INFO" "Bypassing pending_assignment gate (force=${CONDUCTOR_FORCE:-false}, concurrency=$MAX_CONCURRENT_TICKETS)."
            else
                # Still waiting — don't pick new work
                log "INFO" "=== Conductor cycle complete (waiting for CI/reviews) ==="
                exit 0
            fi
        fi
    fi

    if [ "$status" = "working" ]; then
        check_active_work
        meta=$(meta_read)
        status=$(echo "$meta" | jq -r '.status')
        if [ "$status" = "idle" ]; then
            log "INFO" "Previous task completed successfully. Checking for next task."
            # fall through to find_ticket below
        elif [ "$status" = "working" ] && [ "$MAX_CONCURRENT_TICKETS" -gt 1 ]; then
            # Still working but concurrency allows more — fall through to pick next
            log "INFO" "Current ticket still working. Checking if we can pick more (concurrency: $MAX_CONCURRENT_TICKETS)."
            # fall through to concurrency check + find_ticket below
        else
            log "INFO" "=== Conductor cycle complete ==="
            exit 0
        fi
    elif [ "$status" = "failed" ]; then
        log "INFO" "Project in FAILED state. Run 'conductor reset $PROJECT_NAME' to resume."
        log "INFO" "=== Conductor cycle complete ==="
        exit 0
    fi

    # Enforce concurrency limit — count tickets in flight (anything not terminal).
    # Previously this only counted "working", which is a fraction of the lifecycle:
    # a session can sit in awaiting_ci / awaiting_review / approved for hours
    # while a separate ticket is picked up, blowing past MAX_CONCURRENT_TICKETS.
    # The user reported 3 convoy tickets active under a limit of 2 because none
    # were in "working" — they were in awaiting_review / awaiting_ci.
    # In flight = any non-terminal state. Terminal = merged|closed|failed.
    # blocked / needs_input still count (user/external action pending).
    local active_count=0
    local _wt
    while IFS= read -r _wt; do
        [ -n "$_wt" ] || continue
        local _s
        _s=$(read_session_state "$_wt")
        case "$_s" in
            working|awaiting_ci|awaiting_review|approved|blocked|needs_input)
                active_count=$((active_count + 1))
                ;;
        esac
    done < <(list_session_worktrees)
    if [ "$active_count" -ge "$MAX_CONCURRENT_TICKETS" ] && [ "${CONDUCTOR_FORCE:-}" != "true" ]; then
        log "INFO" "Concurrency limit reached ($active_count/$MAX_CONCURRENT_TICKETS in flight). Waiting."
        log "INFO" "=== Conductor cycle complete ==="
        exit 0
    fi
    if [ "$active_count" -ge "$MAX_CONCURRENT_TICKETS" ] && [ "${CONDUCTOR_FORCE:-}" = "true" ]; then
        log "INFO" "Concurrency limit ($active_count/$MAX_CONCURRENT_TICKETS in flight) bypassed with --force."
    fi

    # Enforce max worktrees limit — count existing worktrees for this project
    if [ -d "$PROJECT_DIR/.git" ] || [ -f "$PROJECT_DIR/.git" ]; then
        local wt_count
        # Count only worktrees under WORKTREES_BASE (exclude Cursor/IDE worktrees)
        wt_count=$(git -C "$PROJECT_DIR" worktree list 2>/dev/null | grep -c "$WORKTREES_BASE" 2>/dev/null)
        wt_count=${wt_count:-0}
        if [ "$wt_count" -ge "$MAX_WORKTREES" ] && [ "${CONDUCTOR_FORCE:-}" != "true" ]; then
            log "INFO" "Worktree limit reached ($wt_count/$MAX_WORKTREES). Clean up existing worktrees or use --force."
            log "INFO" "=== Conductor cycle complete ==="
            exit 0
        fi
    fi

    # If a specific ticket was passed via --ticket, use it directly
    if [ -n "$ticket_override" ]; then
        # Extract ticket key from URL
        TICKET_KEY=$(echo "$ticket_override" | grep -oE '[A-Z]+-[0-9]+' | tail -1)
        if [ -z "$TICKET_KEY" ]; then
            log "ERROR" "Could not extract ticket key from: $ticket_override"
            exit 1
        fi
        # Fetch real ticket metadata from Jira so worktree name is descriptive
        local override_response override_http override_body
        override_response=$(jira_api GET "/issue/$TICKET_KEY?fields=summary,issuetype,priority")
        override_http=$(echo "$override_response" | tail -1)
        override_body=$(echo "$override_response" | sed '$d')
        if [ "$override_http" = "200" ]; then
            TICKET_SUMMARY=$(echo "$override_body" | jq -r '.fields.summary // "Manual ticket override"')
            TICKET_TYPE=$(echo "$override_body" | jq -r '.fields.issuetype.name // "Task"')
            TICKET_PRIORITY=$(echo "$override_body" | jq -r '.fields.priority.name // "High"')
        else
            log "WARN" "Could not fetch $TICKET_KEY from Jira (HTTP $override_http); falling back to generic summary"
            TICKET_SUMMARY="Manual ticket override"
            TICKET_TYPE="Task"
            TICKET_PRIORITY="High"
        fi
        log "INFO" "Ticket override: $TICKET_KEY - $TICKET_SUMMARY ($TICKET_TYPE, $TICKET_PRIORITY) (from $ticket_override)"
    elif ! find_ticket; then
        log "INFO" "=== Conductor cycle complete (no work) ==="
        exit 0
    fi

    log "INFO" "=== Starting work on $TICKET_KEY ==="

    if ! transition_ticket "$TICKET_KEY"; then
        log "ERROR" "Could not transition $TICKET_KEY. Skipping."
        exit 1
    fi

    local worktree_name
    worktree_name=$(create_worktree_name "$TICKET_KEY" "$TICKET_SUMMARY")

    local effective_base="${PICKER_BASE_BRANCH:-$BASE_BRANCH}"
    if ! setup_worktree "$worktree_name" "$effective_base"; then
        log "ERROR" "Failed to create worktree for $TICKET_KEY"
        comment_on_ticket "$TICKET_KEY" "Conductor: Failed to create worktree. Keeping in progress for manual intervention."
        meta_set_failed "Worktree creation failed"
        exit 1
    fi

    if ! setup_session "$worktree_name"; then
        log "ERROR" "Failed to create session for $TICKET_KEY"
        comment_on_ticket "$TICKET_KEY" "Conductor: Failed to create session."
        meta_set_failed "Session creation failed"
        exit 1
    fi

    # Port is resolved from worktree metadata (set by create-worktree-session.sh)
    local port
    port=$(resolve_port "$worktree_name")

    start_dev_server "$worktree_name"

    local ticket_url
    ticket_url=$(build_ticket_url "$TICKET_KEY")

    # Set metadata to working BEFORE launching Claude
    meta_set_working "$TICKET_KEY" "$ticket_url" "$worktree_name" "${RESOLVED_WORKTREE_PATH:-$WORKTREES_BASE/$worktree_name}" "$effective_base"

    launch_claude "$worktree_name" "$TICKET_KEY" "$port"

    comment_on_ticket "$TICKET_KEY" "Conductor: Started working on this ticket. Worktree: $worktree_name, Port: $port"

    log "INFO" "=== $TICKET_KEY dispatched to Claude. Will check on next cycle. ==="
}

main "$@"
