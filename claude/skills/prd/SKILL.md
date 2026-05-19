---
name: prd
description: "Generate Product Requirements Documents with optional research — brainstorm, challenge assumptions, define scope"
argument-hint: "<idea or feature description>"
user-invocable: true
model: opus[1m]
---

# /prd - Generate Product Requirements Documents

<HARD-GATE>
Do NOT invoke `/spec`, `/spec-plan`, `/spec-implement`, write any code, scaffold any project, or take any implementation action until you have written a PRD and the user has approved it. This applies to EVERY idea regardless of perceived simplicity.

`/prd`'s output is a written PRD at the path determined in Step 6 (write-prd). The terminal state is offering hand-off to `/spec` and waiting for the user. The skill does not invoke implementation skills directly.
</HARD-GATE>

**Strategic thought partner and brainstorming surface** — turns vague ideas into concrete Product Requirements Documents (PRDs) through one-on-one conversation, with optional research. Produces a PRD that can be handed off directly to `/spec` for implementation.

**Use `/prd` when:**
- You have an idea but aren't ready to spec it
- Requirements are unclear or you only have a problem statement, not a solution
- You want to **brainstorm back-and-forth** before locking anything down — pitch ideas, react, refine, then converge
- You need to explore trade-offs, challenge assumptions, or define scope before committing to a plan

**Use `/spec` instead when:** Requirements are well-defined. You know what to build and roughly how. Skip straight to technical planning.

`/prd` and `/spec` are designed to chain: `/prd` produces the requirements doc, then offers to hand off to `/spec` for implementation.

---

## Workflow

```
Understand → Research (optional) → Ideate (if vague) → Clarify → Propose → Converge → Write PRD → Hand off to /spec
```

**Two modes inside one flow:**
- **Divergent (Ideate):** free-form prose, Claude pitches directions, user reacts. Used when the idea is vague.
- **Convergent (Clarify → Converge):** structured `AskUserQuestion` forms with predefined options. Used once the shape is known.

The phase boundary is a default, not a wall — Clarify can drop back into 1-2 prose turns when a question opens a genuinely new unknown, then return to structured forms.

The entire flow is conversational. One question at a time. No rushing to solutions.

## Step 1: Understand the Idea

1. **Restate the idea** in your own words — confirm you understand what the user is thinking
2. **Explore the project context with CodeGraph** — start with `codegraph_context(task="<idea description>")` to discover relevant entry points, symbols, and existing code. Use `codegraph_search` + `codegraph_explore` for deeper understanding of specific areas. Use `codegraph_files` to understand project structure. Check docs and recent commits for additional context.
3. **Identify the core problem** — what problem does this solve? For whom? Why now?
4. **Scope check — is this one PRD, or several?** If the request spans multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag it now. Do not spend the rest of the workflow refining details of a project that needs to be split first.

   When the project is too large for a single PRD, help the user decompose:
   - List the independent pieces and how they relate
   - Suggest a build order (what unblocks what)
   - Pick **one** sub-project to PRD now — the rest become follow-up PRDs

   Use `AskUserQuestion` to confirm the chosen sub-project before continuing.

Do NOT jump to solutions. Understand the problem space first.

## Step 2: Research (Optional)

**After understanding the idea, ask the user which research tier they want.** Use `AskUserQuestion` with these options:

- **Quick (Recommended for simple ideas)** — "Skip research, go straight to brainstorming or clarification"
- **Standard** — "Quick web research: competitors, prior art, best practices (5-10 searches)"
- **Deep** — "Thorough parallel research: multiple angles, comprehensive findings (uses sub-agents, higher token cost)"

### Quick Tier

Skip this phase entirely. Proceed to Step 4.

### Standard Tier

1. **Generate 5-8 search queries** based on the topic:
   - Competitor/alternative analysis ("alternatives to X", "X vs Y")
   - Prior art and existing solutions ("how companies solve X")
   - Technical approaches ("best practices for X")
   - User experience patterns ("UX patterns for X")
2. **Discover web-search tool:** `ToolSearch(query="+web-search search")`
3. **Execute searches sequentially**, gathering key findings from each
4. **Optionally fetch full pages** for promising results: `ToolSearch(query="+web-fetch fetch")` then `fetch_url(url="...")`
5. **Compile research summary:**
   - Key findings (3-5 bullet points)
   - Sources with links
   - Trade-offs and patterns discovered
   - Gaps or areas needing more exploration
6. **Present summary to user** before proceeding to ideation (Step 3) or clarification (Step 4)

### Deep Tier

1. **Generate a research outline** with 3-5 research angles based on the topic. Examples:
   - "Competitor landscape" — what exists, market positioning, pricing
   - "Technical approaches" — architectures, frameworks, implementation patterns
   - "User experience" — UX patterns, onboarding flows, common pain points
   - "Prior art" — academic papers, blog posts, case studies
2. **Launch 2-4 web-search-agent sub-agents in parallel:**

   For each research angle:
   ```
   Agent(
     subagent_type="web-search-agent",
     run_in_background=true,
     prompt="Research angle: <angle_name>\n\nTopic: <user_topic>\n\nFocus on: <specific questions for this angle>\n\nReturn findings in this format:\n## <Angle Name>\n### Key Findings\n- ...\n### Sources\n- [Link](url)\n### Trade-offs & Considerations\n- ...\n\nWrite your findings to: <output_path>"
   )
   ```

   Output path: `/tmp/prd-research-<angle-slug>.md`

3. **Wait for all agents to complete** (bash polling):
   ```bash
   for i in $(seq 1 120); do
     COUNT=$(ls /tmp/prd-research-*.md 2>/dev/null | wc -l)
     [ "$COUNT" -ge <expected_count> ] && echo "ALL_DONE" && break
     sleep 2
   done
   ```
4. **Read all output files** and synthesize into a comprehensive research summary
5. **Present synthesized findings to user** — organized by angle, with key insights highlighted
6. **Clean up temp files:** `rm -f /tmp/prd-research-*.md`

**Cap:** Maximum 4 parallel agents, each limited to 5 search queries.

### Research Output

When research was performed (Standard or Deep), the findings are embedded in the PRD under a `## Research Findings` section after Key Decisions.

## Step 3: Ideate (Optional — Skip if Concrete)

**Purpose:** When the input is vague ("I want better onboarding", "something for team updates"), riff with the user before locking into structured questions. This is the divergent phase — generate, react, refine.

**⛔ Skip this step entirely when:**
- The user's input already names a concrete thing to build ("Add OAuth login with Google", "Migrate the worker from cron to BullMQ")
- Step 1 found existing code that clearly answers what's being built
- Research (Step 2) already produced a chosen direction

**Run this step when:**
- The idea is a problem statement, not a solution ("users drop off after signup")
- The user used hedging language ("maybe", "something like", "I'm thinking")
- Multiple obviously-different shapes could satisfy the request

### How to Run It

Free-form prose, **no `AskUserQuestion`**. Each round:

1. **Pitch 3-5 directions.** Short, distinct angles — not variations of the same idea. Lead with one-line summaries; expand only on request. Example:
   > "A few directions I see for 'better onboarding':
   > - **Reduce surface area** — cut the signup form to email-only, defer everything else to first use
   > - **Guided first-run** — keep signup as-is, add a 3-step product tour after first login
   > - **Pre-fill from context** — detect the user's company/role from email domain, skip questions we can infer
   > - **Async setup** — let users start using the product immediately, complete profile in the background
   >
   > Which of these resonate, or where am I off?"

2. **Pressure-test what they pick.** When the user reacts, push back: where does this break? What does it cost? What did they implicitly assume? Surface the failure modes before they get baked in.

3. **Generate next round from their reaction.** Their answer reshapes the next pitch — don't run a fixed checklist. If they reject all 5 directions, ask what's missing rather than pitching 5 more.

4. **Stop when shape emerges.** Usually 1-3 rounds. The signal: the user starts saying "yes, and..." instead of "no, but...". When you can write a one-sentence summary of what they want and they nod, move on.

### Hand-off

End the ideation phase with an explicit transition:

> "OK, so we're building **<one-sentence summary>**. Switching to structured questions to nail down the details."

Then proceed to Step 4 (Clarify) with `AskUserQuestion`.

### Anti-Patterns

- **Pretending to ideate when the user already decided.** If they said "add Google OAuth", do not pitch alternatives — go to clarify.
- **Pitching variations of one idea.** Five flavors of "add a tour" is one idea, not five.
- **Endless rounds.** If round 3 hasn't converged, the problem is probably under-defined — ask the user what success looks like before pitching again.
- **Using `AskUserQuestion` here.** Structured forms collapse divergent thinking. Save them for Step 4.

## Step 4: Ask Clarifying Questions

**⛔ ALWAYS use the `AskUserQuestion` tool** — never list numbered questions in plain text. Each question gets its own entry with 2-4 predefined options users can select. This provides a structured form UI that is much easier to answer than freeform text.

**One question at a time, building on previous answers.** Each `AskUserQuestion` call focuses on a single decision point, and the next question must follow from what the user just said — not from a fixed checklist. If the user's answer exposes a new assumption or constraint, pivot there instead of marching through pre-planned topics.

**⛔ Skip obvious questions.** Do not ask anything already answered by the one-line idea, the codebase exploration in Step 1, or earlier answers in this conversation. The goal is to surface what the user hasn't thought about yet, not to collect a standard intake form.

**⛔ Code-first rule.** Before each question, ask "can the codebase answer this?" If yes — read the code. Use `codegraph_context`, `codegraph_search`, `codegraph_explore`, or Semble to resolve "how does X currently work / where does Y live / what's the existing pattern for Z". Only ask the user about things code can't tell you: purpose, priorities, audience, constraints, scope boundaries, behavioural expectations not yet encoded. Asking the user about facts the code already encodes wastes their time and signals you didn't explore.

Coverage areas (ask only where genuinely unclear):
- **Purpose** — what's the core outcome the user wants?
- **Users** — who benefits from this? What's their workflow today?
- **Constraints** — timeline, technical limitations, existing architecture
- **Success criteria** — how will we know this works?
- **Scope boundaries** — what's explicitly NOT included?

**Question format:** Every question must have 2-4 concrete options with trade-offs. Use `multiSelect: true` when choices aren't mutually exclusive. Include an "Other" option when the user might have a direction you haven't considered.

**Per-question mode flexibility — slip into prose when needed.** Default is structured `AskUserQuestion`. But if the user's last answer opens a new unknown that doesn't have 2-4 obvious options yet — or if their answer is a question back to you ("what would you do here?") — drop into 1-2 prose turns to explore it (Ideate-style), then return to structured questions for the next decision point. The phase boundary between Ideate and Clarify is a default, not a wall. Don't force four options onto a question that genuinely needs open-ended exploration; equally, don't drift into endless prose when the next decision is a clean A/B/C choice.

**Principles:**
- Challenge assumptions — "You mentioned X. Have you considered Y?"
- Surface trade-offs — "That's possible, but it comes at the cost of Z"
- Be constructive but strategic — don't be a yes-man
- If the idea has red flags or scope creep risks, raise them now
- Typically 3-6 questions total, depending on complexity — stop asking once you have 90% of the spec

## Step 5: Propose Approaches

**Not the same as Step 3 (Ideate).** Ideate is divergent — pitching distinct *directions* when the problem itself is vague. Propose is convergent — once the problem is clear, pitching 2-3 concrete *implementation approaches* for that known problem. If you already did Ideate and the user picked a direction, Step 5 narrows that direction into approaches. If the input was concrete and you skipped Ideate, Step 5 is the first place options get presented.

After understanding the problem:

1. **Propose 2-3 approaches** with clear trade-offs
2. **Lead with your recommendation** and explain why
3. **Present approaches as context**, then use `AskUserQuestion` for selection
4. **Get the user's choice** before proceeding

Each approach should have:
- A short name
- How it works (2-3 sentences)
- Trade-offs framed as "X at the cost of Y"

**Selection:** After presenting approaches in text, use `AskUserQuestion` with each approach as an option. Mark your recommended approach clearly. The user selects — don't proceed without a choice.

## Step 6: Converge on Scope

Based on the chosen approach:

1. **State what's in scope** — concrete deliverables
2. **State what's explicitly out** — and why (prevent scope creep later)
3. **Identify the core user flows** — step by step from the user's perspective
4. **Note any technical context** that `/spec` will need — constraints, integration points, existing patterns

**Confirm scope with `AskUserQuestion`:**
- "Yes, scope looks right — proceed to PRD"
- "No, I want to adjust scope" — let me specify what to add/remove
- "Let's discuss further" — I have questions about the scope

## Step 7: Write the PRD

**Save to:** `docs/prd/YYYY-MM-DD-<slug>.md`

Generate the filename from the first 3-4 words of the idea (lowercase, hyphens). Create the `docs/prd/` directory if it doesn't exist:

```bash
mkdir -p docs/prd
```

### PRD Format

```markdown
# [Feature Name]

Created: YYYY-MM-DD
Author: [user email from pilot status]
Category: [one of: Feature, Infrastructure, UX, API, Performance, Security, Documentation, Integration]
Status: Draft
Research: [Quick | Standard | Deep | None]

## Problem Statement

[Concise paragraph: what problem, for whom, why now. This is the north star.]

## Core User Flows

[Step-by-step from the user's perspective. How does the primary user accomplish the core outcome?]

### Flow 1: [Name]
1. User does X
2. System responds with Y
3. ...

### Flow 2: [Name] (if applicable)
1. ...

## Scope

### In Scope
- [Concrete deliverable 1]
- [Concrete deliverable 2]

### Explicitly Out of Scope
- [What's excluded] — [why]
- [What's excluded] — [why]

## Technical Context

[Lightweight technical notes for the implementer. NOT a full technical design — that's /spec's job.]

- **Relevant architecture:** [existing patterns, integration points]
- **Constraints:** [technical limitations, dependencies]
- **Existing code:** [files/modules that relate to this feature]

## Key Decisions

[Trade-offs and decisions made during the conversation, with reasoning.]

| Decision | Choice | Why |
|----------|--------|-----|
| [What was decided] | [The choice] | [Reasoning] |
```

**Fetch author email** (best-effort):

```bash
~/.pilot/bin/pilot status --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('email',''))" 2>/dev/null
```

If the command returns a non-empty email, include `Author: <email>` in the header. If empty or fails, omit the Author line.

**Category selection:** During the conversation (Step 4 or Step 6), use `AskUserQuestion` to select the PRD category from the fixed set: Feature, Infrastructure, UX, API, Performance, Security, Documentation, Integration.

After writing:

1. **Self-review (4-point scan)** — read the file with fresh eyes and fix issues inline:
   - **Placeholders:** any `TBD`, `TODO`, bracketed `[...]` left from the template, or vague "etc." lists?
   - **Internal consistency:** do scope, user flows, and decisions agree with each other? Does anything contradict?
   - **Scope:** focused enough for one `/spec` plan, or did decomposition slip? If it grew during writing, split or trim.
   - **Ambiguity:** could any requirement be read two different ways? Pick one and make it explicit.

   **Calibration — only flag what would actually cause problems during `/spec`.** A missing section, a contradiction, or a requirement so ambiguous it could be built two different ways → fix it. Minor wording improvements, stylistic preferences, sections that are less detailed than others, or "this paragraph could be tighter" → leave it alone. The goal is a PRD that produces a correct plan, not a perfect document.

2. **Tell the user the file is ready and ask them to read it.** Do NOT jump straight to a confirmation form — give them a chance to actually open the file first:

   > "PRD written to `docs/prd/YYYY-MM-DD-<slug>.md`. Please open it in your editor and read it through, then let me know if anything needs to change before we hand off to `/spec`."

   Wait for the user's response. They may reply with edits in chat ("change scope item 3 to ...") or confirm it's good.

3. **Apply any requested changes** with `Edit` directly on the file — don't rewrite the whole document. Then re-run the 4-point scan and ask the user to re-read **only the changed sections**.

4. **Set Status to Final** once the user approves.

5. **Confirm next step with `AskUserQuestion`:**
   - "Looks good — proceed to handoff" — PRD is ready
   - "I want to adjust something else" — let me specify changes
   - "Start over on a section" — a section needs rethinking

## Step 8: Hand Off to /spec

After the user confirms the PRD:

**Ask:** "Ready to hand this off to `/spec` for implementation planning?"

Use `AskUserQuestion` with options:
- **"Yes, start /spec now"** — invoke `/spec` immediately
- **"No, I'll run /spec later"** — just confirm the PRD path

### If yes — invoke /spec:

```
Skill('spec', args='<one-line-summary> — PRD: docs/prd/YYYY-MM-DD-slug.md — see PRD for full requirements')
```

**The args string must NOT end in `.md`** — the trailing text after the path prevents the `/spec` dispatcher from treating it as an existing plan file. The dispatcher only triggers plan-file mode when args end with `.md` AND the file exists.

### If no:

```
PRD saved to docs/prd/YYYY-MM-DD-slug.md

To implement later, run:
  /spec "Implement <summary> — PRD: docs/prd/YYYY-MM-DD-slug.md — see PRD for full requirements"
```

## Step 9: Anti-Patterns

- **Defaulting to free-form questions during the convergent phase** — once you're in Clarify/Converge (Step 4 onward), `AskUserQuestion` with predefined options is the default. Brief prose riffs are allowed when a question opens a genuinely new unknown (see Step 4), but don't drift back into open-ended chat for decisions that have a clean A/B/C shape.
- **Skipping ideation when the idea is vague** — if the user gave a problem statement instead of a solution, don't jump straight to structured questions. Brainstorm in prose first (Step 3).
- **Pretending to ideate when the user already decided** — if the input is concrete, skip Step 3. Don't pitch alternatives the user didn't ask for.
- **Rewriting the whole PRD when the user requests changes** — use `Edit` on specific sections so the user doesn't have to reload the file in their editor and re-read everything.
- **Rushing to solutions** — understand the problem first, always
- **Asking too many questions at once** — one at a time, each building on the last
- **Being a yes-man** — challenge assumptions, surface trade-offs
- **Over-specifying technically** — the PRD describes WHAT and WHY, `/spec` handles HOW
- **Skipping the conversation entirely** — even "simple" features benefit from 2-3 clarifying questions. Unexamined assumptions cause the most wasted work.
- **Letting one PRD swallow a whole platform** — if the request describes multiple independent subsystems, decompose in Step 1 before continuing.

## Step 10: Key Principles

- **Diverge before you converge** — when the idea is vague, brainstorm in prose first (Step 3); only switch to structured questions once the shape is known
- **One question at a time** — don't overwhelm
- **Multiple choice preferred for converging** — `AskUserQuestion` is easier to answer than open-ended, and lets the user click through without re-reading the doc
- **Challenge assumptions** — be a strategic thought partner, not a yes-man
- **YAGNI ruthlessly** — remove unnecessary scope
- **Explore alternatives** — always propose 2-3 approaches before settling
- **Decompose oversized projects** — one PRD per cohesive feature; multiple subsystems become multiple PRDs
- **Converge explicitly** — state the scope, get confirmation
- **Edit, don't rewrite** — when the user requests changes to the PRD, use `Edit` on specific sections rather than regenerating the whole file
- **Write for handoff** — the PRD is a contract between requirements and specification

ARGUMENTS: $ARGUMENTS