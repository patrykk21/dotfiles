# Autopilot - Autonomous Ticket-to-PR Pipeline

Pass a ticket URL from any platform, Claude Code implements it, creates a PR, and comments back. Fully autonomous, multi-project, cross-platform.

## Two Ways to Use

### 1. Manual: `/autopilot` command (any platform)

Inside any Claude Code session, run:

```
/autopilot https://your-org.atlassian.net/browse/PROJ-123
/autopilot https://app.clickup.com/t/abc123
/autopilot https://linear.app/team/issue/TEAM-456
/autopilot https://github.com/org/repo/issues/42
```

Claude detects the platform, fetches the ticket, implements it, and creates a PR. Works with Jira, ClickUp, Linear, GitHub Issues, or any URL it can parse.

### 2. Automated: Scheduler (Jira polling)

```
Every 5 min (launchd / systemd):
  For each configured project:
    1. Query Jira for tickets labeled "claude-autopilot" in "To Do"
    2. Pick the oldest ticket, transition to "In Progress"
    3. Create git worktree + tmux session + dev server
    4. Launch Claude Code with /autopilot <ticket-url>
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
autopilot setup
```

This detects your OS and generates:
- **macOS**: `~/Library/LaunchAgents/com.autopilot-jira.plist`
- **Linux**: `~/.config/systemd/user/autopilot-jira.{service,timer}`

### Step 3: Add a project

```bash
autopilot add my-project
$EDITOR ~/.config/autopilot/projects/my-project.env
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
JIRA_LABEL="claude-autopilot"

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
JIRA_CREDENTIALS_FILE="$HOME/.config/autopilot/jira-credentials.env"

# Script to run after worktree creation (copy env files, generate configs, etc.)
# Receives env vars: WORKTREE_PATH, PROJECT_DIR, WORKTREE_NAME
WORKTREE_SETUP_HOOK="$PROJECT_DIR/.autopilot/setup-worktree.sh"

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
cat > ~/.config/autopilot/jira-credentials.env << 'EOF'
JIRA_BASE_URL=https://your-org.atlassian.net
JIRA_EMAIL=you@company.com
JIRA_API_TOKEN=your-api-token
EOF
```

Generate a token at https://id.atlassian.com/manage-profile/security/api-tokens

If you already have Jira creds in another config (e.g., Tempo MCP in `~/.cursor/mcp.json`), you can reuse those values.

### Step 5: Create the Jira label

In your Jira project, create a label matching your `JIRA_LABEL` config (default: `claude-autopilot`).

### Step 6: Enable and test

```bash
autopilot on
autopilot run my-project    # test one cycle
autopilot logs my-project   # check output
autopilot status            # see all projects
```

## Commands

| Command | Description |
|---------|-------------|
| `autopilot on` | Enable polling (all projects) |
| `autopilot off` | Disable polling (active work continues) |
| `autopilot status` | Show all projects and their state |
| `autopilot setup` | Install OS scheduler (launchd/systemd) |
| `autopilot add <name>` | Add a new project |
| `autopilot remove <name>` | Remove a project config |
| `autopilot list` | List configured projects |
| `autopilot run [project]` | Manual run (one or all projects) |
| `autopilot logs [project] [N]` | Show last N log lines |
| `autopilot history [project]` | Show completed/failed tickets |
| `autopilot reset <project>` | Reset stuck project to idle |
| `autopilot reset --all` | Reset all projects |

## Multi-Project Support

Each project runs independently with its own state, lock, logs, and history. The runner fires all projects in parallel every 5 minutes.

```bash
autopilot add frontend
autopilot add backend
autopilot add mobile-app

autopilot status
# Shows:
#   frontend  (FE)   — WORKING on FE-42
#   backend   (BE)   — IDLE
#   mobile-app (MOB) — IDLE
```

## Project-Level Setup Hook

For projects that need custom worktree setup (env files, config generation, etc.), create `.autopilot/setup-worktree.sh` in the project repo:

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
WORKTREE_SETUP_HOOK="$PROJECT_DIR/.autopilot/setup-worktree.sh"
```

## Using `/autopilot` Manually

You don't need the scheduler to use autopilot. In any Claude Code session:

```
/autopilot https://groupondev.atlassian.net/browse/ECH-571
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
~/.config/autopilot/
├── autopilot.sh              # Core logic (one project per invocation)
├── autopilot-runner.sh       # Loops all projects in parallel
├── autopilot-ctl.sh          # CLI control
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

## Customizing the `/autopilot` Command

The command lives at `~/.claude/commands/autopilot.md`. It handles both:
- **Ticket URLs** → autonomous implementation flow
- **GSD args** (`new-project`, `resume`, etc.) → existing GSD workflow

The ticket flow detects the platform from the URL and uses appropriate tools:

| URL pattern | Platform | Tools used |
|-------------|----------|------------|
| `*.atlassian.net/browse/*` | Jira | Atlassian MCP |
| `app.clickup.com/t/*` | ClickUp | WebFetch |
| `linear.app/*/issue/*` | Linear | WebFetch |
| `github.com/*/issues/*` | GitHub | GitHub MCP |
