# Test Archive

## Document Metadata
- Version: 0.1
- Status: Active
- Last Updated: 2026-04-21
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

## Change Log
- 2026-04-21: Initial version.
- 2026-04-21: Removed `TC-003` from the archive after a fresh GUI run showed the case is still active and currently failing at the issue-comment to proposal boundary.
- 2026-04-21: Archived `TC-003` again after the strengthened live GUI path auto-created proposal PR `#12` and shifted the remaining gap to host-side canonical traceability refresh.
