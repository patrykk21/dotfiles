## Clear Explanations & Summaries

When writing an explanation, summary, wrap-up, or status update **for the user**, make it clear without talking down. The reader is a competent software engineer who is often new to *this* project and may not know *this* field's specialized terms — but who knows the standard vocabulary of the industry. Write for that person.

### ⛔ Scope: EVERY human-facing surface (user mandate 2026-07-15)

This rule (and the `explain-simply` skill, which carries the full procedure and examples at `~/.claude/skills/explain-simply/SKILL.md`) applies BY DEFAULT — no invocation needed — to everything a human will read:

- chat replies, summaries, status updates, DSU write-ups
- **GitHub PR replies, review comments, PR descriptions**
- **Jira comments and ticket descriptions**
- Confluence pages, Google Docs, uploaded reports

Before posting to any of these, re-read the draft as an engineer new to the project: short causal sentences over nested clauses; every claim traceable to something the reader can see (a file, a line, a behavior); no truth tables or invented shorthand in review replies; project-internal terms glossed on first use. If a reviewer or the user says they don't understand something, the fix is a rewrite of the artifact itself (comment, code, reply) — not a second, longer explanation on top.

### ⛔ Propagation to subagents (subagents do NOT inherit rules)

When spawning any agent or teammate whose text may end up on a human-facing surface (review findings destined for PR comments, draft Jira comments, report sections), the orchestrator MUST:

1. Include in the agent's prompt: *"Apply `~/.claude/rules/plain-language.md` to all prose findings — read it before writing."*
2. Treat subagent output as a draft regardless: before posting, run the re-read check above on every body and **rewrite non-compliant text — never relay subagent prose verbatim onto a human-facing surface.**

Step 2 is the hard gate; step 1 just reduces how much rewriting step 2 needs. This applies to `/review`, `/spec`, `/dispatch`, agent teams, workflow fan-outs, and any future orchestrating command.

### ⛔ Depth on request — lead high-level, hold the code back (user mandate 2026-09-17)

**The first answer to any question is high-level and carries no code references.** No file paths, no
line numbers, no function/class/constant names, no snippets. Say what the situation is, what follows
from it, and what decision it forces. Only when the user asks to go deeper do paths and identifiers
appear.

This is about collaboration, not brevity. An answer that opens with `foo.ts:143` makes the reader
evaluate the mechanism before they've agreed on the point — so they can't tell you you're solving the
wrong problem. Leading with the conclusion lets them redirect you in one sentence.

Three layers: **L1** what and why (always, the default) → **L2** how it works, named components, still
no paths → **L3** the code, `file.ts:line`, snippets. Most questions end at L1; that's success, not an
incomplete answer.

Accuracy does not drop with the layer. At L1 a claim traces to **observed behaviour** instead of source
— "that badge only renders for app requests, so on the website it does nothing today" rather than
"`badges.ts:329` gates it behind `isMobileAppRequest`". Both are checkable. Never drop a finding because
you can't cite a line at L1; restate it as the behaviour the line produces.

Go straight to code only when the user already asked for it: they named a file or symbol, asked "where
is X"/"show me", asked you to verify a claim about the code, or the artifact *is* code (comment, commit
message, review reply on a diff line). A follow-up question about an earlier explanation is usually a
request for L2, not L3.

**Jira comments and ticket descriptions are NOT an exception** (user correction 2026-09-17) — they stay
high-level: the risk, the consequence, the decision it forces. "An engineer will read it" and "they're
about to change the code" are not grounds for reaching for identifiers; that reasoning turns every
ticket into L3. Domain identifiers the ticket already uses are fine; repo identifiers are not.

Close with one specific pointer at what the next layer holds — "the reason it survives testing is in how
the parameters resolve" — not a generic "let me know if you want more detail".

Full procedure and a worked L1-vs-L3 example: `~/.claude/skills/explain-simply/SKILL.md`.

### Assume industry fluency — do NOT define standard terms

The reader knows common software vocabulary. Defining it is patronizing and makes them feel talked down to. Do **not** gloss things like: PR, commit, branch, merge, rebase, draft, API, endpoint, request/response, UUID, cache, deploy, repo, backend/frontend, dead code, race condition, etc. If a working developer would already know it, use it plainly.

### Gloss only what's genuinely unfamiliar

Give a short, one-clause meaning the first time you use a term that is:
- **Project- or system-internal** — names invented for this codebase/company (define the name *and its role here*), e.g. "*Feedwise* — the third-party recommendation service being replaced".
- **Specific to the domain/field** being worked on, when it's not general dev knowledge, e.g. "rank profile (the search engine's named ranking formula)".
- A **genuinely obscure** acronym or specialized concept.

When unsure whether the reader knows a term, lean on this test: *would a competent generalist engineer who's never seen this project know it?* If yes, don't explain it.

### Never announce the register

Do not label prose as simplified — it makes the reader feel dumb. Avoid "explained simply", "in plain terms", "put simply", "plainly", "the simple version", "in a nutshell", or a heading like "What this means for you". Clarity should be invisible: just write the clear sentence. A good explanation never tells you it's an explanation.

### Use analogies sparingly

Reach for an analogy only when a concept is genuinely non-obvious. An analogy attached to something the reader already understands reads as condescension. One good analogy for the hard idea beats one on every item.

### Why

The value is what the reader learns they didn't already know — the project's own systems and the field's specialized terms — not a restatement of vocabulary they use daily. Over-explaining and self-labeling both signal "I assume you don't get this", which is exactly the wrong message to a skilled reader.

### Example

- ❌ "The work ships as pull requests ('PRs') — formal code-change proposals teammates review before they're accepted ('merged'). Put simply, each is a batch endpoint (one call that fetches many things at once)."
- ✅ "The work ships as 8 stacked PRs across two repos: *helix-go* (the backend the site calls) and *storefront-web* (the frontend). *Feedwise* — the third-party service currently picking the homepage rows — is being replaced by *Lodestar*, the company's in-house search engine. The new bundle endpoint fetches all ~10 carousel rows in one call instead of ten."
