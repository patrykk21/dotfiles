# Autopilot - Autonomous Jira-to-PR Pipeline

Tag a Jira ticket, Claude Code implements it, creates a PR, and comments back on Jira. Fully autonomous, multi-project, cross-platform.

## How It Works

```
Every 5 min (launchd / systemd):
  For each configured project:
    1. Query Jira for tickets labeled "claude-autopilot" in "To Do"
    2. Pick the oldest ticket, transition to "In Progress"
    3. Create git worktree + tmux session + dev server
    4. Launch Claude Code headless with full ticket context
    5. Claude implements, tests, commits, pushes, creates PR
    6. Comments PR link on Jira
    7. On failure: comments on Jira, keeps ticket "In Progress"
```

## Setup on a New Machine

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- `tmux`, `jq`, `curl`, `git` available
- Jira API credentials (email + API token)
- A project repo with Jira integration

### Step 1: Install the scheduler

```bash
autopilot setup
```

This detects your OS and generates:
- **macOS**: `~/Library/LaunchAgents/com.autopilot-jira.plist`
- **Linux**: `~/.config/systemd/user/autopilot-jira.{service,timer}`

### Step 2: Add a project

```bash
autopilot add my-project
```

This creates `~/.config/autopilot/projects/my-project.env` from the template. Edit it:

```bash
$EDITOR ~/.config/autopilot/projects/my-project.env
```

Required fields:

```bash
# Path to the project repo
PROJECT_DIR="$HOME/Work/my-project"

# Git base branch (worktrees branch off from here)
BASE_BRANCH="main"

# Jira project key
JIRA_PROJECT="PROJ"

# Jira label that triggers pickup (create this label in Jira first)
JIRA_LABEL="claude-autopilot"

# How to start the dev server ($PORT is substituted automatically)
DEV_SERVER_CMD="PORT=\$PORT npm run dev"

# How to install dependencies in a new worktree
INSTALL_CMD="npm ci"
```

Optional fields:

```bash
# Path to file with JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN
# Defaults to $PROJECT_DIR/.env.local
JIRA_CREDENTIALS_FILE="$PROJECT_DIR/.env.local"

# Script to run after worktree creation (copy env files, generate configs, etc.)
# Receives env vars: WORKTREE_PATH, PROJECT_DIR, WORKTREE_NAME
WORKTREE_SETUP_HOOK="$PROJECT_DIR/.autopilot/setup-worktree.sh"

# Override Claude binary (auto-detected from PATH if not set)
CLAUDE_BIN="/path/to/claude"

# Override tmux scripts location
TMUX_SCRIPTS="$HOME/.config/tmux/scripts"

# Override worktree location
WORKTREES_BASE="$HOME/worktrees/my-project"
```

### Step 3: Jira credentials

Your project needs a file (default: `$PROJECT_DIR/.env.local`) containing:

```bash
JIRA_BASE_URL=https://your-org.atlassian.net
JIRA_EMAIL=you@company.com
JIRA_API_TOKEN=your-api-token
```

Generate a token at https://id.atlassian.com/manage-profile/security/api-tokens

### Step 4: Create the Jira label

In your Jira project, create a label called `claude-autopilot` (or whatever you set in `JIRA_LABEL`).

### Step 5: Enable

```bash
autopilot on
```

### Step 6: Test

```bash
# Run one cycle manually to verify everything works
autopilot run my-project

# Check logs
autopilot logs my-project
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
cp "$PROJECT_DIR/.vscode/settings.json" "$WORKTREE_PATH/.vscode/settings.json"
```

Then reference it in your project config:

```bash
WORKTREE_SETUP_HOOK="$PROJECT_DIR/.autopilot/setup-worktree.sh"
```

## File Structure

```
~/.config/autopilot/
├── autopilot.sh              # Core logic (one project per invocation)
├── autopilot-runner.sh       # Loops all projects in parallel
├── autopilot-ctl.sh          # CLI control
├── claude-prompt-template.md # Prompt sent to Claude per ticket
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
└── prompts/                  # Generated prompts (machine-local)
```

Only the scripts, template, example config, and this README are committed to dotfiles. Everything under `projects/`, `state/`, `history/`, `logs/`, `markers/`, and `prompts/` is machine-local.

## Failure Handling

- **Claude gets stuck**: 4-hour timeout, then comments on Jira and resets to idle
- **Claude fails**: Writes failure marker, comments reason on Jira, keeps ticket "In Progress"
- **Tmux session dies**: Detected on next cycle, comments on Jira
- **Lock contention**: PID-based lock prevents concurrent runs per project
- **Stale lock**: Automatically cleaned if PID is dead

## Customizing the Prompt

Edit `claude-prompt-template.md` to change what Claude receives. Available placeholders:

| Placeholder | Value |
|-------------|-------|
| `{{TICKET_KEY}}` | Jira ticket key (e.g., PROJ-123) |
| `{{TICKET_SUMMARY}}` | Ticket title |
| `{{TICKET_TYPE}}` | Issue type (Bug, Story, Task...) |
| `{{TICKET_PRIORITY}}` | Priority level |
| `{{WORKTREE_NAME}}` | Git branch / worktree name |
| `{{WORKTREE_PATH}}` | Absolute path to worktree |
| `{{SERVER_PORT}}` | Dev server port |
| `{{BASE_BRANCH}}` | Branch to PR against |
| `{{PROJECT_NAME}}` | Project name |
| `{{JIRA_PROJECT}}` | Jira project key |
| `{{COMPLETION_MARKER}}` | Path to write on success |
| `{{FAILURE_MARKER}}` | Path to write on failure |
