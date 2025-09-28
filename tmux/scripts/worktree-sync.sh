#!/usr/bin/env bash

# Sync worktree metadata with actual state
# This script reconciles metadata with actual worktrees and sessions

# Source metadata functions
source "$(dirname "$0")/worktree-metadata.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Worktree Metadata Sync ===${NC}"
echo

# Get main repository info
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
if [ -z "$MAIN_REPO" ]; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

REPO_NAME=$(basename "$MAIN_REPO")

# Ensure directories exist
ensure_metadata_dirs "$REPO_NAME"

# Register repo if not already done
register_repo "$REPO_NAME" "$MAIN_REPO"

echo -e "${BLUE}Repository:${NC} $REPO_NAME"
echo -e "${BLUE}Main path:${NC} $MAIN_REPO"
echo

# Step 1: Find orphaned metadata (metadata exists but worktree doesn't)
echo -e "${YELLOW}Checking for orphaned metadata...${NC}"
ORPHANED_COUNT=0

for metadata_file in "$WORKTREES_BASE/$REPO_NAME/.worktree-meta/sessions"/*.json; do
    if [ -f "$metadata_file" ]; then
        ticket=$(basename "$metadata_file" .json)
        worktree_path=$(jq -r '.worktree_path // empty' "$metadata_file")
        
        if [ -n "$worktree_path" ]; then
            # Check if worktree still exists
            if ! git worktree list | grep -q "^$worktree_path"; then
                echo -e "${RED}  ✗ Orphaned metadata:${NC} $ticket (path: $worktree_path)"
                
                # Check if session still exists
                if tmux has-session -t "$ticket" 2>/dev/null; then
                    echo "    - Tmux session still active"
                fi
                
                # Remove orphaned metadata
                rm -f "$metadata_file"
                ((ORPHANED_COUNT++))
            fi
        fi
    fi
done

if [ $ORPHANED_COUNT -eq 0 ]; then
    echo -e "${GREEN}  ✓ No orphaned metadata found${NC}"
fi
echo

# Step 2: Find worktrees without metadata
echo -e "${YELLOW}Checking for worktrees without metadata...${NC}"
MISSING_METADATA_COUNT=0

git worktree list --porcelain | while IFS= read -r line; do
    if [[ "$line" =~ ^worktree[[:space:]](.+)$ ]]; then
        worktree_path="${BASH_REMATCH[1]}"
        
        # Skip main worktree
        if [ "$worktree_path" = "$MAIN_REPO" ]; then
            continue
        fi
        
        # Try to extract ticket from path
        ticket=""
        if [[ "$worktree_path" =~ $WORKTREES_BASE/$REPO_NAME/([^/]+)$ ]]; then
            ticket="${BASH_REMATCH[1]}"
        elif [[ "$worktree_path" =~ .*-([A-Z]+-[0-9]+)$ ]]; then
            ticket="${BASH_REMATCH[1]}"
        elif [[ "$worktree_path" =~ .*/([^/]+)$ ]]; then
            ticket="${BASH_REMATCH[1]}"
        fi
        
        if [ -n "$ticket" ]; then
            metadata_file="$WORKTREES_BASE/$REPO_NAME/.worktree-meta/sessions/${ticket}.json"
            
            if [ ! -f "$metadata_file" ]; then
                # Get branch name
                branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
                
                echo -e "${YELLOW}  ! Missing metadata:${NC} $ticket"
                echo "    Path: $worktree_path"
                echo "    Branch: $branch"
                
                # Check if session exists
                if tmux has-session -t "$ticket" 2>/dev/null; then
                    echo "    Tmux session: active"
                else
                    echo "    Tmux session: none"
                fi
                
                # Create missing metadata
                save_session_metadata "$REPO_NAME" "$ticket" "$worktree_path" "$branch" "$ticket"
                echo -e "${GREEN}    → Created metadata${NC}"
                ((MISSING_METADATA_COUNT++))
            fi
        fi
    fi
done

if [ $MISSING_METADATA_COUNT -eq 0 ]; then
    echo -e "${GREEN}  ✓ All worktrees have metadata${NC}"
fi
echo

# Step 3: Check for mismatched sessions
echo -e "${YELLOW}Checking tmux sessions...${NC}"
ORPHANED_SESSIONS=0

tmux list-sessions -F "#{session_name}" 2>/dev/null | while read -r session; do
    # Skip non-ticket sessions
    if ! [[ "$session" =~ ^[A-Z]+-[0-9]+$ ]] && ! [[ "$session" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        continue
    fi
    
    # Check if session has corresponding metadata
    found=false
    for repo_dir in "$WORKTREES_BASE"/*; do
        if [ -d "$repo_dir/.worktree-meta/sessions" ]; then
            if [ -f "$repo_dir/.worktree-meta/sessions/${session}.json" ]; then
                found=true
                break
            fi
        fi
    done
    
    if [ "$found" = false ]; then
        # Check if it matches old-style session names
        if [[ "$session" =~ ^_?${REPO_NAME}-(.+)$ ]]; then
            ticket="${BASH_REMATCH[1]}"
            echo -e "${YELLOW}  ! Legacy session format:${NC} $session (ticket: $ticket)"
        else
            echo -e "${RED}  ✗ Orphaned session:${NC} $session (no metadata)"
        fi
        ((ORPHANED_SESSIONS++))
    fi
done

if [ $ORPHANED_SESSIONS -eq 0 ]; then
    echo -e "${GREEN}  ✓ All sessions have metadata${NC}"
fi
echo

# Step 4: Summary
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "Orphaned metadata removed: $ORPHANED_COUNT"
echo -e "Missing metadata created: $MISSING_METADATA_COUNT"
echo -e "Orphaned sessions found: $ORPHANED_SESSIONS"

# List current state
echo
echo -e "${BLUE}=== Current Worktrees ===${NC}"
list_repo_sessions "$REPO_NAME" | while read -r ticket; do
    metadata_file="$WORKTREES_BASE/$REPO_NAME/.worktree-meta/sessions/${ticket}.json"
    if [ -f "$metadata_file" ]; then
        worktree_path=$(jq -r '.worktree_path // empty' "$metadata_file")
        branch=$(jq -r '.branch // empty' "$metadata_file")
        
        # Check session status
        if tmux has-session -t "$ticket" 2>/dev/null; then
            session_status="${GREEN}[SESSION]${NC}"
        else
            session_status="${YELLOW}[NO SESSION]${NC}"
        fi
        
        echo -e "  $ticket $session_status - $branch"
    fi
done