### Fixed — two source comments still call the multi-quantifier family admitted

`src/arch.h:153` and `src/search.h:1215` describe the multi-quantifier family as one the structural screen
admits — "the multi-quantifier residual `a*a*a*a*a*b`, which the screen admits by construction" and "the
structural screen ADMITS". Since #484 landed (#688), it does not: `--regex='a*a*a*a*a*b'` is refused at
byte 2, by name, before any engine sees it. Both comments now name a family member that is refused as if the
gap were still open, on the same lines that explain what `RegexVerdict::Exhausted` is for.

The paragraph still needs a real example of an admitted pattern whose cost in the subject is super-linear,
so it takes `(a|aa){1,100}b$` — measured ADMITTED on the #688 binary, and the shape `docs/LIMITS.md`
already names for exactly this residual ("a bounded outer over a branch that repeats itself only through
the outer quantifier, so no clause fires"). The family is recorded as refused since #484, beside the M2-c
note the same sentence already carries for the overlapping-alternation shape.

`docs/LIMITS.md` and `docs/limits_build.py` were regenerated in #688 and already say the screen now refuses
these shapes, so this is the residue of that regeneration: generated prose was updated and the two
hand-written comments were not, because no generator owns them and no gate reads a comment for truth. The
two other pre-existing mentions in `test/regexguardcheck.sh` are already correct — both say the spec closes
the residual and that the real-engine leg moved to `(a*){20}b` for that reason.

Comment-only: no code, no behaviour, no gate, no version. `git apply --check` on `385ebd0bb` and
`clang++ -std=c++23 -fsyntax-only src/main.cpp` (the largest TU, which includes both headers) both rc=0.
