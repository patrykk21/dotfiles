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

# Save session metadata
save_session_metadata() {
    local repo_name="$1"
    local ticket="$2"
    local worktree_path="$3"
    local branch="$4"
    local session_name="${5:-$ticket}"
    
    ensure_metadata_dirs "$repo_name"
    
    local metadata_file="$WORKTREES_BASE/$repo_name/.worktree-meta/sessions/${ticket}.json"
    
    # Generate port for worktrees (not base repos)
    local port=""
    if [[ ! "$ticket" =~ -base$ ]]; then
        # Check if we already have a port assigned
        if [ -f "$metadata_file" ]; then
            port=$(jq -r '.port // empty' "$metadata_file")
        fi
        # If no port assigned yet, generate one
        if [ -z "$port" ]; then
            port=$(generate_worktree_port)
        fi
    fi
    
    # Build JSON with optional port field
    local json_content="{
  \"ticket\": \"$ticket\",
  \"session_name\": \"$session_name\",
  \"worktree_path\": \"$worktree_path\",
  \"branch\": \"$branch\",
  \"created\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"last_accessed\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"tabs\": [\"claude\", \"server\", \"commands\"]"
    
    if [ -n "$port" ]; then
        json_content+=",
  \"port\": $port"
    fi
    
    json_content+="
}"
    
    echo "$json_content" > "$metadata_file"
}

# Update last accessed time
update_session_access() {
    local repo_name="$1"
    local ticket="$2"
    
    local metadata_file="$WORKTREES_BASE/$repo_name/.worktree-meta/sessions/${ticket}.json"
    
    if [ -f "$metadata_file" ]; then
        local temp_file=$(mktemp)
        jq --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           '.last_accessed = $date' \
           "$metadata_file" > "$temp_file" && mv "$temp_file" "$metadata_file"
    fi
}

# Get session metadata
get_session_metadata() {
    local repo_name="$1"
    local ticket="$2"
    local field="$3"
    
    local metadata_file="$WORKTREES_BASE/$repo_name/.worktree-meta/sessions/${ticket}.json"
    
    if [ -f "$metadata_file" ]; then
        if [ -n "$field" ]; then
            jq -r ".$field // empty" "$metadata_file"
        else
            cat "$metadata_file"
        fi
    fi
}

# List all sessions for a repo
list_repo_sessions() {
    local repo_name="$1"
    local sessions_dir="$WORKTREES_BASE/$repo_name/.worktree-meta/sessions"
    
    if [ -d "$sessions_dir" ]; then
        find "$sessions_dir" -name "*.json" -type f | while read -r file; do
            basename "$file" .json
        done
    fi
}

# Remove session metadata
remove_session_metadata() {
    local repo_name="$1"
    local ticket="$2"
    
    local metadata_file="$WORKTREES_BASE/$repo_name/.worktree-meta/sessions/${ticket}.json"
    
    [ -f "$metadata_file" ] && rm -f "$metadata_file"
}

# Check if session exists in metadata
session_exists_in_metadata() {
    local repo_name="$1"
    local ticket="$2"
    
    local metadata_file="$WORKTREES_BASE/$repo_name/.worktree-meta/sessions/${ticket}.json"
    
    [ -f "$metadata_file" ]
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