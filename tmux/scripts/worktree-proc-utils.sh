#!/usr/bin/env bash

# worktree-proc-utils.sh — kill dev servers / watchers tied to a worktree.
#
# Ported from conductor-ctl.sh's kill_worktree_procs() so the tmux worktree
# picker tears down lingering processes the same way `conductor prune`/`stop`
# do. `bun run dev` dev servers reparent to launchd/init (PPID 1), so killing
# the tmux session never reaches them — they keep holding ports (e.g. 3000)
# after the worktree dir is gone. This finds and kills the whole subtree.
#
# Usage — source this file, then call as a PLAIN STATEMENT (never $(...)):
#     kill_worktree_procs "<worktree-path>"
#     echo "$WT_KILLED_PROCS"   # number of processes killed (0 if none)
#
# Why not a command substitution: the cwd matching below catches every shell
# whose cwd is in the worktree. The picker popup runs with cwd inside it
# (display-popup -d "#{pane_current_path}"), so $$ and the popup/server chain
# must be protected — done via the ancestry guard. But MSG=$(kill_worktree_procs
# ...) would also spawn a capturing subshell with that same cwd, and on bash 3.2
# (macOS default, no BASHPID) there is no reliable way to identify and protect
# it, so it would kill itself and lose the result. Returning via a global and
# calling as a plain statement keeps the running shell as $$, which IS protected.
# Conductor doesn't face this — it runs from a daemon whose cwd is never in a
# worktree, and uses a modern bash.

# Collect a PID and all of its descendants (depth-first). Echoes one PID per line.
# Needed because a dev server is a tree: bun → node → next-server. Only the node's
# argv embeds the worktree path; the next-server child (the actual CPU hog) shows
# argv "next-server (vX)" with no path, so it must be reached via the parent.
_descendant_pids() {
    local root="$1"
    echo "$root"
    local child
    for child in $(pgrep -P "$root" 2>/dev/null || true); do
        _descendant_pids "$child"
    done
}

# Echo a PID and every ancestor up to (but not including) PID 1, one per line.
# Used to protect the shell running this cleanup and its parent popup/server
# chain from being killed when cwd matching catches them.
_ancestor_pids() {
    local pid="$1"
    while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
        echo "$pid"
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
}

# Filter stdin (one PID per line), dropping any PID present in the newline-
# separated list passed as $1. Used to strip protected (self/ancestor) PIDs.
# Uses grep (not awk -v) because BSD/macOS awk rejects a multi-line -v value.
_exclude_pids() {
    local protect
    protect=$(printf '%s\n' "$1" | grep -E '^[0-9]+$' | sort -u)
    if [ -z "$protect" ]; then
        cat
        return
    fi
    grep -vxF -f <(printf '%s\n' "$protect")
}

# Kill any lingering processes tied to a worktree (dev servers, file watchers, etc.)
# that aren't tracked by tmux or PID files. Dev servers started with `bun run dev`
# reparent to launchd/init (PPID 1), so killing the tmux session never reaches them.
#
# Finds "seed" processes two ways, then kills each seed's entire subtree:
#   1. Command line referencing the worktree path — catches the node process whose
#      argv embeds the absolute worktree path. Survives even after the worktree
#      directory has been deleted (the orphan case).
#   2. Current working directory at/under the worktree — catches bun/next-server
#      that don't name the path in argv (only while the directory still exists).
# Subtree expansion then reaches the next-server child in the orphan case where its
# directory is gone and only its node parent could be matched by argv.
# $$ and its ancestors are excluded so the picker can never kill its own popup shell.
# Sets the global WT_KILLED_PROCS to the number of processes killed.
kill_worktree_procs() {
    WT_KILLED_PROCS=0
    local wt_path="$1"
    [ -n "$wt_path" ] || return 0

    # Resolve the real path too, so cwd matching survives symlinked parents
    # (e.g. macOS /var -> /private/var).
    local wt_real="$wt_path"
    if [ -d "$wt_path" ]; then
        wt_real=$(cd "$wt_path" 2>/dev/null && pwd -P 2>/dev/null || echo "$wt_path")
    fi

    # PIDs we must never kill: this shell ($$) and its whole ancestry (the popup
    # wrapper, tmux server). The picker popup's cwd is inside the worktree, so
    # without this the cwd match below would target our own process chain.
    local protect
    protect=$(_ancestor_pids "$$")

    local seeds=""

    # 1. By command line (works post-deletion).
    seeds=$(pgrep -f "$wt_path" 2>/dev/null || true)

    # 2. By cwd (only meaningful while the directory exists), matching either the
    #    given path or its resolved real path.
    if [ -d "$wt_path" ]; then
        local cwd_pids
        cwd_pids=$(lsof -a -d cwd -F pn 2>/dev/null | awk -v d1="$wt_path" -v d2="$wt_real" '
            /^p/{ pid=substr($0,2) }
            /^n/{ p=substr($0,2);
                  if (p==d1 || index(p, d1"/")==1 || p==d2 || index(p, d2"/")==1) print pid }' || true)
        seeds=$(printf '%s\n%s\n' "$seeds" "$cwd_pids")
    fi

    # Normalize seeds: numeric, unique, excluding $$ + ancestors.
    seeds=$(echo "$seeds" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u \
        | _exclude_pids "$protect")
    [ -z "$seeds" ] && return 0

    # Expand each seed to its full subtree (reaches next-server children), then
    # re-dedupe and drop $$ + ancestors again (subtree expansion of a protected
    # parent can re-introduce them).
    local pids="" s
    for s in $seeds; do
        pids="$pids
$(_descendant_pids "$s")"
    done
    pids=$(echo "$pids" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u \
        | _exclude_pids "$protect")
    [ -z "$pids" ] && return 0

    # Drop PIDs that already exited — chiefly this function's own short-lived
    # discovery subshells (pgrep/lsof/awk) that momentarily shared the worktree
    # cwd. Leaves only the real lingering processes, so the count stays honest.
    local live="" p
    for p in $pids; do
        kill -0 "$p" 2>/dev/null && live="$live $p"
    done
    pids=$(echo "$live" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u)
    [ -z "$pids" ] && return 0

    # Graceful TERM first, then SIGKILL any straggler (next-server can ignore TERM
    # while mid-compile under turbopack).
    echo "$pids" | xargs kill 2>/dev/null || true
    sleep 1
    for p in $pids; do
        kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null || true
    done

    WT_KILLED_PROCS=$(echo "$pids" | grep -c . || true)
}
