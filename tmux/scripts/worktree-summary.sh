#!/usr/bin/env bash
# Display the current worktree's context.md summary.
# Falls back to a helpful message if no summary exists yet.
#
# Invoked by tmux worktree-mode keybind `s`.

set -euo pipefail

session_name=$(tmux display-message -p '#S' 2>/dev/null || echo "")

if [[ -z "$session_name" ]]; then
    echo "Error: could not determine current tmux session." >&2
    read -n 1 -s -r -p "Press any key to close..."
    exit 1
fi

# Look for context.md across all project worktree metadata dirs.
# Post-migration layout: ~/worktrees/<project>/.worktree-meta/sessions/<session>/context.md
context_path=""
for candidate in "$HOME"/worktrees/*/.worktree-meta/sessions/"$session_name"/context.md; do
    if [[ -f "$candidate" ]]; then
        context_path="$candidate"
        break
    fi
done

if [[ -n "$context_path" ]]; then
    # Prefer glow for rendered markdown; fall back to less if unavailable.
    if command -v glow >/dev/null 2>&1; then
        # Pager mode (-p) gives us scrolling + glow rendering.
        # Style "auto" adapts to terminal background.
        glow -p -s auto "$context_path"
    else
        updated=""
        if [[ -f "$(dirname "$context_path")/summary.json" ]]; then
            updated=$(jq -r '.updated // "unknown"' "$(dirname "$context_path")/summary.json" 2>/dev/null || echo "")
        fi
        prompt="Worktree summary — $session_name${updated:+ (updated: $updated)}"
        less -R --prompt="$prompt" "$context_path"
    fi
else
    # No summary yet — show a friendly message explaining why and how to force one.
    cat <<EOF
No summary available for this worktree yet.

Session: $session_name

Summaries are written by the conductor summarizer pass (runs every 60s
alongside the ticket pipeline). They appear once one of these has happened:

  - A Claude turn ended in this worktree (Stop hook)
  - You ran /pause-worktree in a Claude session
  - A commit was made (post-commit hook)
  - Conductor finished a run on this ticket

To force a summary on the next tick, drop the force flag:

  mkdir -p ~/worktrees/*/.worktree-meta/sessions/$session_name/flags 2>/dev/null
  touch ~/worktrees/*/.worktree-meta/sessions/$session_name/flags/needs-summary-update-force

Note: the summarizer may not be implemented yet. See
~/.config/conductor/docs/worktree-context-system.md for the design.

Press any key to close...
EOF
    read -n 1 -s -r
fi
