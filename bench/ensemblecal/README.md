# ensemblecal — the family-calibration harness for `--ensemble` and `--quality-panel`

The measurement behind **`docs/EVALS.md` §9** (four families, `--verb ensemble`, the default) and
**§9.9** (six families, `--verb panel`). It answers four questions and nothing else:

1. how often does each evidence family fire, and where do the shipped thresholds sit in a corpus's
   own distribution;
2. do the families **correlate** — the orthogonality test that decides whether the join is four
   signals or one signal wearing four hats;
3. how many symbols trip 1 / 2 / 3 / 4 families, and which combinations dominate;
4. does a family flag the **same symbols over time**, or jitter.

It computes no metric of its own. Every number is parsed out of `--ensemble` (or
`--quality-panel=lenient`), `--readability` and `--metrics`, through their existing entry points.

**The family list is read from the verb's own root element**, never hardcoded here — `families=` /
`enabled=`. A family added to a verb is therefore measured the moment it ships, instead of going
missing because this harness was not updated alongside it. That is why the same code produces a 4×4
matrix on `--verb ensemble` and a 6×6 one on `--verb panel`.

**`--verb panel` runs the LENIENT preset on purpose.** Its cut of 1 emits a row for every symbol where
any family fired, which is the census φ is computed over; a higher cut would drop exactly the
single-family rows the coefficient needs.

## Running it

```bash
# 1. per-corpus scan. LABEL is optional; the third field marks a corpus as INDEPENDENT evidence,
#    and only those are pooled.
python3 bench/ensemblecal/run_ensemblecal.py collect --out cal.json \
    /path/to/repo:myrepo:indep  /path/to/other:other:indep  /path/to/sibling:sibling

# 2. stability. This CHECKS OUT PAST COMMITS — point it at a throwaway clone, never a working tree.
git clone --local --shared /path/to/repo /tmp/repo-clone
python3 bench/ensemblecal/run_ensemblecal.py stability --out stab.json /tmp/repo-clone:myrepo --samples 8

# 3. report
python3 bench/ensemblecal/run_ensemblecal.py report --in cal.json --stability stab.json

# …or the same three with --verb panel, to measure the six-family --quality-panel instead.
```

`RIPWIRE_BIN` overrides the binary (default `./build/ripwire`).

## The rules it follows, and why

- **Independence is declared, never assumed.** Two checkouts of one project, a repo and its own
  subdirectory, or a fork and its ancestor are one piece of evidence. Only corpora marked `indep`
  are pooled; the rest are reported beside them and never summed in.
- **The denominator is the full eligible set**, not the rows the verb printed. Symbols where no
  family fired are all-zero vectors in the correlation, not missing rows — dropping them would
  manufacture correlation out of nothing. `collect` refuses a run whose symbol listing was capped.
- **A family that could not be measured is `UNAVAILABLE`**, is excluded from every correlation it
  would enter, and shrinks that corpus's denominator for the pooled historical figures. A family
  that *was* measured and stayed silent is a zero. These are different facts and the report keeps
  them apart.
- **φ is undefined, not zero, when an indicator is constant.** That case is real: the confusion
  family cannot fire outside C/C++/ObjC, so on a Rust corpus it is constant-zero and every φ
  involving it is `nan`. The report prints `nan` rather than a fabricated 0.000.
- **Stability fixes the instrument and varies the corpus** — one binary over many commits, and
  comparisons restricted to symbols present in *both* trees, so added and deleted code cannot look
  like jitter.
- **A candidate family is measured BEFORE it is enabled by default, not after.** Both of §9.9's new
  families were run through this harness on §9's own corpora first, and the stability pass is the
  reason `strict` counts four families rather than five: `colocation` came out below the criterion-C1
  cut on the ladder where the corpus grew. `UNSTABLE_FOR_GATING` in the harness names the families
  that verdict excludes, and it is one list for both verbs.

## Corpus caveat that belongs beside every number

A preset derived from one codebase overfits to that codebase's conventions. The §9 run used nine
trees of which five were independent, all reachable on one machine, four of them private. Re-derive
on your own tree before pointing a gate at any of it.
