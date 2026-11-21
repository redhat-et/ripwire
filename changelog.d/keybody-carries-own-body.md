### Fixed — a `--for` answer's key-body group carries its own body again, whatever else the page serves

The group `<bodies of="key">` adds the definition body of each symbol the question names in backticks. It used
to be handed the first 12,000 bytes of the finished answer and drop any definition whose body was already in
there, so once another section's body landed on page 1 the group silently lost its own copy of it — and
*which* copy it lost depended on which body that other section happened to serve. The group no longer reads
the page: a body served elsewhere on the same page does not satisfy this contract, so the same `p=` and `l=`
appearing both in the key group and in a row section is correct and intended.

Measured on 89 `--for` questions over 89 repositories, one binary pair, same corpus: the fix moves **three**
cells and costs **+4,760 bytes in total**, all of it the restored bodies. On **2 of those 3 cells the group
had been emptied completely** — every backticked definition suppressed, so a question that named symbols got
no key bodies at all. On the third the group survived but **`total=` was under-reporting**: the suppression ran
before the count, so an answer disclosed `total="3" capped="0"` for a task with five keyed definitions. On a
check fixture the same defect produced `<bodies of="key" shown="3" total="3" capped="1">` with no `next=` —
`capped=` claiming a cut, `shown`=`total` claiming nothing was withheld, and the pointer the legend promises
for a cut simply absent. Both are fixed, because nothing is removed before the count, and the disclosure
triple is now gated: `capped="1"` iff `shown` < `total` iff `next=` is present. Page counts, page-1 tail rows
and `deferred=` are unchanged on all 89 cells — the group's bytes are not counted against the page budget, so
nothing is displaced.

What it does NOT mean: the restored body is a duplicate of one the page already carries, so this buys no new
information on a page that already had it — all four retrieval rungs measured flat. It buys the contract, and
it makes the group independent of the body selector: with the body fold switched off entirely, the key group
is now byte-identical (911 B and 2,693 B on the two cells checked), where before it changed.
