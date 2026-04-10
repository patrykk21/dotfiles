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
# State is stored in a single metadata JSON file per project:
#   projects/<project>.state.json
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
CLICKUP_TAG="${CLICKUP_TAG:-claude-autopilot}"

# AI Picker defaults
AI_PICKER_ENABLED="${AI_PICKER_ENABLED:-true}"
PICKER_MODEL="${PICKER_MODEL:-sonnet}"

# Concurrency: max tickets worked on simultaneously
MAX_CONCURRENT_TICKETS="${MAX_CONCURRENT_TICKETS:-1}"

# Max worktrees per project — won't pick new tickets if this limit is reached
MAX_WORKTREES="${MAX_WORKTREES:-8}"

# Unified metadata file (single source of truth per project)
META_FILE="$AUTOPILOT_DIR/projects/${PROJECT_NAME}.state.json"
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
    local activity="Autopilot: $ticket"
    local pr_num
    pr_num=$(echo "$details" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+')
    [ -n "$pr_num" ] && activity="Autopilot: $ticket -> PR #$pr_num"

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
        log "INFO" "Another autopilot instance is running (PID: $lock_pid). Exiting."
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

find_autopilot_ticket_clickup() {
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
    if [ "$TRACKER" = "clickup" ] && [ "${AI_PICKER_ENABLED:-true}" = "true" ]; then
        if ai_pick_ticket; then return 0; fi
        log "WARN" "AI picker failed, falling back to oldest-first"
    fi
    if [ "$TRACKER" = "clickup" ]; then
        find_autopilot_ticket_clickup
    else
        find_autopilot_ticket
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

ai_pick_ticket() {
    log "INFO" "Running AI ticket picker (model: $PICKER_MODEL)"

    if ! fetch_all_candidates_clickup; then
        return 1
    fi

    gather_local_context

    # Build picker prompt
    local prompt_file="$AUTOPILOT_DIR/prompts/_picker_prompt.md"
    mkdir -p "$AUTOPILOT_DIR/prompts"
    cat > "$prompt_file" << 'PICKER_HEADER'
You are choosing the next task for an autonomous coding agent to implement.

## Instructions
- Pick the task that should be done NEXT considering dependencies and priority.
- If task B depends on task A, A must be completed first (check completed history for matching task IDs).
- Priority ordering: 1=urgent, 2=high, 3=normal, 4=low, null=none. Prefer higher priority.
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

    # Check worktrunk path pattern first (project.branch)
    local wt_path="$(dirname "$PROJECT_DIR")/$(basename "$PROJECT_DIR").${worktree_name}"
    if [ -d "$wt_path" ]; then
        log "INFO" "Worktree already exists: $wt_path"
        RESOLVED_WORKTREE_PATH="$wt_path"
        return 0
    fi
    if [ -d "$worktree_path" ]; then
        log "INFO" "Worktree already exists: $worktree_path"
        RESOLVED_WORKTREE_PATH="$worktree_path"
        return 0
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
    fi

    # Install dependencies if configured
    if [ -n "$INSTALL_CMD" ]; then
        log "INFO" "Installing dependencies: $INSTALL_CMD"
        cd "$worktree_path" && eval "$INSTALL_CMD" 2>&1 | tail -5 | while read -r line; do
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

PIDS_DIR="$AUTOPILOT_DIR/pids"

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

    # Tag worktree metadata with autopilot=true
    local meta_session_file="$WORKTREES_BASE/.worktree-meta/sessions/${worktree_name}.json"
    if [ -f "$meta_session_file" ]; then
        jq '.autopilot = true' "$meta_session_file" > "${meta_session_file}.tmp" && mv "${meta_session_file}.tmp" "$meta_session_file"
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
        local server_log="$AUTOPILOT_DIR/logs/${worktree_name}-server.log"
        tmux send-keys -t "$worktree_name:2" "$DEV_SERVER_CMD 2>&1 | tee $server_log" Enter
    else
        # Run dev server as background process with PID tracking
        local port
        port=$(resolve_port "$worktree_name")
        local server_log="$AUTOPILOT_DIR/logs/${worktree_name}-server.log"
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
        -e 's|{{COMPLETION_MARKER}}|$AUTOPILOT_COMPLETION_MARKER|g' \
        -e 's|{{FAILURE_MARKER}}|$AUTOPILOT_FAILURE_MARKER|g' \
        "$PROMPT_TEMPLATE" > "$prompt_file"

    echo "$prompt_file"
}

launch_claude() {
    local worktree_name="$1"
    local ticket_key="$2"
    local port="${3:-}"
    local worktree_path="${RESOLVED_WORKTREE_PATH:-$WORKTREES_BASE/$worktree_name}"
    local server_log="$AUTOPILOT_DIR/logs/${worktree_name}-server.log"

    # Build ticket URL (tracker-agnostic)
    local ticket_url
    ticket_url=$(build_ticket_url "$ticket_key")

    # Build a readable tab title
    local tab_title="🤖 ${ticket_key} — ${TICKET_SUMMARY:-$worktree_name}"

    # Convert META_FILE to a Windows path for jq inside the launcher if needed
    local meta_file_path="$META_FILE"

    # Write a launcher script — starts Claude interactively with /autopilot command
    # Claude writes to temp marker files; the launcher reads them after Claude exits
    # and updates the unified metadata JSON.
    local launcher="$AUTOPILOT_DIR/prompts/${worktree_name}.sh"
    cat > "$launcher" << LAUNCHER
#!/usr/bin/env bash
# Set terminal tab title
echo -ne "\\033]0;${tab_title}\\007"
cd '$worktree_path'

# Marker files at fixed paths — the runner checks these each cycle
# so state updates even while Claude is still running in the TUI
MARKERS_DIR="$AUTOPILOT_DIR/markers"
mkdir -p "\$MARKERS_DIR"
export AUTOPILOT_STATE_MARKER="\$MARKERS_DIR/${worktree_name}.state"
# Legacy compat — some commands may still reference these
export AUTOPILOT_COMPLETION_MARKER="\$MARKERS_DIR/${worktree_name}.done"
export AUTOPILOT_FAILURE_MARKER="\$MARKERS_DIR/${worktree_name}.failed"
export AUTOPILOT_WAITING_MARKER="\$MARKERS_DIR/${worktree_name}.waiting"
export AUTOPILOT_PR_ASSIGNEE="${PR_ASSIGNEE:-}"

# Run Claude
SYSTEM_PROMPT="YOU ARE RUNNING IN AN AUTOPILOT SESSION with a state marker file at:
  \$AUTOPILOT_STATE_MARKER

This file controls the workflow. Write to it whenever your state changes. Format: STATE|details

STATES (write exactly these):
  working|description of what you're doing     — you are actively coding, testing, committing
  awaiting_ci|PR_URL                           — you created/updated a PR, CI and reviews will run
  needs_input|your question                    — you need the user to answer something
  failed|reason                                — you cannot complete the task

WHEN TO TRANSITION:
  Session starts                → echo \"working|reading ticket and planning\" > \$AUTOPILOT_STATE_MARKER
  Actively implementing         → echo \"working|implementing changes\" > \$AUTOPILOT_STATE_MARKER
  Created or updated a PR       → echo \"awaiting_ci|PR_URL\" > \$AUTOPILOT_STATE_MARKER
  Need user input               → echo \"needs_input|your question\" > \$AUTOPILOT_STATE_MARKER
  User responded                → echo \"working|addressing feedback\" > \$AUTOPILOT_STATE_MARKER
  Cannot complete               → echo \"failed|reason\" > \$AUTOPILOT_STATE_MARKER

IMPORTANT: Update this file EVERY time your state changes. The tmux worktree picker and autopilot scheduler read it to show your current status.

ENVIRONMENT:
  - Dev server running on port \$SERVER_PORT
  - Server logs: $server_log
  - Do NOT assign the PR — the scheduler handles that after CI and reviews pass"

$CLAUDE_BIN --dangerously-skip-permissions --name "${tab_title}" \
  --append-system-prompt "\$SYSTEM_PROMPT" \
  "/autopilot $ticket_url"
EXIT_CODE=\$?

# Update metadata JSON based on outcome
META_FILE="$meta_file_path"
NOW=\$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ -f "\$COMPLETION_MARKER" ] && [ -s "\$COMPLETION_MARKER" ]; then
    DETAILS=\$(cat "\$COMPLETION_MARKER")
    if [ -n "\$AUTOPILOT_PR_ASSIGNEE" ]; then
        # PR needs CI/review before assignment — stay in pending_assignment
        jq --arg details "\$DETAILS" --arg now "\$NOW" \\
          '.status = "pending_assignment" | .current.pr_url = \$details | .current.completed_at = \$now' \\
          "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
    else
        # No assignee configured — go straight to idle
        jq --arg details "\$DETAILS" --arg now "\$NOW" \\
          '.status = "idle" | .history += [.current + {outcome: "completed", details: \$details, completed_at: \$now}] | .current = null' \\
          "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
    fi
elif [ -f "\$FAILURE_MARKER" ] && [ -s "\$FAILURE_MARKER" ]; then
    REASON=\$(cat "\$FAILURE_MARKER")
    jq --arg reason "\$REASON" --arg now "\$NOW" \\
      '.status = "failed" | .history += [.current + {outcome: "failed", details: \$reason, completed_at: \$now}] | .current = null' \\
      "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
elif [ "\$EXIT_CODE" -eq 0 ]; then
    jq --arg now "\$NOW" \\
      '.status = "failed" | .history += [.current + {outcome: "failed", details: "Exit 0 but no completion marker", completed_at: \$now}] | .current = null' \\
      "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
else
    jq --arg code "\$EXIT_CODE" --arg now "\$NOW" \\
      '.status = "failed" | .history += [.current + {outcome: "failed", details: ("Exit code: " + \$code), completed_at: \$now}] | .current = null' \\
      "\$META_FILE" > "\${META_FILE}.tmp" && mv "\${META_FILE}.tmp" "\$META_FILE"
fi

# Cleanup temp markers
rm -f "\$COMPLETION_MARKER" "\$FAILURE_MARKER" "\$WAITING_MARKER"

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
        bash "$launcher" >> "$AUTOPILOT_DIR/logs/${worktree_name}-claude.log" 2>&1 &
        local claude_pid=$!
        echo "$claude_pid" > "$PIDS_DIR/${worktree_name}-claude.pid"
        log "INFO" "Claude launched in background (PID: $claude_pid)"
    fi

    log "INFO" "Claude launched. Metadata will be updated by launcher on exit."
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
        comment_on_ticket "$last_ticket" "Autopilot encountered an issue and could not complete this ticket automatically. Reason: $last_reason"
        log "WARN" "State is FAILED. Run 'autopilot reset $PROJECT_NAME' to retry."
        return 0
    fi

    if [ "$status" != "working" ]; then
        return 1
    fi

    # Status is "working" — check Claude's state marker for transitions
    local ticket worktree_name
    ticket=$(echo "$meta" | jq -r '.current.ticket')
    worktree_name=$(echo "$meta" | jq -r '.current.worktree_name')

    log "INFO" "Checking active work: $ticket ($worktree_name)"

    # Read the unified state marker (format: STATE|details)
    local state_marker="$AUTOPILOT_DIR/markers/${worktree_name}.state"
    if [ -f "$state_marker" ] && [ -s "$state_marker" ]; then
        local marker_content marker_state marker_details
        marker_content=$(cat "$state_marker")
        marker_state=$(echo "$marker_content" | cut -d'|' -f1)
        marker_details=$(echo "$marker_content" | cut -d'|' -f2-)

        case "$marker_state" in
            awaiting_ci)
                log "INFO" "$ticket: PR created, transitioning to pending_assignment. PR: $marker_details"
                if [ -n "${PR_ASSIGNEE:-}" ]; then
                    meta_write "$(echo "$meta" | jq \
                        --arg pr "$marker_details" \
                        --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                        '.status = "pending_assignment" | .current.pr_url = $pr | .current.completed_at = $now')"
                    log "INFO" "State: pending_assignment (waiting for CI/reviews)"
                else
                    meta_set_idle_from_completion "$marker_details"
                    log "INFO" "State: idle"
                fi
                return 0
                ;;
            failed)
                log "WARN" "$ticket failed: $marker_details"
                comment_on_ticket "$ticket" "Autopilot encountered an issue. Reason: $marker_details"
                meta_set_failed "$marker_details"
                rm -f "$state_marker"
                return 0
                ;;
            needs_input)
                log "INFO" "$ticket: Claude needs input — $marker_details"
                # Don't transition — just log. User will attach to tmux.
                ;;
            working)
                log "INFO" "$ticket: Claude is working — $marker_details"
                ;;
        esac
    fi

    # On tmux: check if session is still alive as secondary signal
    if [ "$HAS_TMUX" = true ]; then
        if ! tmux has-session -t "$worktree_name" 2>/dev/null; then
            log "WARN" "Session $worktree_name died unexpectedly (tmux session gone)"
            comment_on_ticket "$ticket" "Autopilot: Session terminated unexpectedly. Keeping in progress for manual review."
            meta_set_failed "Session died (tmux session gone)"
            log "WARN" "State set to FAILED. Run 'autopilot reset $PROJECT_NAME' to retry."
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
                comment_on_ticket "$ticket" "Autopilot: Session terminated unexpectedly. Keeping in progress for manual review."
                meta_set_failed "Session died (PID gone)"
                log "WARN" "State set to FAILED. Run 'autopilot reset $PROJECT_NAME' to retry."
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
        comment_on_ticket "$ticket" "Autopilot: Timed out after $(( elapsed / 3600 )) hours. Keeping in progress for manual review."
        meta_set_failed "Timeout after ${elapsed}s"
        log "WARN" "State set to FAILED. Run 'autopilot reset $PROJECT_NAME' to retry."
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

    # Run gh commands from project dir so it picks up the correct remote
    cd "$PROJECT_DIR" 2>/dev/null || true

    # Check CI status
    local ci_states
    ci_states=$(gh pr checks "$pr_number" --json 'state' -q '.[].state' 2>/dev/null)

    if echo "$ci_states" | grep -q "FAILURE"; then
        log "WARN" "PR #$pr_number ($ticket): CI failed — assigning anyway for review"
        # Assign even on CI failure so someone can fix it
    elif echo "$ci_states" | grep -q "PENDING\|QUEUED"; then
        log "INFO" "PR #$pr_number ($ticket): CI still running"
        return 0
    fi

    # Check review status — wait for at least one review to be submitted
    local review_count
    review_count=$(gh pr view "$pr_number" --json 'reviews' -q '.reviews | length' 2>/dev/null || echo "0")

    if [ "$review_count" = "0" ]; then
        log "INFO" "PR #$pr_number ($ticket): no reviews submitted yet — waiting"
        return 0
    fi

    local review_state
    review_state=$(gh pr view "$pr_number" --json 'reviewDecision' -q '.reviewDecision' 2>/dev/null)
    log "INFO" "PR #$pr_number ($ticket): $review_count review(s), decision: ${review_state:-pending}"

    # CI done + reviews done (or submitted) — assign and move to idle
    log "INFO" "PR #$pr_number ($ticket): ready — assigning to $PR_ASSIGNEE"
    # Run gh from project dir so it picks up the correct remote
    if gh pr edit "$pr_number" --add-assignee "$PR_ASSIGNEE" 2>/dev/null; then
        log "INFO" "PR #$pr_number assigned to $PR_ASSIGNEE"
    else
        log "WARN" "Failed to assign PR #$pr_number (continuing anyway)"
    fi

    # Move to idle + record in history
    meta_set_idle_from_completion "$pr_url"
    return 0
}

# --- Stale Marker Cleanup ---
# Remove markers for worktrees with no active session (tmux or PID)
cleanup_stale_markers() {
    local markers_dir="$AUTOPILOT_DIR/markers"
    [ -d "$markers_dir" ] || return 0

    for f in "$markers_dir"/*; do
        [ -f "$f" ] || continue
        local name wt
        name=$(basename "$f")
        # Extract worktree name — strip marker suffix
        wt=$(echo "$name" | sed 's/\.\(state\|done\|waiting\|failed\|exit_code\)$//')

        # Keep markers for worktrees with live sessions
        if [ "$HAS_TMUX" = true ] && tmux has-session -t "$wt" 2>/dev/null; then
            continue
        fi
        # Check PID file fallback
        if [ -f "$PIDS_DIR/${wt}-claude.pid" ]; then
            local pid
            pid=$(cat "$PIDS_DIR/${wt}-claude.pid" 2>/dev/null || echo "")
            [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && continue
        fi

        # No live session — remove stale marker
        rm -f "$f"
    done
}

# --- Main Flow ---
main() {
    mkdir -p "$AUTOPILOT_DIR/logs" "$AUTOPILOT_DIR/prompts" "$AUTOPILOT_DIR/projects"

    if [ ! -f "$ENABLED_FILE" ]; then
        [[ -t 1 ]] && log "INFO" "Autopilot is disabled. Run 'autopilot on' to enable."
        exit 0
    fi

    acquire_lock
    if [ "$TRACKER" = "jira" ]; then
        load_jira_credentials
    fi

    log "INFO" "=== Autopilot cycle started ($PROJECT_NAME, tracker: $TRACKER) ==="

    # Clean up markers for dead sessions
    cleanup_stale_markers

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
            # Still waiting — don't pick new work
            log "INFO" "=== Autopilot cycle complete (waiting for CI/reviews) ==="
            exit 0
        fi
    fi

    if [ "$status" = "working" ]; then
        check_active_work
        meta=$(meta_read)
        status=$(echo "$meta" | jq -r '.status')
        if [ "$status" = "idle" ]; then
            # Only success sets idle — safe to pick next immediately
            log "INFO" "Previous task completed successfully. Checking for next task."
            # fall through to find_ticket below
        else
            # "failed" or still "working" — don't pick new work
            log "INFO" "=== Autopilot cycle complete ==="
            exit 0
        fi
    elif [ "$status" = "failed" ]; then
        log "INFO" "Project in FAILED state. Run 'autopilot reset $PROJECT_NAME' to resume."
        log "INFO" "=== Autopilot cycle complete ==="
        exit 0
    fi

    # Enforce concurrency limit via metadata files
    # States that block new work: "working" (active) and "failed" (needs manual reset)
    local active_count=0
    for meta_file in "$AUTOPILOT_DIR/projects/"*.state.json; do
        [ -f "$meta_file" ] || continue
        local s
        s=$(jq -r '.status' "$meta_file" 2>/dev/null || echo "")
        [ "$s" = "working" ] || [ "$s" = "failed" ] && active_count=$((active_count + 1))
    done
    if [ "$active_count" -ge "$MAX_CONCURRENT_TICKETS" ]; then
        log "INFO" "Concurrency limit reached ($active_count/$MAX_CONCURRENT_TICKETS). Waiting."
        log "INFO" "=== Autopilot cycle complete ==="
        exit 0
    fi

    # Enforce max worktrees limit — count existing worktrees for this project
    if [ -d "$PROJECT_DIR/.git" ] || [ -f "$PROJECT_DIR/.git" ]; then
        local wt_count
        wt_count=$(git -C "$PROJECT_DIR" worktree list 2>/dev/null | wc -l | tr -d ' ')
        # Subtract 1 for the main worktree (base repo)
        wt_count=$((wt_count - 1))
        if [ "$wt_count" -ge "$MAX_WORKTREES" ]; then
            log "INFO" "Worktree limit reached ($wt_count/$MAX_WORKTREES). Clean up existing worktrees before picking new tickets."
            log "INFO" "=== Autopilot cycle complete ==="
            exit 0
        fi
    fi

    if ! find_ticket; then
        log "INFO" "=== Autopilot cycle complete (no work) ==="
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
        comment_on_ticket "$TICKET_KEY" "Autopilot: Failed to create worktree. Keeping in progress for manual intervention."
        meta_set_failed "Worktree creation failed"
        exit 1
    fi

    if ! setup_session "$worktree_name"; then
        log "ERROR" "Failed to create session for $TICKET_KEY"
        comment_on_ticket "$TICKET_KEY" "Autopilot: Failed to create session."
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

    comment_on_ticket "$TICKET_KEY" "Autopilot: Started working on this ticket. Worktree: $worktree_name, Port: $port"

    log "INFO" "=== $TICKET_KEY dispatched to Claude. Will check on next cycle. ==="
}

main "$@"
