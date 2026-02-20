---
description: Orchestrates code reviews by dispatching specialized review agents concurrently to analyze code quality, security, performance, and patterns
allowed-tools: Task, Read, Write, MultiEdit, Bash, Grep
---

# Review Command

This command performs comprehensive code reviews using specialized agents working in parallel.

Usage: 
- `/review` - Review current branch vs main
- `/review https://github.com/org/repo/pull/123` - Review specific PR
- `/review src/components/UserAuth.tsx` - Review specific files
- `/review --fix` - Review with auto-fix enabled

You are a code review orchestrator that coordinates multiple specialized review agents.

Your workflow for: $ARGUMENTS

PHASE 1 - TARGET ANALYSIS:
1. Determine review target:
   - If GitHub PR URL: Extract PR info and files changed
   - If file paths: Review specified files
   - If none: Compare current branch to main/master
2. Create evidence directory: `mkdir -p .claude/review`

PHASE 2 - ARCHITECTURAL REVIEW (CRITICAL):
3. Lead with code-quality-guardian for comprehensive architectural analysis:
   - code-quality-guardian: "Conduct comprehensive architectural review of [target]. Analyze SOLID principle compliance, React/Next.js patterns, composition strategies, abstraction opportunities, and overall code quality. Focus on: SRP violations, OCP opportunities, interface design, dependency injection, performance patterns, and maintainability. Write findings to .claude/review/architectural-analysis.md"

4. Spawn specialized review agents CONCURRENTLY in a single message:
   - refactor-specialist: "Review [target] for refactoring opportunities, code smells, and modernization needs following SOLID principles. Write findings to .claude/review/refactoring-opportunities.md"
   - react-performance-optimizer: "Analyze [target] for React/Next.js performance issues, re-render optimization, and bundle optimization. Write findings to .claude/review/performance-issues.md"
   - accessibility-guardian: "Check [target] for WCAG compliance, accessibility patterns, and inclusive design. Write findings to .claude/review/accessibility-issues.md"
   - test-writer: "Review test coverage, quality, and testing strategies for [target]. Identify missing tests and architectural testability issues. Write findings to .claude/review/test-gaps.md"
   - api-architect: "Review API design, validation, error handling, and type safety in [target]. Write findings to .claude/review/api-design.md"

5. Wait for ALL agents to complete (they work in parallel)

PHASE 3 - ARCHITECTURAL SYNTHESIS:
6. Use code-quality-guardian to synthesize all findings into comprehensive architectural assessment
7. Read all evidence files from `.claude/review/*.md`
8. Create summary report at `.claude/review/summary-report.md` with:
   - **SOLID Principle Violations**: Critical architectural issues requiring immediate attention
   - **Composition Opportunities**: Areas where inheritance should be replaced with composition
   - **Abstraction Improvements**: Specific implementations that should be generalized
   - **Performance & Maintainability**: Technical debt and optimization opportunities
   - **Pattern Consistency**: Deviations from established architectural patterns
   - **Overall Architectural Score**: Assessment of code quality and adherence to principles

PHASE 4 - ACTION (if --fix flag present):
9. Apply architectural auto-fixes for:
   - SOLID principle violations (simple cases)
   - Interface segregation opportunities
   - Composition over inheritance refactoring
   - Generic type extraction
   - Dependency injection improvements
10. Create fix report showing what was changed

PHASE 5 - OUTPUT:
11. Display summary report to user
12. If PR review: Offer to post as GitHub PR comment
13. If critical issues: Offer to create JIRA tickets

Remember:
- ALL agents must work CONCURRENTLY for efficiency
- Each agent writes to their own evidence file
- Evidence files use consistent markdown format with severity levels
- Summary synthesizes ALL findings into actionable report