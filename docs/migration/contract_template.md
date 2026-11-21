# Distillator Migration Contract Template

## Site Identification
- Site name:
- Site ID (if applicable):
- Source system(s): Wringer / Condenser / Console
- Target system: Distillator
- Contract version:
- Contract author:
- Date created:
- Last updated:
- Related links (pipeline config, issue, PR, dashboards):

## Purpose of Contract
- Define expected pipeline output quality and structure for this site during migration.
- Establish comparison criteria between baseline output and Distillator output.
- Ensure Artsdata input quality is preserved or improved.

## Expected Output Characteristics
- Output type(s) expected (for example: events):
- Coverage scope (date range, locale, categories):
- Output freshness expectation:
- Deduplication expectation:
- URL integrity expectation:
- Language/content completeness expectation:

## Event Count Expectations
- Baseline event count (source system):
- Distillator expected range:
- Accepted variance tolerance (absolute and/or %):
- Notes on seasonality/time-window effects:

## Required Fields Checklist
Mark each as `Present`, `Missing`, or `N/A`.

| Field | Status | Notes |
|---|---|---|
| `id` |  |  |
| `name` |  |  |
| `startDate` |  |  |
| `location` |  |  |
| `url` |  |  |
| `organizer` |  |  |
| `description` |  |  |
| `image` |  |  |
| `offers` |  |  |
| Other required field: |  |  |
| Other required field: |  |  |

## Field Quality Expectations
Use concrete quality expectations per field.

| Field | Quality expectation | Baseline quality notes | Distillator observed quality | Verdict |
|---|---|---|---|---|
| `name` | Accurate, human-readable title |  |  |  |
| `startDate` | Correct timezone and precision |  |  |  |
| `location` | Resolved venue and locality |  |  |  |
| `url` | Canonical, reachable, event-specific |  |  |  |
| `description` | Not empty, not boilerplate only |  |  |  |
| Other field: |  |  |  |  |

## Known Edge Cases
Document expected handling for site-specific edge cases.

| Edge case | Expected behavior | Baseline behavior | Distillator behavior | Verdict |
|---|---|---|---|---|
| Missing start time |  |  |  |  |
| Multi-day event |  |  |  |  |
| Recurring listing |  |  |  |  |
| Cancelled/postponed event |  |  |  |  |
| Duplicate source pages |  |  |  |  |
| Other edge case: |  |  |  |  |

## Known Issues (Baseline)
List current known defects in baseline output before migration.

| Issue ID | Description | Severity | Baseline impact | Planned handling in migration |
|---|---|---|---|---|
|  |  |  |  |  |
|  |  |  |  |  |

## Allowed Differences
Differences that may be accepted if final quality is preserved or improved.

- [ ] Event count differs within defined tolerance.
- [ ] Normalization differences (formatting/casing/whitespace only).
- [ ] URL canonicalization improvements.
- [ ] Better entity resolution (venue/locality/organizer).
- [ ] Improved completeness for optional fields.
- [ ] Other explicitly approved difference:

## Forbidden Regressions
Any item below is considered a failure unless explicitly approved.

- [ ] Required field missing when previously present.
- [ ] Broken, incorrect, or non-canonical event URLs.
- [ ] Invalid event structure for Artsdata ingestion.
- [ ] Significant unexplained event loss outside tolerance.
- [ ] Date/time degradation (wrong day/time/timezone).
- [ ] Location degradation (less specific or incorrect).
- [ ] New duplicate events introduced.
- [ ] Other site-specific blocker:

## Comparison Rules
Assign one status per evaluated item.

- `MATCH`: Distillator output is equivalent to baseline for required quality.
- `IMPROVED`: Distillator output is clearly better with no offsetting regression.
- `ACCEPTABLE`: Minor difference, within allowed differences and tolerance.
- `REGRESSION`: Quality or correctness declined versus baseline.
- `BLOCKER`: Severe issue that invalidates migration readiness.

### Decision Guidance
- Overall result should be `MATCH`, `IMPROVED`, or explicitly accepted as `ACCEPTABLE` for approval.
- Any unresolved `REGRESSION` requires remediation before approval.
- Any `BLOCKER` stops approval.

## Validation Checklist
Complete before requesting approval.

- [ ] Contract metadata completed.
- [ ] Baseline sample/window documented.
- [ ] Distillator sample/window documented.
- [ ] Event count comparison completed.
- [ ] Required fields checklist completed.
- [ ] Field quality review completed.
- [ ] Edge cases reviewed.
- [ ] Baseline known issues acknowledged.
- [ ] Allowed differences explicitly listed.
- [ ] Forbidden regressions checked.
- [ ] Comparison statuses assigned and justified.
- [ ] Evidence links attached (queries, snapshots, diffs, logs).

## Approval
- Migration decision: `APPROVED` / `APPROVED WITH CONDITIONS` / `NOT APPROVED`
- Decision date:
- Approved by:
- Reviewers:
- Conditions (if any):
- Follow-up actions and owners:
- Re-validation due date (if applicable):

## Evidence References
- Baseline extraction/reference:
- Distillator extraction/reference:
- Comparison artifact(s):
- Related issue(s)/PR(s):
