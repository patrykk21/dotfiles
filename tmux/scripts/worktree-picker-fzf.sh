#!/usr/bin/env bash

# Worktree picker using fzf-tmux
# Shows all git worktrees with metadata-based session status

# Source metadata functions
source "$(dirname "$0")/worktree-metadata.sh"

# Get the main repository path
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
REPO_NAME=$(basename "$MAIN_REPO")
# Sanitize repo name - replace dots and other special chars with underscores
SAFE_REPO_NAME=$(echo "$REPO_NAME" | sed 's/[^a-zA-Z0-9-]/_/g')

# Get current directory to identify current worktree
CURRENT_DIR=$(tmux display-message -p "#{pane_current_path}")
CURRENT_WORKTREE=$(cd "$CURRENT_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
CURRENT_SESSION=$(tmux display-message -p "#{session_name}")

# Get list of worktrees with metadata-enhanced info
get_worktrees() {
    # Print header (without delimiter so it shows in fzf)
    printf "%-4s %-15s %-10s %-12s %-6s %-30s %s\n" "" "NAME" "TYPE" "SESSION" "PORT" "BRANCH" "PATH"
    printf "%-4s %-15s %-10s %-12s %-6s %-30s %s\n" "" "----" "----" "-------" "----" "------" "----"
    
    # Process each worktree
    git worktree list --porcelain | awk -v current="$CURRENT_WORKTREE" -v repo_name="$REPO_NAME" -v safe_repo_name="$SAFE_REPO_NAME" -v worktrees_base="$WORKTREES_BASE" '
    BEGIN {
        # Function to check metadata file
        metadata_cmd = "source " ENVIRON["HOME"] "/.config/tmux/scripts/worktree-metadata.sh"
    }
    /^worktree/ {
        path = $2
        # Extract just the directory name
        split(path, parts, "/")
        dirname = parts[length(parts)]
    }
    /^HEAD/ {
        commit = substr($2, 1, 7)
    }
    /^branch/ {
        branch = $2
        # Remove refs/heads/ prefix to save space
        sub(/^refs\/heads\//, "", branch)
        
        # Extract ticket from path or branch
        ticket = ""
        session_status = "inactive"
        session_text = "[NO SESSION]"
        type_text = "[WORKTREE]"
        
        # Check if this is the main repository (base)
        if (path !~ worktrees_base) {
            type_text = "[BASE]"
            ticket = safe_repo_name "-base"
        } else {
            # This is a worktree
            # Check if this is under our worktrees structure
            pattern = worktrees_base "/" repo_name "/"
            if (index(path, pattern) > 0) {
                # Extract the ticket from the path
                path_copy = path
                sub(".*" worktrees_base "/" repo_name "/", "", path_copy)
                sub("/.*", "", path_copy)
                ticket = path_copy
            } else if (match(branch, /[A-Z]+-[0-9]+/)) {
                ticket = substr(branch, RSTART, RLENGTH)
            } else if (match(dirname, /[A-Z]+-[0-9]+/)) {
                ticket = substr(dirname, RSTART, RLENGTH)
            } else {
                ticket = dirname
            }
        }
        
        # Check session status
        if (type_text == "[BASE]") {
            # For base repo, check if repository-specific base session exists
            base_session_name = safe_repo_name "-base"
            cmd = "tmux has-session -t " base_session_name " 2>/dev/null && echo active || echo inactive"
            cmd | getline session_status
            close(cmd)
            
            if (session_status == "active") {
                session_text = "[SESSION]"
            } else {
                # Check if metadata exists for base
                metadata_file = worktrees_base "/" repo_name "/.worktree-meta/sessions/" base_session_name ".json"
                if (system("test -f " metadata_file) == 0) {
                    session_text = "[METADATA]"
                }
            }
        } else {
            # For worktrees, check metadata and session as before
            metadata_file = worktrees_base "/" repo_name "/.worktree-meta/sessions/" ticket ".json"
            if (system("test -f " metadata_file) == 0) {
                # Metadata exists, check if tmux session also exists
                cmd = "tmux has-session -t " ticket " 2>/dev/null && echo active || echo inactive"
                cmd | getline session_status
                close(cmd)
                
                if (session_status == "active") {
                    session_text = "[SESSION]"
                } else {
                    session_text = "[METADATA]"  # Has metadata but no active session
                }
            } else {
                # No metadata, check if session exists anyway
                cmd = "tmux has-session -t " ticket " 2>/dev/null && echo active || echo inactive"
                cmd | getline session_status
                close(cmd)
                
                if (session_status == "active") {
                    session_text = "[ORPHAN]"  # Has session but no metadata
                }
            }
        }
        
        # Format output
        if (path == current) {
            # Current worktree - show with arrow
            if (session_status == "active") {
                status_icon = "→ ● "
            } else {
                status_icon = "→ ○ "
            }
        } else {
            if (session_status == "active") {
                status_icon = "  ● "
            } else {
                status_icon = "  ○ "
            }
        }
        
        # Get port from metadata if it is a worktree session
        port_text = "-"
        if (type_text == "[WORKTREE]" && session_text != "[NO SESSION]") {
            # Read port from metadata file
            metadata_file = worktrees_base "/" repo_name "/.worktree-meta/sessions/" ticket ".json"
            cmd = "test -f " metadata_file " && jq -r \".port // \\\"-\\\"\" " metadata_file " 2>/dev/null || echo \"-\""
            cmd | getline port_text
            close(cmd)
        }
        
        # Output format with type column and port
        printf "%s%-15s %-10s %-12s %-6s %-30s %s\n", status_icon, ticket, type_text, session_text, port_text, branch, path
    }'
}


# Function to reload worktrees list
reload_worktrees() {
    get_worktrees
}

# Handle script being called with reload argument
if [ "$1" = "reload" ]; then
    reload_worktrees
    exit 0
fi

# Use fzf-tmux to select a worktree
selected=$(get_worktrees | fzf-tmux -p 80%,60% \
    --prompt=" Select worktree: " \
    --header="● = Active | ○ = Inactive | → = Current | [SESSION]=Active | [METADATA]=Saved | ↵ switch | ctrl-x delete | ctrl-k kill session" \
    --header-lines=2 \
    --color="fg:250,bg:235,hl:114,fg+:235,bg+:114,hl+:235,prompt:114,pointer:114,header:243" \
    --border=rounded \
    --border-label=" Git Worktrees " \
    --bind "ctrl-x:execute-silent(~/.config/tmux/scripts/worktree-delete-from-picker.sh {})+accept" \
    --bind "ctrl-k:execute-silent(~/.config/tmux/scripts/worktree-kill-session.sh {})+reload(~/.config/tmux/scripts/worktree-picker-fzf.sh reload)" \
    --bind "ctrl-r:reload(~/.config/tmux/scripts/worktree-picker-fzf.sh reload)")

# Check if deletion was requested
if [ -f /tmp/tmux-worktree-delete-requested ]; then
    rm -f /tmp/tmux-worktree-delete-requested
    # Exit with special code to trigger deletion confirmation
    exit 99
fi

# If a worktree was selected (Enter pressed), switch to it
if [ -n "$selected" ]; then
    # Debug tmux environment
    echo "[PICKER DEBUG] TMUX env: '$TMUX'" >> /tmp/tmux-worktree-debug.log
    echo "[PICKER DEBUG] TMUX_PANE: '$TMUX_PANE'" >> /tmp/tmux-worktree-debug.log
    echo "[PICKER DEBUG] Selected: '$selected'" >> /tmp/tmux-worktree-debug.log
    echo "[PICKER DEBUG] SAFE_REPO_NAME at selection: '$SAFE_REPO_NAME'" >> /tmp/tmux-worktree-debug.log
    
    # Debug the raw selected line
    echo "[PICKER DEBUG] Raw selected: '$selected'" >> /tmp/tmux-worktree-debug.log
    echo "[PICKER DEBUG] Length: ${#selected}" >> /tmp/tmux-worktree-debug.log
    
    # Parse using a single awk command to avoid subshell issues
    local parsed_fields
    parsed_fields=$(echo "$selected" | awk '
    {
        # Save original line
        original = $0
        
        # Check if starts with arrow (before removing spaces)
        has_arrow = 0
        if (match($0, /^[[:space:]]*→/)) {
            has_arrow = 1
            # Remove everything up to and including arrow
            sub(/^[[:space:]]*→[[:space:]]+/, "", $0)
        }
        
        # Remove leading spaces if any remain
        gsub(/^[[:space:]]+/, "", $0)
        
        # Remove status icon and spaces
        sub(/^[●○][[:space:]]+/, "", $0)
        
        # Now we have: "name type session port branch path..."
        # Extract fields
        name = $1
        type = $2
        session = $3
        port = $4
        branch = $5
        
        # Determine icon based on arrow presence and original content
        if (has_arrow) {
            icon = "→"
        } else {
            # Extract status icon from original line (● or ○)
            if (match(original, /[●○]/)) {
                icon = substr(original, RSTART, 1)
            } else {
                icon = "?"
            }
        }
        
        # Path is the last field of the ORIGINAL line
        n = split(original, arr, " ")
        path = arr[n]
        
        # Output as tab-separated values
        print icon "\t" name "\t" type "\t" session "\t" port "\t" branch "\t" path "\t" has_arrow
    }')
    
    # Parse the tab-separated values
    local icon name type session port branch worktree_path has_arrow session_name
    IFS=$'\t' read -r icon name type session port branch worktree_path has_arrow <<< "$parsed_fields"
    
    echo "[PICKER DEBUG] Parsed - icon:'$icon' name:'$name' type:'$type' session:'$session' path:'$worktree_path'" >> /tmp/tmux-worktree-debug.log
    
    # Check if we selected the current session (indicated by arrow)
    if [ "$has_arrow" = "1" ]; then
        echo "[PICKER DEBUG] Already in current session, no switch needed" >> /tmp/tmux-worktree-debug.log
        exit 0
    fi
    
    # Check if this is the main repository (base)
    if [ "$type" = "[BASE]" ]; then
        # For base repo, use the name which already includes -base
        session_name="$name"
        echo "[PICKER DEBUG] Base repo: name='$name', session_name='$session_name'" >> /tmp/tmux-worktree-debug.log
        
        # Check if base session exists
        if tmux has-session -t "$session_name" 2>/dev/null; then
            echo "[PICKER DEBUG] Base session exists, switching to: $session_name" >> /tmp/tmux-worktree-debug.log
            echo "$session_name" > /tmp/tmux-switch-to-session
            exit 0
        else
            # Check if we have metadata for base
            if session_exists_in_metadata "$REPO_NAME" "$session_name"; then
                # Restore from metadata
                local stored_path=$(get_session_metadata "$REPO_NAME" "$session_name" "worktree_path")
                local tabs=$(get_session_metadata "$REPO_NAME" "$session_name" "tabs")
                
                # Use main repo path
                worktree_path="$MAIN_REPO"
                
                # Create session using dedicated script
                ~/.config/tmux/scripts/create-worktree-session.sh "$session_name" "$worktree_path"
                
                # Update last accessed time
                update_session_access "$REPO_NAME" "$session_name"
                
                # Write session name for tmux to switch to
                echo "$session_name" > /tmp/tmux-switch-to-session
                exit 0
            else
                # No metadata, create new base session with defaults
                echo "[PICKER DEBUG] Creating new base session at $MAIN_REPO" >> /tmp/tmux-worktree-debug.log
                
                # Create session using dedicated script
                ~/.config/tmux/scripts/create-worktree-session.sh "$session_name" "$MAIN_REPO"
                
                # Save metadata
                save_session_metadata "$REPO_NAME" "$session_name" "$MAIN_REPO" "master" "$session_name"
                
                # Write session name for tmux to switch to
                echo "$session_name" > /tmp/tmux-switch-to-session
                exit 0
            fi
        fi
    else
        # This is a worktree, use the name as ticket
        local ticket
        ticket="$name"
        
        # Debug ticket value
        echo "[PICKER DEBUG] Worktree ticket: '$ticket' (from name: '$name')" >> /tmp/tmux-worktree-debug.log
        
        # Check if session exists
        if tmux has-session -t "$name" 2>/dev/null; then
            echo "[PICKER DEBUG] Session $name already exists, switching" >> /tmp/tmux-worktree-debug.log
            # Write session name to temp file for tmux to read
            echo "$name" > /tmp/tmux-switch-to-session
            # Send keys to tmux to execute the switch
            tmux send-keys -t $TMUX_PANE Escape
            exit 0
        else
            # Check if we have metadata for this worktree
            if session_exists_in_metadata "$REPO_NAME" "$name"; then
                # Restore from metadata
                local stored_path=$(get_session_metadata "$REPO_NAME" "$name" "worktree_path")
                local tabs=$(get_session_metadata "$REPO_NAME" "$name" "tabs")
                
                # Use stored path if available, otherwise use detected path
                [ -n "$stored_path" ] && worktree_path="$stored_path"
                
                # Make sure we have a valid path
                if [ -z "$worktree_path" ]; then
                    echo "[PICKER DEBUG] ERROR: Empty worktree path from metadata!" >> /tmp/tmux-worktree-debug.log
                    exit 1
                fi
                
                # Create session using dedicated script
                ~/.config/tmux/scripts/create-worktree-session.sh "$name" "$worktree_path"
                
                # Update last accessed time
                update_session_access "$REPO_NAME" "$name"
                
                # Write session name for tmux to switch to
                echo "$name" > /tmp/tmux-switch-to-session
                exit 0
            else
                # No metadata, create new session with defaults
                echo "[PICKER DEBUG] Creating new session for $name at $worktree_path" >> /tmp/tmux-worktree-debug.log
                
                # Make sure we have a valid path
                if [ -z "$worktree_path" ]; then
                    echo "[PICKER DEBUG] ERROR: Empty worktree path!" >> /tmp/tmux-worktree-debug.log
                    exit 1
                fi
                
                # Create session using dedicated script
                ~/.config/tmux/scripts/create-worktree-session.sh "$name" "$worktree_path"
                
                # Save metadata
                local branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
                save_session_metadata "$REPO_NAME" "$name" "$worktree_path" "$branch" "$name"
                
                # Write session name for tmux to switch to
                echo "$name" > /tmp/tmux-switch-to-session
                exit 0
            fi
        fi
    fi
fi