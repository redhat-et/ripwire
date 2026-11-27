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

A second pass extends the map past the answer's own phases into the **section renderers**: 53
markers across 27 more files, one at the entry of each block `runForLensPass` calls —
`forfold.h`, `forslots.h`, `fordocbody.h`, `forowner.h`, `fordispatchhop.h`, `forreexport.h`,
`epmanifest.h`, `listedin.h`, `forfilepage.h`, `forunused.h`, `forselfhook.h`, `fordemoteall.h`,
`formembers.h`, `regindex.h`, `forctorhop.h`, `forcallerhop.h`, `foraliashop.h`,
`fordottedstring.h`, `demoterefill.h`, `forliteral.h`, `clones.h`, `lexical.h`, `mention.h`,
`subjectanchor.h`, `forrowfeatures.h`, `filter.h` and `infra/sortutil.h`.

The point of covering them is subtractive: with each renderer named, whatever time is left inside
`runForLensPass` is attributable to `serialize.h`'s `pack*` serializers, which are not
instrumented. `runForLensPass` is a single 2,004-line block with no sub-blocks at body
indentation, so there is no additive way to scope inside it; naming everything it *calls* is how
the leftover becomes a number instead of a residue. The `*On()` gate predicates are scoped too,
rather than assumed free — a gate that quietly scans would otherwise hide in that leftover.

Not instrumented, and therefore inside the leftover: `serialize.h`, and eleven O(1) string and
predicate helpers (`emitRaw`, `accessshape.h contains`, `gitstampstore.h find`,
`memstats.h enabled`, `model.h rootRelPath`, `sarif.h rootPrefixOf`/`rootRelativeUri`,
`graphlegend.h forZeroNoteBytes`/`forIdRouteLegendParts`, `lexical.h isNameExactRouteTag`/
`isAdaptiveHomonymDecline`, `subjectanchor.h routeAnchorNotHeadClause`).

`forscopecheck` covers all 29 files, with a floor of 95 scopes. Arm A's placement invariant holds
for every scope in them, the pre-existing ones included. Arm D asserts the scopes this map owns
(`for/…`, `sortutil:…`) and leaves other lanes' pre-existing scopes in those shared files alone,
since their posture coverage is not this gate's claim.
