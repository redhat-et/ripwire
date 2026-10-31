### Fixed — `--regex` refuses the multi-quantifier family instead of handing it to the engine

Three shapes that both structural screens admitted, and that cost the engine time growing with the *subject*,
are now refused by name, bounded, before any engine sees the pattern:

- `a*a*a*a*a*b` — adjacent unbounded quantifiers at top level, where there is no group for the
  nested-repetition or alternation arms to inspect (measured on libstdc++: 5.4 ms at a 21-byte subject,
  29.5 s at 97 bytes — a doubling every ~6.1 bytes).
- `^(a)*(a)*(a)*(a)*(a)*$` — the same adjacency one level down, where the quantified groups are siblings
  (~degree-4 polynomial: 2.3 ms at 20 bytes, 984 ms at 80).
- `^(ab\w|((.|.){1,3}){1,3}){1,3}$` — an alternation the screen cannot prove disjoint, repeated inside a
  repeat. Its outer `{1,3}` is *bounded*, so the existing alternation arm never fired on the `(.|.)` overlap.
  The lone `(.|.){1,3}` stays admitted: it is cheap at every length, and it is the nesting that enumerates.

What this means in practice: these patterns used to reach the engine, where libc++ abandons the match
(`error_complexity`) and libstdc++ has no budget at all and simply does not return. The verdict is now one
answer on every platform, exits 1, and says what is wrong and what to write instead — collapse the atoms
(`a*a*a*` is the language of `a*`), separate them with a literal neither can swallow (`a*b*a*b`), or bound
all but one (`a{0,3}a*b`).

It does **not** claim the residual closed. Any *admitted* pattern whose cost in the subject is super-linear
is still unbounded on libstdc++, including a bounded quantifier over a group that itself repeats
(`((a|aa){2,5}){2,5}b$`), which no disjointness proof can answer. That is disclosed in `docs/LIMITS.md`, and
it is why the screen refuses rather than guesses: a refusal is a bounded, named failure; a hang is not.

Gate: `test/regexmultiquantcheck.sh` (new, 31 arms). The two preceding families are asserted undisplaced
in the same gate, and `test/regexguardcheck.sh` arm (b2)'s real-engine vehicle moved from `a*a*a*a*a*b`
(now refused at admission, correctly) to `(a*){20}b`, so that arm keeps proving what it was written to
prove.

Fixed by @pt-act.
