#!/usr/bin/env bash

# Migrate existing worktrees to new centralized structure
# This is a one-time migration script

# Source metadata functions
source "$(dirname "$0")/worktree-metadata.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Worktree Migration Tool ===${NC}"
echo -e "${YELLOW}This will migrate existing worktrees to ~/worktrees/<repo>/<ticket>/${NC}"
echo

# Get main repository info
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
if [ -z "$MAIN_REPO" ]; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

REPO_NAME=$(basename "$MAIN_REPO")
PARENT_DIR=$(dirname "$MAIN_REPO")

echo -e "${BLUE}Repository:${NC} $REPO_NAME"
echo -e "${BLUE}Main path:${NC} $MAIN_REPO"
echo

# Find existing worktrees that need migration
echo -e "${YELLOW}Finding worktrees to migrate...${NC}"

# Use temp file to collect worktrees since we're in a subshell
TEMP_FILE=$(mktemp)

git worktree list --porcelain | while IFS= read -r line; do
    if [[ "$line" =~ ^worktree[[:space:]](.+)$ ]]; then
        worktree_path="${BASH_REMATCH[1]}"
        
        # Skip main worktree
        if [ "$worktree_path" = "$MAIN_REPO" ]; then
            continue
        fi
        
        # Check if it's already in the new structure
        if [[ "$worktree_path" =~ ^$WORKTREES_BASE/$REPO_NAME/ ]]; then
            echo -e "${GREEN}  ✓ Already migrated:${NC} $worktree_path"
            continue
        fi
        
        # This worktree needs migration
        echo "$worktree_path" >> "$TEMP_FILE"
        echo -e "${YELLOW}  → To migrate:${NC} $worktree_path"
    fi
done

# Read worktrees to migrate into array
WORKTREES_TO_MIGRATE=()
while IFS= read -r path; do
    [ -n "$path" ] && WORKTREES_TO_MIGRATE+=("$path")
done < "$TEMP_FILE"
rm -f "$TEMP_FILE"

# Count worktrees to migrate
MIGRATE_COUNT=${#WORKTREES_TO_MIGRATE[@]}

if [ $MIGRATE_COUNT -eq 0 ]; then
    echo
    echo -e "${GREEN}No worktrees need migration!${NC}"
    
    # Run sync to ensure metadata is up to date
    echo
    echo -e "${BLUE}Running metadata sync...${NC}"
    ~/.config/tmux/scripts/worktree-sync.sh
    exit 0
fi

echo
echo -e "${BLUE}Found $MIGRATE_COUNT worktree(s) to migrate${NC}"
echo
read -p "Proceed with migration? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Migration cancelled."
    exit 0
fi

# Create repo directory
mkdir -p "$WORKTREES_BASE/$REPO_NAME"

# Migrate each worktree
for worktree_path in "${WORKTREES_TO_MIGRATE[@]}"; do
    echo
    echo -e "${BLUE}Migrating: $worktree_path${NC}"
    
    # Extract ticket/name from path
    ticket=""
    if [[ "$worktree_path" =~ .*-([A-Z]+-[0-9]+)$ ]]; then
        ticket="${BASH_REMATCH[1]}"
    elif [[ "$worktree_path" =~ .*/([^/]+)$ ]]; then
        # Use directory name as ticket
        ticket="${BASH_REMATCH[1]}"
        # Remove repo name prefix if present
        ticket="${ticket#${REPO_NAME}-}"
    fi
    
    if [ -z "$ticket" ]; then
        echo -e "${RED}  ✗ Could not determine ticket name${NC}"
        continue
    fi
    
    echo -e "  Ticket: $ticket"
    
    # Get branch info
    branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    echo -e "  Branch: $branch"
    
    # New path
    NEW_PATH="$WORKTREES_BASE/$REPO_NAME/$ticket"
    echo -e "  New path: $NEW_PATH"
    
    # Check if new path already exists
    if [ -e "$NEW_PATH" ]; then
        echo -e "${RED}  ✗ Target path already exists${NC}"
        continue
    fi
    
    # Move the worktree
    echo -e "  ${YELLOW}Moving worktree...${NC}"
    if mv "$worktree_path" "$NEW_PATH"; then
        echo -e "  ${GREEN}✓ Moved successfully${NC}"
        
        # Update git worktree
        echo -e "  ${YELLOW}Updating git worktree reference...${NC}"
        # Git will automatically detect the move on next operation
        
        # Create metadata
        echo -e "  ${YELLOW}Creating metadata...${NC}"
        save_session_metadata "$REPO_NAME" "$ticket" "$NEW_PATH" "$branch" "$ticket"
        
        # Update tmux session if it exists
        if tmux has-session -t "${REPO_NAME}-${ticket}" 2>/dev/null; then
            # Old-style session name exists
            echo -e "  ${YELLOW}Renaming tmux session...${NC}"
            tmux rename-session -t "${REPO_NAME}-${ticket}" "$ticket" 2>/dev/null
        elif tmux has-session -t "_${REPO_NAME}-${ticket}" 2>/dev/null; then
            # Another old-style variant
            echo -e "  ${YELLOW}Renaming tmux session...${NC}"
            tmux rename-session -t "_${REPO_NAME}-${ticket}" "$ticket" 2>/dev/null
        fi
        
        echo -e "  ${GREEN}✓ Migration complete${NC}"
    else
        echo -e "${RED}  ✗ Failed to move worktree${NC}"
    fi
done

echo
echo -e "${BLUE}=== Migration Summary ===${NC}"
echo -e "Worktrees migrated: $MIGRATE_COUNT"
echo

# Run sync to finalize
echo -e "${BLUE}Running final sync...${NC}"
~/.config/tmux/scripts/worktree-sync.sh