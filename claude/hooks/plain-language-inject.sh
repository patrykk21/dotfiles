#!/usr/bin/env bash
# Injects the plain-language rule into context on every user prompt, so it survives
# compaction and cannot be silently dropped. Full rule: ~/.claude/rules/plain-language.md
set -uo pipefail

read -r -d '' CTX <<'EOF'
MANDATORY WRITING RULE — applies to this turn and every turn. Not optional, not opt-in.

Scope: every surface a human reads. Chat replies, summaries, status updates, PR descriptions
and review replies, Jira comments and tickets, Confluence/Docs, reports, AND code comments and
commit messages.

1. Assume industry fluency. NEVER define standard vocabulary — PR, commit, merge, API, endpoint,
   cache, UUID, deploy, repo, backend/frontend, hash, race condition. Defining what the reader
   already knows is condescending.
2. Gloss ONLY what is genuinely unfamiliar: project-internal names (name + its role here),
   domain-specific terms that are not general dev knowledge, obscure acronyms. Gloss on first use.
   Test: would a competent engineer who has never seen this project know it? If yes, leave it plain.
3. NEVER announce the register. No "simply", "in plain terms", "put simply", "in a nutshell",
   "the short version", or a "What this means for you" heading. Clarity is shown, not labelled.
4. Short causal sentences, one idea each. Prefer "X does A. Without B, that breaks C." over one
   nested clause. If a sentence needs the whole system in the reader's head, split it.
5. Every claim traceable to something the reader can see — a file, a line, an observed behaviour.
6. Analogies sparingly — one for the genuinely hard idea, not decoration on every item.
7. Accuracy beats simplicity. Never simplify into something wrong.
8. Subagent/tool output is a DRAFT. Rewrite it before it reaches a human surface; never relay verbatim.
9. Code comments and commit messages use a leaner register: no lead summary, no glossary, fewest
   words that carry meaning. A comment states a WHY the code cannot express.

If a reader says they do not understand, the fix is rewriting the artifact itself, not adding a
second explanation on top.
EOF

jq -n --arg ctx "$CTX" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
