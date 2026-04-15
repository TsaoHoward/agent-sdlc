# Issue Dashboard

## Document Metadata
- Version:
- Status: Draft | Active | Superseded
- Last Updated:
- Owner:
- Source Template: docs/templates/issue-dashboard.template.md

## Purpose
- describe what this dashboard is for
- clarify that it is the durable dashboard for active near-term project issues
- clarify that it does not replace forge issues, WBS, decision backlog, or ADRs

## Issue Classification
- include only active or near-term issues that deserve operator attention or durable handoff
- keep complex issue detail in supporting notes under `docs/issues/items/`
- do not mirror every forge issue, comment thread, or small implementation task here

## Status Model
- `Open`
- `In Progress`
- `Blocked`
- `Ready For Review`
- `Deferred`
- `Done`
- `Closed`

## Move-Out Rule
- keep only active or near-term items in this document
- move `Done` or `Closed` items out at the next document maintenance pass
- move `Deferred` items out when they are no longer near-term
- record moved-out items in `docs/issues/issue-archive.md` when a lightweight history entry is still useful

## Supporting-Note Rule
- create a supporting issue note under `docs/issues/items/` when background, dependency, evidence, or handoff context no longer fits cleanly in the dashboard
- keep the dashboard concise even when a supporting note exists

## Exit And Promotion Rule
- every active issue item should record its intended exit path
- update roadmap and WBS when an issue changes work structure, scope, sequencing, or dependencies
- update `docs/decisions/decision-backlog.md` when an issue reveals a major unresolved decision
- create or update an ADR when an issue changes architecture, source-of-truth ownership, or cross-cutting governance

## Dashboard
| Issue ID | Title | Status | Related Docs / WBS | Next Action | Exit Path |
|---|---|---|---|---|---|
| I-001 |  |  |  |  |  |

## Issue Items

### I-001 - [Title]
- Status:
- Related Docs / WBS:
- Why It Matters:
- Current State:
- Next Action:
- Exit Path:
- Supporting Notes:
- Promotion / Escalation Check:
- Notes:

## Change Log
- YYYY-MM-DD: Initial version
