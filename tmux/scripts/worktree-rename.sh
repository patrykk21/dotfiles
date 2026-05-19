#!/usr/bin/env bash

# Rename an existing git worktree and its tmux session.
# Branch is intentionally left untouched (open PRs stay valid).
# Usage: worktree-rename.sh <old-name> <new-name>

source "$(dirname "$0")/worktree-metadata.sh"

OLD="$1"
NEW="$2"

# ── Validation ─────────────────────────────────────────────────────
if [ -z "$OLD" ] || [ -z "$NEW" ]; then
    tmux display-message -d 2000 "Usage: worktree-rename.sh <old> <new>"
    exit 1
fi

if [ "$OLD" = "$NEW" ]; then
    tmux display-message -d 2000 "Error: old and new names are identical"
    exit 1
fi

if ! echo "$NEW" | grep -qE '^[A-Za-z]+-[0-9]+$|^[A-Za-z0-9_-]+$'; then
    tmux display-message -d 2000 "Error: invalid new name '$NEW'"
    exit 1
fi

# ── Resolve repo ───────────────────────────────────────────────────
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
if [ -z "$MAIN_REPO" ]; then
    tmux display-message -d 2000 "Error: not in a git repository"
    exit 1
fi
REPO_NAME=$(basename "$MAIN_REPO")

OLD_META="$WORKTREES_BASE/$REPO_NAME/.worktree-meta/sessions/${OLD}.json"
NEW_META="$WORKTREES_BASE/$REPO_NAME/.worktree-meta/sessions/${NEW}.json"

if [ ! -f "$OLD_META" ]; then
    tmux display-message -d 2000 "Error: no metadata for '$OLD'"
    exit 1
fi
if [ -f "$NEW_META" ]; then
    tmux display-message -d 2000 "Error: '$NEW' already exists"
    exit 1
fi

OLD_PATH=$(jq -r '.worktree_path // empty' "$OLD_META")
NEW_PATH="$WORKTREES_BASE/$REPO_NAME/$NEW"

if [ -z "$OLD_PATH" ] || [ ! -d "$OLD_PATH" ]; then
    tmux display-message -d 2000 "Error: worktree path missing: $OLD_PATH"
    exit 1
fi
if [ -e "$NEW_PATH" ]; then
    tmux display-message -d 2000 "Error: path already exists: $NEW_PATH"
    exit 1
fi

# ── Refuse if dev server is running on this worktree's port ────────
PORT=$(jq -r '.port // empty' "$OLD_META")
if [ -n "$PORT" ] && lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    tmux display-message -d 3000 "Error: dev server on :$PORT is up — stop it first"
    exit 1
fi

tmux display-message -d 1500 "Renaming $OLD → $NEW..."

# ── 1. Move worktree on disk ───────────────────────────────────────
if ! git -C "$MAIN_REPO" worktree move "$OLD_PATH" "$NEW_PATH" 2>/dev/null; then
    tmux display-message -d 3000 "Error: git worktree move failed (open files?)"
    exit 1
fi

# ── 2. Move + update metadata (preserve branch, port, created, tabs)
TEMP_META=$(mktemp)
jq --arg new "$NEW" \
   --arg path "$NEW_PATH" \
   --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
   '.ticket = $new
    | .session_name = $new
    | .worktree_path = $path
    | .last_accessed = $ts' \
   "$OLD_META" > "$TEMP_META" && mv "$TEMP_META" "$NEW_META"
rm -f "$OLD_META"

# ── 3. Patch .claude/launch.json (absolute-path rewrite) ───────────
if [ -f "$NEW_PATH/.claude/launch.json" ]; then
    TEMP_LAUNCH=$(mktemp)
    sed "s|$OLD_PATH|$NEW_PATH|g" "$NEW_PATH/.claude/launch.json" > "$TEMP_LAUNCH" \
        && mv "$TEMP_LAUNCH" "$NEW_PATH/.claude/launch.json"
fi

# ── 4. Rename tmux session + respawn stale panes ───────────────────
if tmux has-session -t "$OLD" 2>/dev/null; then
    tmux rename-session -t "$OLD" "$NEW"

    MY_PANE="${TMUX_PANE:-}"
    tmux list-panes -s -t "$NEW" -F '#{pane_id} #{pane_current_path}' \
      | while read -r pane_id pane_path; do
            case "$pane_path" in
                "$OLD_PATH"|"$OLD_PATH"/*)
                    # Don't kill the pane running this script
                    [ "$pane_id" = "$MY_PANE" ] && continue
                    new_pane_path="$NEW_PATH${pane_path#$OLD_PATH}"
                    tmux respawn-pane -k -t "$pane_id" -c "$new_pane_path" 2>/dev/null || true
                    ;;
            esac
        done
fi

tmux display-message -d 3000 "✓ Renamed $OLD → $NEW"
