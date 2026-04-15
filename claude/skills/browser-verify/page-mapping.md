# File → URL Page Mapping

When no URL is specified, use this mapping to determine which page to verify
based on the files that changed.

## Echelon Mappings

| File path pattern | Page URL |
|-------------------|----------|
| `app/dashboards/ai-analytics/` | `/dashboards/ai-analytics` |
| `app/dashboards/teams/` | `/dashboards/teams` |
| `app/dashboards/users/` | `/dashboards/users` |
| `app/dashboards/tribes/` | `/dashboards/tribes` |
| `app/dashboards/incidents/` | `/dashboards/incidents` |
| `app/dashboards/sprints/` | `/dashboards/sprints` |
| `app/retrospective/` | `/retrospective` |
| `app/teams/` | `/teams` |
| `app/users/` | `/users` |
| `components/charts/` | `/dashboards/ai-analytics` (charts are used here) |
| `components/blocks/` | Check which dashboard imports the block |
| `lib/api/connectors/coderabbit/` | `/dashboards/ai-analytics` |
| `lib/api/connectors/anthropic/` | `/dashboards/ai-analytics` |
| `lib/api/connectors/cursor/` | `/dashboards/ai-analytics` |
| `lib/api/connectors/incidents/` | `/dashboards/incidents` |
| `packages/db/src/schema/` | Schema change — verify any page that queries the changed table |

## Fallback

If no mapping matches, check `git log --oneline -1` for a ticket key,
then look up the ticket to find which page it relates to.

## Multiple Pages

If changes span multiple directories, verify ALL affected pages — not just the first one.
