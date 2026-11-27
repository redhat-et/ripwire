### Added — the warm model section is attributed, and it is the row decode rather than the validation

`warmsnap: load the model section` is **509.9 ms of a ~1,058 ms warm llvm-project run** — 48% of the
accounted warm cost and the single largest item (`bench/PROFILE.md`, "Large-repo phase balance"). It
was one scope, so which half of it cost that was unknown. `readModel` now reports a tree: the two
symbol families, the row streams, the side families, the interned-name table, both row decodes, the
two text/stream readers, and — separately — the shape validation.

**The attribution contradicted the obvious hypothesis, which is why it was measured first.**
`readModel` ends in seven `all_of` / `is_sorted` passes that re-walk containers the reads have just
touched, and at llvm scale those containers are large, so "the validation re-walk is the cost" looked
compelling. Measured on envoy it is **0.03 ms of 84.46 ms**, and the ref/bind shape-table loops are
**0.00 ms**. The cost is the **serial row decode**: `decode the reference rows` is **56%** of the
model section, `decode the binding rows` **19%**, and the parallel interned-name table build 17%.
Nothing is optimised here; the next change has a measured target instead of a plausible one.

The shape-validation scope is deliberately bracketed to its two loops alone. A `PROFILE_SCOPE` lives
to the end of its enclosing block, so declaring it beside those loops would have made it inclusive of
the two row decodes below and double-counted them against their own scopes — the instrumentation
would then have "confirmed" the hypothesis it was added to test.

`test/verbscopecheck.sh` arm D covers this tree, with a control in arm B's shape: a scope that cannot
exist must be reported absent, so the arm cannot pass by matching anything. Two gate defects were
found and fixed in the writing, both of the silent kind: the arm set `TMPDIR`/`XDG_CACHE_HOME` to
directories it never created, which made the snapshot *write* fail silently so the second run had
nothing to load and every model scope read as absent while the source was correct; and the first red
arm — reverting `warmsnap_model.h` in a scratch copy — was confounded, because a scratch root is not
a git repo, `warmsnap` records no snapshot there, and every model scope reads absent whatever the
source says. A red whose cause is not isolated is not evidence.
