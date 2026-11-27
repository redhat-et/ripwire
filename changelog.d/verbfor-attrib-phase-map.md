### Added — a permanent `PROFILE_SCOPE` phase map for the `--for` answer

A warm `--for` on a large tree spent about 80% of its time in one unlabelled bucket. The per-verb
scope in `main.cpp` nested nothing below itself for this verb, so the single largest per-query term
in the profile could only be read as a total.

`src/verbs_for.h` and `src/forpage.h` now carry 41 `PROFILE_SCOPE_DESCRIBE` markers, one at the
entry of each phase of the answer: the ranking (`for/rank:`), the bundle render (`for/pass:`), the
enrichment hops (`for/hops:`), the bodies (`for/bodies:`), the header and legend (`for/header:`),
the file-grain tail and file page (`for/tail:`), the JSON and candidates dialects
(`for/dialect:`), the budget-fitted re-render (`for/fit:`) and the post-passes (`for/post:`).

Every marker is at a BLOCK ENTRY — the line after `{`. A `PROFILE_SCOPE` lives to the end of its
enclosing block, so a marker placed beside the code someone suspects also times everything below
it and returns a number that reads as confirmation. At a block entry the extent is exactly the
block the name claims, which is what makes the map readable by someone who did not write it.

`test/forscopecheck.sh` holds the map to that shape: every scope is at a block entry (with a
poisoned-copy control, so the placement matcher is shown able to report a misplacement), every
scope fires with `calls>=1` across six postures (with an absent-description control, so the firing
matcher is shown able to report a miss), and the default build still emits no profiler text on any
stream. The markers compile to `((void)0)` without `-DRIPWIRE_PROFILE=ON`, so the shipped binary's
output is byte-identical with and without them.
