# I-006: Large-File Documentation Truncation Risk

## Metadata
- Issue ID: I-006
- Status: Ready For Review
- Last Updated: 2026-04-30
- Owner: Project Maintainer
- Related Phase / WBS: `docs/roadmap.md` Phase 1; WBS `3.9`
- Source Dashboard: `docs/issues/issue-dashboard.md`
- Source Template: `docs/templates/issue-note.template.md`

## Summary
The current provider-backed `documentation_update` path can truncate large files because the execution prompt includes only the first `8000` bytes of a context file while still requiring the provider to return complete file contents.

That means a small intended docs edit can become a destructive whole-file rewrite that drops unseen tail content.

The destructive path is now blocked, and a narrower safe fragment-edit path has been added for large-file docs updates, but the live workflow still needs one post-fix rerun before the issue can be considered cleared.

## Why This Exists
The current agent execution contract combines two individually reasonable constraints into a risky pair:
- context files are truncated to `maxFileBytes`
- provider edits must return full file contents, not patches

When the target file is larger than the context cap, the provider is asked to regenerate content it never saw.

## Evidence
Fresh live evidence exists on 2026-04-29:
- issue `#41` / comment `#193`
- task request `trq-097cad6b8f77`
- session `ags-2736c300be71`
- PR `#42`
- proposal commit `83acd236a04c1d59dbf109c964e389308b53a053`

Requested task:
- `@agent run docs`
- `summary: Add a short note to README.md about today's weather.`

Observed result:
- `README.md` gained a short weather note near the top
- the same commit deleted the unseen tail of `README.md`, including the full `Project-Local Dev Startup` section
- the repo's current `README.md` is `11606` bytes, while `config/agent-execution.template.yaml` still caps `maxFileBytes` at `8000`
- the truncation line-up is exact: the deleted tail begins around the same point where the prompt would have stopped including file content

This does not look like an API token limit failure:
- provider usage for the run was about `6051` prompt tokens and `1957` completion tokens
- the failure shape matches file-context truncation, not response exhaustion

## Why It Matters
This is more serious than normal bounded-model quality drift because it is partly created by the repo-owned execution contract itself.

Under the current defaults, a supported `documentation_update` task can:
- pass validation
- stay inside allowed paths
- still delete unrelated content from a large markdown file

That makes the current docs-safe path unsafe to treat as fully closed Phase 1 baseline behavior.

## Candidate Mitigation Directions
Reasonable next-step options include:
1. block provider edits to any file whose supplied context was truncated
2. switch docs-safe updates toward patch-style edits rather than full-file replacement
3. add targeted file-slice loading around referenced edit locations instead of one fixed leading-byte cap
4. increase `maxFileBytes` only if prompt-size tradeoffs stay acceptable and the contract still preserves untouched content safely
5. add a post-edit guardrail that detects suspicious tail deletion when the original file exceeded the context cap

The safest narrow first fix is likely:
- do not allow full-file rewrite of a context file that was marked `truncated: true`

## Landed Narrow Fix
The first narrow mitigation is now implemented in `scripts/lib/agent-execution.js`:
- context files that exceed `maxFileBytes` are still marked `truncated: true`
- if the provider then attempts to rewrite one of those same files, the execution path now fails closed before writing the edit
- the failure message explicitly says the file exceeded the context-file limit and that full-file rewrite is refused for partial-context input

This no longer leaves large-file docs updates fully blocked.
The execution contract now also supports safer non-replace edit modes:
- `append`
- `prepend`
- `insert_after`
- `insert_before`

That means a docs-safe request can now still succeed on a large truncated file when the provider returns a bounded fragment edit anchored in visible content, instead of attempting a whole-file rewrite.

## Verification
The landed guardrail now has one local deterministic verification:
- date: 2026-04-30
- mode: local stubbed execution of `executeAgentSlice`
- setup: temporary repo with a large `README.md`, `maxFileBytes: 100`, and a mocked provider response that tries to rewrite `README.md`
- observed result: execution threw `Agent edit is blocked because README.md exceeded the context-file limit and was truncated before provider execution. Refusing full-file rewrite for partial-context input.`

The same local verification also confirmed restored partial capability:
- mode: local stubbed `insert_after` edit on the same truncated `README.md`
- observed result: the requested note was inserted successfully and the unseen tail content remained intact

The remaining follow-up is a live rerun through the normal issue-comment path so the project can confirm the same safe fragment-edit behavior in proposal-facing workflow state.

## Boundaries
This is an implementation and quality-hardening issue inside the existing WBS `3.9` execution boundary.

It should not be used to:
- redefine the overall architecture
- move orchestration authority out of the repo
- turn the issue thread into a richer control plane

Promote to the decision backlog only if the chosen fix changes source-of-truth ownership or introduces a broader generated-patch/structured-edit architecture direction.

## Exit Path
This issue can move out of the active dashboard once:
- the current execution contract no longer permits silent tail truncation for large docs files
- a regression test or canonical repro exists for the scenario
- `docs/phase1-close-checklist.md`, `docs/wbs.md`, and `docs/testing/test-dashboard.md` all agree on the post-fix interpretation

Near-term review target:
- confirm whether the landed fragment-edit support plus fail-closed guardrail are sufficient for Phase 1 close, or whether Phase 1 also requires a live rerun through the full issue-comment path before the blocker is considered cleared

## Change Log
- 2026-04-29: Initial version after analyzing PR `#42` / commit `83acd236a04c1d59dbf109c964e389308b53a053` and identifying the `maxFileBytes` plus full-file-response contract as the likely root cause.
- 2026-04-30: Recorded the landed fail-closed guardrail and the first deterministic local verification that blocked truncated-context full-file rewrite before file write.
- 2026-04-30: Recorded the new safe fragment-edit modes and the deterministic local verification that `insert_after` can update a truncated large file without deleting its unseen tail.
