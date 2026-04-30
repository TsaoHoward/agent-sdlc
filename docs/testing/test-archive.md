# Test Archive

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-30
- Owner: Project Maintainer

## Purpose
This document records test-dashboard items that were intentionally moved out of `docs/testing/test-dashboard.md`.

Use it to preserve a lightweight history when:
- a dashboard item passed for the current validation window and no longer needs active visibility
- a dashboard item was deferred and is no longer near-term
- a dashboard item was retired or superseded

This archive is not a replacement for canonical test-case notes, CI history, forge history, or ADRs.

## Archived Items
| Test ID | Title | Outcome | Durable Reference | Moved Out On | Notes |
|---|---|---|---|---|---|
| TC-003 | GUI Full Live Issue-Comment Smoke | Passed | `docs/testing/items/TC-003-gui-full-live-issue-comment-smoke.md` | 2026-04-21 | Re-archived after issue `#11`, task request `trq-bd85673302e7`, session `ags-335855297620`, and PR `#12` confirmed that the strengthened listener path now auto-creates the proposal and root traceability file. The remaining active gap moved to `TC-002` because host-side canonical traceability still lags CI completion until a later host-side sync. |
| TC-002 | CLI Proposal And Traceability Smoke | Passed | `docs/testing/items/TC-002-cli-proposal-and-traceability-smoke.md` | 2026-04-30 | Proposal creation, CI linkage, and host-side traceability convergence are stable for the current Phase 1 window and no longer need active dashboard visibility. |
| TC-004 | Agent Execution Adapter Smoke | Passed | `docs/testing/items/TC-004-agent-execution-adapter-smoke.md` | 2026-04-30 | Provider-backed adapter behavior is validated across all enabled task classes for the current close window. |
| TC-005 | Real AI Connectivity Manual Flow | Passed | `docs/testing/items/TC-005-real-ai-connectivity-manual-flow.md` | 2026-04-30 | The operator-facing real-provider flow is currently healthy and now lives as a canonical runbook rather than an active testing concern. |
| TC-006 | External Target Service-Evaluation Baseline | Passed | `docs/testing/items/TC-006-external-target-service-evaluation-baseline.md` | 2026-04-30 | The first docs-oriented external target baseline is complete for the current Phase 1 window. |
| TC-007 | External Target Bounded-Code Evaluation Baseline | Passed | `docs/testing/items/TC-007-external-target-bounded-code-evaluation-baseline.md` | 2026-04-30 | The first bounded-code external target baseline is complete for the current Phase 1 window, including retained failure-history context in the canonical note. |
| TC-008 | Phase 1 Manual Deliver Acceptance | Passed | `docs/testing/items/TC-008-phase1-manual-deliver-acceptance.md` | 2026-04-30 | The 2026-04-24 manual acceptance remains historical delivery evidence and no longer needs active dashboard visibility after formal Phase 1 close-out. |
| TC-009 | Issue-Comment Feedback Coverage | Deferred | `docs/testing/items/TC-009-issue-comment-feedback-coverage.md` | 2026-04-30 | Rejection feedback is proven and the remaining deterministic no-op repro gap is intentionally deferred outside Phase 1 close. |
| TC-010 | Large-File Documentation Update Guardrail | Passed | `docs/testing/items/TC-010-large-file-documentation-update-guardrail.md` | 2026-04-30 | Live rerun evidence on issue `#41` / comment `#204` produced `trq-763eac216fe1` -> `ags-716c62e3f62c` -> `PR #44` -> run `#71`, with `README.md` limited to additions and no tail truncation. |

## Change Log
- 2026-04-21: Initial version.
- 2026-04-21: Removed `TC-003` from the archive after a fresh GUI run showed the case is still active and currently failing at the issue-comment to proposal boundary.
- 2026-04-21: Archived `TC-003` again after the strengthened live GUI path auto-created proposal PR `#12` and shifted the remaining gap to host-side canonical traceability refresh.
- 2026-04-30: Archived the passed or deferred Phase 1 close-window cases after the final large-file docs-update rerun cleared `TC-010`.
