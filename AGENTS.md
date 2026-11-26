# Agent guidance

Keep context small and preserve behavior. This Rails repository is migrating legacy Wringer fetching into Condenser/Distillator; reliability and output parity take priority over optimization.

## Before editing
1. Read the task and the relevant diff (`git status`, `git diff`, `git log -n 5`). Identify the affected code, callers, and focused tests.
2. Read only the code and documentation relevant to that behavior. Use `rg -n` or scoped searches first; inspect narrow file ranges before full files. Do **not** recursively paste the repository or read all of `docs/`.
3. Use [docs/README.md](docs/README.md) to choose a few pertinent documents. The document map is an index, not an instruction to read every linked file.
4. Do not automatically load large fixtures, snapshots, VCR cassettes, test artifacts, database dumps, or generated outputs; consult them only for relevant tests or contract verification.
5. Summarize decisions and changed files when switching subtasks; avoid repeatedly rereading unchanged material.

## Invariants
- Do not silently change legacy Wringer fetch/cache semantics, DSL extraction and selected statement behavior, ResourceList URL discovery/reconciliation, Artsdata/Databus exports, or serving modes.
- Preserve safe fetching, failure/last-good-cache behavior, transition validation and recovery, and repeatable replay. Treat optimization as secondary to parity.
- Do not loosen migration admission/qualification rules just to make a failing check pass. Distinguish genuine source/DSL issues from stale or missing operational evidence.
- Prefer small, targeted changes and regression tests. Verify behavior across consumers when touching shared contracts. Avoid unrelated refactors.

## Verification and handoff
- Start with relevant focused tests; the README documents `DISABLE_SPRING=1 bin/rails test:distillator_fast` and the full suite. For release-sensitive or cross-cutting changes, run broader integration/contract tests before proposing a merge.
- Report commands and results actually observed, relevant test coverage, remaining risks, and any checks not run. Never claim passing tests without evidence.
- Do not merge a PR, deploy, or alter production/staging data unless explicitly asked. Keep secrets and private database contents out of logs and reports.
