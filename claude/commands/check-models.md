---
name: check-models
description: "Fetch latest Claude Code model names and options from online documentation"
---

# Check Available Claude Code Models

Fetches the latest available models for Claude Code from official documentation.

## Execution Steps

### 1. Search for Claude Code Model Documentation

```javascript
WebSearch({
  query: "Claude Code /model command available models 2026 site:code.claude.com OR site:docs.anthropic.com"
})
```

### 2. Fetch Official Model Configuration Page

```javascript
WebFetch({
  url: "https://code.claude.com/docs/en/model-config",
  prompt: "List all available Claude Code models with their aliases, full model names, context windows (standard vs 1M), and recommended use cases. Include information about [1m] suffix for extended context."
})
```

### 3. Fetch Additional Model Information

```javascript
WebFetch({
  url: "https://platform.claude.com/docs/en/about-claude/models/overview",
  prompt: "What are the latest Claude model IDs and their capabilities? Include Opus 4.6, Sonnet 4.5, Haiku 4.5 with version numbers and context window sizes."
})
```

### 4. Display Results

**Format:**

```
## Available Claude Code Models

### Model Aliases (Recommended)

| Alias | Current Model | Context | Use Case |
|-------|---------------|---------|----------|
| opus[1m] | claude-opus-4-6 | 1M tokens | Most powerful + extended context |
| opus | claude-opus-4-6 | Standard | Complex reasoning |
| sonnet[1m] | claude-sonnet-4-5-... | 1M tokens | General dev + long sessions |
| sonnet | claude-sonnet-4-5-... | Standard | General development (default) |
| haiku | claude-haiku-4-5-... | Standard | Quick tasks |
| opusplan | Hybrid | - | Opus planning + Sonnet execution |

### Usage Examples

/model opus[1m]        # Switch to Opus 4.6 with 1M context
/model sonnet          # Switch to Sonnet 4.5 (default)
/model haiku           # Switch to Haiku 4.5 (fast)
/model opusplan        # Hybrid mode

### Effort Levels (Opus 4.6)

- low: Faster, cheaper
- medium: Balanced
- high: Maximum reasoning (default)

### Account Availability

[Show which models are available for which account types]
```

### 5. Show Current Model

```bash
# Display currently active model
echo "Currently using: [model from status]"
```

## Notes

- Always fetch from official sources: code.claude.com or docs.anthropic.com
- Model aliases auto-update to latest versions
- [1m] suffix requires pay-as-you-go account for some models
- Include full model IDs for reference
- Note any account-type restrictions
