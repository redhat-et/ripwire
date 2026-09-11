# bench/shotgun — Shotgun Surgery, two formulations measured

Throwaway prototypes behind the `docs/EVALS.md` section *"Shotgun Surgery — two formulations measured on two
histories (2026-09-08)"*. They read only what ripwire already produces (the uncapped map) and what git already
records (`git log --name-only`); nothing here is a shipped verb, and the section explains why.

```bash
T="$( mktemp -d )"
git log --format='COMMIT %H %ad %s' --date=short --name-only --no-merges > "$T/log.txt"
./build/ripwire . --top-k=100000 > "$T/map.xml"

python3 bench/shotgun/scatter.py            "$T/log.txt" 30            # (b) per-commit / per-file degree of scatter
python3 bench/shotgun/cc_static.py          "$T/map.xml" 7 5           # (a) Lanza & Marinescu CM>7 AND CC>5, unambiguous edges
python3 bench/shotgun/cc_static.py          "$T/map.xml" 7 5 all       #     the name-based inversion, to see the resolver artifact
python3 bench/shotgun/cc_vs_history.py      "$T/map.xml" "$T/log.txt"  # (a) Spearman: static fan-in-by-files vs historical scatter
python3 bench/shotgun/cochange_backtest.py  "$T/log.txt" 150 0.0       # (c) the shipped --situ rule, precision@8 / recall
python3 bench/shotgun/cochange_backtest.py  "$T/log.txt" 150 0.5       #     the same, partners with deg >= 0.5 only
python3 bench/shotgun/cochange_followup.py  "$T/log.txt" 3 0.5         # (c) is an alarmed partner edited within 3 commits?
```

`scatter.py` takes an optional third argument, a comma-separated list of paths to print every kept commit for.
All five drop commits touching more than 30 files (the Code Maat bulk-commit rule every `--cochange` walk applies)
and consider non-merge commits only. `cochange_backtest.py` and `cochange_followup.py` share one history reader (`cochange_history.py`) and reproduce
`cochangePartners` in `src/gitmine.h` — `together >= 3`, `deg = together / commits(A)`, an 18-month window that
slides with the commit being scored, top 8 by `deg` — and score each commit against PRIOR history only.
