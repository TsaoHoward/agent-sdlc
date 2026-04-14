# Change Control Policy

## Purpose
This document defines how different types of change should be handled.

## 1. Change Categories
### Category A — Implementation Change
Changes that stay within current roadmap, WBS, architecture, and policy boundaries.

Typical examples:
- implementing an already-approved interface
- adding tests for an existing scoped feature
- refining a bounded adapter

### Category B — Planning Change
Changes that modify:
- roadmap phase meaning
- milestone shape
- WBS structure
- work sequencing or dependencies

### Category C — Architecture or Governance Change
Changes that modify:
- system boundaries
- source-of-truth ownership
- policy ownership
- runtime isolation assumptions
- CI or deploy ownership
- replaceability assumptions

## 2. Required Actions by Category
### Category A
- update WBS status if applicable
- update implementation notes if such docs exist later

### Category B
- update roadmap and/or WBS
- explain the reason for the planning shift
- ensure roadmap and WBS still map correctly
- update the decision backlog when the planning shift introduces, resolves, or narrows a meaningful major decision item
- remove or narrow any stale open-question entries that the planning shift resolved

### Category C
- write or update an ADR before implementation
- update relevant architecture docs
- update policies if governance changes
- update the decision backlog to show promotion status and remaining detail decisions, if any
- move the promoted item out of the active decision backlog once the durable ADR link exists
- update any supporting notes, roadmap, or WBS entries that would otherwise still describe the selected direction as unresolved

## 3. Mandatory Re-Alignment Triggers
Return to roadmap/WBS/ADR review when:
- a task introduces a new integration path
- a task adds a new control-plane assumption
- a task changes which layer owns a responsibility
- a task weakens replaceability between layers
- a task changes who verifies or deploys

## 4. Silent Drift Is Not Allowed
Do not:
- bury architecture changes in implementation commits
- let durable policy exist only in chat or prompts
- repurpose roadmap phases without updating planning docs

## 5. Practical Rule of Thumb
If a change affects **what the system is**, update architecture or ADR.
If a change affects **when or in what order work happens**, update roadmap/WBS.
If a change affects **how a bounded task is executed inside existing rules**, it is usually implementation only.
