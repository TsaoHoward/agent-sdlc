# Test Dashboard

## Document Metadata
- Version:
- Status: Draft | Active | Superseded
- Last Updated:
- Owner:
- Source Template: docs/templates/test-dashboard.template.md

## Purpose
- describe what this dashboard is for
- clarify that it is the durable dashboard for active near-term testing work
- clarify that it does not replace CI history, issue/decision dashboards, WBS, or ADRs

## Test Classification
- include only active or near-term testing work that deserves operator attention or durable handoff
- keep detailed procedures in `docs/testing/items/`
- do not mirror every individual CI run or shell transcript here

## Status Model
- `Draft`
- `Ready`
- `In Progress`
- `Blocked`
- `Passed`
- `Failed`
- `Deferred`
- `Retired`

## Move-Out Rule
- keep only active or near-term items in this document
- move `Passed` or `Retired` items out at the next document maintenance pass when they no longer need dashboard visibility
- move `Deferred` items out when they are no longer near-term
- record moved-out items in `docs/testing/test-archive.md` when a lightweight history entry is still useful

## Canonical-Case Rule
- create or update a supporting test case note under `docs/testing/items/` when the dashboard summary is no longer sufficient
- keep the dashboard concise even when a case note exists

## Dashboard
| Test ID | Title | Status | Mode | Related Docs / WBS | Next Action | Exit Path |
|---|---|---|---|---|---|---|
| TC-001 |  |  |  |  |  |  |

## Test Items

### TC-001 - [Title]
- Status:
- Mode:
- Related Docs / WBS:
- Why It Matters:
- Current State:
- Next Action:
- Exit Path:
- Canonical Case:
- Escalation Check:
- Notes:

## Change Log
- YYYY-MM-DD: Initial version.
