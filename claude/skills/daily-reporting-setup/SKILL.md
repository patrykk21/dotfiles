---
name: daily-reporting-setup
description: >
  Use when setting up /eod (daily-reporting) for the first time, adding or removing
  projects from the EOD registry, rotating the Google Chat webhook, fixing a broken EOD
  configuration, or troubleshooting "my eod isn't working". Also use when the user says
  "set up eod", "configure eod", "add a project to eod", "register a new repo for daily
  reporting", or "test my eod channel".
user_invocable: true
argument-hint: "[--check audit-only | --add-project | --rotate-webhook | text specifics]"
---

# /daily-reporting-setup — Configure the /eod Skill

Interactive setup helper for the `daily-reporting` skill (`/eod`). Audits the current
configuration, fills in what's missing, validates that the Google Chat channel is
reachable, and manages the multi-project registry at `~/.claude/eod-projects.json`.

**Companion to:** `~/.claude/skills/daily-reporting/SKILL.md` — read that skill to
understand the runtime behavior this setup enables.

## Mode Detection

| Flag / phrase | Mode |
|---|---|
| `--check`, "audit my setup", "check my eod" | **Audit-only** — read state, report, propose fixes, make NO changes |
| `--add-project`, "add a project" | Jump to Step 4 (project registry) |
| `--rotate-webhook`, "new webhook", "change channel" | Jump to Step 3 (channel) |
| (no flag) | Full guided setup — run every step |

## Step 1 — Audit Current State

Gather the current state silently before reporting anything. The audit covers four
layers: **tooling** (binaries on PATH), **system config** (git config), **skills**
(runtime + setup both installed), and **EOD state** (tribe.env + registry).

### 1a. File + skill checks

```bash
[ -f ~/.claude/tribe.env ]          && echo "tribe.env: exists"          || echo "tribe.env: MISSING"
[ -f ~/.claude/eod-projects.json ]  && echo "eod-projects.json: exists"  || echo "eod-projects.json: MISSING"
[ -f ~/.claude/skills/daily-reporting/SKILL.md ]  && echo "runtime skill: exists"      || echo "runtime skill: MISSING"
[ -f ~/.claude/skills/daily-reporting/aggregator.py ] && echo "ai aggregator: exists"  || echo "ai aggregator: MISSING"
[ -x ~/.claude/hooks/eod-reminder.sh ] && echo "reminder hook: installed" || echo "reminder hook: absent"
```

### 1b. Tooling prerequisites

```bash
command -v git     >/dev/null 2>&1 && echo "git: ok"     || echo "git: MISSING"
command -v gh      >/dev/null 2>&1 && echo "gh: ok"      || echo "gh: MISSING"
command -v curl    >/dev/null 2>&1 && echo "curl: ok"    || echo "curl: MISSING"
command -v python3 >/dev/null 2>&1 && echo "python3: ok" || echo "python3: MISSING"
```

### 1c. git + gh config

```bash
git config --global user.name  >/dev/null 2>&1 && echo "git.user.name: set"  || echo "git.user.name: missing"
git config --global user.email >/dev/null 2>&1 && echo "git.user.email: set" || echo "git.user.email: missing"
gh auth status 2>&1 | grep -q "Logged in" && echo "gh auth: authenticated" || echo "gh auth: not-authenticated"
```

### 1d. tribe.env keys + registry validation

If `tribe.env` exists, source it in a subshell and check which keys are present —
**never echo secret values back to the user**, only report "set" / "missing":

```bash
( set -a; source ~/.claude/tribe.env 2>/dev/null; set +a
  for k in ENGINEER_NAME ENGINEER_TEAM GCHAT_WEBHOOK_URL EOD_SPACE_ID; do
    if [ -n "${!k}" ]; then echo "$k: set"; else echo "$k: missing"; fi
  done )
```

If `eod-projects.json` exists, parse it and for each project verify the `path` still
exists and contains a `.git` directory:

```bash
python3 -c "
import json, pathlib
reg = json.load(open(pathlib.Path.home()/'.claude/eod-projects.json'))
for p in reg.get('projects', []):
    path = pathlib.Path(p['path']).expanduser()
    git_ok = (path/'.git').is_dir()
    print(f\"  {p['id']:25} enabled={p.get('enabled',True)}  path={'ok' if path.exists() else 'MISSING'}  git={'ok' if git_ok else 'no'}\")
"
```

### 1e. Audit report

Present a compact audit report with four sections:

```
📋 Current /eod setup

Tooling (required for /eod to function):
  ✓ git             (required — reads commit history)
  ✓ curl            (required — posts to webhook)
  ✓ python3         (required — JSON handling + safe upsert writes)
  ✓ gh CLI          (recommended — enriches PR state)

System config:
  ✓ git user.name       set  (used to filter /eod to your own commits)
  ✗ git user.email      missing
  ✓ gh authenticated    at least one hostname

Skills:
  ✓ daily-reporting runtime installed
  ✓ daily-reporting-setup installed (that's us!)
  ✗ eod-reminder.sh hook absent (optional — nudges at session end)

Identity (~/.claude/tribe.env):
  ✓ ENGINEER_NAME       set
  ✗ ENGINEER_TEAM       missing
  ✓ GCHAT_WEBHOOK_URL   set

Projects (~/.claude/eod-projects.json): 5 entries, 4 enabled
  ✓ monorepo            path=ok  git=ok
  ✓ gsc-analytics       path=ok  git=ok
  ✗ personalized-helper path=MISSING  git=no

Fixes needed:
  Tooling:  Install gh CLI (brew install gh) for PR enrichment
  Config:   Set git user.email
  Identity: Set ENGINEER_TEAM in tribe.env (Step 2)
  Projects: personalized-helper path no longer exists (Step 4 edit)
  Optional: Install eod-reminder.sh hook (Step 5c)
```

**In `--check` mode:** stop here. List the fixes and exit without modifying anything.

**Otherwise:** ask "Walk through the fixes? (y/n)" and proceed. **Run Step 1b first**
(prerequisites) before going to Step 2 — identity setup depends on `git config user.name`.

## Step 1b — Prerequisites & Tooling Fixes

Only run this step if Step 1 detected any of: missing binaries, missing git config, or
missing runtime skill. Skip entirely if every `1a`/`1b`/`1c` check passed.

This step is a setup skill's job: we **help the engineer fix what we can** rather than
just warning. For each gap, classify as **BLOCKER** (can't proceed), **FIXABLE** (we can
run the fix), or **OPTIONAL** (warn + continue).

### FIXABLE — Runtime skill or AI aggregator missing

If **either** `~/.claude/skills/daily-reporting/SKILL.md` or
`~/.claude/skills/daily-reporting/aggregator.py` is missing, install both immediately
**without prompting**. These two files together make up the runtime skill — the markdown
drives the flow, the aggregator produces the deterministic AI-usage JSON the message reads
from. Installing one without the other leaves `/eod` broken.

This is the setup skill's core job — it is the only supported way to install the runtime,
so asking for confirmation is redundant. Announce the action to the engineer:

```
Installing the daily-reporting runtime skill + AI usage aggregator from the bundled refs...
```

Run the following Python helper. It copies two files:

1. **`daily-reporting-template.md` → `skills/daily-reporting/SKILL.md`**, stripping the
   leading HTML comment bootstrap block so the file starts cleanly with `---` frontmatter
2. **`ai-usage-aggregator.py` → `skills/daily-reporting/aggregator.py`**, chmod +x so
   `/eod` can invoke it directly

```bash
python3 <<'PY'
import pathlib, re, shutil, os

refs = pathlib.Path.home()/'.claude/skills/daily-reporting-setup/references'
dst_dir = pathlib.Path.home()/'.claude/skills/daily-reporting'
dst_dir.mkdir(parents=True, exist_ok=True)

# --- 1. Runtime skill markdown ---------------------------------------------
tpl = refs/'daily-reporting-template.md'
if not tpl.exists():
    raise SystemExit(f"Bootstrap template missing at {tpl} — distribution is broken")

content = tpl.read_text()
# Strip leading <!-- ... --> HTML comment block. Everything from the first
# `---` onwards is the actual skill content (the YAML frontmatter).
m = re.search(r'^---', content, re.MULTILINE)
if not m:
    raise SystemExit("Template does not contain YAML frontmatter — invalid template")
skill_content = content[m.start():]

skill_dst = dst_dir/'SKILL.md'
skill_dst.write_text(skill_content)

parsed = skill_dst.read_text()
if not parsed.startswith('---\n'):
    raise SystemExit("Written SKILL.md does not start with frontmatter — write failed")
assert 'name: daily-reporting' in parsed.split('---', 2)[1], "name field missing"
print(f"Wrote {skill_dst} ({len(parsed.splitlines())} lines)")

# --- 2. AI usage aggregator ------------------------------------------------
agg_src = refs/'ai-usage-aggregator.py'
if not agg_src.exists():
    raise SystemExit(f"Aggregator missing at {agg_src} — distribution is broken")

agg_dst = dst_dir/'aggregator.py'
shutil.copy2(agg_src, agg_dst)
os.chmod(agg_dst, 0o755)
print(f"Wrote {agg_dst} ({agg_dst.stat().st_size} bytes, chmod 0755)")
PY
```

After creation, verify both files are present and the aggregator runs cleanly:

```bash
[ -f ~/.claude/skills/daily-reporting/SKILL.md ]      && echo "runtime skill: ok"   || echo "runtime skill: STILL MISSING"
[ -x ~/.claude/skills/daily-reporting/aggregator.py ] && echo "ai aggregator: ok"   || echo "ai aggregator: STILL MISSING"
python3 ~/.claude/skills/daily-reporting/aggregator.py --date "$(date +%Y-%m-%d)" --stdout \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('aggregator self-test:', d['_aggregator_version'])"
```

Then continue to the next check. Confirm to the engineer: "✅ Created daily-reporting
skill + AI usage aggregator at ~/.claude/skills/daily-reporting/. Run `/reload-plugins`
(or restart Claude Code) to make `/eod` available."

### BLOCKER — git / curl / python3 missing

These are hard requirements. Stop and give install instructions:

```
❌ git / curl / python3 is not installed. /eod cannot function without it.

   macOS: xcode-select --install    (installs git + curl)
          brew install python3
   Linux: apt install git curl python3   (or your distro equivalent)

   Install the missing tool(s), then re-run /daily-reporting-setup.
```

### FIXABLE — git config user.name missing

`git log --author=` in the runtime skill uses this value. If it's missing, `/eod` will
fail to filter to the current engineer's commits.

```
⚠️ `git config --global user.name` is not set. /eod uses this to filter commits to you.
```

Offer to fix it. Two paths:
- **Already ran Step 2 (identity)?** Use the `ENGINEER_NAME` value from `tribe.env` as
  the default. Ask: "Set git user.name to `<ENGINEER_NAME>`? (y/n or enter a different name)"
- **Haven't run Step 2 yet?** Prompt for a name directly.

Then run:
```bash
git config --global user.name "<name>"
```

Same pattern for `git config --global user.email` if missing — prompt with a default
(from whatever email can be inferred) or ask.

### FIXABLE — gh not authenticated

If `gh` is installed but `gh auth status` shows no hostname:

```
⚠️ gh CLI is installed but not authenticated. /eod will still post EODs, but PR links
   in the message won't be enriched (no "PR #N merged/in review" labels).

   Want me to run `gh auth login` now?
     [1] Yes, log in to github.com       (for public repos / github.com work)
     [2] Yes, log in to a custom host     (e.g. GitHub Enterprise — I'll ask for the hostname)
     [3] No, skip                          (continue without PR enrichment)
```

For options 1/2, run `gh auth login` (or `gh auth login --hostname <host>`) interactively.
The engineer completes the browser flow. After it returns, verify with `gh auth status`
and continue.

### OPTIONAL — gh CLI missing entirely

If `gh` is not on PATH at all:

```
ℹ️ gh CLI is not installed. /eod will still work without it — PR enrichment just gets
   skipped silently. Not a blocker.

   If you want PR links (recommended):
     macOS: brew install gh
     Linux: https://github.com/cli/cli/blob/trunk/docs/install_linux.md

   Continue without gh? (y = proceed to Step 2, n = install gh first)
```

Default to `y` — this is a soft warning, not a stop.

### OPTIONAL — Reminder hook absent

Note that `~/.claude/hooks/eod-reminder.sh` is absent but defer the actual install to
**Step 5c** (after identity, channel, and registry are in place). Mention it here so
the engineer knows it's coming.

### After Step 1b

Re-run the `1b` tooling checks silently. If every BLOCKER is resolved, continue to
Step 2. If a BLOCKER is still outstanding (e.g. engineer didn't install git), stop.

## Step 2 — Engineer Identity

Only run if `ENGINEER_NAME` or `ENGINEER_TEAM` is missing.

Prompt with sensible defaults:

```
Engineer identity (used in the EOD message header):
  Name  [Alex Korinek]:      ← default from `git config user.name`
  Team  []:                  ← no default, required
```

Write via safe upsert (avoids duplicate lines, quotes the value):

```bash
python3 <<'PY'
import pathlib, shlex
p = pathlib.Path.home()/'.claude/tribe.env'
p.touch(mode=0o600, exist_ok=True)
existing = dict(
    line.split('=', 1) for line in p.read_text().splitlines()
    if '=' in line and not line.startswith('#')
)
# Update in-place (values come from prompts above)
existing['ENGINEER_NAME'] = shlex.quote(NEW_NAME)
existing['ENGINEER_TEAM'] = shlex.quote(NEW_TEAM)
p.write_text('\n'.join(f'{k}={v}' for k, v in existing.items()) + '\n')
p.chmod(0o600)
PY
```

Confirm: "Identity updated in `~/.claude/tribe.env`."

## Step 3 — Google Chat Channel

Only run if `GCHAT_WEBHOOK_URL` and `EOD_SPACE_ID` are both missing, OR if invoked with
`--rotate-webhook`.

Ask which method the user prefers:

1. **Incoming Webhook URL** (recommended — simplest, works from any environment)
2. **Space ID + Google Chat MCP** (only if the MCP is already configured)

For webhook, walk the user through creation:

```
To create a Google Chat webhook:
  1. Open the Google Chat space where EOD should be posted
  2. Click the space name → "Apps & integrations" → "Webhooks"
  3. Click "Add Webhook", name it "Claude EOD" (optional avatar)
  4. Copy the webhook URL. It looks like:
     https://chat.googleapis.com/v1/spaces/AAAA.../messages?key=...&token=...

Paste the webhook URL below (stored locally in ~/.claude/tribe.env, never transmitted):
```

**Validate with a test post before persisting:**

```bash
curl -sS -X POST "$WEBHOOK" \
  -H "Content-Type: application/json" \
  -d '{"text":"✅ Claude /eod setup test — this message confirms the webhook works. Safe to delete."}'
```

If the response JSON contains a `"name"` field starting with `"spaces/"`, the post
succeeded. Otherwise show the error body and let the user paste a corrected URL. Loop
until it works or the user cancels.

**Only after success**, persist via the same `python3` upsert helper from Step 2 with
key `GCHAT_WEBHOOK_URL`. When confirming, show only the first 40 chars of the URL
followed by `...` — never echo the full token.

## Step 4 — Project Registry

### Case A — Registry doesn't exist (first-time setup)

Ask where the user's repos live (default `~/Programming`). Discover git repos:

```bash
find "${PARENT/#\~/$HOME}" -maxdepth 2 -type d -name .git 2>/dev/null \
  | sed 's|/\.git$||' | sort
```

Present as a checklist (pre-check ones that already have Claude memory dirs at
`~/.claude/projects/-Users-...`):

```
Found 8 git repos in ~/Programming:
  [x] groupon-monorepo       ← has Claude memory dir
  [x] gsc-analytics          ← has Claude memory dir
  [x] firmeet2               ← has Claude memory dir
  [x] market-researcher      ← has Claude memory dir
  [ ] ai-scheduler
  [ ] db_dump
  [ ] next-pwa-app
  [ ] seo-pulse

Which should be eligible for /eod reporting? (y to accept the defaults, or list ids)
```

For each selected repo, derive and collect:
- `id` — kebab-case slug of the directory name
- `label` — Title Case of the directory name (confirm with user, editable)
- `path` — absolute path to the repo
- `team` — `null` (inherits global `ENGINEER_TEAM` from `tribe.env`)
- `jira_prefix` — ask "Jira key prefix for $label (e.g. `MBNXT`, optional, blank to skip):"
- `enabled` — `true`

Write `~/.claude/eod-projects.json` preserving the `_docs` schema block so the file
stays self-documenting. Use `json.dump(..., indent=2)`.

### Case B — Registry exists (modify)

Offer sub-actions and make **minimal edits** — never rewrite the whole file unless
the user asks to start over:

| Action | How |
|---|---|
| Add a project | Append one entry, preserve everything else. **Always prompt for `jira_prefix`** (see below). |
| Remove a project | Prefer `enabled: false` over deletion (keeps history) |
| Edit a project | Update only the changed fields for that one entry |
| Re-scan | Look for git repos under the parent dir not yet in the registry; offer to add (same prompt flow as "Add a project") |
| Fix broken path | When Step 1 flagged a missing path, prompt for new path or disable |

**When adding a project**, always prompt the user for a Jira prefix so it is recorded
at registry-write time and the user doesn't have to edit the JSON by hand later:

```
Jira key prefix for <label> (e.g. MBNXT, MCE, GRO) — press Enter to leave empty:
```

Accept the response as follows:
- **Empty input / just Enter** → write `"jira_prefix": null` (the default; EOD skill will
  skip per-project Jira hour attribution for this project)
- **A single uppercase-letters + optional digits token** (e.g. `MBNXT`, `ENC`, `GRO`,
  `LEGACYWEB2`) matching `^[A-Z][A-Z0-9]{1,9}$` → write that literal value
- **Anything else** → show "doesn't look like a Jira key prefix" and reprompt once; on
  second invalid response accept it as-is with a warning
- **Word "skip" or "none"** → treat as empty

Same prompt is used during the initial checklist-driven first-time setup in Case A
(so the question "what's the Jira prefix?" is always asked at project-add time, never
deferred to a later `--check` run).

After any modification, re-validate with `python3 -c "import json; json.load(open(...))"`
and show a one-line diff (e.g. "Added project `next-pwa-app` (jira=SEOP). 5 → 6 enabled projects.").

## Step 5 — Validate & Test Post

Silently re-run the Step 1 audit. Every previously-failing item should now pass.

If anything still fails, loop back to the relevant step. Do not proceed while broken.

### 5a. Preview the EOD message format

Show the engineer what their daily EODs will look like once they start posting. This gives
them a concrete mental model for the `daily-reporting` skill's output — a rich, AI-focused
format with distinct sections for Shipped work, In Progress, AI Workflow showcase, and
Blockers.

Print this preview using the engineer's actual name/team (from tribe.env) and placeholder
ticket data. **Preserve the exact formatting** — Google Chat native markdown (`*bold*`,
`_italic_`), horizontal rules (`━`), and emoji per AI activity category:

```
Here's what your future EODs will look like when you run /eod:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📅 *EOD · [engineer name] · [team]*
_[today's weekday, month date]_
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ *Shipped (2)*
• *EXAMPLE-123* — Fix deal page BreadcrumbList schema
  → PR #2789 ✓ _merged_
• *EXAMPLE-124* — Add canonical tag validation
  → PR #2792 · _in review_

🔄 *In progress (1)*
• *EXAMPLE-125* — Core Web Vitals regression on /deals
  _60% · reproduced locally, profiling in progress_

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🤖 *AI workflow today*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• 💬 *2 Claude Code sessions*
• 📝 *3 plans written* · 📐 *1 design doc*
• 🎭 *6 agents dispatched* — Explore × 3, Plan × 2, code-reviewer × 1
• 🔌 *18 MCP calls* — atlassian × 12, github × 5, posthog × 1
• 🛠️ *295 tool calls · 27 files edited* — Bash 54, Edit 20, Read 14
• 👀 *1 PR review* via /pr-review
• 💾 *2 memory updates*

_Skills used today: /pick-task /dev-start /pr-create /pr-review /log-tempo_

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚧 *Blockers*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
None

↑ This is the format your real EODs will use. The AI workflow section
  showcases what Claude Code skills you actually leveraged today — your EM
  can see exactly which parts of the workflow you're using.
```

After showing the preview, note to the engineer:
- The format automatically **omits bullets with zero value** — e.g. if you didn't generate
  tests, the 🧪 line is skipped entirely
- It supports **multi-project** layouts when you pick more than one project in `/eod`
- If you use other AI tools (Cursor, Copilot, etc.), Claude will ask you during the post
  flow and add a `🧠 Also:` line under the AI section

### 5b. Offer a real dry-run of `/eod`

Then offer a dry-run:

```
Want to also run a real /eod right now with today's actual git activity?
  • Gather today's commits from each enabled project
  • Format using the structure above (with your real data)
  • Ask for approval BEFORE posting (nothing auto-posts)

(y/n)
```

If yes, invoke the `daily-reporting` skill in interactive mode. Do not pass `--auto` —
the user should see the full flow at least once.

### 5c. Optional — install the EOD reminder hook

Only run if Step 1 detected `~/.claude/hooks/eod-reminder.sh` as absent. Skip if
already installed.

Offer to install it:

```
Last thing — install the EOD reminder hook? It's an optional Stop hook that fires at
session end and nudges you if /eod hasn't been run today.

  • Writes ~/.claude/hooks/eod-reminder.sh (chmod +x)
  • Adds one entry to ~/.claude/settings.json hooks.Stop array
  • Checks for the flag file ~/.claude/eod-YYYY-MM-DD
  • Stays silent if /eod was already run today

Install it? (y/n)
```

If **yes**:

1. Write the hook script:
```bash
mkdir -p ~/.claude/hooks
cat > ~/.claude/hooks/eod-reminder.sh <<'HOOK'
#!/usr/bin/env bash
# EOD Reminder — fires at session end, stays silent if /eod was already run today
# /eod writes a flag file (~/.claude/eod-YYYY-MM-DD) when it posts successfully.
today=$(date +%Y-%m-%d)
flag="$HOME/.claude/eod-${today}"
if [ ! -f "$flag" ]; then
  echo "📋 EOD REMINDER: You haven't posted your EOD today (${today})."
  echo "   Run /eod to send your update."
fi
exit 0
HOOK
chmod +x ~/.claude/hooks/eod-reminder.sh
```

2. Merge the hook entry into `~/.claude/settings.json` under `hooks.Stop`. **Never clobber
the whole file** — use a safe JSON merge that preserves any existing hooks:

```bash
python3 <<'PY'
import json, pathlib
p = pathlib.Path.home()/'.claude/settings.json'
cfg = json.loads(p.read_text()) if p.exists() else {}
hooks = cfg.setdefault('hooks', {})
stop = hooks.setdefault('Stop', [])
new_cmd = "bash ~/.claude/hooks/eod-reminder.sh"

# Check if an entry with the same command already exists — idempotent
exists = any(
    any(h.get('command') == new_cmd for h in entry.get('hooks', []))
    for entry in stop
)
if not exists:
    stop.append({
        "hooks": [{"type": "command", "command": new_cmd, "timeout": 5}]
    })
    p.write_text(json.dumps(cfg, indent=2) + '\n')
    print("Added eod-reminder hook to settings.json")
else:
    print("eod-reminder hook already present — no change")
PY
```

3. Validate the resulting `settings.json` is syntactically correct:
```bash
python3 -c "import json; json.load(open('$HOME/.claude/settings.json')); print('settings.json valid')"
```

4. Confirm: "✅ eod-reminder.sh installed. It will fire at session end and nudge you if
you haven't run `/eod` today."

If **no**: skip silently and continue to Step 6. The engineer can re-run
`/daily-reporting-setup` later to install it.

## Step 6 — Summary

Print a terminal-friendly summary of what's configured and how to use it:

```
✅ /eod is configured.

  Identity:  Alex Korinek — Search Tribe
  Channel:   Google Chat webhook (https://chat.googleapis.com/v1/spaces/AAAA...)
  Projects:  4 enabled — monorepo, gsc-analytics, firmeet2, market-researcher
  Message:   Rich format with Shipped / In progress / AI workflow / Blockers
             sections, Google Chat markdown, and per-skill AI breakdown

Files touched:
  ~/.claude/tribe.env          (0600)
  ~/.claude/eod-projects.json

Daily use:
  /eod                             → interactive project selection
  /eod --all                       → include every enabled project
  /eod --project monorepo,gsc      → specific projects
  /eod --auto                      → unattended mode (for ai-scheduler)

Modify later:
  /daily-reporting-setup --check              → audit only
  /daily-reporting-setup --add-project        → register a new repo
  /daily-reporting-setup --rotate-webhook     → update channel
```

## Security Notes

- `tribe.env` contains secrets. Always `chmod 600`. Never commit it.
- Never echo full webhook URLs or tokens back to the user. Show only the first ~40 chars
  + `...` when confirming.
- The project registry (`eod-projects.json`) has **no** secrets — only paths, labels, and
  references. Safe to include in dotfiles repos.
- When showing env var status, report only "set" / "missing" — never the value.

## Common Issues

| Symptom | Cause | Fix |
|---|---|---|
| `/eod` says "no projects selected" | `eod-projects.json` missing or all entries `enabled=false` | Step 4 |
| Test post returns 404 | Webhook URL wrong or space was deleted | Step 3 — recreate webhook |
| Test post returns 401 / 403 | Token revoked or permissions changed | Step 3 — recreate in same space |
| Test post returns 200 but no message in chat | Posted to wrong space | Step 3 — verify which space owns the webhook |
| EOD posts but skips a project | Project `path` in registry doesn't exist | Step 4 — fix or disable that entry |
| EOD shows wrong engineer name | `ENGINEER_NAME` unset, falling back to `git config user.name` | Step 2 |
| `tribe.env` edits vanish next run | Duplicate lines / wrong quoting | Use the Step 2 python upsert, never `echo >>` |

## Common Mistakes (when running this skill)

- **Writing to `tribe.env` with `echo "X=Y" >> tribe.env`** — creates duplicates every
  run. Always use the python upsert helper that reads existing keys first.
- **Persisting the webhook before validating it** — leaves a broken URL in the file if
  the user mistyped. Test post first, write second.
- **Overwriting `eod-projects.json` wholesale on edits** — loses the `_docs` block and
  any hand-edited labels. Always load → mutate → dump.
- **Echoing secret values during confirmation** — truncate to first 40 chars + `...`.
- **Running Step 4 interactively during `--auto` invocation** — the setup skill should
  refuse to run in non-interactive mode. Detect with `[ -t 0 ]` and abort with a clear
  message if stdin is not a TTY.
- **Assuming `~/Programming` as the parent dir** — always ask, with that as the default.
