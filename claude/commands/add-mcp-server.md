---
name: add-mcp-server
description: "Add and configure MCP server connections with proper validation and troubleshooting"
---

# Add MCP Server Connection

Adds a Model Context Protocol (MCP) server to Claude Code with proper configuration and validation.

## Important Facts

**Configuration Storage Locations:**
- User scope (global): `~/.claude.json` under `mcpServers` field
- Local scope (project-specific): `~/.claude.json` under project path
- Project scope (team-shared): `.mcp.json` in project root
- **NOT** in `~/.config/claude/settings.json` (that's for general settings)

**Transport Types (2026):**
- `http`: Recommended for remote servers (most widely supported)
- `stdio`: For local processes with system access
- `sse`: Deprecated, use HTTP instead where available

**Scope Options:**
- `local` (default): Available only to you in current project
- `project`: Shared with team via `.mcp.json` (checked into git)
- `user`: Available to you across all projects (formerly called "global")

## Execution Steps

### 1. Gather Server Information

Ask user for:
- **Server name**: Short identifier (e.g., "notion", "github", "sentry")
- **Transport type**: http, stdio, or sse
- **Server URL** (for http/sse): Full endpoint URL
- **Command** (for stdio): Command to run (e.g., "npx -y @package/name")
- **Environment variables**: Any required API keys or config
- **Scope**: local, project, or user
- **OAuth credentials** (if required): Client ID, client secret, callback port

### 2. Validate Configuration

**For HTTP/SSE servers:**
```bash
# Test if URL is accessible (optional but recommended)
curl -s -I {url} | head -5
```

**For stdio servers:**
```bash
# Verify command exists
which {command} || npm view {package-name} 2>&1 | grep -E "(name|version)"
```

**For API keys:**
```bash
# If applicable, test API key validity
# Example for Notion:
curl -s -X POST https://api.notion.com/v1/search \
  -H "Authorization: Bearer {api-key}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{"page_size":1}' | head -50
```

### 3. Add MCP Server Using CLI

**Option A: HTTP Server (Recommended for remote services)**
```bash
# Basic HTTP server
claude mcp add --scope {scope} --transport http {name} {url}

# With authentication header
claude mcp add --scope {scope} --transport http {name} {url} \
  --header "Authorization: Bearer {token}"

# With OAuth credentials (pre-configured)
claude mcp add --scope {scope} --transport http \
  --client-id {client-id} --client-secret --callback-port {port} \
  {name} {url}
```

**Option B: Stdio Server (for local processes)**
```bash
# Basic stdio server
claude mcp add --scope {scope} --transport stdio {name} -- {command} {args}

# With environment variables (CRITICAL: --env goes AFTER name, BEFORE --)
claude mcp add --scope {scope} --transport stdio {name} \
  --env KEY1=value1 --env KEY2=value2 -- {command} {args}

# Example: Notion with API key
claude mcp add --scope user --transport stdio notion \
  --env NOTION_API_KEY=ntn_xxx -- npx -y @notionhq/notion-mcp-server
```

**Option C: SSE Server (deprecated, use HTTP if available)**
```bash
# Basic SSE server
claude mcp add --scope {scope} --transport sse {name} {url}

# With header
claude mcp add --scope {scope} --transport sse {name} {url} \
  --header "X-API-Key: {key}"
```

### 4. Verify Installation

```bash
# List all configured servers
claude mcp list

# Get specific server details
claude mcp get {name}

# Check server health and connection status
# (Look for "✓ Connected" in the output)
```

### 5. Test MCP Server Access

**After restart (if needed):**

```javascript
// Search for tools from the new server
ToolSearch({
  query: "{server-name}",
  max_results: 10
})

// List resources from the server
ListMcpResourcesTool({
  server: "{server-name}"
})
```

### 6. Authenticate (if required)

For servers requiring OAuth:

**In Claude Code:**
```
/mcp
```
Then follow browser authentication flow.

### 7. Handle Common Issues

**Issue: Server not appearing in list after `claude mcp list` shows it**
- **Solution**: Restart Claude Code completely
- **Reason**: New servers need full session restart to initialize

**Issue: "spawn claude ENOENT" or command not found**
- **Solution**: Use full path to executable
```bash
which claude  # Get full path
# Then use: /full/path/to/claude in your config
```

**Issue: Environment variables not working**
- **Solution**: Verify `--env` flags come AFTER server name but BEFORE `--`
```bash
# CORRECT:
claude mcp add --transport stdio myserver --env KEY=val -- npx package

# WRONG:
claude mcp add --transport stdio --env KEY=val myserver -- npx package
```

**Issue: Windows "Connection closed" errors with npx**
- **Solution**: Use `cmd /c` wrapper on Windows
```bash
claude mcp add --transport stdio my-server -- cmd /c npx -y @some/package
```

**Issue: Server configured but tools not available**
- **Check**: Scope might be wrong (local vs user vs project)
- **Check**: Current working directory for local scope
- **Solution**: Use `--scope user` for global access

## Common MCP Server Examples

### Notion
```bash
claude mcp add --scope user --transport stdio notion \
  --env NOTION_API_KEY=ntn_your_key_here \
  -- npx -y @notionhq/notion-mcp-server
```

### GitHub (HTTP)
```bash
claude mcp add --scope user --transport http github \
  https://api.githubcopilot.com/mcp/
# Then authenticate with: /mcp
```

### Sentry
```bash
claude mcp add --scope user --transport http sentry \
  https://mcp.sentry.dev/mcp
# Then authenticate with: /mcp
```

### PostgreSQL (stdio)
```bash
claude mcp add --scope project --transport stdio db \
  -- npx -y @bytebase/dbhub \
  --dsn "postgresql://readonly:pass@prod.db.com:5432/analytics"
```

### Playwright
```bash
claude mcp add --scope user --transport stdio playwright \
  -- npx -y @playwright/mcp@latest
```

### Filesystem (local access)
```bash
claude mcp add --scope local --transport stdio fs \
  -- npx -y @modelcontextprotocol/server-filesystem /path/to/directory
```

## Management Commands

```bash
# List all servers
claude mcp list

# Get server details
claude mcp get {name}

# Remove server
claude mcp remove {name}

# Import from Claude Desktop (macOS/WSL only)
claude mcp add-from-claude-desktop

# Reset project approval choices
claude mcp reset-project-choices

# Add from JSON config
claude mcp add-json {name} '{"type":"http","url":"https://..."}' --client-secret
```

## Output Format

After successful installation, display:

```
✅ MCP Server Added: {name}

Transport: {http|stdio|sse}
Scope: {user|local|project}
Command/URL: {details}
Environment: {if any env vars}

Next Steps:
1. Restart Claude Code (if tools don't appear immediately)
2. Use /mcp to authenticate (if OAuth required)
3. Verify with: claude mcp list
4. Test with: ToolSearch for "{name}" tools

Configuration stored in:
{path to config file}
```

## Notes

- **Always use CLI commands**, don't manually edit JSON files (prevents syntax errors)
- **Scope hierarchy**: local > project > user (local overrides others)
- **Security**: Be careful with project-scoped servers containing secrets
- **Approval**: Project-scoped servers require user approval before first use
- **Tool Search**: Auto-enabled when MCP tools exceed 10% of context window
- **OAuth**: Use `/mcp` command for authentication, not manual config
- **Windows**: Use `cmd /c` wrapper for npx commands
- **Restart**: Always restart Claude Code after adding servers for full integration
- **Config location**: Remember `~/.claude.json` for servers, NOT `settings.json`

## References

- Official docs: https://code.claude.com/docs/en/mcp
- MCP Registry: https://api.anthropic.com/mcp-registry/docs
- MCP Protocol: https://modelcontextprotocol.io
