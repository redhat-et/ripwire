### Fixed

- CI's per-gate timeout budget is now scaled per operating system: 8 on the macOS legs, 4 on ubuntu as
  before. `test/pargates.py`'s own note had already measured that a macOS runner runs every gate at
  **6-10x its idle-local wall**, while the scale was 4 everywhere — so the two heaviest gates in the
  suite (`binoverridecheck`, rank 2 of 662 by cost, and `estchargecheck`, rank 11) hit `rc=124` at the
  1200 s per-gate budget on macOS regardless of how the cost-balanced shards fell. Cost balancing
  equalises shard *totals*; a per-gate tripwire bites wherever the heaviest *individual* gate lands.
