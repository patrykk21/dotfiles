#!/usr/bin/env bash

# Metadata management functions for git worktree integration
# This file provides functions to read/write worktree metadata

WORKTREES_BASE="$HOME/worktrees"
GLOBAL_METADATA_DIR="$WORKTREES_BASE/.metadata"
REPOS_JSON="$GLOBAL_METADATA_DIR/repos.json"

# Ensure metadata directories exist
ensure_metadata_dirs() {
    local repo_name="$1"
    mkdir -p "$GLOBAL_METADATA_DIR"
    [ -n "$repo_name" ] && mkdir -p "$WORKTREES_BASE/$repo_name/.worktree-meta/sessions"
}

# Register a repository in global metadata
register_repo() {
    local repo_name="$1"
    local main_path="$2"
    
    ensure_metadata_dirs
    
    # Create or update repos.json
    if [ -f "$REPOS_JSON" ]; then
        # Update existing file
        local temp_file=$(mktemp)
        jq --arg name "$repo_name" \
           --arg path "$main_path" \
           --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           '.repositories[$name] = {main_path: $path, created: $date}' \
           "$REPOS_JSON" > "$temp_file" && mv "$temp_file" "$REPOS_JSON"
    else
        # Create new file
        cat > "$REPOS_JSON" <<EOF
{
  "repositories": {
    "$repo_name": {
      "main_path": "$main_path",
      "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    }
  }
}
EOF
    fi
}

# Generate a random port between 55000 and 56000
generate_worktree_port() {
    echo $((55000 + RANDOM % 1001))
}

# Canonical per-session storage layout: one directory per ticket holding
# meta.json (identity/port), summary.json + context.md (LLM-written), conductor.json
# (runtime state), and flags/ (event markers). Readers and writers must agree on
# this layout — see docs/worktree-context-system in conductor for consumers.
_session_dir_for()  { echo "$WORKTREES_BASE/$1/.worktree-meta/sessions/$2"; }
_session_meta_for() { echo "$WORKTREES_BASE/$1/.worktree-meta/sessions/$2/meta.json"; }

# Save session metadata
save_session_metadata() {
    local repo_name="$1"
    local ticket="$2"
    local worktree_path="$3"
    local branch="$4"
    local session_name="${5:-$ticket}"

    ensure_metadata_dirs "$repo_name"

    local session_dir metadata_file
    session_dir=$(_session_dir_for "$repo_name" "$ticket")
    metadata_file="$session_dir/meta.json"

    mkdir -p "$session_dir/flags"

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Resolve port: reuse existing, else generate
    local port=""
    if [ -f "$metadata_file" ]; then
        port=$(jq -r '.port // empty' "$metadata_file" 2>/dev/null)
    fi
    if [[ ! "$ticket" =~ -base$ ]] && [ -z "$port" ]; then
        port=$(generate_worktree_port)
    fi

    # Seed from existing metadata so custom fields set by conductor —
    # e.g. `conductor: true`, `schema_version` — survive re-saves.
    local base_source='{}'
    if [ -f "$metadata_file" ]; then
        base_source=$(cat "$metadata_file")
    fi

    local tmp
    tmp=$(mktemp)
    echo "$base_source" | jq \
        --arg ticket "$ticket" \
        --arg session_name "$session_name" \
        --arg worktree_path "$worktree_path" \
        --arg branch "$branch" \
        --arg now "$now" \
        --argjson port_raw "${port:-null}" \
        '. + {
            schema_version: 1,
            ticket: $ticket,
            session_name: $session_name,
            worktree_path: $worktree_path,
            branch: $branch,
            created: (.created // $now),
            last_accessed: $now,
            tabs: (.tabs // ["claude", "server", "commands"])
        } | if $port_raw != null then .port = $port_raw else . end' \
        > "$tmp" && mv "$tmp" "$metadata_file"
}

# Helper: resolve the metadata file to read. Echoes empty if it doesn't exist.
_resolve_metadata_read() {
    local repo_name="$1" ticket="$2"
    local nested
    nested=$(_session_meta_for "$repo_name" "$ticket")
    [ -f "$nested" ] && echo "$nested"
}

# Update last accessed time
update_session_access() {
    local repo_name="$1"
    local ticket="$2"

    local metadata_file
    metadata_file=$(_resolve_metadata_read "$repo_name" "$ticket")
    [ -z "$metadata_file" ] && return 0

    local temp_file
    temp_file=$(mktemp)
    jq --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.last_accessed = $date' \
       "$metadata_file" > "$temp_file" && mv "$temp_file" "$metadata_file"
}

# Get session metadata
get_session_metadata() {
    local repo_name="$1"
    local ticket="$2"
    local field="$3"

    local metadata_file
    metadata_file=$(_resolve_metadata_read "$repo_name" "$ticket")
    [ -z "$metadata_file" ] && return 0

    if [ -n "$field" ]; then
        jq -r ".$field // empty" "$metadata_file"
    else
        cat "$metadata_file"
    fi
}

# List all sessions for a repo (directories with a meta.json inside).
list_repo_sessions() {
    local repo_name="$1"
    local sessions_dir="$WORKTREES_BASE/$repo_name/.worktree-meta/sessions"
    [ -d "$sessions_dir" ] || return 0

    find "$sessions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r dir; do
        [ -f "$dir/meta.json" ] && basename "$dir"
    done
}

# Remove session metadata — removes the per-ticket directory.
# Guarded to paths under $WORKTREES_BASE so a typoed ticket can't escape.
remove_session_metadata() {
    local repo_name="$1"
    local ticket="$2"

    local session_dir
    session_dir=$(_session_dir_for "$repo_name" "$ticket")

    if [ -d "$session_dir" ] && [[ "$session_dir" == "$WORKTREES_BASE/"* ]]; then
        rm -rf "$session_dir"
    fi
}

# Check if session exists in metadata
session_exists_in_metadata() {
    local repo_name="$1"
    local ticket="$2"
    [ -f "$(_session_meta_for "$repo_name" "$ticket")" ]
}

# Get current worktree info from path
get_worktree_info_from_path() {
    local path="$1"
    
    # Check if path is under worktrees directory
    if [[ "$path" == "$WORKTREES_BASE/"* ]]; then
        # Extract repo name and ticket from path
        local relative_path="${path#$WORKTREES_BASE/}"
        local repo_name=$(echo "$relative_path" | cut -d'/' -f1)
        local ticket=$(echo "$relative_path" | cut -d'/' -f2)
        
        echo "$repo_name|$ticket"
    fi
}

# Unified function to ensure metadata exists and get SERVER_PORT
# This is the single source of truth for all SERVER_PORT resolution
ensure_and_get_server_port() {
    local repo_name="$1"
    local ticket="$2"
    
    # Skip port assignment for base sessions
    if [[ "$ticket" =~ -base$ ]]; then
        return 0
    fi
    
    ensure_metadata_dirs "$repo_name"

    local metadata_file
    metadata_file=$(_resolve_metadata_read "$repo_name" "$ticket")
    if [ -n "$metadata_file" ]; then
        local existing_port
        existing_port=$(jq -r '.port // empty' "$metadata_file" 2>/dev/null)
        if [ -n "$existing_port" ] && [ "$existing_port" != "null" ]; then
            echo "$existing_port"
            return 0
        fi
    fi

    # No metadata or no port - need to ensure complete metadata exists
    # This handles cases where session was created outside normal flow

    # Try to gather information about the worktree
    local worktree_path="$WORKTREES_BASE/$repo_name/$ticket"
    local branch=""

    # Try to get branch from git if worktree exists
    if [ -d "$worktree_path" ] && git -C "$worktree_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null || echo "unknown")
    else
        # Fallback: use ticket name as branch name
        branch="$ticket"
    fi

    # Generate and save complete metadata
    save_session_metadata "$repo_name" "$ticket" "$worktree_path" "$branch" "$ticket"

    # Read the port back from the newly written nested meta.json
    local new_meta
    new_meta=$(_session_meta_for "$repo_name" "$ticket")
    if [ -f "$new_meta" ]; then
        local new_port
        new_port=$(jq -r '.port // empty' "$new_meta" 2>/dev/null)
        if [ -n "$new_port" ] && [ "$new_port" != "null" ]; then
            echo "$new_port"
        fi
    fi
}