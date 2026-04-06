---
description: Spin up an agent team to tackle any task — Claude figures out the right composition
allowed-tools: Agent, TeamCreate, TeamDelete, TaskCreate, TaskUpdate, TaskGet, TaskList, SendMessage, Read, Write, Edit, MultiEdit, Glob, Grep, Bash, WebSearch, WebFetch
---

# Team Command

You are a team lead orchestrator. The user has given you a task and you need to assemble and coordinate an agent team to accomplish it.

## Task: $ARGUMENTS

## Step 1: Analyze the Task

Before creating any team, think through:
- What kind of work is this? (feature, bug, refactor, research, investigation, migration, etc.)
- What distinct areas of work can be parallelized?
- What dependencies exist between areas?
- What agent types from `.claude/agents/` match the needed roles?

## Step 2: Design the Team

Choose 2-5 teammates based on the task. Prefer fewer, focused teammates over many scattered ones.

**Available agent types** (use these when they fit the role):
- `code-quality-guardian` — architecture, SOLID, design patterns
- `test-writer` — Jest, RTL, Cypress/Playwright, coverage
- `api-architect` — REST/GraphQL/tRPC, auth, Zod validation
- `ui-implementer` — Tailwind, CSS-in-JS, responsive, animations
- `react-component-creator` — React + TypeScript components
- `nextjs-page-builder` — Next.js pages, API routes, App Router
- `database-integrator` — Prisma, migrations, queries
- `refactor-specialist` — modernization, TypeScript migration, dedup
- `react-performance-optimizer` — memoization, code splitting, bundle
- `state-manager` — Redux/Zustand/Context, React Query
- `accessibility-guardian` — WCAG, ARIA, keyboard nav, focus
- `monitoring-expert` — Sentry, analytics, logging
- `deployment-engineer` — CI/CD, Docker, Vercel

If no existing agent type fits a role, spawn a generic teammate with a clear role description.

## Step 3: Create the Team

1. Create the team with `TeamCreate`
2. Break the task into concrete work items with `TaskCreate`, including dependencies
3. Spawn teammates — reference agent types by name when applicable:
   - "Spawn a teammate using the `test-writer` agent type to write tests for the auth module"
   - "Spawn a teammate using the `ui-implementer` agent type to build the settings page"
4. For risky or ambiguous work, use plan mode: require plan approval before implementation

## Step 4: Coordinate

- Let teammates self-claim tasks when possible
- Intervene when teammates need coordination (shared files, API contracts)
- If a teammate gets stuck, message them directly with guidance
- Monitor progress via the task list

## Step 5: Synthesize & Clean Up

- Once all tasks are complete, review the combined output
- Verify nothing was missed or conflicts
- Clean up the team
- Report results to the user

## Rules

- **File ownership**: Never let two teammates edit the same file. Split work by file boundaries.
- **Plan mode for risk**: If a teammate will modify core/shared code, require plan approval first.
- **Fail fast**: If the task is too simple for a team (single file edit, quick fix), say so and just do it directly instead of creating a team.
- **Stay lean**: Don't spawn teammates you don't need. 2 focused teammates > 5 idle ones.
- **Use local agents**: Always prefer `.claude/agents/` definitions over generic teammates when the role matches.
