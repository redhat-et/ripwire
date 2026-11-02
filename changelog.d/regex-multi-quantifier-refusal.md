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

**Proportionality** (the review round, measured and adopted): clause 1 no longer refuses any adjacent
intersecting pair — a *same-set* pair (`a*a*`, `.*.*`, `\w+\w+`) refuses, and *three or more* intersecting
atoms in a row refuse as degree-(atoms−1) growth; a cross-set pair (`\s+.*`, `\w+.*`) costs a constant factor
on ordinary source lines (measured: sub-millisecond, and on a 4 KB minified line the rewrite `\w.*TODO`
costs 413 ms against `\w+.*TODO`'s 898 ms — the same order) and is admitted. Nine patterns in a 900-regex
agent sample (1%) were such pairs (`import\s+.*from`, `TODO:\s*.*`, `ERROR.*\d+`, `\w+.*`, `=\s*[^;]+;`,
`^#+.*`); all are re-admitted, and the refusal message now names the pair rewrite — drop one quantifier
(`import\s.*from`), same hits on ordinary source lines. An unquantified group is transparent to the walk
(`(a*)(a*)(a*)(a*)(a*)b`, over 6 s at 80 bytes on libstdc++, now refused), and the walk no longer reads
inside a character class it cannot parse (`[[:alpha:]*.*.*]` is a class, not an adjacency); its skip is
POSIX-aware — a bracket form (`[:alpha:]`, `[.x.]`, `[=x=]`) owns a `]` of its own, and the scan closes the
class only past its terminator. Clause 2 no
longer counts an *optional* (`?`, `{0,1}`) as one of its two repeats — `(https?://(www\.|www2\.)?)?example`
and `(((public|private)\s+)?static\s+)?void` measured sub-0.1 ms and are re-admitted; `((a|aa){2,5}){2,5}b$`
keeps its refusal, because a bounded *repeat* is a repeat.

What this means in practice: these patterns used to reach the engine, where libc++ abandons the match
(`error_complexity`) and libstdc++ has no budget at all and simply does not return. The verdict is now one
answer on every platform, exits 1, and says what is wrong and what to write instead — collapse the atoms
(`a*a*a*` is the language of `a*`), separate them with a literal neither can swallow (`a*b*a*b`), bound
all but one (`a{0,3}a*b`), or drop one quantifier of a pair when a pair is all it is.

It does **not** claim the residual closed. Any *admitted* pattern whose cost in the subject is super-linear
is still unbounded on libstdc++, including a *single-level* bounded quantifier over an unproven-disjoint alternation (`(a|aa){1,100}b$`, measured 7.8 ms at a 21-byte subject rising to 99.1 s at 41 B, roughly 7x per 4 bytes), which no disjointness proof can answer — and the review's own two additions to that disclosure:
`.*x.*x.*x.*x.*y` is four disjoint `.*` separated by literals, admitted, and is the same subject-growth
class; `(a*){20}b` (over 6 s at 80 bytes on libstdc++) is named in `docs/LIMITS.md` with it. That is
disclosed in `docs/LIMITS.md`, and it is why the screen refuses rather than guesses: a refusal is a bounded,
named failure; a hang is not.

Gate: `test/regexmultiquantcheck.sh` (80 assertions over 31 patterns). The two preceding families are
asserted undisplaced in the same gate, and `test/regexguardcheck.sh` arm (b2)'s real-engine vehicle moved from
`a*a*a*a*a*b` (now refused at admission, correctly) to `(a*){20}b`, so that arm keeps proving what it was
written to prove. Four evasion/over-refusal classes found in the PR's two review rounds are asserted in the
same gate: clause-1's scope collector now reads a nested group's body at every depth
(`((a*a*a*a*)b)c`, `(?:x(?:a*a*)y`), a lazy `?` suffix after a quantifier is part of the same atom, not a
delimiter that breaks adjacency (`a*?a*?a*?a*?b`), the pair/three threshold holds both directions
(`a*a*?b` refused, `import\s+.*from` admitted, `\w+.*\w+.*\w+` refused), and the optionals under either
quantifier admit (`(https?://(www\.|www2\.)?)?example`, `((www|www2)?\.){1,5}example`).

Fixed by @pt-act.
