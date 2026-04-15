---
name: review-solution
description: "Comprehensive pre-delivery solution review checklist"
version: 1.0.0
tags: [quality, review, standards]
---

# Review Solution - Pre-Delivery Quality Gate

**CRITICAL:** Run this review BEFORE delivering ANY solution to the user.

## Mandatory Review Checklist

### 1. Project Standards Compliance

**CLAUDE.md / AGENTS.md Checks:**
- [ ] Read and followed ALL instructions in CLAUDE.md
- [ ] Read and followed ALL instructions in project-specific .md files
- [ ] Checked for coding standards (logging, formatting, patterns)
- [ ] Verified no violations of priority rules
- [ ] Followed required file organization (no files in root unless specified)

**Example Violations to Catch:**
- Using `console.log` instead of `createLogger`
- Creating files in root folder
- Not using specialized tools (bash instead of dedicated tools)
- Ignoring required patterns or conventions

### 2. Code Quality Standards

**DRY Principle:**
- [ ] No duplicated code patterns (3+ occurrences = refactor needed)
- [ ] Created helper functions for repeated logic
- [ ] Single source of truth for configuration

**Architecture:**
- [ ] Follows existing project patterns
- [ ] Respects layer separation (3-layer, etc.)
- [ ] Uses existing utilities/helpers where available
- [ ] No unnecessary abstraction or over-engineering

**Security:**
- [ ] No hardcoded secrets or credentials
- [ ] Environment-specific checks where needed
- [ ] Input validation at boundaries
- [ ] No SQL injection, XSS, or OWASP top 10 vulnerabilities

### 3. Testing & Verification

**Functional Testing:**
- [ ] Solution actually works end-to-end
- [ ] Tested with real data/scenarios
- [ ] Edge cases considered and handled
- [ ] Error handling tested

**Performance:**
- [ ] No infinite loops or performance issues
- [ ] No unnecessary API calls or database queries
- [ ] Appropriate caching used

### 4. Documentation

**Code Documentation:**
- [ ] Functions have clear JSDoc comments
- [ ] Complex logic explained with inline comments
- [ ] ENV variables documented in .env.example

**User Documentation:**
- [ ] Only created docs if explicitly requested
- [ ] README/docs updated if necessary
- [ ] Configuration instructions clear

### 5. Git & PR Standards

**Commit Quality:**
- [ ] Follows project commit message format
- [ ] Clear, descriptive commit messages
- [ ] Co-author attribution included
- [ ] No merge conflicts

**PR Description:**
- [ ] Comprehensive summary of changes
- [ ] Test plan included
- [ ] Breaking changes noted
- [ ] Links to relevant tickets/issues

## Pre-Delivery Actions

**Before saying "Ready to commit" or "Implementation complete":**

1. **Run Project Linters:**
   ```bash
   # Check for linting issues
   npm run lint 2>&1 | grep -i "error\|warning" || echo "✅ Lint passed"

   # Check type errors
   npm run typecheck 2>&1 | grep -i "error" || echo "✅ Types passed"
   ```

2. **Search for Anti-Patterns:**
   ```bash
   # Check for console statements
   git diff | grep "console\.\(log\|warn\|error\)" && echo "❌ Found console statements!"

   # Check for TODO/FIXME left behind
   git diff | grep -i "TODO\|FIXME" && echo "⚠️  Found TODOs"
   ```

3. **Verify Against CLAUDE.md:**
   ```bash
   # Re-read project standards
   cat CLAUDE.md | grep -i "never\|always\|must\|critical"
   ```

4. **Test the Solution:**
   - Actually run/execute the code
   - Test happy path AND edge cases
   - Verify it works in the target environment

## Failure Protocol

**If ANY checklist item fails:**
1. ❌ DO NOT deliver the solution
2. 🔧 Fix the issues immediately
3. ✅ Re-run the full checklist
4. 📝 Document what was missed for future learning

## Success Criteria

**Only deliver solution when:**
- ✅ ALL checklist items passed
- ✅ No violations in CI/linting
- ✅ Solution tested and verified working
- ✅ User explicitly asked for delivery (commit/PR)

## Learning & Improvement

**After Each Review:**
- Document common mistakes in MEMORY.md
- Update this checklist if new patterns discovered
- Note project-specific standards for future reference

---

**Remember:** Quality over speed. A solution that works perfectly is better than a fast solution that violates standards.
