### Changed
- `--pack-task` and `--for`'s candidate body groups now cap a definition body at 120 lines
  (`min(span, 120)`), stating the cause as `cap_lines=` beside the existing `truncated=`/`lines=`/`next=`.
  The route, hops and launch body groups are unchanged.
- The key-body block carries up to 5 bodies, not 2. The number is GA1 DEV's p90 of gold functions per task.

### Measured
- On the only GA1 DEV stratum where the cap can act (25 tasks whose largest gold body exceeds 120 lines,
  49 gold functions) the cap fired on 4 of 25 `--pack-task` answers, changed edit-covering completions 5 -> 5,
  moved median bytes by +0, and cost one STRICT completion by construction. `--for` served no body on any of
  the 25, so the count-cap raise is unexercised there.
