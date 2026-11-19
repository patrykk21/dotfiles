---
name: explain-simply
description: |
  Rewrites an explanation, summary, report, PR, concept, or error so a
  competent engineer who is new to this project or field can follow it,
  defining only the project-internal and field-specific terms (not standard
  industry vocabulary). ALWAYS-ON (user mandate 2026-07-15): apply these rules
  by default to every human-facing surface — chat summaries and status
  updates, GitHub PR replies/descriptions/comments, Jira comments and
  tickets, Confluence/Google Docs, and reports — not only when explicitly
  invoked. DEPTH ON REQUEST (user mandate 2026-09-17): the first answer is
  always high-level with NO code references; file paths, line numbers,
  function names and snippets are held back until the user asks to go
  deeper. ALSO covers code comments and commit messages (user mandate
  2026-07-27), which follow the leaner register in "Code comments & commit
  messages" below — same clarity goal, no summary sentence or glossary.
  Explicit invocation remains for "too much jargon", "re-explain this",
  "what does this term mean here".
targets: [claude]
tags: [communication, explanations]
license: MIT
metadata:
  author: vigenerr
  version: 3.0.0
---

# Explain Simply

Make a dense or jargon-heavy explanation followable by a skilled engineer who happens to be new to *this* project and *this* field — without dumbing it down or announcing that you're doing so.

## Depth on request (user mandate 2026-09-17)

**The first answer is always high-level and carries no code references.** Depth is something the reader pulls, not something you push.

The reason is collaboration, not brevity. An explanation that opens with file paths and line numbers forces the reader to evaluate the mechanism before they have agreed on the point. They cannot tell you "you're solving the wrong problem" because they are still parsing `foo.ts:143`. Leading with the conclusion lets them redirect you in one sentence.

### The three layers

| Layer | Contains | When |
|---|---|---|
| **L1 — What and why** | The situation, the consequence, the decision at stake, who it affects. Prose only. | **Always. This is the default answer.** |
| **L2 — How it works** | Named components and the flow between them. Still no paths, no line numbers, no snippets. | Reader asks "how does that work" / "walk me through it". |
| **L3 — The code** | `file.ts:line`, function names, snippets, diffs. | Reader asks to go deeper, or is about to change the code. |

Most questions end at L1. That is success, not an incomplete answer.

### What L1 must NOT contain

- File paths or line numbers (`libs/web/core/src/hooks/use-open-in-app/get-one-link.tsx:106`)
- Function, class, constant, or type names (`isAppExclusiveMerchantPersona`, `APP_EXCLUSIVE_TAGS`)
- Code blocks or inline code spans quoting implementation
- Directory structure, module layout, import graphs
- Config key names, unless the key *is* the subject the reader asked about

Identifiers from the **problem domain** are fine and often necessary — a ticket key, a deal tag the business uses, a campaign parameter named in a spec. The test is whether the reader needs a repo open to make sense of it. If yes, it's L2 or L3.

### Staying accurate without code references

The always-on rule requires every claim be traceable. At L1 you trace to **observed behaviour and named artifacts**, not to source:

- ❌ "`badges.ts:329` gates it behind `isMobileAppRequest`"
- ✅ "That badge only renders for app requests, so on the website it does nothing today"

Both are checkable. The second doesn't require the reader to open anything. Never drop a claim just because you can't cite a line at L1 — restate it as the behaviour the line produces.

### Offering the next layer

End with a specific pointer at what the deeper layer holds, not a generic offer. "Let me know if you want more detail" is noise. "The reason it survives testing is in how the parameters resolve — say the word and I'll walk through it" tells the reader what they'd be buying.

One pointer, one line. Don't enumerate every possible follow-up.

### When to go straight to code

Skip the layering when the reader has already asked for it:

- They named a file, function, or symbol in their question
- They asked "where is X" / "which file" / "show me"
- The artifact **is** code — a comment, a commit message, a review reply anchored to a diff line
- They asked you to verify a claim about the code (the evidence *is* the answer)

A follow-up question about your earlier explanation is not automatically a request for code. "Why does that happen?" usually wants L2.

**Jira comments and ticket descriptions are NOT an exception** (user correction 2026-09-17). They stay
high-level like everything else: state the risk, the consequence, and the decision it forces. Do not
reach for identifiers on the grounds that "an engineer will read this" or "they're about to change the
code" — that reasoning turns every ticket into L3 and was the exact mistake this note records. Domain
identifiers the ticket itself already uses (a deal tag, a flag name, a campaign value from the spec)
are fine; repo identifiers are not.

## Always-on enforcement (user mandate 2026-07-15)

This skill is not opt-in. Its rules apply BY DEFAULT to **every human-facing surface** written in a session:

- chat replies, summaries, status updates, wrap-ups
- GitHub: PR descriptions, review replies, issue comments
- Jira: comments, ticket descriptions
- Confluence pages, Google Docs, uploaded reports (e.g. an internal reports portal)
- **code comments and commit messages** (user mandate 2026-07-27) — a leaner register: see "Code comments & commit messages" below

Before sending anything on these surfaces, run Step 4 (the re-read check) on it. The recurring failure modes that triggered the mandate: inverted/nested sentences that describe code less clearly than the code itself, truth-table jargon in review replies, and stringing three project terms into one clause without saying what happens in plain words. If a sentence needs the reader to already hold the whole system in their head, rewrite it as two shorter causal sentences ("X does A. Without B, that would break C.").

**Subagent-authored text is NOT exempt.** Subagents don't inherit rules, so text they produce (e.g. review-team findings in `/review`) reaches these surfaces only through the orchestrating session — which must include the plain-language instruction in agent prompts and run Step 4 on every body before posting, rewriting rather than relaying verbatim. Full propagation protocol: `~/.claude/rules/plain-language.md`.

## Important

- **Lead high-level, hold the code back.** See "Depth on request" above — this is the first thing to get right, because it decides the shape of the whole answer.
- **Assume industry fluency. Never define standard vocabulary.** The reader is a working engineer. Do not gloss PR, commit, merge, rebase, draft, API, endpoint, UUID, cache, deploy, repo, backend/frontend, dead code, etc. Explaining what they already know is the fastest way to make them feel talked down to.
- **Gloss only the genuinely unfamiliar:** project- or system-internal names (and their role here), field/domain-specific terms that aren't general dev knowledge, and truly obscure acronyms. Test: *would a competent engineer who's never seen this project already know it?* If yes, leave it plain.
- **Never label the register.** No "explained simply", "in plain terms", "put simply", "plainly", "in a nutshell", or a "What this means for you" heading. Clarity is shown, not announced — labeling it insults the reader.
- **Analogies sparingly** — only for a genuinely non-obvious idea, not as decoration on every item.
- **Accuracy beats simplicity.** Never simplify into something wrong; keep the real terms and pair the unfamiliar ones with their meaning. Dropping to L1 removes code references, never correctness.

## Instructions

### Step 1: Identify the target
Decide what to clarify: your previous message, a report/doc, a named concept, a PR/diff, or an error. If it's ambiguous which, ask one short question first.

### Step 2: Pick the layer, then the terms
First decide the layer. Default is L1 unless the reader has already asked for depth (see "When to go straight to code").

Then list only the terms a competent engineer *new to this project/field* wouldn't know — internal system/service names, domain jargon, obscure acronyms. Explicitly discard standard industry vocabulary from this list. At L1, discard code identifiers too.

### Step 3: Write it
- **Lead with a one- or two-sentence summary** of the whole thing — just the sentence, no label.
- Explain in clear prose, one idea per sentence. Gloss each unfamiliar term inline the first time (a clause naming the term *and its role*), and name the "so what" — why it matters. Add an analogy only where the idea is genuinely hard.
- Investigation may have been deep; the answer still starts at L1. Research effort is not a reason to raise the layer.
- If several project/field terms recur, end with a short **glossary of only those terms** (`name → role/meaning + brief example`). Never list standard vocabulary there.
- Close with one specific pointer at the next layer, if there is one worth pulling.

### Step 4: Check it
Re-read as a sharp engineer seeing this project for the first time.

- **Layer check first:** scan for file paths, line numbers, and code identifiers. If the reader didn't ask for depth, every one of them is a defect. Convert each to the behaviour it produces, or cut it.
- Cut every sentence that explains something they'd already know.
- Delete any "simply/plainly" self-labeling.
- Confirm you didn't distort a real term while shortening it.
- Confirm every remaining claim is still traceable — to observed behaviour at L1, to source at L3.

## Examples

### Example 1: "this report is too jargony, redo it"
Rewrite it keeping all standard terms as-is, glossing only the internal names and field terms, with no "plain version" labeling and a small glossary of just the project-specific terms.

### Example 2: "what does 'rank profile' mean here?"
Answer in this project's context: "a named ranking formula inside Lodestar (the search engine) — it decides the order results come back in. Here, each carousel points at a different one so the discount row and the nearby row rank differently." No analogy needed unless it's still unclear.

### Example 3: over-explained draft
If a draft defines PR, merge, or API, strip those definitions and keep only the glosses for internal systems (Feedwise, Lodestar, helix-go, storefront-web…).

### Example 4: same finding at L1 and L3

A review found that a feature could be wired to the wrong deal tag.

**L1 (the default answer):**

> There's already a helper named for exactly this feature, but it points at the old tag — the one the ticket says must no longer drive this behaviour. Anyone searching for the obvious name finds it and wires it up, and everything looks consistent. That would flip 40 live deals to app-only, which is precisely what the ticket's last acceptance criterion forbids.
>
> The reason it looks correct right up until it ships is worth a walkthrough if you want it.

**L3 (only after the reader asks):**

> `libs/gql-shared/src/constants/merchandising-tags.ts:1` still binds `APP_EXCLUSIVE_TAGS` to `acme-deals-8345`, and `is-app-exclusive.ts:5` exports `isAppExclusiveMerchantPersona` over it…

Same finding, same accuracy. L1 is enough to decide what to do about it — which is the point.

## Code comments & commit messages

Same goal — a reader new to this project can follow it — but a **leaner register** than prose. Do NOT lead with a summary sentence, and never add a glossary here. Write the fewest words that carry meaning; the code and the diff are already on the page.

The L1/L2/L3 layering does **not** apply here. These artifacts live in the code, so naming code is correct. What still applies: gloss project-internal names, never standard ones, and keep it to the fewest lines that state the constraint.

**Code comments.**
- The code is self-describing. Add a comment only for a **constraint the code cannot express** — a *why*, an invariant, an ordering requirement, a non-obvious edge case, a "looks wrong but is intentional".
- Delete comments that restate the name or the next line (`// increment i` over `i++`; `// the sponsored handler` over `homepageSponsoredHandler`).
- Describe *this* code's behavior, not another system's internals. No cross-service implementation claims ("the downstream searcher clamps this"), and no Jira/ticket IDs in comments — only `TODO(TICKET)` where the project explicitly allows it.
- Trim multi-line blocks to their load-bearing point. One sharp sentence beats four that circle it.

**Commit messages.**
- Subject: imperative and concrete — what changed and where (`Fail closed the homepage sponsored row when the gate is off`), not a bare `[TICKET]` or a vague `fix stuff`.
- Body (only when the *why* isn't obvious from the subject): short causal sentences — the same "X does A; without B that breaks C" shape as prose, one idea per line. Say why, and any non-obvious consequence.
- Someone skimming `git log` should understand the change without opening the diff.

## When NOT to Use

- The reader wants the terse, maximally technical version, or is clearly expert in this exact area and asked for depth.
- When the text is already at the right level — don't rewrite just to add a summary or glossary. (And never add a summary or glossary to a code comment or commit message — those use the leaner register above.)
- Never as a reason to define standard industry vocabulary; that is the failure mode this skill exists to avoid.
- Never as a reason to withhold a finding. Depth on request governs *how much mechanism* an answer carries, never *whether* the reader is told something matters.
