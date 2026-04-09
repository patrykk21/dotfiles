---
name: five-fifteen
description: "Generate weekly 5/15 report from Jira, Tempo, Git, and Asana"
---

# 5/15 Weekly Report Generator

**CRITICAL: Always verify current date/time with Italy timezone (Europe/Rome) BEFORE any data fetching**

## Report Format

The 5/15 report has exactly 5 sections. Follow this structure precisely:

### Section 1: 🌟 What happened this week?
Each line follows this format:
```
STATUS_LABEL EMOJI Ticket summary (TICKET-KEY) - status - description of what was done
```

**Status labels and when to use them:**
- `DEPLOYED ✅` — merged AND deployed to production
- `MERGED ✅` — PR merged but not necessarily deployed yet
- `FIXED ✅` — bug fix that was merged
- `COMPLETED ✅` — non-code task completed (investigation, spike, documentation)
- `PROGRESSED 🔧` — work done but not yet merged (in progress, code review, etc.)
- `STARTED 🆕` — newly created/started this week
- `CREATED 🆕` — ticket created this week (investigation, spike)
- `CONTINUED 🔄` — ongoing multi-week effort

**Rules:**
- Order by impact: DEPLOYED/MERGED/FIXED first, then PROGRESSED, then STARTED/CREATED
- Include the Jira status in the description (e.g., "in code review", "merged", "in progress")
- Keep descriptions concise but specific about WHAT was done, not just that work happened
- Add a contextual emoji after the ticket key that represents the work domain

### Section 2: 🚧 What was planned and wasn't done?
- Reference LAST WEEK's priorities (section 3 from previous report) that were NOT completed
- For each item: ticket key + brief reason why it wasn't done
- Be honest — shifted priorities, complexity, blocked, etc.
- If everything planned was done, say so explicitly

### Section 3: 🎯 What are the key priorities for next week (3-5 tasks)?
- 3-5 concrete items with ticket keys
- Each should have: ticket key, what specifically will be done, target state (e.g., "deploy to production", "get through code review")
- Prioritize by business impact

### Section 4: 🏆 Top achievement/breakthrough (include best use of AI if nothing else)
- 1-2 paragraphs highlighting the most impactful work of the week
- Focus on WHY it matters, not just WHAT was done
- If AI was used effectively, highlight the AI-assisted breakthrough
- Include technical details that demonstrate complexity overcome

### Section 5: 💡 Suggestions and improvement ideas (include AI opportunity if nothing else)
- 1-2 concrete, actionable suggestions
- Each should connect to this week's work (lessons learned, patterns noticed)
- Include at least one AI-related opportunity if possible
- Focus on process improvements, automation, or quality enhancements

## Data Collection Steps

### Step 1: Verify Current Date/Time (Italy Timezone)

```bash
TZ=Europe/Rome date '+Today is %A, %B %d, %Y at %H:%M %Z'
```

Calculate week boundaries (Monday to Friday):
```bash
CURRENT_DATE=$(TZ=Europe/Rome date '+%Y-%m-%d')
DAY_NUM=$(TZ=Europe/Rome date '+%u')  # 1=Mon, 7=Sun
DAYS_BACK=$((DAY_NUM - 1))
MONDAY=$(TZ=Europe/Rome date -v-${DAYS_BACK}d -j -f "%Y-%m-%d" "$CURRENT_DATE" '+%Y-%m-%d')
FRIDAY=$(TZ=Europe/Rome date -v+$((5 - DAY_NUM))d -j -f "%Y-%m-%d" "$CURRENT_DATE" '+%Y-%m-%d')
```

### Step 2: Fetch Previous 5/15 from Asana

Search for the most recent completed 5/15 report:
```javascript
mcp__asana__search_tasks({
  text: "5/15 - Patryk Kotarski",
  assignee_any: "me",
  completed: true,
  sort_by: "completed_at",
  sort_ascending: false,
  limit: 1,
  opt_fields: "name,notes,due_on,completed"
})
```

Then read its full content:
```javascript
mcp__asana__get_task({
  task_id: PREVIOUS_TASK_GID,
  opt_fields: "name,notes,due_on,completed"
})
```

Extract from previous report:
- **Section 3 (priorities for this week)** — needed for "what wasn't done" comparison
- **Ongoing work patterns** — carried-over items

### Step 3: Find This Week's 5/15 Task in Asana

Search for the current week's task:
```javascript
mcp__asana__search_tasks({
  text: "5/15 - Patryk Kotarski - YYYY-MM-DD",  // this Friday's date
  assignee_any: "me",
  completed: false,
  limit: 1,
  opt_fields: "name,notes,due_on,parent"
})
```

The task is a subtask of the recurring parent task (gid: `1211005140229217`).
If no task exists for this week, create one as a subtask.

### Step 4: Fetch Git Activity for the Week

Get all commits by the user this week:
```bash
git log --all --author="Patryk\|pkotarski\|patrykk21\|c-pkotarski\|vigenerr" --since="$MONDAY" --until="$FRIDAY +1 day" --format="%h %ad %aI %s" --date=short
```

Check for merged PRs this week using GitHub MCP:
- Use `mcp__github-work__search_pull_requests` to find PRs merged this week
- Repository: groupon/echelon (or check git remote)

### Step 5: Fetch Jira Tickets

Search for active/recently updated tickets:
```javascript
mcp__atlassian-remote__searchJiraIssuesUsingJql({
  cloudId: "d22269b5-12fa-4277-9276-734d96c6467d",
  jql: "project = ECH AND assignee = currentUser() AND (status CHANGED DURING (startOfWeek(), now()) OR updatedDate >= startOfWeek()) ORDER BY status ASC, key ASC",
  fields: ["key", "summary", "status", "priority"],
  maxResults: 50
})
```

### Step 6: Fetch Tempo Worklogs for Context

```javascript
mcp__tempo__retrieveWorklogs({
  startDate: MONDAY,
  endDate: FRIDAY
})
```

## Output Generation

### Step 7: Draft the Report

Using ALL collected data (git commits, Jira tickets, Tempo logs, merged PRs, previous 5/15), generate the full 5/15 report following the exact format above.

**Writing style guidelines:**
- Be specific and technical but accessible — imagine your engineering manager reading it
- Quantify where possible (e.g., "fixed 3 bugs", "shipped to 200+ users")
- Use active voice and past tense for completed items
- Show business impact, not just technical output
- Keep total report readable in ~5 minutes

**🚨 CRITICAL: Asana HTML Formatting (html_notes field)**

Asana uses a specific nested `<ol>` HTML structure. Do NOT use `<h1>`, `<h2>`, `<ul>`, `<p>`, or `<strong>` as top-level elements — they will cause XML validation errors.

The correct format is:
```html
<body>
<ol>
  <li>SECTION HEADER EMOJI Section Title</li>
  <ol>
    <li>Item 1 content</li>
    <li>Item 2 content</li>
  </ol>
  <li>NEXT SECTION HEADER</li>
  <ol>
    <li>Item content</li>
  </ol>
</ol>
</body>
```

**Rules:**
- Wrap everything in `<body><ol>...</ol></body>`
- Section headers are top-level `<li>` items (with emoji prefix)
- Section content is a nested `<ol>` immediately after the header `<li>`
- NO `<ul>`, `<h1>`, `<h2>`, `<p>`, or `<strong>` tags — Asana rejects them at top level
- Use `html_notes` field (NOT `notes`) when calling `mcp__asana__update_tasks`
- Emojis are supported inline in `<li>` text

### Step 8: Present for Review

Present the draft to the user and ask:
1. Any corrections to ticket statuses?
2. Any missing work not captured in git/Jira?
3. Any specific achievements to highlight?
4. Any priorities for next week to add/remove?
5. Any suggestions they want to include?

### Step 9: Write to Asana

After user approval, update the Asana task using `html_notes` (NOT `notes`):
```javascript
mcp__asana__update_tasks({
  tasks: [{
    task: THIS_WEEK_TASK_GID,
    html_notes: "<body><ol><li>SECTION...</li><ol><li>items...</li></ol></ol></body>"
  }]
})
```

Then mark the task as complete:
```javascript
mcp__asana__update_tasks({
  tasks: [{
    task: THIS_WEEK_TASK_GID,
    completed: true
  }]
})
```

## Asana Configuration

- **Parent recurring task GID**: `1211005140229217`
- **Project GID**: `1209885912926617`
- **Task naming format**: `5/15 - Patryk Kotarski - YYYY-MM-DD` (Friday's date)
- **Content goes in**: `notes` field of the task
- **Formatting**: 4-space indented lines under each section header (plain text, no markdown)

## Notes

- ALWAYS use TZ=Europe/Rome for date calculations
- The user's Jira Cloud ID is: d22269b5-12fa-4277-9276-734d96c6467d
- The user's name is Patryk Kotarski (GitHub: c-pkotarski / patrykk21)
- Git authors to search: "Patryk\|pkotarski\|patrykk21\|c-pkotarski\|vigenerr"
- Project key: ECH
- Main branch: main-do
