---
description: "Record an accomplishment for your engineering review brag book"
allowed-tools: ["Read", "Write", "Edit", "AskUserQuestion", "Bash"]
---

# Brag Book - Record Your Accomplishments

You are helping the user build a "brag book" — a running list of professional accomplishments to reference during their engineering performance review.

## INPUT

The user has provided: $ARGUMENTS

If no arguments were provided, ask the user: "What accomplishment do you want to record?"

## WORKFLOW

### Step 1: Understand the accomplishment

Read the user's input. If it's vague or short, ask 1-2 clarifying questions to understand:
- What exactly they did
- What the impact was (business, team, technical)

### Step 2: Ask for supporting evidence

Use AskUserQuestion to ask for any supporting proof they can provide. Examples:
- Links to PRs, tickets, dashboards, docs
- Metrics or numbers (% improvement, users affected, time saved, revenue impact)
- Teammates who can vouch / were involved
- Before/after comparisons

The user can skip this if they don't have evidence handy.

### Step 3: Rewrite the accomplishment

Transform the user's raw input into a polished, impact-focused bullet point suitable for a performance review. Follow the **X-Y-Z formula**:

> "Accomplished [X] as measured by [Y], by doing [Z]"

Write it in first person, professional tone. Be specific and quantitative where possible. Avoid fluff words. Make it sound impressive but honest.

### Step 4: Get approval

Show the rewritten version to the user and ask if they want to edit it or if it looks good.

### Step 5: Store the entry

The brag book file lives at: `~/.claude/brag-book.md`

Read the file first (create it if it doesn't exist). Then append the new entry in this format:

```markdown
### [DATE] — [Short Title]

[Polished accomplishment statement]

**Evidence:**
- [link or metric 1]
- [link or metric 2]

---
```

Use today's date (YYYY-MM-DD format) from the environment.

If the file doesn't exist yet, create it with this header:

```markdown
# Brag Book

A running record of professional accomplishments for performance reviews.

---

```

Then append the entry after the header.

### Step 6: Confirm

Tell the user the entry has been saved. Show the final entry. Remind them they can run `/brag-book` anytime to add more, or read `~/.claude/brag-book.md` to review all entries.

## GUIDELINES

- Keep the tone professional but not robotic
- Prioritize measurable impact over activity descriptions
- "Led", "Drove", "Delivered", "Reduced", "Improved" are strong action verbs
- Don't oversell — keep it honest and credible
- Each entry should be concise (2-4 sentences max for the main statement)
- If the user provides multiple accomplishments, process them one at a time
