#!/usr/bin/env bash

# Worktree picker using fzf-tmux
# Shows all git worktrees with metadata-based session status

# Source metadata functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/worktree-metadata.sh"
source "$SCRIPT_DIR/tmux-session-utils.sh"

# Get current directory to identify current worktree
CURRENT_DIR=$(tmux display-message -p "#{pane_current_path}")
cd "$CURRENT_DIR" 2>/dev/null || cd "$HOME"

# Get the main repository path
MAIN_REPO=$(git worktree list 2>/dev/null | head -1 | awk '{print $1}')
if [ -z "$MAIN_REPO" ]; then
    echo "Error: Not in a git repository" >&2
    exit 1
fi
REPO_NAME=$(basename "$MAIN_REPO")
# Sanitize repo name - replace dots and other special chars with underscores
SAFE_REPO_NAME=$(echo "$REPO_NAME" | sed 's/[^a-zA-Z0-9-]/_/g')
CURRENT_WORKTREE=$(cd "$CURRENT_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
RAW_SESSION=$(tmux display-message -p "#{session_name}")
CURRENT_SESSION=$(resolve_master_session "$RAW_SESSION")

# Write the master session name to /tmp/tmux-switch-to-session.
# The actual grouped-child creation happens in switch-to-session.sh
# AFTER the popup closes, so it can accurately check attached clients.
write_switch_session() {
    local target="$1"
    echo "$target" > /tmp/tmux-switch-to-session
}

# Get list of worktrees with metadata-enhanced info
get_worktrees() {
    # Print header (without delimiter so it shows in fzf)
    printf "%-4s %-50s %-10s %-18s %-6s %-18s %s\n" "" "NAME" "TYPE" "STATUS" "PORT" "LAST ACTIVITY" "BRANCH"
    printf "%-4s %-50s %-10s %-18s %-6s %-18s %s\n" "" "─────" "────" "──────" "────" "─────────────" "──────"
    
    # Pre-compute autopilot state for all projects (avoids quoting hell in awk)
    local autopilot_states=""
    for sf in "$HOME/.config/autopilot/projects/"*.state.json; do
        [ -f "$sf" ] || continue
        local ap_st ap_wt
        ap_st=$(jq -r '.status // ""' "$sf" 2>/dev/null)
        ap_wt=$(jq -r '.current.worktree_name // ""' "$sf" 2>/dev/null)
        [ -n "$ap_wt" ] && autopilot_states="${autopilot_states}${ap_wt}=${ap_st};"
    done

    # Process each worktree
    git worktree list --porcelain | awk -v current="$CURRENT_WORKTREE" -v repo_name="$REPO_NAME" -v safe_repo_name="$SAFE_REPO_NAME" -v worktrees_base="$WORKTREES_BASE" -v autopilot_states="$autopilot_states" '
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
            # For base repo
            base_session_name = safe_repo_name "-base"
            cmd = "tmux has-session -t " base_session_name " 2>/dev/null && echo active || echo inactive"
            cmd | getline session_status
            close(cmd)
        } else {
            # For worktrees — check tmux session
            cmd = "tmux has-session -t " ticket " 2>/dev/null && echo active || echo inactive"
            cmd | getline session_status
            close(cmd)
        }

        # --- Determine STATUS (single source of truth) ---
        # Priority: autopilot state > waiting marker > session status > metadata
        autopilot_dir = ENVIRON["HOME"] "/.config/autopilot"
        status_text = ""
        is_autopilot = 0
        needs_input = 0
        port_text = "-"

        # Read worktree metadata (port, autopilot flag)
        metadata_file = worktrees_base "/" repo_name "/.worktree-meta/sessions/" ticket ".json"
        if (system("test -f " metadata_file) == 0) {
            cmd = "jq -r \".port // \\\"-\\\"\" " metadata_file " 2>/dev/null || echo \"-\""
            cmd | getline port_text
            close(cmd)
            cmd = "jq -r \".autopilot // false\" " metadata_file " 2>/dev/null || echo \"false\""
            cmd | getline ap_flag
            close(cmd)
            if (ap_flag == "true") is_autopilot = 1
        }

        if (is_autopilot) type_text = "[AUTO]"

        # Read Claude state marker (STATE then pipe then details)
        state_marker = autopilot_dir "/markers/" ticket ".state"
        cmd = "test -f " state_marker " && head -1 " state_marker " 2>/dev/null"
        cmd | getline claude_state_line
        close(cmd)
        # Extract state (everything before first pipe)
        claude_state = claude_state_line
        sub(/\x7c.*/, "", claude_state)

        if (claude_state == "awaiting_ci") status_text = "[AWAITING CI]"
        else if (claude_state == "awaiting_review") status_text = "[AWAITING REVIEW]"
        else if (claude_state == "working") status_text = "[AI WORKING]"
        else if (claude_state == "needs_input") { status_text = "[NEEDS INPUT]"; needs_input = 1 }
        else if (claude_state == "failed") status_text = "[FAILED]"

        # Fallback: check autopilot project state (pre-computed from state.json)
        if (status_text == "" && is_autopilot && autopilot_states != "") {
            pattern = ticket "="
            if (index(autopilot_states, pattern) > 0) {
                rest = substr(autopilot_states, index(autopilot_states, pattern) + length(pattern))
                sub(/;.*/, "", rest)
                if (rest == "pending_assignment") status_text = "[CI/REVIEW]"
                else if (rest == "working") status_text = "[AI WORKING]"
            }
        }

        # Fallback to session-based status
        if (status_text == "") {
            if (session_status == "active") {
                status_text = "[ACTIVE]"
            } else if (system("test -f " metadata_file) == 0) {
                status_text = "[SAVED]"
            } else {
                status_text = "[INACTIVE]"
            }
        }

        # Status icon — only arrow for current, dot for active/inactive
        if (path == current) {
            if (session_status == "active") status_icon = "→ ● "
            else status_icon = "→ ○ "
        } else {
            if (session_status == "active") status_icon = "  ● "
            else status_icon = "  ○ "
        }

        # Truncate ticket name to 48 chars for alignment
        display_name = substr(ticket, 1, 48)

        # Get last activity timestamp from .state file mtime
        last_activity = "-"
        sort_epoch = "0"
        if (claude_state != "") {
            cmd = "date -r " state_marker " +\"%m/%d %H:%M\" 2>/dev/null"
            cmd | getline last_activity
            close(cmd)
            if (last_activity == "") last_activity = "-"
            cmd = "date -r " state_marker " +\"%s\" 2>/dev/null"
            cmd | getline sort_epoch
            close(cmd)
            if (sort_epoch == "") sort_epoch = "0"
        }

        # Output with hidden sort key (epoch, 0 = no date = highest prio)
        printf "%s%-50s %-10s %-18s %-6s %-18s %s\t%s\n", status_icon, display_name, type_text, status_text, port_text, last_activity, branch, sort_epoch
    }'
}


# Function to reload worktrees list
reload_worktrees() {
    get_worktrees | {
        IFS= read -r line1; echo "$line1"
        IFS= read -r line2; echo "$line2"
        base_lines=""
        no_ts_lines=""
        ts_lines=""
        while IFS= read -r line; do
            epoch=$(echo "$line" | cut -f2)
            display=$(echo "$line" | cut -f1)
            if echo "$display" | grep -q '\[BASE\]'; then
                base_lines="$display"
            elif [ "$epoch" = "0" ] || [ -z "$epoch" ]; then
                no_ts_lines="${no_ts_lines}${display}
"
            else
                ts_lines="${ts_lines}${epoch}	${display}
"
            fi
        done
        if [ -n "$ts_lines" ]; then
            printf '%s' "$ts_lines" | sort -t$'\t' -k1 -n | cut -f2-
        fi
        if [ -n "$no_ts_lines" ]; then
            printf '%s' "$no_ts_lines"
        fi
        if [ -n "$base_lines" ]; then
            echo "$base_lines"
        fi
    }
}

# Handle script being called with reload argument
if [ "$1" = "reload" ]; then
    reload_worktrees
    exit 0
fi

# Get the worktree data
# Sort: base at bottom, then no-timestamp, then timestamped descending (most recent at bottom)
WORKTREE_DATA=$(get_worktrees | {
    IFS= read -r line1; echo "$line1"
    IFS= read -r line2; echo "$line2"
    # Split into 3 groups, reassemble in order
    base_lines=""
    no_ts_lines=""
    ts_lines=""
    while IFS= read -r line; do
        epoch=$(echo "$line" | cut -f2)
        display=$(echo "$line" | cut -f1)
        if echo "$display" | grep -q '\[BASE\]'; then
            base_lines="$display"
        elif [ "$epoch" = "0" ] || [ -z "$epoch" ]; then
            no_ts_lines="${no_ts_lines}${display}
"
        else
            ts_lines="${ts_lines}${epoch}	${display}
"
        fi
    done
    # Timestamped ascending (oldest first, most recent at bottom)
    if [ -n "$ts_lines" ]; then
        printf '%s' "$ts_lines" | sort -t$'\t' -k1 -n | cut -f2-
    fi
    # No timestamp
    if [ -n "$no_ts_lines" ]; then
        printf '%s' "$no_ts_lines"
    fi
    # Base always last
    if [ -n "$base_lines" ]; then
        echo "$base_lines"
    fi
})

# Find the longest visual line for consistent padding
# The arrow → is 3 bytes but 1 visual character, so we need to handle this
LONGEST_VISUAL_LENGTH=$(echo "$WORKTREE_DATA" | awk '
{
    line = $0
    # Replace multi-byte arrow with single char for visual length
    gsub(/→/, "X", line)
    print length(line)
}' | sort -nr | head -1)

# Create separator for the popup first to know the target width
# Adjust based on the fixed width
FIXED_WIDTH=140  # Desired fixed width in characters
SEPARATOR_WIDTH=$((FIXED_WIDTH - 6))

# Create separator line
SEPARATOR=$(printf '─%.0s' $(seq 1 $SEPARATOR_WIDTH))

# Pad only the data rows to match the full popup width (separator + 2)
TARGET_WIDTH=$((SEPARATOR_WIDTH + 2))
WORKTREE_DATA=$(echo "$WORKTREE_DATA" | awk -v target_width="$TARGET_WIDTH" '
NR <= 2 {
    # Keep header lines as-is
    print $0
}
NR > 2 {
    # Calculate visual length for this line
    visual_line = $0
    gsub(/→/, "X", visual_line)
    visual_len = length(visual_line)
    
    # Add padding to reach target width
    padding = target_width - visual_len
    if (padding > 0) {
        for (i = 0; i < padding; i++) {
            $0 = $0 " "
        }
    }
    print $0
}')

# Calculate popup width for fixed character width
TERM_WIDTH=$(tput cols)

# Calculate percentage needed to achieve fixed character width
POPUP_PERCENT=$(( (FIXED_WIDTH * 100) / TERM_WIDTH ))

# Ensure it doesn't exceed 100%
if [ $POPUP_PERCENT -gt 100 ]; then
    POPUP_PERCENT=100
fi

# Use fzf (tmux display-popup creates the popup window)
selected=$(echo "$WORKTREE_DATA" | fzf \
    --prompt=" Select worktree: " \
    --header=$'\n'"$SEPARATOR"$'\n    [AI WORKING] [NEEDS INPUT] [AWAITING CI] [AWAITING REVIEW] [ACTIVE] [SAVED] [AUTO]\n'"$SEPARATOR"$'\n    enter switch   ctrl-x delete   ctrl-k kill session   ctrl-r reload' \
    --header-lines=2 \
    --ansi \
    --color="fg:250,bg:235,hl:114,fg+:235,bg+:114,hl+:235,prompt:114,pointer:114,header:243,border:114" \
    --border=rounded \
    --border-label=" Git Worktrees " \
    --bind "ctrl-x:execute-silent(~/.config/tmux/scripts/worktree-delete-from-picker.sh {})+accept" \
    --bind "ctrl-k:execute-silent(~/.config/tmux/scripts/worktree-kill-session.sh {})+reload(~/.config/tmux/scripts/worktree-picker-fzf.sh reload)")

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
        sub(/^[●○>][[:space:]]+/, "", $0)

        # Now we have: "name type session port branch"
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
            if (match(original, /[●○>]/)) {
                icon = substr(original, RSTART, 1)
            } else {
                icon = "?"
            }
        }

        # Output as tab-separated values (no path — derived downstream)
        print icon "\t" name "\t" type "\t" session "\t" port "\t" branch "\t" has_arrow
    }')

    # Parse the tab-separated values
    IFS=$'\t' read -r icon name type session port branch has_arrow <<< "$parsed_fields"

    # Derive worktree_path from name
    if [ "$type" = "[BASE]" ]; then
        worktree_path="$MAIN_REPO"
    else
        worktree_path="$WORKTREES_BASE/$REPO_NAME/$name"
    fi
    
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
            write_switch_session "$session_name"
            exit 0
        else
            # Check if we have metadata for base
            if session_exists_in_metadata "$REPO_NAME" "$session_name"; then
                # Restore from metadata
                stored_path=$(get_session_metadata "$REPO_NAME" "$session_name" "worktree_path")
                tabs=$(get_session_metadata "$REPO_NAME" "$session_name" "tabs")
                
                # Use main repo path
                worktree_path="$MAIN_REPO"
                
                # Create session using dedicated script
                ~/.config/tmux/scripts/create-worktree-session.sh "$session_name" "$worktree_path"
                
                # Update last accessed time
                update_session_access "$REPO_NAME" "$session_name"
                
                # Write session name for tmux to switch to
                write_switch_session "$session_name"
                exit 0
            else
                # No metadata, create new base session with defaults
                echo "[PICKER DEBUG] Creating new base session at $MAIN_REPO" >> /tmp/tmux-worktree-debug.log
                
                # Create session using dedicated script
                ~/.config/tmux/scripts/create-worktree-session.sh "$session_name" "$MAIN_REPO"
                
                # Save metadata
                save_session_metadata "$REPO_NAME" "$session_name" "$MAIN_REPO" "master" "$session_name"
                
                # Write session name for tmux to switch to
                write_switch_session "$session_name"
                exit 0
            fi
        fi
    else
        # This is a worktree, use the name as ticket
        ticket="$name"
        
        # Debug ticket value
        echo "[PICKER DEBUG] Worktree ticket: '$ticket' (from name: '$name')" >> /tmp/tmux-worktree-debug.log
        
        # Check if session exists
        if tmux has-session -t "$name" 2>/dev/null; then
            echo "[PICKER DEBUG] Session $name already exists, switching" >> /tmp/tmux-worktree-debug.log
            # Write session name to temp file for tmux to read
            write_switch_session "$name"
            exit 0
        else
            # Check if we have metadata for this worktree
            if session_exists_in_metadata "$REPO_NAME" "$name"; then
                # Restore from metadata
                stored_path=$(get_session_metadata "$REPO_NAME" "$name" "worktree_path")
                tabs=$(get_session_metadata "$REPO_NAME" "$name" "tabs")
                
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
                write_switch_session "$name"
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
                branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
                save_session_metadata "$REPO_NAME" "$name" "$worktree_path" "$branch" "$name"
                
                # Write session name for tmux to switch to
                write_switch_session "$name"
                exit 0
            fi
        fi
    fi
fi