#!/usr/bin/env bash

# Worktree picker using fzf-tmux
# Shows all git worktrees with metadata-based session status

# Source metadata functions
source "$(dirname "$0")/worktree-metadata.sh"

# Get the main repository path
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
REPO_NAME=$(basename "$MAIN_REPO")

# Get current directory to identify current worktree
CURRENT_DIR=$(tmux display-message -p "#{pane_current_path}")
CURRENT_WORKTREE=$(cd "$CURRENT_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
CURRENT_SESSION=$(tmux display-message -p "#{session_name}")

# Get list of worktrees with metadata-enhanced info
get_worktrees() {
    # Print header (without delimiter so it shows in fzf)
    printf "%-4s %-15s %-10s %-12s %-30s %s\n" "" "NAME" "TYPE" "SESSION" "BRANCH" "PATH"
    printf "%-4s %-15s %-10s %-12s %-30s %s\n" "" "----" "----" "-------" "------" "----"
    
    # Process each worktree
    git worktree list --porcelain | awk -v current="$CURRENT_WORKTREE" -v repo_name="$REPO_NAME" -v worktrees_base="$WORKTREES_BASE" '
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
        
        # Extract ticket from path or branch
        ticket = ""
        session_status = "inactive"
        session_text = "[NO SESSION]"
        type_text = "[WORKTREE]"
        
        # Check if this is the main repository (base)
        if (path !~ worktrees_base) {
            type_text = "[BASE]"
            ticket = repo_name
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
            # For base repo, check if any numeric session exists (main tmux session)
            # Get the first session name
            cmd = "tmux list-sessions -F \"#{session_name}\" 2>/dev/null | head -1"
            cmd | getline first_session
            close(cmd)
            
            if (first_session != "") {
                session_text = "[SESSION]"
                session_status = "active"
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
        
        # Output format with type column
        printf "%s%-15s %-10s %-12s %-30s %s\n", status_icon, ticket, type_text, session_text, branch, path
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
    --header="● = Active | ○ = Inactive | → = Current | [SESSION]=Active | [METADATA]=Saved | [ORPHAN]=No metadata | ↵ switch | ctrl-x delete" \
    --header-lines=2 \
    --color="fg:250,bg:235,hl:114,fg+:235,bg+:114,hl+:235,prompt:114,pointer:114,header:243" \
    --border=rounded \
    --border-label=" Git Worktrees " \
    --bind "ctrl-x:execute-silent(~/.config/tmux/scripts/worktree-delete-from-picker.sh {})+reload(~/.config/tmux/scripts/worktree-picker-fzf.sh reload)" \
    --bind "ctrl-r:reload(~/.config/tmux/scripts/worktree-picker-fzf.sh reload)")

# If a worktree was selected (Enter pressed), switch to it
if [ -n "$selected" ]; then
    echo "[PICKER DEBUG] Selected: '$selected'" >> /tmp/tmux-worktree-debug.log
    
    # Use read to split fields - this works correctly
    # Format depends on whether it has arrow or not
    # With arrow: "→ ● name type session branch path"
    # Without arrow: "  ● name type session branch path"
    local fields=($selected)
    local icon name type session branch path
    
    # Check if first field is arrow
    if [[ "${fields[0]}" == "→" ]]; then
        # Arrow present: → ● name type session branch path
        icon="${fields[1]}"  # ● or ○
        name="${fields[2]}"
        type="${fields[3]}"
        session="${fields[4]}"
        branch="${fields[5]}"
        path="${fields[6]}"
    else
        # No arrow: ● name type session branch path
        icon="${fields[0]}"  # ● or ○
        name="${fields[1]}"
        type="${fields[2]}"
        session="${fields[3]}"
        branch="${fields[4]}"
        path="${fields[5]}"
    fi
    
    # The path might have been split if it contains spaces, so we need to reconstruct it
    if [ -n "$rest" ]; then
        path="$path $rest"
    fi
    
    # For fixed-width format, path is always the last complete field
    # But we need to handle the case where there are many spaces between columns
    local worktree_path=$(echo "$selected" | rev | cut -d' ' -f1 | rev)
    
    echo "[PICKER DEBUG] Name: '$name', Type: '$type', Path: '$worktree_path'" >> /tmp/tmux-worktree-debug.log
    
    # Check if this is the main repository (base)
    if [ "$type" = "[BASE]" ]; then
        # For base repo, switch to the first available session (your original tmux session)
        local first_session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E '^[0-9]+$' | head -1)
        if [ -n "$first_session" ]; then
            echo "[PICKER DEBUG] Switching to base session: $first_session" >> /tmp/tmux-worktree-debug.log
            tmux switch-client -t "$first_session"
        else
            # No numeric session found, try any first session
            first_session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | head -1)
            if [ -n "$first_session" ]; then
                echo "[PICKER DEBUG] Switching to first session: $first_session" >> /tmp/tmux-worktree-debug.log
                tmux switch-client -t "$first_session"
            else
                echo "[PICKER DEBUG] No sessions found" >> /tmp/tmux-worktree-debug.log
            fi
        fi
    else
        # This is a worktree, use the name as ticket
        local ticket
        ticket="$name"
        
        # Debug all variables
        echo "[PICKER DEBUG] All vars - icon:'$icon' name:'$name' type:'$type' session:'$session' branch:'$branch' path:'$path'" >> /tmp/tmux-worktree-debug.log
        echo "[PICKER DEBUG] Worktree ticket: '$ticket' (from name: '$name')" >> /tmp/tmux-worktree-debug.log
        
        # Check if session exists
        if tmux has-session -t "$name" 2>/dev/null; then
            echo "[PICKER DEBUG] Session $name already exists, switching" >> /tmp/tmux-worktree-debug.log
            # Session exists, just switch to it
            tmux switch-client -t "$name"
        else
            # Check if we have metadata for this worktree
            if session_exists_in_metadata "$REPO_NAME" "$name"; then
                # Restore from metadata
                local stored_path=$(get_session_metadata "$REPO_NAME" "$name" "worktree_path")
                local tabs=$(get_session_metadata "$REPO_NAME" "$name" "tabs")
                
                # Use stored path if available, otherwise use detected path
                [ -n "$stored_path" ] && worktree_path="$stored_path"
                
                # Create session using dedicated script
                ~/.config/tmux/scripts/create-worktree-session.sh "$name" "$worktree_path"
                
                # Update last accessed time
                update_session_access "$REPO_NAME" "$name"
                
                # Switch to the session
                tmux switch-client -t "$name"
            else
                # No metadata, create new session with defaults
                echo "[PICKER DEBUG] Creating new session for $name at $worktree_path" >> /tmp/tmux-worktree-debug.log
                # Create session using dedicated script
                ~/.config/tmux/scripts/create-worktree-session.sh "$name" "$worktree_path"
                
                # Save metadata
                local branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
                save_session_metadata "$REPO_NAME" "$name" "$worktree_path" "$branch" "$name"
                
                # Switch to the session
                tmux switch-client -t "$name"
            fi
            
            # Switch to the session (only reached if session creation was skipped)
            tmux switch-client -t "$name"
        fi
    fi
fi