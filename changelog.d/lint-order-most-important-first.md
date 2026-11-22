### Changed — a default `--lint` page shows the most important findings first, and `--page-bytes=0` is the whole answer on every paged verb

A default `--lint` answer is a page of findings under the 24,000-character output ceiling, so the order decides what an agent sees first. It used to be file path order: on the eslint tree of the development question set (571 findings, 99 on page 1) the page opened with a `do-while` in `Makefile.js` and then ten rows from a vendored ponyfill under `docs/src/assets/js/`. Findings now sort most important first:

1. files nobody in the repository authors go last — a tool, vendored or generated path, a minified file (`--skipped`'s `minified-suspect`), or a bundle (the same bytes-per-line evidence the ranking lenses already demote by);
2. then rule severity from the lint catalog, `error` before `warn` before `info` (a user rule's own `sev=`);
3. then source files before test, bench and fixture files (the same path tier the ranking lenses already down-weight), then the file's place in the map's PageRank order;
4. then file path, line, rule and text, as before, so the order is still total and deterministic.

Nothing is dropped: following `next=` to the end still yields every finding exactly once, and the set of findings is unchanged.

The rules that found nothing no longer print a `<rule … count="0"/>` row each (31 of 39 rows on that eslint tree). One `<zero_rules n= ran= inert=/>` row after the counted rules names them all: `ran=` the rules that ran on a language the repository holds and matched nothing, `inert=` the rules none of whose languages are there. Every selected rule is still named once.

`--page-bytes=0` now means "the whole answer" on `--lint` (every finding; with `--offset=K`, every one from K) and on `--expand` (every body uncut), as it already did on `--for` and the bare map. Each of the four prints one stderr line, before the answer, when the whole answer is over the output ceiling. `--lint` and `--expand` still page by their own unit, so beside them `--page-bytes` takes `0` only, and it refuses to combine with their own size flags (`--limit=N`, `--pack-budget-bytes=N`), which keep working on their own. Gate: `test/lintordercheck.sh`.
