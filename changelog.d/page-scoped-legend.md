### Changed — a paged `--for` answer's page 1 no longer defines, in advance, what only a later page carries

A paged `--for` answer (the default, about 12 KB a page) used to put the WHOLE document legend on page 1, including the clauses
that define rows page 1 does not hold: the hops clause for a `<hops>` that starts on page 3, the fold clause for a `<fold>` on
page 4, `c via=name` for a `<c via="name">` two pages on. Such a clause now travels with the page whose rows carry it: page 1
leaves it out, and each later page that carries its element or attribute ends with one comment holding it verbatim
(`<!-- defined for this page, the rest on page 1; … -->`), before its `<about legend="ref" have="page1"/>`. A later page never
re-sends a clause page 1 still holds. The page clause says so in one sentence: root next= is the next page, "no legend but the
definitions of what only its rows carry (this one defines the rest)".

The rule a reader can rely on: **whatever page N carries is defined on page N or on page 1** — page 1 because every continuation
page names it, nothing between because a page may be asked directly. Nothing is reworded: a moved clause is its dictionary entry,
so `--legend-seen` leaves it out of the later page when the reader holds it, as it does on page 1. Rows are byte-identical. A clause
stays on page 1 when page 1 carries one of its elements or attributes, and also when it is the only page-1 text spelling `a=` for an
attribute a page carries (the hops clause's `n=` is the only `n=` an element-form `<d n=>` meets; with the default row-line form the
row-line clause spells it, so the hops clause can move). The MCP `for` answer is not paged by this path and is unchanged.

MEASURED on the 89 GA1 DEV questions (default argv, page 1 and every followed page): see the lane readout for the figures.
Gate: `test/pagelegendcheck.sh` (the rule per page on two page sizes, in both row forms, with mutation controls).
