### Added
- `test/carriedpageboundcheck.sh` registers the bar for bounding the carried `--for` page on routed answers.
  The mechanism itself is NOT built: the implementation shrinks the page 14,531 B -> 8,292 B (-43%) but
  SILENTLY, because the carried page's root loses its `page=`/`pages=`/`withheld_bytes=` paging attributes in
  the routed assembly. Shipping a 43% cut with no disclosure would be a silent cut; the code was reverted and
  the gate's unbuilt arms print as DEFER with the blocker.
