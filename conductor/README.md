# Conductor - Autonomous Ticket-to-PR Pipeline

Pass a ticket URL from any platform, Claude Code implements it, creates a PR, and comments back. Fully autonomous, multi-project, cross-platform.

## Two Ways to Use

### 1. Manual: `/conductor` command (any platform)

Inside any Claude Code session, run:

```
/conductor https://your-org.atlassian.net/browse/PROJ-123
/conductor https://app.clickup.com/t/abc123
/conductor https://linear.app/team/issue/TEAM-456
/conductor https://github.com/org/repo/issues/42
```

Claude detects the platform, fetches the ticket, implements it, and creates a PR. Works with Jira, ClickUp, Linear, GitHub Issues, or any URL it can parse.

### 2. Automated: Scheduler (Jira polling)

```
Every 5 min (launchd / systemd):
  For each configured project:
    1. Query Jira for tickets labeled "claude-conductor" in "To Do"
    2. Pick the oldest ticket, transition to "In Progress"
    3. Create git worktree + tmux session + dev server
    4. Launch Claude Code with /conductor <ticket-url>
    5. Claude implements, tests, commits, pushes, creates PR
    6. Comments PR link on Jira
    7. On failure: comments on Jira, keeps ticket "In Progress"
```

## Setup on a New Machine

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- `tmux`, `jq`, `curl`, `git` available
- For automated polling: Jira API credentials (email + API token)

### Step 1: Source the alias

The dotfiles should already be cloned to `~/.config`. Open a new shell or:

```bash
source ~/.config/zsh/aliases.sh
```

### Step 2: Install the scheduler

```bash
conductor setup
```

This detects your OS and generates:
- **macOS**: `~/Library/LaunchAgents/com.conductor-jira.plist`
- **Linux**: `~/.config/systemd/user/conductor-jira.{service,timer}`

### Step 3: Add a project

```bash
conductor add my-project
$EDITOR ~/.config/conductor/projects/my-project.env
```

Required fields:

```bash
# Path to the project repo
PROJECT_DIR="$HOME/Work/my-project"

# Git base branch (worktrees branch off from here)
BASE_BRANCH="main"

# Jira project key (for automated polling)
JIRA_PROJECT="PROJ"

# Jira label that triggers pickup (create this label in Jira first)
JIRA_LABEL="claude-conductor"

# How to start the dev server ($SERVER_PORT is set by tmux session)
DEV_SERVER_CMD="PORT=\$SERVER_PORT npm run dev"

# How to install dependencies in a new worktree
INSTALL_CMD="npm ci"
```

Optional fields:

```bash
# URL pattern for building ticket links from keys. Use {{KEY}} as placeholder.
TICKET_URL_PATTERN="https://your-org.atlassian.net/browse/{{KEY}}"
# TICKET_URL_PATTERN="https://app.clickup.com/t/{{KEY}}"
# TICKET_URL_PATTERN="https://linear.app/your-org/issue/{{KEY}}"

# Jira credentials file (needs JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN)
# Defaults to $PROJECT_DIR/.env.local
JIRA_CREDENTIALS_FILE="$HOME/.config/conductor/jira-credentials.env"

# Script to run after worktree creation (copy env files, generate configs, etc.)
# Receives env vars: WORKTREE_PATH, PROJECT_DIR, WORKTREE_NAME
WORKTREE_SETUP_HOOK="$PROJECT_DIR/.conductor/setup-worktree.sh"

# Override Claude binary (auto-detected from PATH if not set)
# CLAUDE_BIN="/path/to/claude"

# Override tmux scripts location
# TMUX_SCRIPTS="$HOME/.config/tmux/scripts"

# Override worktree location
# WORKTREES_BASE="$HOME/worktrees/my-project"
```

### Step 4: Jira credentials (for automated polling)

Create a credentials file:

```bash
cat > ~/.config/conductor/jira-credentials.env << 'EOF'
JIRA_BASE_URL=https://your-org.atlassian.net
JIRA_EMAIL=you@company.com
JIRA_API_TOKEN=your-api-token
EOF
```

Generate a token at https://id.atlassian.com/manage-profile/security/api-tokens

If you already have Jira creds in another config (e.g., Tempo MCP in `~/.cursor/mcp.json`), you can reuse those values.

### Step 5: Create the Jira label

In your Jira project, create a label matching your `JIRA_LABEL` config (default: `claude-conductor`).

### Step 6: Enable and test

```bash
conductor on
conductor run my-project    # test one cycle
conductor logs my-project   # check output
conductor status            # see all projects
```

## Commands

| Command | Description |
|---------|-------------|
| `conductor on` | Enable polling (all projects) |
| `conductor off` | Disable polling (active work continues) |
| `conductor status` | Show all projects and their state |
| `conductor setup` | Install OS scheduler (launchd/systemd) |
| `conductor add <name>` | Add a new project |
| `conductor remove <name>` | Remove a project config |
| `conductor list` | List configured projects |
| `conductor run [project]` | Manual run (one or all projects) |
| `conductor logs [project] [N]` | Show last N log lines |
| `conductor history [project]` | Show completed/failed tickets |
| `conductor reset <project>` | Reset stuck project to idle |
| `conductor reset --all` | Reset all projects |

## Multi-Project Support

Each project runs independently with its own state, lock, logs, and history. The runner fires all projects in parallel every 5 minutes.

```bash
conductor add frontend
conductor add backend
conductor add mobile-app

conductor status
# Shows:
#   frontend  (FE)   — WORKING on FE-42
#   backend   (BE)   — IDLE
#   mobile-app (MOB) — IDLE
```

## Project-Level Setup Hook

For projects that need custom worktree setup (env files, config generation, etc.), create `.conductor/setup-worktree.sh` in the project repo:

```bash
#!/usr/bin/env bash
# Available env vars: WORKTREE_PATH, PROJECT_DIR, WORKTREE_NAME

# Copy environment files
cp "$PROJECT_DIR/.env.local" "$WORKTREE_PATH/.env.local"

# Generate IDE config, copy settings, etc.
mkdir -p "$WORKTREE_PATH/.claude"
cp "$PROJECT_DIR/.claude/settings.local.json" "$WORKTREE_PATH/.claude/settings.local.json"
```

Then reference it in your project config:

```bash
WORKTREE_SETUP_HOOK="$PROJECT_DIR/.conductor/setup-worktree.sh"
```

## Using `/conductor` Manually

You don't need the scheduler to use conductor. In any Claude Code session:

```
/conductor https://your-company.atlassian.net/browse/PROJ-571
```

Claude will:
1. Detect the platform (Jira) from the URL
2. Fetch the ticket details via MCP tools
3. Read project conventions (AGENTS.md / CLAUDE.md)
4. Implement, test, commit, push, create PR
5. Comment the PR link back on the ticket

If Claude needs clarification, it will ask — you can answer in the same session.

This works with any ticket URL: Jira, ClickUp, Linear, GitHub Issues.

## File Structure

```
~/.config/conductor/
├── conductor.sh              # Core logic (one project per invocation)
├── conductor-runner.sh       # Loops all projects in parallel
├── conductor-ctl.sh          # CLI control
├── claude-prompt-template.md # Legacy prompt template (kept for reference)
├── config.env.example        # Template for project configs
├── setup.sh                  # OS scheduler installer
├── README.md                 # This file
├── projects/                 # Per-project configs (machine-local)
│   └── *.env
├── state/                    # Per-project state (machine-local)
│   └── *.json, *.lock
├── history/                  # Per-project history (machine-local)
│   └── <project>/*.json
├── logs/                     # Per-project logs (machine-local)
│   └── *.log
├── markers/                  # Completion markers (machine-local)
└── prompts/                  # Generated launcher scripts (machine-local)
```

Only the scripts, template, example config, and this README are committed to dotfiles. Everything under `projects/`, `state/`, `history/`, `logs/`, `markers/`, and `prompts/` is machine-local.

## Failure Handling

- **Claude gets stuck**: 4-hour timeout, then comments on Jira and resets to idle
- **Claude fails**: Writes failure marker, comments reason on Jira, keeps ticket "In Progress"
- **Tmux session dies**: Detected on next cycle, comments on Jira
- **Lock contention**: PID-based lock prevents concurrent runs per project
- **Stale lock**: Automatically cleaned if PID is dead

## Customizing the `/conductor` Command

The command lives at `~/.claude/commands/conductor.md`. It handles both:
- **Ticket URLs** → autonomous implementation flow
- **GSD args** (`new-project`, `resume`, etc.) → existing GSD workflow

The ticket flow detects the platform from the URL and uses appropriate tools:

| URL pattern | Platform | Tools used |
|-------------|----------|------------|
| `*.atlassian.net/browse/*` | Jira | Atlassian MCP |
| `app.clickup.com/t/*` | ClickUp | WebFetch |
| `linear.app/*/issue/*` | Linear | WebFetch |
| `github.com/*/issues/*` | GitHub | GitHub MCP |

## Employer Layer

Anything that belongs to one employer stays out of this repo, in `~/.claude/company/<name>/`. Conductor reads these from there:

| Path | Read by | Effect |
|---|---|---|
| `company.env` → `WORK_ROOT` | `conductor.sh` | A project whose `PROJECT_DIR` is inside this directory belongs to that employer. |
| `company.env` → `PACKAGES_TOKEN_ALIASES` | `conductor.sh`, before `INSTALL_CMD` | Space-separated names an `.npmrc` uses for the GitHub Packages token. Conductor copies the token between `GITHUB_PACKAGES_TOKEN` and these names, filling whichever are empty. |
| `conductor/jira-hygiene-prompt.md` | `conductor.sh`, when it writes a session prompt | Appended to the prompt for Jira tickets of that employer's projects, with `{{TICKET_KEY}}` replaced. |
| `conductor/hooks/<project>-setup.sh` | `conductor.sh`, after creating a worktree | The project's setup hook, used when its config doesn't set `WORKTREE_SETUP_HOOK`. Runs only if executable. |
| `conductor/projects/<project>.md` | `/conductor`, Phase 0.3 | The project's guide: extra skill-routing rows, a pre-push checklist, its PR base, guardrails. |

GitHub Enterprise needs no setting. Conductor takes the host from the repo's remote URL and reaches any host other than `github.com` with `GH_HOST=<host>`. An SSH host alias (a name with no dot, such as `git@work-gh:org/repo`) counts as `github.com`.
