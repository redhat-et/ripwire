### Added — a gate for bounding the carried `--for` page, and the reason it is not yet bounded

A routed answer carries a `--for` page, and that page is where a first call goes over a client's character
limit: on the measured question sets, 8 of 69 first calls on one set cross, against 1 of 234 on the others, and all 8 of them carry a page. When an
answer crosses, the client replaces it with a small envelope whose preview lands inside the legend, so the
agent receives no answer rows at all and the answer's own completeness attributes go with them.

`test/carriedpageboundcheck.sh` registers the bar. The mechanism itself is deliberately not built. A spec
ladder does shrink the page — 14,531 B to 8,292 B, 43% — but it shrinks it SILENTLY: the carried page's root
carries no `page=`/`pages=`/`withheld_bytes=` before or after, so an agent would lose 43% of its rows with
nothing saying rows were withheld and no follow-up call to recover them. Shrinking an answer without saying
so is the one thing this output format does not do, so the code was reverted and only the gate landed.

The gate's disclosure arm is the one that caught it, and only after being strengthened: it first passed on
the silent cut by reading an absent set of paging attributes as "nothing was cut". It now compares against a
base binary and fails on a page that is smaller without disclosing.
