# M1 look-back harness — does `--hotspots` point at the code that gets bug fixes?

This directory is the measurement pipeline for the **M1 look-back** pre-registration (draft stage): at a past
commit T, rank a repository's units by `--hotspots` and by simpler baselines, label the units that receive
bug-fix commits in the six months after T, and score each order **per line of code a reviewer reads**
(Popt, recall@20% LOC, AUROC).

It is research infrastructure, not a product surface. Nothing here claims a result. The registration is not
frozen yet; until it is, every constant below may still change, and every change is logged with its reason.

## Files

| File | What it does |
|---|---|
| `common.py` | Every FROZEN constant (thresholds, windows, regexes, word lists, salts, path rules) and the git helper |
| `exclusions.py` + `exclusions_hand.txt` | Builds the exclusion list E (repositories the tool was developed or measured against): a mechanical scan of this tree plus dataset rows and tracker text, merged with a hand list; prints the list's SHA-256 |
| `selectrepos.py` | The metadata screen through `gh api` (no clone): candidate search, the eligibility funnel, per-stratum counts, and the salted hash order. Named so it does not shadow the stdlib `select` module that `subprocess` imports |
| `labels.py` | T and the windows; the bug-fix rule: route A (issue-linked), route B (`fix:` Conventional Commits), the keyword rule |
| `maphunks.py` | The ONE hunk-to-unit mapper, shared by labels and look-back predictors; rename tracking along the first-parent chain |
| `rankers.py` | Runs the installed ripwire (`--hotspots` every page, `--metrics` every symbol), the §4.3 health checks, git look-back churn/prior, and every arm's score |
| `metrics.py` | Tie-block effort curve, Popt, recall@20%, AUROC — exact integer/rational arithmetic |
| `analyze.py` | Per-repository pooling, the repository-cluster bootstrap, §6's pass/fail conditions, §7's power arithmetic |
| `runrepo.py` | One repository end to end in the registered order: ranking table, label table, both hashed, then one join and score |
| `tsparse.py` | The independent function parser: ctypes over the vendored tree-sitter runtime and grammars, this harness's own queries |
| `fngrain.py` | Function grain: population at T, the ripwire join, look-back CHURN/PRIOR through the one mapper, A1 hand-check cards |
| `test_lookback.py` | Synthetic unit tests (hand-computed curves, the tie-block identity, regex cases, toy git repositories with known fixes). Reads no corpus, runs no ripwire, uses no network |

Run the tests with `python3 bench/lookback/test_lookback.py` (stdlib only; about a second).

## Order of operations (why the tables are hashed)

`runrepo.py` writes the **ranking table** (every arm's score for every unit at each T) and the **label table**
(the FIXED units per window and rule) to separate files and records their SHA-256 values before it joins them.
It joins and scores once. With `--seal`, scores go to `scores.sealed.json` and only that file's hash is
printed, so a pilot can be run for its mechanics without anyone reading its scores.

## Function grain (the primary grain)

`tsparse.py` is the independent parser (decision A9, option 2): Python `ctypes` over the tree-sitter runtime and
the grammars vendored in `third_party/deps`, compiled once into a scratch shared library (`build()`), with this
harness's own definition queries. None of ripwire's extraction code or queries is used. Limitation: labels and
ripwire share the same upstream grammar builds, so a grammar mis-parse is common-mode.

`runrepo.py --grain function --ts-cache DIR` runs the function grain (`fngrain.py`):
- the population is every named function/method with a body in product source at T (nested ones collapse into
  the outermost); effort is its span in lines;
- the join (§4.3): a unit joins the ONE `--graph-query=all` row with its path and name whose line is within ±3 of
  its start; `ccx=`/`in=` come from the `--metrics` row with that path and name (scope breaks a tie). `--metrics`
  merges same-name definitions into one row (`overloads=N`); such units have no per-definition ccx and are
  dropped as ambiguous matches, counted against the 90% join floor;
- CHURN / PRIOR map every look-back commit's hunks (merges through their combined diff) at the commit's parent,
  carried to T's paths by a rename map built over the first-parent chain;
- labels map fix hunks at each fix's parent; every hunk of a primary-route fix in a population file is written to
  `a1_records.json` with a source excerpt, the A1 hand-check frame (`maphunks.a1_sample`).

## ripwire's own blind spots the health floors must catch

- ripwire 0.6.4 prunes every directory NAMED `build`, `dist`, `out`, `target`, `vendor`, `captures` (and a few more;
  `common.RIPWIRE_PRUNED_DIRS`) wherever it sits, so tracked product source inside, say, a Python package called
  `build` is never read, and `--skipped` counts such directories (`pruned_dirs=`) without naming them. Those files
  fall into HOT's bottom tie block with CCX = FANIN = 0. `runrepo.py` counts them against the parse floor
  (`ripwire_read` in the manifest); a (repository, T) below 95% fails its health check and is replaced.
- `--metrics` rows carry no start line (`--pack-signatures` is capped at 50 rows), so the join reads lines from
  `--graph-query=all`; and `--metrics` merges same-name definitions (Java overloads, Go methods of one name on
  several receivers), which drops those units from the scored population.

## Budget notes (measured, for planning the main run)

- The GitHub GraphQL budget (5,000 points an hour) is the metadata screen's bottleneck: route A pages issue
  searches 100 at a time. Route B reads the REST commits list instead (a separate 5,000-an-hour budget). Every
  screen verdict is cached per repository, so an interrupted screen resumes.
- A GitHub budget wait is never a failed attempt, and an unanswered call is never cached as a verdict.

## Known interpretations (each is a registration detail to confirm before freeze)

- Route-B eligibility counts **non-merge** 2025 commits; a merge's subject is the PR title when the merge is a
  GitHub `Merge pull request` commit.
- Author counts exclude bot identities (`[bot]` logins, `dependabot`, `renovate`, `github-actions`, …).
- The product-source rule is per stratum: a C/C++ repository's product source is its C/C++ files, and so on.
- The pooled C/C++ stratum keeps the top 1,000 of the union of the `language:C` and `language:C++` searches.
- The file count screened from metadata applies the path rule only; the generated-marker rule needs file
  contents and is applied at T after clone, so the metadata count is an upper bound.
- A file's effort is its line count with a floor of 1 (an empty file cannot have zero effort).
