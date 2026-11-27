# Keyed multilingual ResourceList: stage 1

This branch adds pure, read-only extraction and alignment services plus focused tests. It does NOT change the DSL parser, refresh orchestration, Webpage/Source models, jobs, URI minting, export, schema or import contracts.

- KeyedCalendarExtractor extracts (key, URL) from each *individual* event card using card-relative XPath and returns errors for missing/ambiguous fields.
- KeyedCalendarAlignment accepts already-validated language => [{key, url}] streams, joins by key, reports missing translations and duplicate-key conflicts, and returns both languages in a canonical key order.
- paired_urls_for refuses incomplete or invalid results. The digest is diagnostic, not an Artsdata ID and not a replacement for transition evidence.
- Cogeco supplied page-one HTML has 12 French and 12 English listings; all 12 image paths correspond, while 4 URL slugs differ. Image path is a PROVISIONAL pairing key, not a proven stable site event ID.

Proposed future DSL syntax (NOT yet supported): get_sorted_calendars={ key: xpath=... } on each language's ResourceList Source. This will require a shared, atomic bilingual discovery context, explicit calendar grouping when multiple ResourceLists exist, bounded dynamic pagination, existing URI reuse prior to minting new IDs, failure-safe last-good inventory, and preservation of AddWebpagesJob and Artsdata migration contracts.

To run focused Rails tests on a full development checkout:

    bin/rails test test/services/resource_lists/keyed_calendar_alignment_test.rb test/services/resource_lists/keyed_calendar_extractor_test.rb

The Rails test suite has not yet been run in this environment; no production/staging import or configuration changes have been made.
