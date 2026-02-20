---
description: "Continue from the latest conversation in this directory"
allowed-tools: ["Read", "Bash", "Grep"]
---

# Continue Command - Resume Previous Conversation

You are now in conversation continuation mode. Your task is to load and present the **previous** conversation from this directory (not the current one) so the user can continue from where they left off.

## CRITICAL: The latest file is the CURRENT conversation (just spawned by /continue), so get the SECOND most recent file!

## EXECUTION STEPS:

### 1. **Find the Project Directory**

First, get the slugified project directory name, then find the actual directory:

```bash
# Step 1a: Get current directory and slugify it (but don't use in subshell)
pwd | sed 's|/|-|g' | sed 's|^-||'
```

```bash
# Step 1b: List all directories and find the one matching our path
ls -d ~/.claude/projects/*config 2>/dev/null | grep -i config
```

### 2. **Find Previous Conversation (NOT the current one)**

Find the SECOND most recent conversation file (the first is the current /continue session):

```bash
# Step 2: Get the 2nd most recent conversation (skip the current one)
# Replace PROJECT_DIR with the actual directory path from Step 1b
ls -t PROJECT_DIR/*.jsonl 2>/dev/null | grep -v "agent-" | head -2 | tail -1
```

**CRITICAL:** Use `head -2 | tail -1` to get the SECOND file, not the first!

### 3. **Extract Conversation Metadata**

Get the file path and display metadata:

```bash
# Step 3: Get conversation details (replace PREV_CONV with actual file path)
du -h PREV_CONV | awk '{print "📊 Size: " $1}'
wc -l < PREV_CONV | awk '{print "💬 Messages: " $1}'
ls -l PREV_CONV | awk '{print "🕒 Last modified: " $6 " " $7 " " $8}'
```

### 4. **Display Conversation Preview**

Extract and display actual conversation content:

```bash
# Step 4: Show the beginning of the conversation (first meaningful messages)
head -n 20 PREV_CONV | jq -rs 'map(select(.message.role)) | .[0:5] | .[] | "\n" + (.message.role | ascii_upcase) + ":\n" + (.message.content | map(select(.text) | .text | .[0:400]) | join("\n"))'
```

```bash
# Step 5: Show the end of the conversation (last few messages)
tail -n 30 PREV_CONV | jq -rs 'map(select(.message.role)) | .[-5:] | .[] | "\n" + (.message.role | ascii_upcase) + ":\n" + (.message.content | map(select(.text) | .text | .[0:400]) | join("\n"))'
```

### 5. **Provide Summary**

Present a formatted summary showing:
- ✅ Project directory name
- 📁 Previous conversation file path
- 📊 File size and message count
- 🕒 Last modified timestamp
- 🔍 Preview of first and last messages
- 💡 Summary of what was being worked on
- 📋 Next steps for the user

## IMPORTANT IMPLEMENTATION NOTES:

1. **Don't use subshells with $()** - They cause zsh parsing errors. Run commands separately and use the results.
2. **Skip the current conversation** - Use `head -2 | tail -1` to get the SECOND most recent file
3. **Extract text carefully** - Use jq to parse the JSONL and extract readable message text
4. **Handle errors gracefully** - If no previous conversation exists, inform the user clearly
5. **Be concise** - Summarize the conversation focus, don't dump raw data

## EXECUTION WORKFLOW:

When executing this command, follow these steps IN ORDER:

1. Run Step 1b to find the project directory
2. Use that directory path in Step 2 to find the previous conversation file
3. Use that file path in Steps 3-5 to extract and display metadata
4. Parse the message content and provide a human-readable summary
5. Don't just dump tool outputs - analyze and summarize what the user was working on

## OUTPUT FORMAT:

Present a clean summary like:

```
✅ PREVIOUS CONVERSATION LOADED

📁 File: [filename]
📊 Size: [size] | Messages: [count]
🕒 Last Activity: [timestamp]

🔍 CONVERSATION SUMMARY:
[Brief description of what was being worked on based on first/last messages]

💡 HOW TO CONTINUE:
You can now ask follow-up questions or continue working on [topic].
```

Execute these steps using the Bash tool, parse the results, and present a user-friendly summary.
