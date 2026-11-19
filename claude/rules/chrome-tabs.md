## Chrome tabs: close what you open

Every tab opened in the user's Chrome (claude-in-chrome `tabs_create_mcp`, or a click that spawns one) is closed with `tabs_close_mcp` as soon as the task that needed it is finished. Left-open tabs pile up across sessions (user, 19 Nov 2026: "I have dozens of tabs open for no reason").

- Close before the final reply. A task that ends in an error still closes its tabs.
- Keep a tab open only when the user is meant to look at it next, and name it in the reply ("left open: <title>").
- Never close a tab you didn't open unless the user asks.
- Subagents and engineer sessions follow the same rule. When handing browser work to a subagent, tell it to close its tabs.
