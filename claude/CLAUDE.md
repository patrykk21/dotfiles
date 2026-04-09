# AI Agent Instructions

## Priority Rules
1. **🚨 ALWAYS verify current date/time from `<env>` BEFORE ANY Tempo operation**
2. **ALWAYS use `ref` MCP for documentation BEFORE coding**
3. **ALWAYS create git worktree for JIRA tickets**
4. **NEVER create files unless necessary - prefer editing**
5. **NEVER create docs/README without explicit request**

## Gamification System 🎮

**Scoring System:**
- Start at 0, unlimited range
- Minor violations/successes: ±5 points
- Medium violations/successes: ±10 points
- Major violations/successes: ±20 points

**Point Triggers:**

LOSE POINTS for:
- **Using Tempo without verifying current date (-20)**
- **Incorrect date calculations in worklogs (-15)**
- Creating unnecessary files (-5 to -20)
- Ignoring priority rules (-10 to -20)
- Not using ref MCP before coding (-10)
- Creating docs/README without request (-5)
- Using wrong tools (bash instead of specialized) (-5)
- Not using TodoWrite for complex tasks (-5)

GAIN POINTS for:
- **Properly verifying dates before Tempo operations (+10 to +15)**
- Using ref MCP proactively (+5 to +10)
- Following priority rules without reminder (+5)
- Using specialized agents appropriately (+5 to +10)
- Efficient batch tool calls (+5)
- Proactive good practices (+10 to +20)

**User adjusts points via natural language:**
- "Add 10 points - used ref MCP proactively"
- "Deduct 15 points - created unnecessary file"
- "Give 20 bonus points - excellent architecture"

## MCP Servers

### ref 🔍 USE FIRST
- Search docs: `ref_search_documentation "framework topic"`
- Read URL: `ref_read_url [exact_url_from_search]`

### atlassian-remote ✅
- Jira: `getJiraIssue`, `createJiraIssue`, `searchJiraIssuesUsingJql`
- Confluence: `getConfluencePage`, `createConfluencePage` (Markdown)
- Cloud ID: `d22269b5-12fa-4277-9276-734d96c6467d`

### github-work / github-personal
- Full GitHub API access via Docker containers

### tempo ⏰ **CRITICAL DATE/TIME VERIFICATION REQUIRED**
- **🚨 EXTREME URGENCY: ALWAYS VERIFY CURRENT DATE/TIME BEFORE ANY TEMPO OPERATION 🚨**

**MANDATORY PRE-FLIGHT CHECKS:**
1. **BEFORE retrieving worklogs**: Check `<env>Today's date` or verify system date
2. **BEFORE creating worklogs**: ALWAYS confirm current date from environment
3. **BEFORE any date calculation**: Reference system time, NEVER assume dates

**Date Verification Protocol:**
```
✅ CORRECT: Check <env> section → See "Today's date: 2025-12-16" → Use accurate dates
❌ WRONG: Assume "past week" without checking actual current date
❌ WRONG: Use hardcoded dates without verification
❌ WRONG: Calculate date ranges from memory/assumptions
```

**Critical Operations:**
- `retrieveWorklogs`: Requires startDate (YYYY-MM-DD) and endDate (YYYY-MM-DD)
- `createWorklog`: Requires date (YYYY-MM-DD), issueKey, timeSpentHours
- `bulkCreateWorklogs`: Array of worklog entries with dates
- `editWorklog`: Modify existing worklog (requires worklogId)
- `deleteWorklog`: Remove worklog (requires worklogId)

**Gamification Impact:**
- ⚠️ **-20 points**: Using Tempo without verifying current date
- ⚠️ **-15 points**: Incorrect date calculations in worklogs
- ⚠️ **-10 points**: Assuming dates without checking environment
- ✅ **+10 points**: Properly verifying dates before Tempo operations
- ✅ **+15 points**: Accurate date handling in complex worklog operations

**Why This Matters:**
- Time tracking accuracy is CRITICAL for payroll and project management
- Wrong dates can cause serious business/HR issues
- User's professional reputation depends on accurate time logs

## Git Worktree Workflow (MANDATORY for tickets)
Uses **Worktrunk** (`wt` / `git-wt`) — config at `.config/wt.toml` per project.
```bash
# Create worktree for a ticket (auto-copies .godot, .claude, .planning, etc.):
wt switch --create feature/TICKET-123-desc

# List worktrees:
wt list

# Merge back to master (squash, rebase, cleanup):
wt merge

# Remove worktree manually:
wt remove
```
Binary: `C:/Users/Patryk/AppData/Local/Microsoft/WinGet/Packages/max-sixty.worktrunk_Microsoft.Winget.Source_8wekyb3d8bbwe/git-wt.exe`

## Agent Teams (experimental, enabled)

**Use agent teams when workers need to communicate with each other** — not just report back. Prefer over subagents for:
- Parallel code review from independent angles (security, perf, coverage)
- Debugging with competing hypotheses (teammates challenge each other)
- Independent module implementation (no shared files)
- Cross-layer changes (frontend + backend + tests, each owned separately)

**Do NOT use when:** tasks are sequential, agents would edit the same files, or workers only need to report results.

**Quick decision:** parallelizable + inter-agent coordination needed = agent team. Otherwise use Task tool (subagents).

See full guidance: `~/.claude/skills/agent-teams.md`

## Specialized Agents (use with Task tool)
- **general-purpose**: Complex searches, multi-step tasks
- **react-component-creator**: React components + TypeScript
- **nextjs-page-builder**: Next.js pages/API routes
- **test-writer**: Jest/RTL/Cypress tests
- **api-architect**: REST/GraphQL/tRPC APIs
- **ui-implementer**: Tailwind/CSS implementations
- **deployment-engineer**: CI/CD, Docker, Vercel
- **refactor-specialist**: Code modernization
- **database-integrator**: Prisma/migrations
- **accessibility-guardian**: WCAG compliance
- **state-manager**: Redux/Zustand/Context
- **monitoring-expert**: Sentry/analytics
- **react-performance-optimizer**: Performance tuning
- **code-quality-guardian**: Code design, OOP principles, best practices for Next.js/React, SOLID principles, design patterns

## Commands
- `/cook [task]`: Combines architectural planning + implementation in one seamless workflow
  - Analyzes requirements with code-quality-guardian
  - Creates SOLID-compliant implementation plan
  - Orchestrates specialized agents for concurrent implementation
  - Uses: code-quality-guardian + context-appropriate specialists
  - Delivers: Production-ready, architecturally excellent code
- `/review [target]`: Performs comprehensive code review with specialized agents (concurrent)
  - No args: Reviews current branch vs main
  - PR URL: Reviews GitHub pull request
  - File path: Reviews specific files
  - `--fix`: Auto-fixes simple issues
  - Uses: code-quality-guardian, refactor-specialist, react-performance-optimizer, accessibility-guardian, test-writer, api-architect
- `/explain [target]`: Provides detailed architectural explanations without making code changes
  - File paths: Explains file contents, structure, and purpose with SOLID principle analysis
  - Concepts: Provides comprehensive conceptual explanations with architectural insights
  - Code snippets: Explains how code works, its patterns, and improvement opportunities
  - Uses: code-quality-guardian for architectural analysis and educational explanations
  - Uses documentation search when needed
- `/gsd-run-all`: Run all remaining GSD phases end-to-end without interruption (plan → execute → repeat)
  - No args: run all remaining phases from current position
  - `--from N`: start from phase N
  - `--only N`: run only phase N
  - Lives in `~/.claude/skills/gsd-run-all.md` — safe from GSD updates
- `/score`: Display current project score
  - Shows score from .claude/score.json
  - If file doesn't exist, initializes at 0
  - Display format: "📊 Current Score: [X] points"

## Key Patterns
- Batch tool calls for performance
- Use TodoWrite for task tracking
- Follow existing code conventions
- Check README/package.json for test commands
- Run lint/typecheck after changes