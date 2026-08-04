# r5 pre-registration — query-noun-in-name lift under the conceptual route

**Registered 2026-08-03, BEFORE any candidate code ran on any benchmark instance.** Freezes
hypothesis, mechanism, grid, metrics, and decision tree; anything not written here is post-hoc.

## Evidence this is registered from (r3-headroom loss buckets, not locbench)

`bench/headtohead/r3-headroom-2026-08-03/REPORT.md` §(ii), buckets q07/q08 — both conceptual-route
rankings where a symbol carrying the query's own salient noun never surfaced:

- q07: query says "…where the **match** object is produced"; `ResolverMatch` (the answer class,
  fully indexed, correct call edges) absent from the entire `--for` candidate pool at 5× budget.
- q08: query says "when I call form.**is_valid**()…"; `BaseForm.is_valid` ranked **112th** while an
  unrelated same-file `ManagementForm` topped the list at ~2× the next score.

The name-exact router already wins when the query IS a name (`--for=full_clean` → r2). The gap is
**mixed conceptual queries that embed a name or name-fragment**: the subtoken route dilutes the
name evidence into common tokens ("is", "valid", "match").

## Prior art this must answer

The mention anchor (shipped) lifts *literal* `file.py` / `Type.method` / dotted mentions — it does
not fire on a bare noun inside prose ("match object") or a call-spelling fragment ("is_valid()").
The two anchor-hop candidates were rejected for adding score *mass* along edges; this candidate is
again the *slot-ladder* mechanism (forced placement, `max()`, #1 never displaced), not mass.

## Hypothesis

Under the conceptual (subtoken+body) route, a symbol whose WHOLE name contains a query token of
length ≥ `minTokLen` as a name-subtoken (camel/snake boundary match: `match` → `ResolverMatch`;
`is_valid` → `is_valid`) AND that already carries positive body/doc score (anti-noise guard: zero
lexical evidence is never lifted) belongs in the slot ladder below the mention band. This moves
q07/q08-shaped gold into the visible bundle without touching name-exact routing or #1.

## Candidate mechanics (inert by default)

Env-gated `RIPWIRE_NAMEBOOST="<minTokLen>,<maxLifted>"`; unset → byte-identical output. A nonzero
default requires the acceptance gate below.

## Calibration (TRAIN ONLY)

Same harness/flags as r3/r4 (`--split train`, frozen A7 split, held-out untouched). Grid:
(minTokLen, maxLifted) ∈ {4,5} × {2,4} — four cells vs baseline; no post-hoc growth. Selection:
highest train strict file@10; tie → fewer lifted; any cell regressing train single-file strict@10
by >1pp disqualified. **Sequencing:** runs only after the r4 sibling-lift round fully drains
(machine never shared; if r4 ships a default, r5 calibrates on top of the shipped binary).

## Acceptance (held-out, run ONCE, constants baked)

Primary: strict file@10, held-out 243, paired vs env-unset, repo-clustered bootstrap 95% LB per
`GATE_DECISION.md` two-tier. Secondary (report only): any@10, @1, fn-MRR, strata, all-patch; perf
budgets hold with env set. REJECT is archived here and the default stays off. Independent success
probe (report only, not a gate): the two r3-headroom reproducers — `--for=<q07 text>` must surface
`ResolverMatch`, `--for=<q08 text>` must rank `is_valid` inside the emitted bundle — on the pinned
django@70f39e46 checkout.

## 2026-08-04 pre-run amendments (registered before any candidate code exists or ran)

The r3_pathtok and r4_siblift verdicts (both REJECT — `../r3_pathtok/gate_verdict.txt`,
`../r4_siblift/gate_verdict.txt`, required reading before running this round) set three house
precedents this registration adopts now, while amendment is still legitimate:

1. **Primary metric is the multi-file stratum** strict file@10 (aggregate reported as secondary,
   never switched to). Both prior rounds showed these mechanisms only touch the multi-file
   stratum; r3 died on an aggregate that its real +5.66pp stratum effect could not carry.
2. **Targeting audit BEFORE the grid** (the r4 lesson: score-adjacent ≠ gold-adjacent — its
   chooser never picked gold at any setting, making the whole grid moot). On train, before any
   cell runs: for every instance whose gold is currently missed, report whether this candidate's
   trigger (query token ≥ minTokLen matching a gold-symbol name-subtoken, positive evidence)
   actually FIRES on a gold symbol, and its fire rate on non-gold (precision proxy). If gold
   fire-rate on the missed set is under 20%, the round is dead before the grid — archive and stop.
   Note the design distinction this audit tests: nameboost targets by *direct name evidence* (the
   r3 side of the bracket), not by adjacency to a scored neighbor (the r4 side).
3. **Amortize before accept**: tier-1 timing runs only against an implementation whose
   name-subtoken pass is amortized into the existing postings build (no per-query corpus rescan);
   r3's tier-1 tails were an unamortized scan recorded as a deviation, and that mistake is not
   repeated here.

## Outcome

**REJECT AT CALIBRATION (2026-08-04)** — no held-out run spent; see `gate_verdict.txt` for the full
table, the flip ledger, and the choice post-mortem. The amendment-2 targeting audit passed twice
(66.0%/58.8% exact-predicate gold fire-rate on the missed set), but no grid cell moved the
multi-file primary off baseline: the trigger reaches gold, and the (score desc) choice among the
~1,000+ fired symbols re-buries it (gold's median rank within the fired order: 33; top-maxLifted:
1/97). Both django probes null. Default stays off; scaffolding retained. The next registration must
audit the CHOICE statistic, not just the trigger fire-rate.
