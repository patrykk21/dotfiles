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
    printf '\033[1;31mNot in a git repository\033[0m\n\n'
    printf 'Current path: %s\n' "$CURRENT_DIR"
    printf 'Worktree actions require a git repo.\n\n'
    printf 'Press any key to close...'
    read -r -n 1 -s
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
    printf "%-4s %-50s %-10s %-18s %-6s %-18s %-55s %s\n" "" "NAME" "TYPE" "STATUS" "PORT" "LAST ACTIVITY" "HEADLINE" "BRANCH"
    printf "%-4s %-50s %-10s %-18s %-6s %-18s %-55s %s\n" "" "─────" "────" "──────" "────" "─────────────" "────────" "──────"
    
    # Pre-compute conductor state for all projects (avoids quoting hell in awk)
    local conductor_states=""
    for sf in "$HOME/.config/conductor/projects/"*.state.json; do
        [ -f "$sf" ] || continue
        local ap_st ap_wt
        ap_st=$(jq -r '.status // ""' "$sf" 2>/dev/null)
        ap_wt=$(jq -r '.current.worktree_name // ""' "$sf" 2>/dev/null)
        [ -n "$ap_wt" ] && conductor_states="${conductor_states}${ap_wt}=${ap_st};"
    done

    # Gather sessions, metadata fields, file times and seen markers in a few batched
    # calls; spawning tmux/jq/stat/date per worktree made the picker take seconds.
    local data_dir meta_dir f
    data_dir=$(mktemp -d -t worktree-picker)
    meta_dir="$WORKTREES_BASE/$REPO_NAME/.worktree-meta/sessions"
    tmux list-sessions -F '#{session_name}' > "$data_dir/sessions" 2>/dev/null
    local json_files=() seen_files=()
    for f in "$meta_dir"/*/meta.json "$meta_dir"/*/summary.json "$meta_dir"/*/conductor.json; do
        [ -f "$f" ] && json_files+=("$f")
    done
    for f in "$HOME/.config/conductor/seen/"*.seen; do
        [ -f "$f" ] && seen_files+=("$f")
    done
    if [ ${#json_files[@]} -gt 0 ]; then
        local jq_fields='[input_filename, (.port // "-" | tostring), (.conductor // false | tostring),
            (.headline // "" | tostring | split("\n") | .[0] // ""), (.status // "" | tostring), (.state // "" | tostring)]
            | map(gsub("\t"; " ")) | join("\t")'
        # One bad JSON file aborts a multi-file jq run, so fall back to one file at a time.
        if ! jq -r "$jq_fields" "${json_files[@]}" > "$data_dir/fields" 2>/dev/null; then
            : > "$data_dir/fields"
            for f in "${json_files[@]}"; do
                jq -r "$jq_fields" "$f" >> "$data_dir/fields" 2>/dev/null
            done
        fi
        stat -f '%N%t%m%t%Sm' -t '%m/%d %H:%M' "${json_files[@]}" > "$data_dir/times" 2>/dev/null
    fi
    if [ ${#seen_files[@]} -gt 0 ]; then
        awk 'FNR == 1 { print FILENAME "\t" $0 }' "${seen_files[@]}" > "$data_dir/seen" 2>/dev/null
    fi

    # Process each worktree
    git worktree list --porcelain | awk -v current="$CURRENT_WORKTREE" -v repo_name="$REPO_NAME" -v safe_repo_name="$SAFE_REPO_NAME" -v worktrees_base="$WORKTREES_BASE" -v conductor_states="$conductor_states" -v data_dir="$data_dir" '
    # Mirrors `tmux has-session -t NAME`: exact name, else a unique prefix match.
    function session_status_of(name,   i, hits) {
        if (name in sessions) return "active"
        hits = 0
        for (i = 1; i <= session_count; i++) if (index(session_list[i], name) == 1) hits++
        return hits == 1 ? "active" : "inactive"
    }
    BEGIN {
        FS_TAB = "\t"
        while ((getline line < (data_dir "/sessions")) > 0) {
            sessions[line] = 1
            session_list[++session_count] = line
        }
        while ((getline line < (data_dir "/fields")) > 0) {
            split(line, f, FS_TAB)
            fields[f[1], "port"] = f[2]; fields[f[1], "conductor"] = f[3]
            fields[f[1], "headline"] = f[4]; fields[f[1], "status"] = f[5]; fields[f[1], "state"] = f[6]
        }
        while ((getline line < (data_dir "/times")) > 0) {
            split(line, f, FS_TAB)
            exists[f[1]] = 1; mtime[f[1]] = f[2]; mdate[f[1]] = f[3]
        }
        while ((getline line < (data_dir "/seen")) > 0) {
            split(line, f, FS_TAB)
            seen_value[f[1]] = f[2]
        }
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
            session_status = session_status_of(safe_repo_name "-base")
        } else {
            session_status = session_status_of(ticket)
        }

        # --- Determine STATUS (single source of truth) ---
        # Priority: conductor state > waiting marker > session status > metadata
        conductor_dir = ENVIRON["HOME"] "/.config/conductor"
        status_text = ""
        is_conductor = 0
        needs_input = 0
        port_text = "-"

        # Read worktree metadata (port, conductor flag) from the nested layout
        # under .worktree-meta/sessions/<ticket>/.
        session_dir = worktrees_base "/" repo_name "/.worktree-meta/sessions/" ticket
        metadata_file = session_dir "/meta.json"
        summary_file  = session_dir "/summary.json"
        conductor_file = session_dir "/conductor.json"

        if (metadata_file in exists) {
            port_text = ((metadata_file, "port") in fields) ? fields[metadata_file, "port"] : "-"
            if (fields[metadata_file, "conductor"] == "true") is_conductor = 1
        }

        # Read summary.json for LLM-generated status + headline
        headline = ""
        llm_status = ""
        if (summary_file in exists) {
            headline = fields[summary_file, "headline"]
            llm_status = fields[summary_file, "status"]
        }

        if (is_conductor) type_text = "[AUTO]"

        # Read conductor.json state — highest priority for runtime signals.
        # `.state` carries the rich vocabulary (working|awaiting_ci|awaiting_review|
        # approved|merged|closed|needs_input|blocked|failed). `.status` is the
        # coarse runtime signal — currently only "running" is meaningful here.
        claude_state = ""
        if (conductor_file in exists) {
            ap_runtime_state = fields[conductor_file, "status"]
            rich_state = fields[conductor_file, "state"]
            if (ap_runtime_state == "running") claude_state = "working"
            else if (rich_state != "") claude_state = rich_state
        }

        # Map claude_state / legacy state vocabulary to display label.
        if (claude_state == "merged") status_text = "[MERGED]"
        else if (claude_state == "closed") status_text = "[CLOSED]"
        else if (claude_state == "awaiting_ci") status_text = "[AWAITING CI]"
        else if (claude_state == "awaiting_review") status_text = "[AWAITING REVIEW]"
        else if (claude_state == "approved") status_text = "[APPROVED]"
        else if (claude_state == "working") status_text = "[AI WORKING]"
        else if (claude_state == "needs_input") { status_text = "[NEEDS INPUT]"; needs_input = 1 }
        else if (claude_state == "blocked") status_text = "[BLOCKED]"
        else if (claude_state == "failed") status_text = "[FAILED]"

        # Fall back to LLM summary status (written by summarize-worktree).
        if (status_text == "" && llm_status != "") {
            if      (llm_status == "ACTIVE")          status_text = "[ACTIVE]"
            else if (llm_status == "BLOCKED")         status_text = "[BLOCKED]"
            else if (llm_status == "WAITING_REVIEW")  status_text = "[AWAITING REVIEW]"
            else if (llm_status == "STALE")           status_text = "[STALE]"
            else if (llm_status == "DONE")            status_text = "[DONE]"
        }

        # Fallback: check conductor project state (pre-computed from state.json)
        if (status_text == "" && is_conductor && conductor_states != "") {
            pattern = ticket "="
            if (index(conductor_states, pattern) > 0) {
                rest = substr(conductor_states, index(conductor_states, pattern) + length(pattern))
                sub(/;.*/, "", rest)
                if (rest == "pending_assignment") status_text = "[CI/REVIEW]"
                else if (rest == "working") status_text = "[AI WORKING]"
            }
        }

        # Fallback to session-based status
        if (status_text == "") {
            if (session_status == "active") {
                status_text = "[ACTIVE]"
            } else if (metadata_file in exists) {
                status_text = "[SAVED]"
            } else {
                status_text = "[INACTIVE]"
            }
        }

        # Check if this worktree has unseen activity — compare meta.last_accessed vs seen file.
        seen_dir = ENVIRON["HOME"] "/.config/conductor/seen"
        seen_file = seen_dir "/" ticket ".seen"
        has_unseen = 0
        activity_source = ""
        if (summary_file in exists) activity_source = summary_file
        else if (metadata_file in exists) activity_source = metadata_file
        if (activity_source != "" && claude_state != "merged" && claude_state != "closed") {
            marker_epoch = mtime[activity_source]
            seen_epoch = (seen_file in seen_value) ? seen_value[seen_file] : 0
            if (seen_epoch == "") seen_epoch = 0
            if (marker_epoch + 0 > seen_epoch + 0) has_unseen = 1
        }

        # Status icon — arrow for current, ● for unread, nothing for read
        unseen_tag = ""
        if (path == current) {
            status_icon = "→   "
        } else if (has_unseen) {
            status_icon = "  ● "
        } else {
            status_icon = "    "
        }

        # Truncate ticket name to 48 chars for alignment
        display_name = substr(ticket, 1, 48)

        # Last activity = whichever of summary.json / meta.json exists and is newer.
        last_activity = "-"
        sort_epoch = "0"
        if (activity_source != "") {
            last_activity = mdate[activity_source]
            if (last_activity == "") last_activity = "-"
            sort_epoch = mtime[activity_source]
            if (sort_epoch == "") sort_epoch = "0"
        }

        # Truncate headline to 53 chars for alignment (column width 55).
        # NOTE: substr() in macOS awk operates on BYTES, not characters. Truncating
        # mid-multi-byte (e.g. an em-dash, 3 bytes UTF-8) leaves an orphan continuation
        # byte that breaks downstream `cut` with "Illegal byte sequence" and drops the
        # entire row from the picker. The `iconv -c -f UTF-8 -t UTF-8` pipe at the end
        # of this awk strips any invalid UTF-8 sequences, so half-truncated multi-byte
        # chars are silently dropped instead of corrupting the line.
        display_headline = headline
        if (length(display_headline) > 53) display_headline = substr(display_headline, 1, 50) "..."

        # The base repo is the main checkout, not a feature worktree: it has no
        # PR/work status, AI summary, or unread activity. Blank those so it reads
        # as a plain anchor row (the → current-position arrow is kept).
        if (type_text == "[BASE]") {
            status_text = ""
            display_headline = ""
            last_activity = "-"
            sort_epoch = "0"
            status_icon = (path == current) ? "→   " : "    "
        }

        # Output with hidden sort key (epoch, 0 = no date = highest prio)
        printf "%s%-50s %-10s %-18s %-6s %-18s %-55s %s\t%s\n", status_icon, display_name, type_text, status_text, port_text, last_activity, display_headline, branch, sort_epoch
    }' | iconv -c -f UTF-8 -t UTF-8
    rm -rf "$data_dir"
}


# Sort the get_worktrees output for display.
# fzf default layout: the FIRST output line renders at the bottom (nearest the
# prompt); later lines render higher up. Order is chosen so in-progress work
# stays near the prompt and finished worktrees float to the top, out of the way:
#   1. base                (very bottom)
#   2. active, no timestamp
#   3. active, timestamped — most recent nearest the prompt
#   4. completed/errored   — MERGED/CLOSED/DONE/FAILED, most recent first (top)
sort_worktree_lines() {
    IFS= read -r line1; echo "$line1"
    IFS= read -r line2; echo "$line2"
    base_lines=""
    active_no_ts=""
    active_ts=""
    terminal_ts=""
    while IFS= read -r line; do
        # Same split as `cut -f1` / `cut -f2`: a line without a tab is its own field 1 and 2.
        if [[ "$line" == *$'\t'* ]]; then
            display=${line%%$'\t'*}
            epoch=${line#*$'\t'}
            epoch=${epoch%%$'\t'*}
        else
            display=$line
            epoch=$line
        fi
        if [[ "$display" == *"[BASE]"* ]]; then
            base_lines="$display"
        elif [[ "$display" == *"[MERGED]"* || "$display" == *"[CLOSED]"* || "$display" == *"[DONE]"* || "$display" == *"[FAILED]"* ]]; then
            terminal_ts="${terminal_ts}${epoch}	${display}
"
        elif [ "$epoch" = "0" ] || [ -z "$epoch" ]; then
            active_no_ts="${active_no_ts}${display}
"
        else
            active_ts="${active_ts}${epoch}	${display}
"
        fi
    done
    [ -n "$base_lines" ] && echo "$base_lines"
    [ -n "$active_no_ts" ] && printf '%s' "$active_no_ts"
    [ -n "$active_ts" ] && printf '%s' "$active_ts" | sort -t$'\t' -k1 -rn | cut -f2-
    if [ -n "$terminal_ts" ]; then
        # Full-width divider between active work (below) and finished worktrees
        # (above). Deliberately longer than any terminal — fzf truncates it to
        # the visible width so it spans edge to edge at any popup size. It carries
        # no [WORKTREE]/[BASE]/[AUTO] type token, so the action handlers skip it
        # (guard in the selection block and in worktree-delete-from-picker.sh).
        printf '─%.0s' $(seq 1 300); printf '\n'
        printf '%s' "$terminal_ts" | sort -t$'\t' -k1 -rn | cut -f2-
    fi
}

# Function to reload worktrees list
reload_worktrees() {
    get_worktrees | sort_worktree_lines
}

# Handle script being called with reload argument
if [ "$1" = "reload" ]; then
    reload_worktrees
    exit 0
fi

# Get the worktree data (see sort_worktree_lines for ordering rationale)
WORKTREE_DATA=$(get_worktrees | sort_worktree_lines)

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
    --header=$'\n'"$SEPARATOR"$'\n    [AI WORKING] [NEEDS INPUT] [BLOCKED] [AWAITING CI] [AWAITING REVIEW] [APPROVED] [MERGED] [CLOSED] [ACTIVE] [SAVED] [AUTO]   ● = unread\n'"$SEPARATOR"$'\n    enter switch   ctrl-x delete   ctrl-k kill session   ctrl-r reload' \
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
    # Ignore the section divider (or any line lacking a worktree type token)
    case "$selected" in
        *"[WORKTREE]"*|*"[BASE]"*|*"[AUTO]"*) ;;
        *) exit 0 ;;
    esac
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

    # $name came off the rendered row, which is truncated to 48 chars for column
    # alignment. Everything downstream (seen marker, worktree path, metadata dir)
    # keys off the untruncated name, so restore it from disk before use. Only an
    # unambiguous single match is accepted; anything else keeps the parsed value.
    if [ "$type" != "[BASE]" ] && [ ! -d "$WORKTREES_BASE/$REPO_NAME/$name" ]; then
        resolved=()
        for candidate in "$WORKTREES_BASE/$REPO_NAME/$name"*/; do
            [ -d "$candidate" ] && resolved+=("$candidate")
        done
        if [ ${#resolved[@]} -eq 1 ]; then
            name="$(basename "${resolved[0]}")"
            echo "[PICKER DEBUG] Resolved truncated name to '$name'" >> /tmp/tmux-worktree-debug.log
        elif [ ${#resolved[@]} -gt 1 ]; then
            echo "[PICKER DEBUG] Ambiguous prefix '$name' (${#resolved[@]} matches), left as-is" >> /tmp/tmux-worktree-debug.log
        fi
    fi

    # Derive worktree_path from name
    if [ "$type" = "[BASE]" ]; then
        worktree_path="$MAIN_REPO"
    else
        worktree_path="$WORKTREES_BASE/$REPO_NAME/$name"
    fi
    
    echo "[PICKER DEBUG] Parsed - icon:'$icon' name:'$name' type:'$type' session:'$session' path:'$worktree_path'" >> /tmp/tmux-worktree-debug.log
    
    # Mark this worktree as seen
    mkdir -p "$HOME/.config/conductor/seen"
    date +%s > "$HOME/.config/conductor/seen/${name}.seen"

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