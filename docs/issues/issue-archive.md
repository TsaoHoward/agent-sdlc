# Issue Archive

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-30
- Owner: Project Maintainer

## Purpose
This document records issue items that were intentionally moved out of `docs/issues/issue-dashboard.md`.

Use it to preserve a lightweight history when:
- a dashboard item is completed or closed
- a deferred item is no longer near-term
- an issue is otherwise moved out of the active dashboard but still worth remembering

This archive is not a replacement for detailed supporting notes, WBS history, forge issue history, or ADRs.

## Archived Items
| Issue ID | Title | Outcome | Durable Reference | Moved Out On | Notes |
|---|---|---|---|---|---|
| I-001 | Phase 1 Minimum Closed Loop Implementation Packaging | Done | `docs/issues/items/I-001-phase1-minimum-closed-loop-implementation.md` | 2026-04-30 | Phase 1 packaging closed after WBS `3` / `3.9` moved to done and the last large-file docs-update blocker was cleared by live rerun evidence on `PR #44` / run `#71`. |
| I-006 | Large-File Documentation Truncation Risk | Done | `docs/issues/items/I-006-large-file-documentation-truncation-risk.md` | 2026-04-30 | Live rerun evidence on issue `#41` / comment `#204` confirmed `trq-763eac216fe1` -> `ags-716c62e3f62c` -> `PR #44` with `README.md` changes limited to `2` additions and `0` deletions, plus CI run `#71` success. |
| I-005 | Issue-Comment Failure And No-Op UX Hardening | Deferred | `docs/issues/items/I-005-issue-comment-failure-and-noop-ux-hardening.md` | 2026-04-30 | Follow-up remains valid but is intentionally outside Phase 1 close. It now carries richer UX status taxonomy, duplicate suppression, storage evolution, unified UX discovery, and DFD output mechanism ideas as deferred work. |
| I-004 | Second External Target Fixture Family | Done | `docs/issues/items/I-004-second-external-target-fixture-family.md` | 2026-04-30 | The second external target fixture baseline is complete and no longer needs active dashboard visibility. |
| I-003 | Platform Self-Test And External Target Service-Evaluation Separation | Done | `docs/issues/items/I-003-platform-self-test-and-external-target-service-evaluation-separation.md` | 2026-04-30 | ADR-0009 separation work is complete for the current Phase 1 window and now lives in the supporting note plus roadmap/WBS history. |
| I-002 | Configuration Template Policy Compliance Gaps | Done | `docs/issues/items/I-002-configuration-template-policy-compliance-gaps.md` | 2026-04-30 | ADR-0008 template/local-config governance is now integrated into the current implementation baseline and no longer needs active issue tracking. |

## Change Log
- 2026-04-15: Initial version.
- 2026-04-30: Archived the completed Phase 1 packaging and large-file docs-update items, along with done or deferred follow-up items that no longer need active dashboard visibility.
