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
is still unbounded on libstdc++, including a *single-level* bounded quantifier over an unproven-disjoint alternation (`(a|aa){1,100}b$`, measured 7.8 ms at a 21-byte subject rising to 99.1 s at 41 B, roughly 7x per 4 bytes), which no disjointness proof can answer. That is disclosed in `docs/LIMITS.md`, and
it is why the screen refuses rather than guesses: a refusal is a bounded, named failure; a hang is not.

Gate: `test/regexmultiquantcheck.sh` (new, 54 assertions over 19 patterns). The two preceding families are
asserted undisplaced in the same gate, and `test/regexguardcheck.sh` arm (b2)'s real-engine vehicle moved from
`a*a*a*a*a*b` (now refused at admission, correctly) to `(a*){20}b`, so that arm keeps proving what it was
written to prove. Two evasion classes found in the PR review are asserted in the same gate: clause-1's scope
collector now reads a nested group's body at every depth (`((a*a*a*a*)b)c`, `(?:x(?:a*a*)y`), and a lazy `?`
suffix after a quantifier is part of the same atom, not a delimiter that breaks adjacency
(`a*?a*?a*?a*?b`) — both refused with the same message; the admit set keeps its lazy and nested members
(`\d+\s*?\w+`, `((a*?)b*)c`, `a{1,4}?b{1,4}?`).

Fixed by @pt-act.
