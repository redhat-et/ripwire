### Fixed — `--for` anchors bare filenames and stems, and recognises the `test-` prefix

`--for` now recognizes bare extension-bearing filenames (`document-remind.sh`, `delta.py`), hyphenated
file stems (`document-remind`), and snake_case file stems (`sync_ledger`) as query mentions that anchor
to indexed files. A bare filename without slashes previously split on `.` like a dotted module or fell
back to plain prose, preventing hook scripts and function-less modules from ranking on queries naming
their own filename or stem. Sibling test files starting with `test-` (such as `test-document-remind.sh`)
are now recognized by `isTestPath`, ensuring they receive standard test-tier score down-weighting in
relevance scoring rather than outranking the production script (fixes #466).
