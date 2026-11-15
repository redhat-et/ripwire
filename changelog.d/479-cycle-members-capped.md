### Fixed — a `<cycle>` that lists only 12 of its files now says so (thanks @jflowers, #479)

`--deps` lists at most 12 member files per cycle. A cycle with more printed 12 `<f>` rows and nothing marking the cut, so
only `size=` showed that files were missing. It now carries `members_capped="1"` when the list is cut; `size=` stays the
whole count, and a cycle of 12 or fewer files is byte-identical. The 12 rows kept are the first in strongly-connected-
component order: deterministic, not a ranking. The cut on the list of cycles itself (`<cycles total= shown= capped=>`)
landed earlier in this release (the `--deps` shape entry).
