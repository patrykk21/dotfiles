---
name: time-tracking
description: "Analyze Jira estimates vs Tempo logged time with weekly breakdown"
---

# Time Tracking Analysis

**CRITICAL: Always verify current date/time with Italy timezone (Europe/Rome) BEFORE Tempo operations**

## Execution Steps

### 1. Verify Current Date/Time (Italy Timezone)

```bash
TZ=Europe/Rome date '+Today is %A, %B %d, %Y at %H:%M %Z'
```

Calculate current week Monday:
```bash
CURRENT_DATE=$(TZ=Europe/Rome date '+%Y-%m-%d')
DAY_NUM=$(TZ=Europe/Rome date '+%u')  # 1=Mon, 7=Sun
DAYS_BACK=$((DAY_NUM - 1))
MONDAY=$(TZ=Europe/Rome date -d "$CURRENT_DATE -$DAYS_BACK days" '+%Y-%m-%d' 2>/dev/null || date -v-${DAYS_BACK}d -j -f "%Y-%m-%d" "$CURRENT_DATE" '+%Y-%m-%d')
```

### 2. Fetch Active Jira Tickets

```javascript
mcp__atlassian-remote__searchJiraIssuesUsingJql({
  cloudId: "d22269b5-12fa-4277-9276-734d96c6467d",
  jql: "project = ECH AND assignee = currentUser() AND status IN (\"In Progress\", \"Code Review\", \"Blocked\", \"Ready to Merge\", \"Merged\") ORDER BY key ASC",
  fields: ["key", "summary", "status", "timeoriginalestimate", "timespent", "aggregatetimespent"],
  maxResults: 100
})
```

### 3. Fetch Tempo Worklogs

Current week:
```javascript
mcp__tempo__retrieveWorklogs({
  startDate: MONDAY,
  endDate: CURRENT_DATE
})
```

Last 30 days for full ticket analysis:
```javascript
mcp__tempo__retrieveWorklogs({
  startDate: THIRTY_DAYS_AGO,
  endDate: CURRENT_DATE
})
```

### 4. Display Table 1: Ticket Estimates vs Logged Time

| Ticket | Summary | Status | Est. | Logged | % | Variance |
|--------|---------|--------|------|--------|---|----------|
| ECH-XXX | ... | In Progress | 3.0h | 2.5h | 83% | ✅ Nearly done |

**Variance:**
- ✅ 80-120%: On target
- 🟡 50-79%: Under-logged
- 🔴 <50%: Significantly under
- ⚠️ 0%: Missing logs
- 🟢 >120%: Over estimate

### 5. Display Table 2: Weekly Daily Hours

| Date | Day | Logged | Target | Missing | Status |
|------|-----|--------|--------|---------|--------|
| 2026-02-03 | Mon | 8.0h | 8.0h | 0.0h | ✅ Complete |
| 2026-02-04 | Tue | 0.0h | 8.0h | -8.0h | 🔴 MISSING |
| 2026-02-06 | Fri | 2.0h | 8.0h | -6.0h | 🟡 Today |

**Status:**
- ✅ Complete: 8 hours logged
- 🔴 MISSING: Past day <8 hours
- 🟡 Today: Current day (in progress)

### 6. Check Quick Track Log

Read `~/.claude/time-track.md` if it exists. Parse the current week's entries (Monday through today).

For each entry, extract: Date, Category (ticket or tag), Activity, Duration.

Cross-reference with Tempo worklogs:
- Entries in time-track.md that **don't have** a matching Tempo worklog → flag as "Not in Tempo"
- This helps catch work that was tracked quickly but not yet logged formally

### 7. Display Table 3: Quick Track Entries (This Week)

| Date | Category | Activity | Duration | In Tempo? |
|------|----------|----------|----------|-----------|
| 2026-03-28 | `ECH-648` | Daily sync tests and backfill | 1h | ❌ Not logged |
| 2026-03-27 | `meeting` | Sprint planning | 1h | ✅ Found |

**Matching logic:**
- Match by date + ticket key (if category is a ticket number like ECH-XXX)
- For non-ticket categories (meeting, review, etc.), match by date + similar duration
- If no close match found, mark as ❌

### 8. Display Summary

**Tickets:** Total, estimated, logged, overall %, breakdown by status
**Week:** Days complete, total logged, missing, weekly target, action required
**Quick Track:** X entries this week, Y not yet in Tempo — consider logging them

## Notes

- ALWAYS use TZ=Europe/Rome for date calculations
- Week = Monday-Friday
- Convert seconds to hours: divide by 3600
- Aggregate Tempo logs by ticket key and by date
