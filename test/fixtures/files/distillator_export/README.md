This directory contains golden export fixtures for the Distillator fixture pack.

Files:
- `expected_distillator_fixture_pack.jsonld`: canonical JSON-LD export snapshot.
- `expected_distillator_fixture_pack.nq`: canonical N-Quads export snapshot.

The snapshots are intended to represent graph-equivalent Artsdata export output
for the `distillator_fixture_pack` website fixture.

The linked `distillator-main-hall` venue includes its name and `schema:Place`
type from the selected local place statement. These two triples were restored
when correcting enrichment lookups for prefixed `footlight:` database IDs;
the earlier snapshots accidentally preserved that omission.
