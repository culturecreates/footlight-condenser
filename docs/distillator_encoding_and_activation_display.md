# HTML decoding and activation display

HTML enters the fetch cache as UTF-8 text before title extraction, signal
classification, or persistence. Valid non-binary Ruby strings are treated as
already decoded text; raw HTTP bytes must carry `ASCII-8BIT`. Raw HTML uses a BOM,
then the HTTP charset, then an HTML meta declaration within the first 1024 bytes,
then validated UTF-8. HTML without a Content-Type is recognized from its markup.
Unsupported encodings and invalid byte sequences are left unchanged, never
scrubbed or guessed. Non-HTML responses retain their existing handling.

Title comparison uses an HTML parser, so attributes and entity spellings do not
cause false title changes. Titles and extracted literal text use Unicode NFC
for semantic comparison. JSON export literal values use the same normalization;
URI-like values and raw serialized RDF lines remain distinct. HTML/body hashes
still compare bytes, and actual title or statement changes retain their safety
classification. No stored event titles or DSL definitions are rewritten.

For active websites, the website detail page separates the activation decision
from the latest completed comparison and the latest observed cached-page fetch.
A reviewed comparison is identified only when the rollout snapshot matches the
run ID and configuration digest, all three phases passed, and the recorded review
covers its warnings. New queued/failed/completed runs and configuration changes
cannot inherit that acceptance. Historical acceptance does not expire just
because time passes. A newer failed fetch is shown separately even when the
pre-activation comparison remains accepted. The observation is not a claim of
site-wide health or proof that a normal refresh job ran.

Rollout warnings and blockers remain unchanged in audit snapshots, collapsed
under their historical decision. Publishable event pages (all dates) and upcoming
event pages have separate counts and matching filtered links. Redirects retain
their warning classification and expose the observed URL, final URL, and time.

Website Sources entry points default to `selected=true&term=xpath&per_page=100`.
Explicit filters, page sizes, and cleared filters take precedence. Global Sources
and JSON requests do not acquire these presentation filters.

No database migration is needed for this change. After deployment, run a new
transition check for website 134 to replace the old comparison with fresh
evidence; existing evidence and reviewed rollout events are not rewritten.
