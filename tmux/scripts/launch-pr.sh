#!/usr/bin/env bash
# Launch pull request in browser

# Get current directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Check if we're in a git repository
if ! git -C "$CURRENT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tmux display-message "Not in a git repository"
    exit 1
fi

# Check if gh CLI is available
if ! command -v gh >/dev/null 2>&1; then
    tmux display-message "GitHub CLI (gh) not found"
    exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git -C "$CURRENT_DIR" branch --show-current 2>/dev/null)

if [ -z "$CURRENT_BRANCH" ]; then
    tmux display-message "Not on a branch (detached HEAD)"
    exit 1
fi

# Resolve gh host + token for this repo. Multi-account setups (personal
# patrykk21/* + work c-pkotarski/groupon/*) need the right token per repo, or
# `gh pr list` 404s when the active account can't see the repo.
#
# Resolution order:
#   1. Look up the repo in ~/worktrees/.metadata/repos.json by repo_name
#      (derived from $CURRENT_DIR — either the worktree's $WORKTREES_BASE/<repo>
#      prefix or by matching main_path). If a `gh_account` is recorded there,
#      use that account's token. This is the canonical, explicit source.
#   2. If OWNER (parsed from the remote URL) matches a logged-in gh username,
#      use that account's token (correct for personal repos like
#      `patrykk21/foo` where OWNER == username).
#   3. Fall back to gh's active account.
#
# To register an account for a repo:
#   jq '.repositories.<name>.gh_account = "<user>"' ~/worktrees/.metadata/repos.json
REMOTE_URL=$(git -C "$CURRENT_DIR" remote get-url origin 2>/dev/null)
GH_HOST_VAL="github.com"
case "$REMOTE_URL" in
    *github.groupondev.com*) GH_HOST_VAL="github.groupondev.com" ;;
esac
# Extract <owner> from owner/repo at the end of the URL (handles ssh + https, optional .git)
OWNER=$(printf '%s\n' "$REMOTE_URL" | sed -nE 's#.*[:/]([^/:]+)/[^/]+(\.git)?$#\1#p')

GH_ENV=(env "GH_HOST=$GH_HOST_VAL")
RESOLVED_TOKEN=""

# 1. Metadata lookup: ~/worktrees/.metadata/repos.json
REPOS_JSON="$HOME/worktrees/.metadata/repos.json"
if [ -f "$REPOS_JSON" ] && command -v jq >/dev/null 2>&1; then
    # Match by main_path prefix or by $WORKTREES_BASE/<repo>/ prefix.
    META_REPO=$(jq -r --arg cwd "$CURRENT_DIR" --arg wbase "$HOME/worktrees" '
        .repositories
        | to_entries
        | map(. as $e | select(
            ($cwd | startswith($e.value.main_path)) or
            ($cwd | startswith($wbase + "/" + $e.key + "/"))
          ))
        | .[0].key // empty
    ' "$REPOS_JSON" 2>/dev/null)
    if [ -n "$META_REPO" ]; then
        META_ACCOUNT=$(jq -r --arg k "$META_REPO" '.repositories[$k].gh_account // empty' "$REPOS_JSON" 2>/dev/null)
        META_HOST=$(jq -r    --arg k "$META_REPO" '.repositories[$k].gh_host    // empty' "$REPOS_JSON" 2>/dev/null)
        [ -n "$META_HOST" ] && GH_HOST_VAL="$META_HOST"
        if [ -n "$META_ACCOUNT" ]; then
            RESOLVED_TOKEN=$(gh auth token --hostname "$GH_HOST_VAL" --user "$META_ACCOUNT" 2>/dev/null)
        fi
    fi
fi

# 2. Fall back to OWNER-as-username (personal repos like patrykk21/foo).
if [ -z "$RESOLVED_TOKEN" ] && [ -n "$OWNER" ]; then
    RESOLVED_TOKEN=$(gh auth token --hostname "$GH_HOST_VAL" --user "$OWNER" 2>/dev/null)
fi

# Re-seed GH_ENV with the (possibly updated) host.
GH_ENV=(env "GH_HOST=$GH_HOST_VAL")
if [ -n "$RESOLVED_TOKEN" ]; then
    GH_ENV+=("GH_TOKEN=$RESOLVED_TOKEN")
fi

# Try to find existing PR for current branch (only open PRs — merged/closed
# are intentionally skipped so the keybind always points to actionable work).
PR_URL=$(cd "$CURRENT_DIR" && "${GH_ENV[@]}" gh pr list --head "$CURRENT_BRANCH" --json url --jq '.[0].url' 2>/dev/null)

source ~/.config/tmux/scripts/os-utils.sh

if [ -n "$PR_URL" ] && [ "$PR_URL" != "null" ]; then
    if open_url "$PR_URL"; then
        tmux display-message "Opened PR for branch: $CURRENT_BRANCH"
    else
        tmux display-message "Cannot open browser on $(detect_os)"
    fi
else
    tmux display-message "No PR found for branch: $CURRENT_BRANCH"
fi