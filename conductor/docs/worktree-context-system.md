# Worktree Context System — Design

Status: Phase 3 complete — picker surfaces summary/status, conductor marker→event bridge live
Owner: Patryk
Last updated: 2026-04-23

## Problem

Patryk runs 8–10 active worktrees. Switching between them loses context: what is this worktree for, what was the last thing happening, what's blocking, where's the PR, what did I say in Slack about it. Current infrastructure (per-ticket `<ticket>.json` metadata + conductor markers) covers plumbing but not narrative.

Goal: every worktree has a live, AI-maintained context document plus structured state. Picker surfaces one-line status per worktree. A tmux keybind opens the full context on demand. No auto-popups.

## Key design decisions (locked)

1. **Per-worktree directory** holding several single-writer files — not one shared JSON. Filesystem provides concurrency; no locks needed.
2. **Prose in markdown** (`context.md`), structured data in JSON. Separate artifacts, separate writers.
3. **All state mutations go through `worktree-event`** — a centralized command with a fixed event vocabulary that maps events to flag operations. No caller touches flag paths directly.
4. **Summarizer uses Sonnet**, gated by a signal hash so most scheduler ticks are no-ops.
5. **Four triggers** for summary regeneration: Claude Stop hook, post-commit git hook, 1-minute scheduler, explicit `/pause-worktree` command. All route through `worktree-event` → `summarize-worktree`.
6. **`/with-markers` refactors to delegate to `worktree-event`.** Keeps its ergonomic command-wrapping API; no longer owns flag semantics.

## Directory layout

Canonical home per worktree:

```
~/worktrees/<project>/.worktree-meta/sessions/<ticket>/
  meta.json              # writer: worktree-create.sh (immutable after creation)
  conductor.json         # writer: conductor orchestrator only
  summary.json           # writer: summarizer only
  context.md             # writer: summarizer; hand-editable by user
  flags/                 # each file = one boolean flag; existence = true
    needs-summary-update
    needs-summary-update-force
    conductor-queued
    conductor-running
    conductor-lock
    conductor-error
```

Existing conductor markers at `~/.config/conductor/markers/<ticket>.<type>` migrate into this tree (see Migration section).

## File schemas

### `meta.json`
Set at worktree creation, immutable after. Replaces current `<ticket>.json`.

```json
{
  "schema_version": 1,
  "ticket": "PROJ-639",
  "title": "Incidents severity visibility",
  "branch": "PROJ-639-incidents-sev-vis",
  "session_name": "PROJ-639-incidents-sev-vis",
  "worktree_path": "/Users/vigenerr/worktrees/myapp/PROJ-639-incidents-sev-vis",
  "port": 55231,
  "tabs": ["editor", "server", "claude"],
  "created": "2026-04-19T10:00:00Z",
  "jira_url": "https://...",
  "project": "myapp"
}
```

### `conductor.json`
Conductor's run state. Single writer: the conductor orchestrator.

```json
{
  "schema_version": 1,
  "status": "idle",
  "last_run": "2026-04-22T09:00:00Z",
  "last_run_exit_code": 0,
  "last_review_at": "2026-04-22T09:15:00Z",
  "run_count": 3,
  "last_error": null,
  "attempt_budget_remaining": 5
}
```

### `summary.json`
Structured metadata about the current summary. Single writer: summarizer.

```json
{
  "schema_version": 1,
  "status": "BLOCKED",
  "status_enum": ["ACTIVE", "BLOCKED", "WAITING_REVIEW", "STALE", "DONE"],
  "headline": "Waiting on sev4 color decision",
  "updated": "2026-04-22T14:30:00Z",
  "signal_hash": "sha256:…",
  "pr": "org/myapp#123",
  "pr_state": "open",
  "last_activity_source": "claude"
}
```

### `context.md`
Prose narrative. Summarizer rewrites it; user may edit between regenerations (signal hash detects user edits via file mtime and preserves a "user notes" section).

```markdown
# PROJ-639 · Incidents severity visibility

## Objective
Stable 1–3 lines pulled from Jira summary+description.

## What's done
- Added severity column
- Wired up filter

## What's next / blocked on
- Waiting on sev4 color decision
- PR review comments from @alice unaddressed

## Last conversation with Claude
Q: Should sev4 render as gray or yellow?
A: Pending user decision.

## Pointers
PR: org/myapp#123
Slack: <user-pasted link>

## User notes
<preserved across regenerations>
```

## Flag vocabulary

Flags are empty files under `flags/`. Existence = true, absence = false. No content.

| Flag | Meaning | Touched by | Cleared by |
|---|---|---|---|
| `needs-summary-update` | Something changed; summary should regenerate next tick | any state-changing event | summarizer on completion |
| `needs-summary-update-force` | Regenerate even if signal hash unchanged (e.g., after manual note) | `/pause-worktree`, `note-added` | summarizer on completion |
| `conductor-queued` | User labelled ticket for conductor; orchestrator should pick up | jira-label-poller | `conductor-started` event |
| `conductor-running` | Conductor currently executing in this worktree | `conductor-started` | `conductor-finished`/`-failed` |
| `conductor-lock` | Prevents concurrent conductor runs on same ticket | `conductor-started` | `conductor-finished`/`-failed` |
| `conductor-error` | Last run failed; needs human attention | `conductor-failed` | next successful run |

Extending the vocabulary = adding a row here + the event(s) that touch/clear it.

## Event vocabulary

All callers emit one of these:

| Event | Args | Flags touched | Flags cleared | Also updates |
|---|---|---|---|---|
| `worktree-created` | `--ticket` | — | — | creates directory, writes `meta.json` |
| `worktree-abandoned` | `--ticket` | — | all | marks worktree as terminated |
| `commit-made` | (infers from cwd) | `needs-summary-update` | — | `meta.last_accessed` |
| `claude-turn-ended` | — | `needs-summary-update` | — | `meta.last_accessed` |
| `claude-session-paused` | — | `needs-summary-update`, `needs-summary-update-force` | — | `meta.last_accessed` |
| `conductor-queued` | `--ticket` | `conductor-queued` | `conductor-error` | — |
| `conductor-started` | `--ticket` | `conductor-running`, `conductor-lock` | `conductor-queued` | `conductor.status="running"`, `conductor.last_run` |
| `conductor-finished` | `--ticket`, `--exit-code` | `needs-summary-update` | `conductor-running`, `conductor-lock` | `conductor.status="idle"`, `conductor.last_run_exit_code` |
| `conductor-failed` | `--ticket`, `--error` | `needs-summary-update`, `conductor-error` | `conductor-running`, `conductor-lock` | `conductor.last_error` |
| `pr-state-changed` | `--pr-state` | `needs-summary-update` | — | `summary.pr_state` (no LLM — direct) |
| `note-added` | `--text` | `needs-summary-update`, `needs-summary-update-force` | — | appends to `context.md` "User notes" |
| `summary-written` | — | — | `needs-summary-update`, `needs-summary-update-force` | — |

Every event also stamps `meta.last_accessed` as a universal side effect.

## `worktree-event` command

```
worktree-event <event-name> [--ticket <id>] [--exit-code <n>] [--error <msg>] [--pr-state <s>] [--text <str>]
```

Resolution order for ticket:
1. `--ticket` flag if present
2. Current branch name if inside a worktree (regex `ECH-\d+.*`)
3. `$PWD` match against known worktree paths
4. Error out

Implementation sketch (`~/.config/conductor/bin/worktree-event`):
```bash
#!/usr/bin/env bash
set -euo pipefail
event="$1"; shift
# parse flags, resolve ticket, locate session dir
# look up event in event table (keep it as a data file or case statement)
# perform flag operations idempotently (touch / rm -f)
# apply metadata patches via atomic-write on targeted JSON
```

Event table kept as a data file (JSON or a sourced bash map) so editing it doesn't require touching control flow. Unknown events exit non-zero — unknown-event discipline is a feature.

## `atomic-write` helper

```
atomic-write <target-path> <content-stdin-or-arg>
```

Internally: writes to `<target>.tmp.$$` then `mv` (POSIX atomic rename). All JSON writers use this. Flag operations use plain `touch` / `rm -f` — already atomic.

## `/with-markers` refactor

`/with-markers` becomes a thin wrapper:

```bash
# before: manual marker touches
# after:
worktree-event conductor-started --ticket "$TICKET"
if "$@"; then
  worktree-event conductor-finished --ticket "$TICKET" --exit-code 0
else
  code=$?
  worktree-event conductor-failed --ticket "$TICKET" --error "exit $code"
  exit $code
fi
```

Because `conductor-finished` includes `needs-summary-update` in its flag set, every conductor run automatically queues a summary refresh. No separate bookkeeping.

## Triggers → summarizer

All four triggers emit events; the scheduler consumes `needs-summary-update` flags.

### Claude Stop hook
Configured in `~/.claude/settings.json`:
```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "nohup worktree-event claude-turn-ended >/dev/null 2>&1 &"
      }]
    }]
  }
}
```

Background-spawned. Does not block the user's turn.

### Post-commit git hook
`.git/hooks/post-commit` (installed by worktree-create.sh into each worktree):
```bash
#!/usr/bin/env bash
worktree-event commit-made &
```

### Scheduler — shared with conductor

**No new launchd job.** The existing `com.conductor.plist` already fires `conductor-runner.sh` every 60s. The summarizer runs as a second pass inside the same runner.

Current runner (`conductor-runner.sh`):
1. Iterates `projects/*.env`
2. Fires `conductor.sh` per project in parallel
3. `wait`s for all to finish

Extended runner adds a Pass 2 after the wait:

```bash
# Pass 1 (existing): advance tickets
for config in "$PROJECTS_DIR"/*.env; do
    [ -f "$config" ] || continue
    ( CONDUCTOR_CONF="$config" "$CONDUCTOR_DIR/conductor.sh" ) &
done
wait

# Pass 2 (new): refresh dirty summaries
"$CONDUCTOR_DIR/summarize-dirty.sh"
```

`summarize-dirty.sh`:
```bash
for session_dir in ~/worktrees/*/.worktree-meta/sessions/*/; do
  [[ -f "$session_dir/flags/needs-summary-update" ]] || continue
  ticket=$(basename "$session_dir")
  summarize-worktree --ticket "$ticket" &
done
wait
```

Why Pass 2 is sequential after Pass 1 (not parallel with it): conductor's ticket execution emits `conductor-finished` events which `touch needs-summary-update`. Running summaries *after* the ticket pass means the same 60s tick that advances a ticket also refreshes its summary. One tick, end-to-end.

Cheap on no-ops: directory scan is O(n) stats; LLM invoked only when flag present AND signal hash has changed.

### Event-driven coupling between conductor and summarizer

The ticket pipeline and summary pipeline never call each other directly. They communicate only through flag files.

- Conductor starts a run → `worktree-event conductor-started` → touches `conductor-running`, clears `conductor-queued`, writes `conductor.json`
- Conductor finishes → `worktree-event conductor-finished` → clears `conductor-running`, touches `needs-summary-update`
- Pass 2 picks up `needs-summary-update` later in the same tick, regenerates summary

This is the unification: one scheduler, one event vocabulary, two passes that happen to share state via the filesystem.

### Explicit pause
`/pause-worktree` slash command in Claude — emits `claude-session-paused` and waits for summarizer to complete (synchronous for this trigger only, so the user sees confirmation).

## Summarizer (`summarize-worktree`)

```
summarize-worktree --ticket <id> [--force]
```

Steps:
1. Read `meta.json`, `summary.json`, `conductor.json`.
2. Gather signals:
   - `git log -20 --oneline` on the worktree's branch
   - `git diff --stat` for uncommitted
   - Tail of `~/.claude/projects/<project-path>/history.jsonl` for this worktree (last ~50 entries)
   - Jira ticket body (cached; only re-fetch every 24h)
   - PR state (from `gh pr view --json` if PR exists; cached ~5min)
3. Compute `signal_hash` = sha256 of concatenated: HEAD sha, history.jsonl mtime, PR state, any `force` flag.
4. If `signal_hash == summary.json.signal_hash` and no `--force`: exit (no-op tick).
5. Build prompt for Sonnet with all gathered inputs + current `context.md` (to preserve "User notes" section).
6. Model output: structured JSON (status, headline, rewritten markdown body).
7. Write `context.md` via `atomic-write`, preserving "User notes" section verbatim.
8. Write `summary.json` via `atomic-write` with new status/headline/hash.
9. Emit `worktree-event summary-written --ticket <id>` to clear flags.

**Signal hash includes uncommitted diff hash.** Slightly more expensive (one `git diff | sha256` per tick), but captures in-progress work. Cost is negligible.

## Picker integration

Wrap existing tmux worktree picker. For each session, read `summary.json` + `conductor.json` (single-digit microseconds) and render:

```
PROJ-639  3d   BLOCKED          Waiting on sev4 color decision
PROJ-621  2h   ACTIVE           MCP OAuth stateless impl
PROJ-603  5d   WAITING_REVIEW   @alice's comments unaddressed
PROJ-673  1w   STALE            —
```

Columns: ticket, relative time since `meta.last_accessed`, status, headline.

Status visual badges (conductor columns suppressed unless active):
- `conductor-running` flag present → prepend `[AP]`
- `conductor-error` flag present → prepend `[!]`

## Keybinds (tmux)

Integrated into the existing zellij-style mode system (`C-S-w` enters `worktree-mode`):

| Key (in worktree-mode) | Action |
|---|---|
| `w` | Worktree picker (existing; will be extended with summary columns) |
| `c` | Create new worktree (existing) |
| `x` | Delete current worktree (existing) |
| `s` | **Show current worktree's summary (new)** — opens `context.md` in `less`, or a helpful fallback message if absent |

The `s` binding lives at `tmux.conf:201` and delegates to `~/.config/tmux/scripts/worktree-summary.sh`. The script:
1. Resolves current session name via `tmux display-message -p '#S'`
2. Globs `~/worktrees/*/.worktree-meta/sessions/<session>/context.md`
3. If found: opens in `less -R` with a prompt showing the summary's `updated` timestamp from `summary.json`
4. If absent: prints an explanation of why (summarizer hasn't run yet, no activity, etc.) and how to force regeneration via the `needs-summary-update-force` flag

No auto-popups — summary only appears when user explicitly presses `C-S-w` then `s`.

## Migration from current state

One-shot migrator `~/.config/conductor/bin/migrate-worktree-state` walks:

1. For each `~/worktrees/*/.worktree-meta/sessions/<ticket>.json`:
   - Create `<ticket>/` directory alongside
   - Move the JSON to `<ticket>/meta.json`, wrap with `schema_version`, rename fields if needed
2. For each `~/.config/conductor/markers/<ticket>.<type>` (`.state`, `.exit_code`, `.last_review_at`):
   - Match to a worktree by ticket prefix
   - Translate into fields of `conductor.json` (e.g., `.state` → `status`)
   - Touch equivalent flag files if applicable (`conductor-error` if last exit_code ≠ 0)
3. Leave old marker files in place for one week post-migration for rollback safety, then delete.

All callers updated to use `worktree-event` before the old markers dir is removed.

## Cost model (Sonnet)

Per summarizer call: ~2K input tokens (context.md + git log + Jira body + history tail) + ~500 output tokens. Rough Sonnet cost: ~$0.015/call.

Expected call rate with signal-hash gating: 3–10 actual LLM calls per active worktree per day. With 10 worktrees: ~30–100 calls/day = $0.50–$1.50/day. Acceptable.

If cost grows unexpectedly: fall back to Haiku for the "headline-only" update path, keep Sonnet for full rewrites triggered by `/pause-worktree` or `needs-summary-update-force`.

## Open questions

1. **Jira ticket body caching** — per-worktree cache file or a shared `~/.config/conductor/cache/jira/<ticket>.json`? Lean shared; saves redundant fetches across worktrees for the same epic/link.
2. **PR state source** — poll via `gh` every N minutes, or subscribe to GitHub webhooks (heavier setup, more accurate)? Start with polling in the scheduler.
3. **User-added notes flow** — should `/pause-worktree` accept an inline note (`/pause-worktree "blocked on infra team"`) that gets appended to context.md's User notes? Minor UX question.
4. **Multi-project support** — current design hardcodes `~/worktrees/myapp/`. Need to iterate `~/worktrees/*/` in the scheduler for multi-project. Should be a one-line change but worth making a config entry.
5. **Cleanup** — when does a `<ticket>/` directory get deleted? On `worktree-abandoned` event? On git branch deletion detected by a sweeper? Leaning: sweeper that runs daily and removes dirs whose branch no longer exists.

## Implementation phases

Phase 1 — Foundations
- `atomic-write`, `worktree-event`, event table
- Directory layout + migrator
- `/with-markers` refactor

Phase 2 — Summarizer
- `summarize-worktree` with signal-hash gate
- Stop hook + post-commit hook wired up

Phase 3 — Scheduler + Picker
- `summarize-dirty.sh` + Pass 2 wiring in `conductor-runner.sh`
- Picker wrapper with status columns
- Tmux keybinds

Phase 4 — Polish
- `/pause-worktree` slash command
- Multi-project support
- Cleanup sweeper
