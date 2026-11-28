### Fixed — `--quality-delta` merges overlapping exact and near clone reports

When both clone kinds are selected, `--quality-delta` merges gating exact and directly overlapping
near-clone reports, preferring the reused-helper finding when it applies. The regression fixture
checks that `--clones` still lists the exact group and near pair separately while `--quality-delta`
reports one gating row for their three members. This is a reporting change, not a change to clone
detection or gate thresholds: minor, unrelated and indirectly linked near findings stay separate,
and selecting a single clone kind keeps its per-group rows.

Acknowledgments are applied before reports merge, so an acknowledged group cannot hide an
unacknowledged overlapping group. `--quality-ack` records the selected findings separately, so
an acknowledgment still applies to a group if the overlap goes away.
