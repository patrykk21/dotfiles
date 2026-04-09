---
description: "Quick time tracking log entry for work activities"
allowed-tools: ["Read", "Write", "Edit", "AskUserQuestion", "Bash"]
---

# Track - Quick Work Time Log

You are helping the user quickly log what they just worked on. This is a lightweight time tracking tool — fast, no friction, run from anywhere.

## INPUT

The user has provided: $ARGUMENTS

If no arguments were provided, ask the user: "What did you just work on?"

## WORKFLOW

### Step 1: Parse the input

Extract from the user's input:
- **What** they worked on (task/activity description)
- **Duration** (if mentioned — e.g., "2h", "30m", "1.5 hours")
- **Category** (if mentioned — e.g., ticket number, project name, meeting)

If duration is not provided, ask: "How long did you spend on this? (e.g., 30m, 1h, 2.5h)"

If the activity is unclear, ask one brief clarifying question. Keep it fast — don't over-interrogate.

### Step 2: Determine the date

Check the environment for today's date. Use it in YYYY-MM-DD format.

### Step 3: Format the entry

Create a clean, scannable log entry. Keep it concise — this is a log, not a narrative.

### Step 4: Store the entry

The time tracking file lives at: `~/.claude/time-track.md`

Read the file first (create it if it doesn't exist). Then append the new entry.

**If the file doesn't exist**, create it with this header:

```markdown
# Time Track

A running log of daily work activities.

---

```

**Entry format — group by date:**

First, check if today's date already has a section. If yes, append under it. If no, create a new date section.

```markdown
## YYYY-MM-DD (Day of Week)

| Time | Category | Activity | Duration |
|------|----------|----------|----------|
| HH:MM | `ECH-123` | Description of work done | 1.5h |
| HH:MM | `meeting` | Sprint planning | 1h |

```

- **Time**: Current time when the entry is logged (HH:MM, 24h format). Get from system via `date +%H:%M`.
- **Category**: Ticket number (e.g., `ECH-639`), or a tag like `meeting`, `review`, `support`, `learning`, `admin`, `oncall`. Use backtick formatting.
- **Activity**: Brief description (1 line, no fluff)
- **Duration**: Time spent (e.g., `30m`, `1h`, `2.5h`)

### Step 5: Show daily summary

After saving, show:
1. The entry that was just logged
2. Total hours logged today (sum all durations for today's date section)

Format: "Logged **[duration]** for `[category]`. Total today: **[X]h**"

## GUIDELINES

- Speed is the priority — this should feel instant
- Don't rewrite or polish the user's description — keep their words
- If user says "meeting" or "standup", category is `meeting`
- If user mentions a ticket (ECH-XXX, JIRA-XXX), use that as category
- If no clear category, use `general`
- Durations: normalize to hours for totals (30m = 0.5h, 1h30m = 1.5h)
- Never ask more than 1-2 questions total
- If the user provides everything in one line (e.g., "/track 2h ECH-639 built the incidents page"), just log it directly — no questions needed
