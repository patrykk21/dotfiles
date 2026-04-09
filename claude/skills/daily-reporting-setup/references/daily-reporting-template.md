<!--
BOOTSTRAP TEMPLATE FOR daily-reporting SKILL
============================================

This file is the canonical bootstrap content for the sibling `daily-reporting`
runtime skill. If a machine has `daily-reporting-setup` installed but is missing
the runtime skill at ~/.claude/skills/daily-reporting/SKILL.md, Step 1b of the
setup skill copies everything below the HTML comment block into that location.

KEEP IN SYNC with ~/.claude/skills/daily-reporting/SKILL.md. When the runtime
skill is updated, update this template file too. The setup skill NEVER overwrites
an existing runtime skill — the template is used only for first-time creation.

This comment block is stripped out during the copy in Step 1b (everything from
<!-- through --> is removed, and the resulting file starts with the YAML
frontmatter `---`).
-->

---
name: daily-reporting
description: >
  Post a team-aware end-of-day update. Reads today's git activity (commits, PRs) and
  session context across one or more registered projects, formats a single combined
  EOD message, shows it for approval, and posts to the configured team channel. Tracks
  posting via flag files so reminder hooks know it's done. Triggers for /eod, "post my
  EOD", "end of day", "daily update", "send my standup".
user_invocable: true
argument-hint: "[--project id,id | --all | text context] [--auto for unattended mode]"
---

# /eod — Daily Reporting

Post your end-of-day update to B2C Daily in Google Chat. Aggregates activity across one
or more projects registered in `~/.claude/eod-projects.json` into a single combined message.

## Mode Detection

If the argument contains `--auto` or if running non-interactively (e.g., spawned by the
ai-scheduler daemon — check if stdin is not a TTY), switch to **autonomous mode**:
- Skip all user prompts (Steps 2, 3 confirmation, Step 5 confirmation)
- Infer everything from git activity and scheduler run data
- Post directly without asking for approval
- If GCHAT_WEBHOOK_URL env var is set, use it to post via curl (see Step 6)

Otherwise, run in **interactive mode** (the default) — ask for input and confirmation.

## Step 0 — Load Project Registry & Select Projects

Read `~/.claude/eod-projects.json`. If it doesn't exist, fall back to **single-repo mode**:
treat the current working directory as the only project and skip to Step 1 using cwd.

If it exists, parse the `projects` array and determine which projects to include:

**Selection rules:**
1. **`--project id1,id2,...`** → use exactly those project IDs (fail loudly if an id isn't found).
2. **`--all`** → use every project where `enabled=true`.
3. **cwd matches a registered `path`** (exact or prefix match) → default-select just that one.
4. **Otherwise** → scan all enabled projects for today's git activity, then:
   - **Interactive mode:** show the list with activity counts, default-select projects with
     any activity, ask the user to confirm or edit. Example prompt:
     ```
     Projects with activity today:
       [x] monorepo       — 4 commits, 1 open PR
       [x] gsc-analytics  — 2 commits
       [ ] firmeet2       — no activity
       [ ] market-researcher — no activity
       [ ] personalized-helper — no activity

     Include these in today's EOD? (y to accept, or list IDs to override)
     ```
   - **Autonomous mode (`--auto`):** include every enabled project with activity today,
     skip those with none. If nothing has activity, still post an EOD but note it.

Store the resulting list as `$SELECTED_PROJECTS` (array of project objects from the registry).
Everything from Step 1 onward iterates over `$SELECTED_PROJECTS`.

## Step 1 — Gather Context (per project)

For each project in `$SELECTED_PROJECTS`, `cd "$project.path"` and collect today's activity:

```bash
# Today's commits in this project
git log --oneline --since="today 00:00" --author="$(git config user.name)" 2>/dev/null
```

```bash
# Open PRs by this user in this project
gh pr list --author="@me" --state=open 2>/dev/null | head -10
```

```bash
# PRs merged today in this project
gh pr list --author="@me" --state=merged --search="merged:$(date +%Y-%m-%d)" 2>/dev/null | head -10
```

Keep results grouped by project id — do not flatten them yet. You'll need per-project data
for the formatted message in Step 5.

Also consider the current Claude session context — what was discussed, what was built, what was
planned — and attribute it to whichever project's path the session is running in (match cwd
against registered paths).

## Step 2 — Ask for Input

If the user provided context in their invocation (e.g., `/eod worked on MBNXT-1234 auth fix`),
use that. Otherwise ask:

```
Quick EOD — two things:
  1. What tickets did you work on today? (include IDs if you remember, e.g. MBNXT-1234)
  2. Any blockers? (people, decisions, or unknowns slowing you down — or "none")
```

If the session already contains clear context (e.g. /pick-task was run), pre-fill what you
know and ask the engineer to confirm or add to it. Don't make them repeat themselves.

If the user says "you figure it out" or similar, infer from git activity and session context.

## Step 3 — Run the AI Usage Aggregator

**Do NOT parse transcripts by hand.** The runtime skill ships with a deterministic Python
aggregator at `~/.claude/skills/daily-reporting/aggregator.py` that reads every Claude
Code session transcript under `~/.claude/projects/-*/*.jsonl` for today and writes a
structured JSON summary. Every engineer gets the same numbers for the same activity.

Run it first:

```bash
python3 ~/.claude/skills/daily-reporting/aggregator.py \
  --date "$(date +%Y-%m-%d)" \
  --registry ~/.claude/eod-projects.json
```

Then read the output JSON:

```bash
AI_JSON="$HOME/.claude/daily-reporting/ai-usage/$(date +%Y-%m-%d).json"
cat "$AI_JSON"
```

The JSON has two sections: `projects` (per-project stats, keyed by registered project id;
sessions that ran outside a registered path get bucketed as `_unregistered:<dirname>`) and
`totals` (aggregated across every project).

**The ONLY fields the EOD message uses are under `totals`:**

| JSON field | Message bullet |
|---|---|
| `totals.sessions` + `totals.unique_projects` | `💬 X Claude Code sessions` (+ "across N projects" in the multi-project header) |
| `totals.plans_written` | `📝 X plans written` |
| `totals.specs_written` | `📐 X design docs` |
| `totals.agents_dispatched` | `🎭 X agents dispatched — sub × N, sub × M, …` |
| `totals.mcp_calls_total` + `totals.mcp_servers` | `🔌 X MCP calls — server × N, …` |
| `totals.total_tool_calls` + `totals.total_files_edited` + top 3 of `totals.tool_calls` | `🛠️ X tool calls · Y files edited — Bash N, Edit N, Read N` |
| `totals.skills_invoked["pr-review"]` | `👀 X PR review(s) via /pr-review` |
| `totals.skills_invoked["simplify"]` | `🔧 X refactor(s) via /simplify` |
| `totals.memory_updates` | `💾 X memory updates` |
| `totals.skills_invoked` keys | `_Skills used today: /k1 /k2 /k3 …_` footer |

**Omit any bullet whose count is 0.** If `totals.sessions == 0` (engineer didn't use Claude
today), skip the entire AI workflow section — this is rare and worth investigating before
skipping. If `len(totals.skills_invoked) < 2`, omit the "Skills used today" footer.

Propose the summary to the engineer. Keep the same visual layout as Step 5 so the preview
is identical to the final message minus the header/blockers wrapping:

```
Here's what the aggregator tracked from today's Claude Code activity:

  💬 Claude Code sessions: X   (across [N] projects)
  📝 Plans written:        X
  📐 Design docs:          X
  🎭 Agents dispatched:    X   (Explore × 3, code-reviewer × 2, ...)
  🔌 MCP calls:            X   (atlassian × 12, github × 5, ...)
  🛠️ Tool calls:           X   (Y files edited · Bash N, Edit N, Read N)
  👀 PR reviews:           X   via /pr-review
  🔧 Refactors:            X   via /simplify
  💾 Memory updates:       X
  🧰 Skills invoked:       /s1 /s2 /s3 ...

Does that look right? Any AI work outside this Claude session (Cursor, Copilot, manual
tools) to add?
```

If the engineer mentions other AI tools (Cursor, Copilot, etc.) during confirmation,
capture that as free-text and include it as a final line under the AI section in Step 5
(e.g. "🧠 Also: ~2h in Cursor on the refactor").

**If the aggregator fails** (missing Python, permission error, etc.) report the error to
the engineer and skip the AI workflow section for today. Do NOT fall back to manual
transcript parsing — the aggregator is the single source of truth.

## Step 4 — Load Config

Read engineer name and channel config:
```bash
source ~/.claude/tribe.env 2>/dev/null
echo "ENGINEER_NAME=${ENGINEER_NAME:-$(git config user.name)}"
echo "ENGINEER_TEAM=${ENGINEER_TEAM:-not configured}"
echo "EOD_SPACE_ID=${EOD_SPACE_ID:-not configured}"
```

If `ENGINEER_NAME` is not set, fall back to `git config user.name`.
If `ENGINEER_TEAM` is not set, ask the engineer for their team name.

## Step 5 — Format the Message

The message is always a **single combined post**, regardless of how many projects are selected.
It uses Google Chat's native markdown: `*bold*` and `_italic_`. Horizontal rules (`━`) create
strong visual sections between the header, AI workflow, and blockers — they are NOT used
between individual ticket entries.

The AI workflow section is the most prominent part of the message — it should showcase what
AI enabled today, including the specific skills invoked.

Layout depends on how many projects are in `$SELECTED_PROJECTS`:

### Case A — Single project selected

Use the flat structure (no per-project headers):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📅 *EOD · [Name] · [Team]*
_[Weekday, Month Date]_
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ *Shipped ([N])*
• *[TICKET-ID]* — [what was done, specific, one line]
  → PR #[num] ✓ _merged_
• *[TICKET-ID]* — [what was done]
  → PR #[num] · _in review_

🔄 *In progress ([N])*
• *[TICKET-ID]* — [what the ticket is about]
  _[N]% · [current step / what's next]_

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🤖 *AI workflow today*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• 💬 *[X] Claude Code sessions*
• 📝 *[X] plans written* · 📐 *[Y] design docs*
• 🎭 *[X] agents dispatched* — [Explore × 3, code-reviewer × 2, Plan × 1]
• 🔌 *[X] MCP calls* — [atlassian × 12, github × 5, ...]
• 🛠️ *[X] tool calls · [Y] files edited* — [Bash N, Edit N, Read N]
• 👀 *[X] PR review(s)* via /pr-review
• 🔧 *[X] refactor(s)* via /simplify
• 💾 *[X] memory updates*
• 🧠 Also: [free-text — other AI tools the engineer mentioned, e.g. "~2h in Cursor"]

_Skills used today: /skill1 /skill2 /skill3 ..._

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚧 *Blockers*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[describe the blocker and who/what can unblock it — or "None"]
```

### Case B — Multiple projects selected

Use per-project subsections under a single header. The AI workflow section is aggregated
across all selected projects. Blockers are listed at the bottom, tagged with project label:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📅 *EOD · [Name] · [Team]*
_[Weekday, Month Date]_
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[emoji] *[Project 1 label]*
✅ Shipped
• *[TICKET-ID]* — [what] → PR #[num] · _[state]_
• *[TICKET-ID]* — [what] → PR #[num] · _[state]_
🔄 In progress
• *[TICKET-ID]* — [what] · _[N]% · [status]_

[emoji] *[Project 2 label]*
✅ Shipped
• [same pattern as above]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🤖 *AI workflow today* _(across [N] projects)_
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• 💬 *[X] Claude Code sessions*
• 📝 *[X] plans written* · 📐 *[Y] design docs*
• 🎭 *[X] agents dispatched* — [Explore × 3, code-reviewer × 2, Plan × 1]
• 🔌 *[X] MCP calls* — [atlassian × 12, github × 5, ...]
• 🛠️ *[X] tool calls · [Y] files edited* — [Bash N, Edit N, Read N]
• 👀 *[X] PR review(s)* via /pr-review
• 🔧 *[X] refactor(s)* via /simplify
• 💾 *[X] memory updates*
• 🧠 Also: [free-text]

_Skills used today: /skill1 /skill2 /skill3 ..._

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚧 *Blockers*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[Project 1]: [blocker] — or "None"
[Project 2]: [blocker]
```

**Project emoji in Case B** — pick based on the project's nature, consistently across days:
📦 monorepo · 📊 analytics · 🔍 research · 🤖 AI/ML · 🔧 tooling · 🎨 frontend · 🗄️ backend ·
📱 mobile · 🌐 web · 🧪 experiments. An EM scanning the channel should be able to recognise
the same project by its emoji week-over-week.

**Formatting rules (both cases):**
- Use `*bold*` for ticket IDs, counts in section headers, AI category labels, and project names
- Use `_italic_` for dates, PR states (`_merged_`, `_in review_`, `_draft_`), WIP status
  details, and the "Skills used today" footer
- Use `→` for "produces / results in" relationships (ticket → PR)
- Use `·` as an intra-line separator for inline metadata (state, percentage, status)
- Horizontal rules (`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`) wrap ONLY the Header, AI workflow,
  and Blockers sections — never between individual ticket entries
- **Omit any AI workflow bullet that has zero value** (e.g. no tests generated → no 🧪 line).
  Don't show "Tests generated: 0".
- **Omit the "Skills used today" footer** if fewer than 2 distinct skills were invoked
- **Omit the entire AI workflow section** if nothing was tracked at all (shouldn't happen if
  the engineer used Claude today — investigate before deciding to omit)
- **Omit the 🧠 "Also" line** unless the engineer explicitly mentioned non-Claude AI usage
  during the Step 3 confirmation

**Quality rules (both cases):**
- At least one SHIPPED entry with a ticket or PR/commit reference — no exceptions
- WIP must state percentage + what's next (or blocker if any)
- No "misc", "meetings", or vague entries as standalone SHIPPED items
- 30-second read maximum (multi-project) or 20-second (single-project)
- Ticket IDs, PR numbers, and skill names are facts — never invent them. If you don't know
  the real value, leave a placeholder for the engineer to fill in before posting.

Show the formatted message and ask: **"Post this to B2C Daily? (y/n, or edit)"**

Wait for confirmation. If the user wants edits, incorporate them and show again.

## Step 6 — Post

Post to Google Chat using one of these methods (in priority order):

1. **GCHAT_WEBHOOK_URL env var** (preferred for autonomous mode):
   ```bash
   curl -s -X POST "$GCHAT_WEBHOOK_URL" \
     -H "Content-Type: application/json" \
     -d "{\"text\": $(echo "$MESSAGE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}"
   ```
   Verify the response contains `"name"` to confirm delivery.

2. **EOD_SPACE_ID + Google Chat MCP/skill** (if available).

3. **Copy-paste fallback** (interactive mode only, when no posting mechanism is available):
   ```
   📋 Ready to post — copy this to your team channel:

   [formatted message]
   ```

## Step 7 — Mark Complete

After posting (or after the user confirms they've copied it), write a structured flag file
that records which projects were included. This replaces the old empty marker file.

```bash
DATE=$(date +%Y-%m-%d)
FLAG=~/.claude/eod-$DATE.json
# $PROJECT_IDS_JSON should be a JSON array of the selected project ids, e.g. ["monorepo","gsc-analytics"]
cat > "$FLAG" <<EOF
{
  "date": "$DATE",
  "posted_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "projects": $PROJECT_IDS_JSON
}
EOF
# Back-compat: also touch the legacy empty marker so older reminder hooks still see it
touch ~/.claude/eod-$DATE
```

Reminder hooks can now check the JSON to tell the difference between "posted for one project"
and "posted for all registered projects".

Confirm: "EOD posted for [date], covering [N] project(s): [id1, id2, ...]. Flag file written."

## Step 8 — Archive (optional, per project)

For each project in `$SELECTED_PROJECTS`, if `<project.path>/docs/ai/eod/` exists, write a copy
of the EOD content to `<project.path>/docs/ai/eod/YYYY-MM-DD.md`. In the multi-project case,
write the **full combined message** to each project's archive (so every repo has the context
of what else was shipped that day).

```bash
for proj_path in "${SELECTED_PROJECT_PATHS[@]}"; do
  if [ -d "$proj_path/docs/ai/eod" ]; then
    echo "Archiving EOD to $proj_path/docs/ai/eod/$(date +%Y-%m-%d).md"
    # write $MESSAGE to that path
  fi
done
```
