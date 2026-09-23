#!/usr/bin/env python3
# served_syms_signal.py — the pre-registered scoring procedure for `served_syms` as a miss/abstention
# signal (docs/research/confidence-and-abstention.md §5.4, pre-registered 2026-09-23; fix round 1
# 2026-09-23 after adversarial review `reports/rv-served-syms-prereg.md`).
#
# WHAT THIS IS. `served_syms` (calibrate_confidence.py's `grade()`'s `served_syms=len(head)`) already
# ships on every `--for` bundle as the size of the served head. No number computed UNDER THIS
# PROCEDURE existed when §5.4 was written — but two EXPLORATORY numbers were already seen and are
# disclosed, not hidden: a prior review (`reports/rv-margin-resolution.md`) computed served_syms's
# AUROC as a miss detector at 0.669 (file_hit) / 0.723 (func_hit) on this same 92, and 0.769/0.791 on
# a different 40-row sample — in both cases without an operating point and without a recorded
# orientation (the reviewer's scratch script is lost). The registered orientation below (§5.4.3) is
# INFORMED BY those seen numbers, not blind — say so, don't claim otherwise. This module is the
# scoring itself, run over rows `calibrate_confidence.py`'s `scored_instances()` already produces — it
# reads no LocBench data itself, invokes the binary nowhere, and fetches nothing. It is pure
# post-processing of a `rows` list whose per-row shape already carries `served_syms`, `file_hit`,
# `func_hit`, `confidence`, `margin_pct`, `repo`, `instance_id` (see calibrate_confidence.py's
# `grade()`/`measure_instance()`).
#
# COMMENSURABILITY. Reuses `auroc`, `confusion` and `prf` from bench/arb/score_abstention_calibration.py
# — the registered primitives — rather than re-deriving any of them. The registered orientation (§5.4.3
# — larger served_syms is more miss evidence) warns on the HIGH side of a threshold, but `confusion()`
# only counts the LOW-side predicate `value <= threshold`. Rather than a second counting loop, `_confusion_ge`
# gets there by calling `confusion(labels, values, t - 1)` (exact, because served_syms is an integer)
# and relabelling its four cells — see that function's docstring for the swap. No new loop, no new
# comparison logic; `confusion()` is the only place `<=`/`>=` counting happens in this module.
#
# FIX ROUND 1 (2026-09-23, after `reports/rv-served-syms-prereg.md`, VERDICT NOT READY):
#   HIGH-1 — §5.4.3's mechanism argument (adaptiveCut/kept/hitCeiling) does not run under the
#     registered invocation (that chain is `--adaptive`-only; default `--for` never reads `kept`).
#     Orientation is now registered as "raw value, informed by the seen 0.669/0.723", not derived from
#     a mechanism. ORIENTATION and the no-flip rule are unchanged (the reviewer's own ruling).
#   HIGH-2 — the fingerprint's AUROC tolerance rejected the only 4-dp value the figure it pins was ever
#     published as (0.5805). FINGERPRINT now pins the exact nearest lattice point to that published
#     value, with a per-grain tolerance sized to the AUROC lattice's own step (see FINGERPRINT_AUROC_TOL).
#     Added `rows_len_matches_n`, missing before.
#   HIGH-3 — SR-1 (fire-rate) was folded into the band verdict, so a FAIL could be reported on
#     data where the owner's actual band (false-warn/recall only) WAS met. `choose_operating_point`
#     now returns band_met and sr1_met separately; `score_served_syms` has four outcomes.
#   MEDIUM — "was never scored"/"our best disclosed signal" removed from every sentence (served_syms
#     WAS scored, exploratorily); §5.2's AUROC band is now reported (not gating) via `auroc_band_5_2`.
#
# FROZEN BY THE PRE-REGISTRATION — none of the constants below may be tuned after seeing a served_syms
# number COMPUTED UNDER THIS PROCEDURE; a change to any of them is a new pre-registration, not a bug fix:
#   ORIENTATION        — §5.4.3: +1 == larger served_syms is registered as MORE miss evidence, informed
#                         by the exploratory 0.669/0.723 already seen (not a mechanism derivation).
#   GATING_GRAIN        — §5.4.2: func_hit is the sole grain a PASS is checked against; file_hit is
#                          scored and reported but never gates a PASS.
#   FALSE_WARN_MAX,
#   RECALL_MIN          — §5.2's operating-point band, unchanged: 0.20 / 0.50. (§5.2's separate AUROC
#                          band is reported, not gating here — see auroc_band_5_2.)
#   FIRE_RATE_CEILING    — §5.3 rule 2, carried into this round as SR-1: 0.25. Reported and
#                          verdict-bearing for its OWN outcome (pass_fire_rate_rejected), never folded
#                          silently into band_met.
#   FINGERPRINT          — §5.4.1's reproduction figures, checked before anything else runs.
#   BOOTSTRAP_SEED,
#   BOOTSTRAP_RESAMPLES  — §5.4.5: fixed so a re-run reproduces the same interval.
#
# USAGE (library). `from served_syms_signal import score_served_syms`; called by
# calibrate_confidence.py's main() with the `summary` dict it already built and the `rows` list that
# produced it. Direct unit tests live in the sibling `test_served_syms_signal.py` (synthetic, hand-built
# rows only — never touches LocBench data or the network; run `python3
# bench/locbench/test_served_syms_signal.py`).
#
# R-MARGIN ADDENDUM (lane/margin-rescore, 2026-09-23; docs/research/confidence-and-abstention.md §5.5).
# §5.5 pre-commits that if `served_syms` does NOT reach the band, `margin_bp` gets exactly ONE
# re-score, "the same §5.4.4 threshold procedure (candidate set, tie rule, SR-1), substituting
# margin_bp for served_syms" but under margin_bp's OWN fixed orientation ("warn iff margin_bp <= t" —
# the opposite direction from served_syms's "warn iff served_syms >= t"). Rather than fork a second
# copy of this module (and risk the two drifting), the internal primitives below (`_confusion_ge` /
# `sweep` / `choose_operating_point` / the two bootstrap functions) are generalised to take an explicit
# `direction` ("ge" or "le") and, for the bootstrap/AUROC helpers, an explicit `statistic` (the row key)
# and `orientation` (the AUROC score sign) — each with a DEFAULT that reproduces the served_syms
# behaviour exactly, so `score_served_syms` and every existing call site are unchanged byte-for-byte
# (proven in `test_served_syms_signal.py`'s `test_sweep_direction_ge_default_matches_original_sweep`
# and the end-to-end served_syms regression tests, which all still pass unmodified). `score_margin_bp`
# at the bottom of this file is the new, parallel entry point: same band (0.20/0.50/0.25), same gating
# grain (func_hit), same §5.4.1 fingerprint check (a population property, not a statistic property, so
# entirely unchanged), different statistic key, different direction, different frozen orientation.
import pathlib, random, sys

HERE = pathlib.Path( __file__ ).resolve().parent
sys.path.insert( 0, str( HERE.parent / "arb" ) )
from score_abstention_calibration import auroc, confusion, prf   # the registered primitives

# ── frozen constants (docs/research/confidence-and-abstention.md §5.4) ──────────────────────────────
ORIENTATION = 1   # +1: larger served_syms == more miss evidence — the raw value, informed by the
                  # exploratory 0.669/0.723 AUROC already seen on this population (§5.4.3; fix round 1
                  # dropped the adaptiveCut/hitCeiling mechanism argument, which does not run under
                  # default --for). sweep()'s `>=` direction is hardwired to this value (asserted
                  # below) — changing ORIENTATION is a new pre-registration decision, not a config
                  # flip, and must change the comparison direction in _confusion_ge/sweep() too.
assert ORIENTATION == 1, "ORIENTATION changed without updating _confusion_ge's >= direction to match"

GATING_GRAIN = "func_hit"          # §5.4.2 — the sole grain a PASS is checked against
FALSE_WARN_MAX = 0.20              # §5.2's operating-point band
RECALL_MIN = 0.50                  # §5.2's operating-point band
FIRE_RATE_CEILING = 0.25           # §5.3 rule 2 / this round's SR-1 — reported, own outcome (HIGH-3)

# §5.2's SEPARATE AUROC band (distinct from the operating-point band above), reported per grain,
# never gating a PASS/FAIL here (MEDIUM-3 — the owner's question in this round is the operating point).
AUROC_MEETS_5_2 = 0.70
AUROC_WEAK_5_2 = 0.60
AUROC_REFUTATION_5_2 = 0.35        # <= this: reported as a directional refutation, never re-read as a pass


def auroc_band_5_2( auc ):
    """§5.2's AUROC band ('>= 0.70 meets · [0.60,0.70) weak · <0.60 does not meet · <=0.35 directional
    refutation'), REPORTED only. Deliberately not `score_abstention_calibration.py`'s own `auroc_band()`
    — that function implements the ARB round-one registration's band (0.65/0.55/0.35), a DIFFERENT
    numeric registration that happens to share only the 0.35 directional-refutation cut with §5.2's."""
    if auc is None:
        return None
    if auc >= AUROC_MEETS_5_2:
        return "meets"
    if auc >= AUROC_WEAK_5_2:
        return "weak"
    if auc <= AUROC_REFUTATION_5_2:
        return "does_not_meet_opposite_direction"
    return "does_not_meet"


# §5.4.1's reproduction figures. "score" here is the arb_score (confidence=/margin_pct= combined)
# AUROC calibrate_confidence.py's discrimination() already computes — the doc calls it "margin_pct=/
# score AUROC" because on this corpus margin_pct= carries no information confidence= does not already
# carry (§3.3: "margin_pct= adds no ordering information to confidence=").
#
# score_auroc pins the EXACT nearest achievable lattice point to the published figure, not the
# published figure's own rounding (fix round 1, HIGH-2): AUROC over an m-miss/h-hit population is
# k/(m*h) for half-integer k (Mann-Whitney with tie-averaging, exactly what auroc() computes), so
# "0.580" (§3.3's 3-dp rendering) and "0.5805"/"0.581" (reports/rv-margin-resolution.md, a later
# binary, same 92) can only BOTH be true of one real run if the true value is near 670.5/1155:
#   file_hit: 15 misses x 77 hits = 1155 pairs; 670.5/1155 = 0.580519 (prints 0.580 at 3dp, 0.5805/
#             0.581 at 4dp/3sf, matching both published renderings).
#   func_hit: 38 misses x 54 hits = 2052 pairs; 1276.5/2052 = 0.622076 (prints 0.622 at 3dp, 0.6221
#             at 4dp, matching both published renderings).
FINGERPRINT = dict(
    n=92, confidence_low=74, confidence_high=18,
    misses=dict( file_hit=15, func_hit=38 ),
    score_auroc=dict( file_hit=670.5 / 1155, func_hit=1276.5 / 2052 ),
)
# Per-grain tolerance sized to that grain's OWN lattice step (0.5/(misses*hits)), not a shared guess:
# admits the pinned point plus its two nearest neighbours (+-1 step) and excludes the next step out.
#   file_hit: step = 0.5/1155 = 0.0004329 -> tol 0.0006 admits k in {670, 670.5, 671} (0.0006 > 1 step,
#             < 2 steps = 0.0008658).
#   func_hit: step = 0.5/2052 = 0.0002437 -> tol 0.0003 admits k in {1276, 1276.5, 1277} (0.0003 > 1
#             step, < 2 steps = 0.0004874).
FINGERPRINT_AUROC_TOL = dict( file_hit=0.0006, func_hit=0.0003 )

BOOTSTRAP_SEED = "ripwire-served-syms-prereg-v1"
BOOTSTRAP_RESAMPLES = 10000


# ── §5.4.1 — population fingerprint ─────────────────────────────────────────────────────────────────
def check_fingerprint( summary, rows=None ):
    """(ok, detail). ok is True iff this run's population reproduces every one of §5.4.1's pinned
    figures on `summary` (calibrate_confidence.py's already-built summary dict, read here, never
    recomputed). detail is always returned, even when ok, so a report can quote exactly what matched.

    `rows`, optional: when given, also checks `len(rows) == summary["n_scored"]` (fix round 1, HIGH-2's
    "count checks" / the reviewer's C9 — nothing today calls this with rows=None except a caller that
    only wants to check the summary in isolation, e.g. a unit test; `score_served_syms` always passes
    rows, so the real gate always runs this check)."""
    n = summary["n_scored"]
    high = summary["overall"]["confidence_high"]
    low = n - high
    misses = { g: summary["discrimination"][g]["misses"] for g in ( "file_hit", "func_hit" ) }
    score_auroc = { g: summary["discrimination"][g]["auroc"] for g in ( "file_hit", "func_hit" ) }

    def close( a, b, tol ):
        return a is not None and abs( a - b ) <= tol

    checks = dict(
        n=( n == FINGERPRINT["n"] ),
        confidence_low=( low == FINGERPRINT["confidence_low"] ),
        confidence_high=( high == FINGERPRINT["confidence_high"] ),
        misses_file_hit=( misses["file_hit"] == FINGERPRINT["misses"]["file_hit"] ),
        misses_func_hit=( misses["func_hit"] == FINGERPRINT["misses"]["func_hit"] ),
        score_auroc_file_hit=close( score_auroc["file_hit"], FINGERPRINT["score_auroc"]["file_hit"],
                                    FINGERPRINT_AUROC_TOL["file_hit"] ),
        score_auroc_func_hit=close( score_auroc["func_hit"], FINGERPRINT["score_auroc"]["func_hit"],
                                    FINGERPRINT_AUROC_TOL["func_hit"] ),
    )
    if rows is not None:
        checks["rows_len_matches_n"] = ( len( rows ) == n )
    ok = all( checks.values() )
    return ok, dict( checks=checks,
                     measured=dict( n=n, confidence_low=low, confidence_high=high,
                                   misses=misses, score_auroc=score_auroc,
                                   rows_len=( len( rows ) if rows is not None else None ) ),
                     expected=FINGERPRINT )


# ── §5.4.4 — threshold procedure ────────────────────────────────────────────────────────────────────
def _is_served_syms_int( v ):
    """True iff `v` is a real integer count — `bool` is excluded even though `isinstance(True, int)`
    is `True` in Python, because a bool is never a served_syms value and letting one through would
    silently do `True - 1 == 0` arithmetic on the threshold."""
    return isinstance( v, int ) and not isinstance( v, bool )


def _confusion_ge( labels, values, t ):
    """tp/fn/fp/tn for the registered rule `warn(row) <=> served_syms(row) >= t`, reusing
    score_abstention_calibration.py's `confusion()` rather than re-looping — no new counting logic.

    `confusion(labels, values, t - 1)` computes the OPPOSITE-direction predicate
    `predicted_abstain = value <= t - 1`, which (served_syms being an integer, per §5.4.2, so `t - 1`
    is exact) is precisely `NOT (value >= t)` — the complement of the rule this round registers. Every
    row confusion() counts as its "abstain" is therefore a row THIS rule does NOT warn on, and vice
    versa, so tp/fn and fp/tn swap places: confusion()'s tp' (label True, predicted-abstain True) is
    exactly this rule's fn (label True, warned False), and so on for the other three cells.

    VALIDATE (review LOW-1, folded into MEDIUM-4's commit): the `t - 1` trick above is exact only when
    every value and every candidate `t` is a real int, which `grade()`'s `served_syms=len(head)` always
    is today — but a non-integer input would otherwise silently miscount (a float `t` shifts the cut
    point by less than one whole unit, which the half-open `<=`/`>=` boundary does not tolerate). Raise
    rather than degrade: this predicate is cheap enough, and this path's whole purpose is being the one
    place `<=`/`>=` counting happens, that a silent wrong count here is worse than a loud refusal."""
    if not all( _is_served_syms_int( v ) for v in values ):
        raise ValueError( "_confusion_ge: every served_syms value must be a real int (the `t - 1` "
                          "trick is exact only for integers) -- got %r" %
                          ( [ v for v in values if not _is_served_syms_int( v ) ][:3], ) )
    if not _is_served_syms_int( t ):
        raise ValueError( "_confusion_ge: threshold t must be a real int, same reason -- got %r" % ( t, ) )
    tp2, fn2, fp2, tn2 = confusion( labels, values, t - 1 )
    return fn2, tp2, tn2, fp2


def _confusion_le( labels, values, t ):
    """tp/fn/fp/tn for the rule `warn(row) <=> value(row) <= t` — §5.5's margin_bp orientation
    ("warn iff margin_bp <= t"), the mirror image of `_confusion_ge`. Unlike `_confusion_ge`, this
    needs no swap-and-shift trick: `confusion(labels, values, t)`'s own predicate is already
    `predicted_abstain = value <= t`, i.e. exactly this rule's `warn`, cell for cell — "abstain" in
    that function's vocabulary and "warn" in this round's are the same decision (flag the row for a
    human), just named for two different registrations of the same underlying idea. So `confusion()`'s
    tp/fn/fp/tn ARE this rule's tp/fn/fp/tn, unrelabelled. Kept as its own named function (rather than
    calling `confusion` directly at each call site) so every `<=`/`>=` counting decision in this module
    still goes through one of exactly two named, docstringed functions — never a bare comparison."""
    tp, fn, fp, tn = confusion( labels, values, t )
    return tp, fn, fp, tn


def _confusion_dir( labels, values, t, direction ):
    """Dispatch to `_confusion_ge` or `_confusion_le` by `direction` ("ge" | "le") — the one place a
    caller that is generic over direction (R-MARGIN's `sweep`/bootstrap helpers) picks which rule
    applies, so the two counting functions above stay the only places comparisons happen."""
    if direction == "ge":
        return _confusion_ge( labels, values, t )
    if direction == "le":
        return _confusion_le( labels, values, t )
    raise ValueError( "_confusion_dir: direction must be 'ge' or 'le', got %r" % ( direction, ) )


def _sweep_dir( labels, values, direction ):
    """The full §5.4.4 threshold table, generalised over `direction` ("ge": warn iff value >= t, the
    served_syms rule; "le": warn iff value <= t, §5.5's margin_bp rule). Candidate set T is always
    distinct(values) plus ONE sentinel that represents "warn on nobody" — which value that sentinel
    takes depends on direction, since "warn on nobody" sits on the opposite side of the data for each
    rule: `max(values)+1` for "ge" (a threshold above every value warns on none), `min(values)-1` for
    "le" (a threshold below every value warns on none). `sweep(labels, values)` (unchanged, below) is
    exactly `_sweep_dir(labels, values, "ge")` — this function does not change served_syms's own table
    in any way, it only factors out what `sweep` already did so `direction="le"` can reuse it.
    One row per candidate t: recall, false_warn (= prf()'s `false_abstain_rate`, relabelled to this
    round's vocabulary), warn_rate (= (tp+fp)/n, the fraction of rows this t would warn on — what SR-1
    gates), `band` (recall/false_warn alone, the owner's actual question, per HIGH-3), `safe` (`band`
    AND warn_rate under SR-1's ceiling — what `choose_operating_point`'s real-PASS branch requires),
    and the raw confusion counts."""
    if not values:
        return []
    distinct = sorted( set( values ) )
    if direction == "ge":
        candidates = distinct + [ max( values ) + 1 ]
    elif direction == "le":
        candidates = [ min( values ) - 1 ] + distinct
    else:
        raise ValueError( "_sweep_dir: direction must be 'ge' or 'le', got %r" % ( direction, ) )
    n = len( labels )
    table = []
    for t in candidates:
        tp, fn, fp, tn = _confusion_dir( labels, values, t, direction )
        stats = prf( tp, fn, fp, tn )
        recall, false_warn = stats["recall"], stats["false_abstain_rate"]
        warn_rate = ( tp + fp ) / n if n else None
        band = ( false_warn is not None and false_warn <= FALSE_WARN_MAX
                and recall is not None and recall >= RECALL_MIN )
        safe = band and warn_rate is not None and warn_rate <= FIRE_RATE_CEILING
        table.append( dict( threshold=t, recall=recall, false_warn=false_warn,
                            precision=stats["precision"], f1=stats["f1"], warn_rate=warn_rate,
                            band=band, safe=safe, tp=tp, fn=fn, fp=fp, tn=tn ) )
    return table


def sweep( labels, values ):
    """served_syms's own §5.4.4 table — `warn(row) <=> served_syms(row) >= t` — unchanged from before
    the R-MARGIN generalisation: exactly `_sweep_dir(labels, values, "ge")`."""
    return _sweep_dir( labels, values, "ge" )


def choose_operating_point( table, n_rows, direction="ge" ):
    """The §5.4.4 tie rule, SR-1, and the HIGH-3 split, applied to a threshold table (either `sweep()`'s
    own, or any hand-built table of {threshold, recall, false_warn, warn_rate, ...} rows — this function
    derives band/SR-1 membership itself from those four raw fields rather than trusting `sweep()`'s own
    `band`/`safe` columns, so the two can never silently disagree and a hand-built test fixture that
    omits those columns still works). Returns {"band_met", "sr1_met", "chosen", "best_band_only"}:
      - band_met: True iff SOME t satisfies the owner's actual band (false_warn<=0.20, recall>=0.50),
        regardless of SR-1 — this is what "PASS on the 92" means per §5.4.4's verbatim verdict rule.
      - best_band_only: the highest-recall row among ALL band-satisfying rows, ties broken toward the
        MORE CONSERVATIVE (fewer-false-warnings) threshold, ignoring SR-1 — the point a
        pass_fire_rate_rejected sentence cites.
      - sr1_met: True iff some band-satisfying row ALSO clears the fire-rate ceiling.
      - chosen: the tie-rule winner among band-AND-SR1 rows (None unless sr1_met) — the point a real
        PASS sentence cites, and what SR-3 freezes for §5.2's replication.
    n_rows is accepted for symmetry with the doc's phrasing but is not needed separately: `warn_rate`
    in each row already carries the (tp+fp)/n_rows fraction.

    `direction` ("ge", the default — unchanged behaviour for served_syms; or "le" — R-MARGIN's
    margin_bp rule): which threshold is "more conservative" on a recall tie is the OPPOSITE side of
    the data for each rule, because each warns on a different subset as its threshold moves. For "ge"
    (`warn iff value >= t`), a LARGER t warns on a subset of what a smaller t warns on (fewer
    false-warnings) — §5.4.4's own stated tie rule, "ties broken toward the more conservative side …
    translated to this rule's >=-warns-on-large direction", i.e. larger t wins. For "le" (`warn iff
    value <= t`), the subset relationship flips: a SMALLER t warns on a subset of what a larger t
    warns on, so the more-conservative, fewer-false-warnings choice at a given recall is the SMALLER t
    — the same general principle (ties broken toward fewer false warnings), translated to the opposite
    inequality, not a new rule."""
    if direction not in ( "ge", "le" ):
        raise ValueError( "choose_operating_point: direction must be 'ge' or 'le', got %r" % ( direction, ) )

    def in_band( r ):
        return ( r["false_warn"] is not None and r["false_warn"] <= FALSE_WARN_MAX
                and r["recall"] is not None and r["recall"] >= RECALL_MIN )

    def clears_sr1( r ):
        return r["warn_rate"] is not None and r["warn_rate"] <= FIRE_RATE_CEILING

    # tie key: always maximise recall first; among recall ties, favour the more-conservative threshold
    # — largest t for "ge" (matches the unmodified served_syms behaviour exactly), smallest t for "le".
    def tie_key( r ):
        return ( r["recall"], r["threshold"] if direction == "ge" else -r["threshold"] )

    def pick( rows ):
        return max( rows, key=tie_key ) if rows else None

    band_rows = [ r for r in table if in_band( r ) ]
    safe_rows = [ r for r in band_rows if clears_sr1( r ) ]
    return dict( band_met=bool( band_rows ), sr1_met=bool( safe_rows ),
                best_band_only=pick( band_rows ), chosen=pick( safe_rows ) )


# ── §5.4.5 — uncertainty ────────────────────────────────────────────────────────────────────────────
def _by_repo( rows ):
    out = {}
    for r in rows:
        out.setdefault( r["repo"], [] ).append( r )
    return out


def _quantile_ci( boots, alpha=0.025 ):
    """(lo, hi, n_usable) from a sorted-on-return bootstrap distribution. Empty input -> (None, None, 0)."""
    if not boots:
        return None, None, 0
    boots = sorted( boots )
    lo = boots[ max( 0, int( alpha * len( boots ) ) ) ]
    hi = boots[ min( len( boots ) - 1, int( ( 1 - alpha ) * len( boots ) ) ) ]
    return lo, hi, len( boots )


def bootstrap_auroc_ci( rows, grain, seed=BOOTSTRAP_SEED, n_boot=BOOTSTRAP_RESAMPLES,
                        statistic="served_syms", orientation=ORIENTATION ):
    """Repository-clustered bootstrap 95% CI for `statistic`'s AUROC against `grain`'s miss label.
    Default `statistic="served_syms"`, `orientation=ORIENTATION` — reproduces the pre-generalisation
    (R-MARGIN) behaviour exactly. Method: bench/agentloop/analyze.py's `clustered_bootstrap_lower`
    (resample REPOS with replacement, `len(repos)` draws per resample, pool every row belonging to
    the sampled repos, recompute). Independent re-implementation for this row shape and for a
    single-arm AUROC rather than a paired delta — that function is not imported (it is
    paired-delta-specific and inlined in its own module). A resample whose pooled sample is
    single-class on `grain` yields no AUROC (auroc() returns None) and is excluded from the interval;
    the number actually used is returned as n_usable. (lo, hi, n_usable) — the point estimate is
    computed by the caller, once, on the real 92 rows."""
    by_repo = _by_repo( rows )
    repos = sorted( by_repo )
    if not repos:
        return None, None, 0
    rng = random.Random( seed )
    boots = []
    for _ in range( n_boot ):
        sampled_repos = [ rng.choice( repos ) for _ in repos ]
        pooled = [ row for repo in sampled_repos for row in by_repo[repo] ]
        labels = [ not row[grain] for row in pooled ]
        scores = [ orientation * row[statistic] for row in pooled ]
        a = auroc( labels, scores )
        if a is not None:
            boots.append( a )
    lo, hi, n_usable = _quantile_ci( boots )
    return lo, hi, n_usable


def bootstrap_operating_point_ci( rows, grain, t, seed=BOOTSTRAP_SEED, n_boot=BOOTSTRAP_RESAMPLES,
                                  statistic="served_syms", direction="ge" ):
    """Same repo-clustered bootstrap, at the FIXED threshold t — never re-swept per resample (§5.4.5:
    this answers "how stable is THIS t's cell counts", not "would a fresh sweep pick a different t").
    Default `statistic="served_syms"`, `direction="ge"` — reproduces the pre-generalisation (R-MARGIN)
    behaviour exactly. Returns {"false_warn": {...}, "recall": {...}}, each {point, ci_lo, ci_hi,
    n_resamples}. A resample with no positive (or no negative) row on `grain` contributes no reading
    to whichever statistic needs that class and is excluded from that statistic's count only."""
    labels_point = [ not r[grain] for r in rows ]
    values_point = [ r[statistic] for r in rows ]
    tp, fn, fp, tn = _confusion_dir( labels_point, values_point, t, direction )
    point = prf( tp, fn, fp, tn )

    by_repo = _by_repo( rows )
    repos = sorted( by_repo )
    rng = random.Random( seed )
    fw_boots, rc_boots = [], []
    for _ in range( n_boot ):
        sampled_repos = [ rng.choice( repos ) for _ in repos ]
        pooled = [ row for repo in sampled_repos for row in by_repo[repo] ]
        labels = [ not row[grain] for row in pooled ]
        values = [ row[statistic] for row in pooled ]
        tp2, fn2, fp2, tn2 = _confusion_dir( labels, values, t, direction )
        stats = prf( tp2, fn2, fp2, tn2 )
        if stats["false_abstain_rate"] is not None:
            fw_boots.append( stats["false_abstain_rate"] )
        if stats["recall"] is not None:
            rc_boots.append( stats["recall"] )
    fw_lo, fw_hi, fw_n = _quantile_ci( fw_boots )
    rc_lo, rc_hi, rc_n = _quantile_ci( rc_boots )
    return dict( false_warn=dict( point=point["false_abstain_rate"], ci_lo=fw_lo, ci_hi=fw_hi,
                                  n_resamples=fw_n ),
                recall=dict( point=point["recall"], ci_lo=rc_lo, ci_hi=rc_hi, n_resamples=rc_n ) )


# ── §5.4.6 — the assembled result ───────────────────────────────────────────────────────────────────
# Disclosed once, reused in every outcome's sentence so the wording never drifts between them (MEDIUM-1/
# HIGH-1e): served_syms WAS scored once, exploratorily, before this registration -- the sentence must
# say so, never "was never scored", and must say the orientation below was informed by that.
_SEEN_CLAUSE = (
    "served_syms had never been scored against our pre-registered band -- an exploratory AUROC (0.669 "
    "file_hit / 0.723 func_hit) had been computed once in a prior review, on this same 92, without an "
    "operating point or a recorded orientation. Scored now under a named procedure, with the "
    "orientation fixed in advance as the raw value -- informed by that exploratory AUROC having "
    "already been seen, not blind (§5.4.3)" )

PUBLIC_SENTENCE_MISMATCH = (
    _SEEN_CLAUSE + ": the asset tree available today does not reproduce the pre-registered "
    "92-instance population, so no number under this procedure is reported as measured on it." )


def _fmt3( v ):
    return "n/a" if v is None else "%.3f" % v


def _public_sentence_fail( grain, g ):
    return ( _SEEN_CLAUSE + ", it does not reach the band (false-warn <= 0.20 at miss-recall >= 0.50) "
            "on %s: AUROC %s [%s, %s] (§5.2 rung: %s), and no threshold clears both floors "
            "together." %
            ( grain, _fmt3( g["auroc"] ), _fmt3( g["auroc_ci_lo"] ), _fmt3( g["auroc_ci_hi"] ),
             g["auroc_band_5_2"] or "n/a" ) )


def _public_sentence_pass( grain, chosen, op_ci, grain_honesty ):
    fw, rc = op_ci["false_warn"], op_ci["recall"]
    # MEDIUM-4 (delta review, `reports/rv-served-syms-prereg.md`): the non-gating grain's clause must
    # read off `band` (the owner's actual predicate) and `safe` (band + SR-1) SEPARATELY -- `safe`
    # alone conflates the two, so a file_hit row that is genuinely in-band but only above the fire-rate
    # ceiling was reported as "does not meet the same band", which is false (a constructed 92-row PASS
    # at func_hit t=30 with file_hit in-band at t=20, warn_rate 0.293, demonstrated it).
    if grain_honesty["other_safe"]:
        other_verdict = "also meets the band and the fire-rate ceiling"
    elif grain_honesty["other_band"]:
        other_verdict = "meets the band but only above the 25% fire-rate ceiling"
    else:
        other_verdict = "does not meet the band"
    return ( _SEEN_CLAUSE + ", at threshold t=%d served rows it reaches false-warn=%.3f [%s, %s] and "
            "miss-recall=%.3f [%s, %s] on %s (%d/%d and %d/%d bootstrap resamples usable) -- inside "
            "the pre-registered band and within the 25%% fire-rate ceiling (warns on %.1f%% of the "
            "92). At its own best threshold, %s %s. This is an in-sample result on one 92-row sample "
            "(per docs/research/confidence-and-abstention.md §5.2) and licenses 'worth replicating,' "
            "not 'shippable': replication on >=92 fresh held-out instances, at this same frozen "
            "threshold and orientation, has not been run." %
            ( chosen["threshold"], chosen["false_warn"], _fmt3( fw["ci_lo"] ), _fmt3( fw["ci_hi"] ),
             chosen["recall"], _fmt3( rc["ci_lo"] ), _fmt3( rc["ci_hi"] ), grain,
             fw["n_resamples"], BOOTSTRAP_RESAMPLES, rc["n_resamples"], BOOTSTRAP_RESAMPLES,
             chosen["warn_rate"] * 100.0, grain_honesty["other_grain"], other_verdict ) )


def _public_sentence_fire_rate_rejected( grain, best_band_only ):
    return ( _SEEN_CLAUSE + ", it reaches the band at t=%d served rows (false-warn=%.3f, "
            "miss-recall=%.3f on %s) -- but that threshold warns on %.1f%% of the 92, above the 25%% "
            "fire-rate ceiling §5.3 registered (carried into this round as SR-1). It meets the "
            "band and fails the fire-rate self-reject: not a candidate for shipping, and this sample "
            "has no in-band threshold that also clears SR-1." %
            ( best_band_only["threshold"], best_band_only["false_warn"], best_band_only["recall"],
             grain, best_band_only["warn_rate"] * 100.0 ) )


def score_served_syms( summary, rows ):
    """The full §5.4 procedure. `summary` is calibrate_confidence.py's already-built summary dict (read
    only for the §5.4.1 fingerprint check, together with `rows` for the count check); `rows` is its
    `instances` list. Returns a dict meant to be merged into that summary under the key
    "served_syms_5_4" — never mutates either argument.

    Four outcomes (fix round 1, HIGH-3): "fingerprint_mismatch" | "pass" (band met AND SR-1 met) |
    "pass_fire_rate_rejected" (band met at some t, but every such t warns on > 25% of rows) | "fail"
    (no t meets the band at all). `out["pass"]` is True iff outcome == "pass" specifically."""
    fp_ok, fp_detail = check_fingerprint( summary, rows )
    out = dict( fingerprint_ok=fp_ok, fingerprint=fp_detail, orientation=ORIENTATION,
               gating_grain=GATING_GRAIN,
               band=dict( false_warn_max=FALSE_WARN_MAX, recall_min=RECALL_MIN,
                         fire_rate_ceiling=FIRE_RATE_CEILING ),
               auroc_band_5_2=dict( meets=AUROC_MEETS_5_2, weak=AUROC_WEAK_5_2,
                                    refutation=AUROC_REFUTATION_5_2 ),
               asset_tree=summary.get( "meta", {} ).get( "assets" ),
               binary_version=summary.get( "meta", {} ).get( "binary_version" ) )
    if not fp_ok:
        out["outcome"] = "fingerprint_mismatch"
        out["public_sentence"] = PUBLIC_SENTENCE_MISMATCH
        return out

    n = len( rows )
    grains = {}
    for grain in ( "file_hit", "func_hit" ):
        labels = [ not r[grain] for r in rows ]
        scores = [ ORIENTATION * r["served_syms"] for r in rows ]
        auc = auroc( labels, scores )
        ci_lo, ci_hi, n_res = bootstrap_auroc_ci( rows, grain )
        table = sweep( labels, [ r["served_syms"] for r in rows ] )
        grains[grain] = dict( n=n, misses=sum( labels ), auroc=auc,
                              auroc_ci_lo=ci_lo, auroc_ci_hi=ci_hi, auroc_ci_resamples=n_res,
                              auroc_band_5_2=auroc_band_5_2( auc ), sweep=table )
    out["grains"] = grains

    op = choose_operating_point( grains[GATING_GRAIN]["sweep"], n )
    out["band_met"] = op["band_met"]
    out["sr1_met"] = op["sr1_met"]
    out["chosen_threshold"] = op["chosen"]
    out["best_band_only_threshold"] = op["best_band_only"]

    if op["band_met"] and op["sr1_met"]:
        chosen = op["chosen"]
        op_ci = bootstrap_operating_point_ci( rows, GATING_GRAIN, chosen["threshold"] )
        out["operating_point_ci"] = op_ci
        other_grain = "file_hit" if GATING_GRAIN == "func_hit" else "func_hit"
        other_sweep = grains[other_grain]["sweep"]
        other_band = any( r["band"] for r in other_sweep )     # the owner's actual predicate, alone
        other_safe = any( r["safe"] for r in other_sweep )     # band AND SR-1 -- a STRICTER subset
        out["grain_honesty"] = dict( gating_grain=GATING_GRAIN, gating_grain_pass=True,
                                     other_grain=other_grain,
                                     other_band=other_band, other_safe=other_safe,
                                     # kept for callers still reading the pre-MEDIUM-4 field name;
                                     # equal to `other_safe`, never the weaker `other_band`.
                                     other_grain_pass=other_safe )
        out["outcome"] = "pass"
        out["pass"] = True
        out["public_sentence"] = _public_sentence_pass( GATING_GRAIN, chosen, op_ci, out["grain_honesty"] )
    elif op["band_met"]:
        out["outcome"] = "pass_fire_rate_rejected"
        out["pass"] = False
        out["public_sentence"] = _public_sentence_fire_rate_rejected( GATING_GRAIN, op["best_band_only"] )
    else:
        out["outcome"] = "fail"
        out["pass"] = False
        out["public_sentence"] = _public_sentence_fail( GATING_GRAIN, grains[GATING_GRAIN] )
    return out


# ── R-MARGIN (docs/research/confidence-and-abstention.md §5.5) — margin_bp's ONE pre-committed re-score ──
# Fires only because served_syms's own §5.4 run reached a non-pass outcome ("fail" or
# "pass_fire_rate_rejected") on a fingerprint-reproduced population (§5.5, second branch) — that
# branch, and only that branch, licenses this function being called at all; if served_syms had
# reached a real "pass", §5.5's FIRST branch fires instead and `lane/for-margin-resolution` is
# CLOSED without any re-score (a doc-level consequence, not something this module enforces, since
# this module has no way to know which branch applies — it only implements what running the
# re-score means once the caller has determined it is licensed).
#
# FROZEN BY §5.5 — same status as §5.4's own frozen block above, and for the same reason (no tuning
# after a margin_bp number computed under this procedure exists):
#   MARGIN_BP_STATISTIC   — the row key this run scores: `margin_bp` (calibrate_confidence.py's
#                           `root_attrs()`, the unzeroed full-precision drop `deriveForConfidence`
#                           computes — see docs/EVALS.md and confidence-and-abstention.md §1/§2 for
#                           the zeroing mechanism `margin_pct` hides that `margin_bp` does not).
#   MARGIN_BP_DIRECTION    — "le": §5.5 fixes the rule as `warn iff margin_bp <= t`, the OPPOSITE
#                           sense from served_syms's `>= t`, informed by (not derived from) the
#                           already-seen 0.579 (file_hit) / 0.604 (func_hit) AUROC
#                           (reports/rv-margin-resolution.md) having most plausibly been computed
#                           under that direction — the same "informed by a seen number, not blind"
#                           disclosure §5.4.3 makes for served_syms, restated here for margin_bp.
#   MARGIN_BP_ORIENTATION  — -1: AUROC's score must rank "more miss evidence" high regardless of
#                           which raw inequality direction warns, so the oriented score fed to
#                           `auroc()` is `-margin_bp` (smaller margin_bp == larger oriented score ==
#                           more miss evidence), consistent with MARGIN_BP_DIRECTION="le".
#   band / gating grain / fire-rate ceiling — UNCHANGED from served_syms's own (§5.5: "the same
#                           band …, the same gating grain …, the same §5.4.4 threshold procedure").
#   FINGERPRINT             — UNCHANGED, reused via `check_fingerprint` as-is: §5.5 is explicit that
#                           "the population check for that re-score is §5.4.1's fingerprint,
#                           unchanged — not a fingerprint re-derived for margin_bp, because the
#                           fingerprint is a property of the population … not of whichever statistic
#                           is being scored against it". This module never redefines it for margin_bp.
#   BOOTSTRAP_SEED,
#   BOOTSTRAP_RESAMPLES     — UNCHANGED (§5.4.5, reused verbatim: "same seed, same 10,000 resamples").
MARGIN_BP_STATISTIC = "margin_bp"
MARGIN_BP_DIRECTION = "le"
MARGIN_BP_ORIENTATION = -1
assert MARGIN_BP_DIRECTION == "le" and MARGIN_BP_ORIENTATION == -1, (
    "MARGIN_BP_DIRECTION/MARGIN_BP_ORIENTATION changed without a fresh §5.5 registration -- this "
    "module encodes ONE pre-committed orientation, not a free parameter" )

_MARGIN_BP_SEEN_CLAUSE = (
    "margin_bp had not been scored under a named, reproducible procedure against our pre-registered "
    "band -- an exploratory AUROC (0.579 file_hit / 0.604 func_hit, reports/rv-margin-resolution.md) "
    "had been computed once on this same 92, without an operating point. Scored now under "
    "docs/research/confidence-and-abstention.md §5.5's pre-committed, exactly-one re-score, with the "
    "orientation fixed in advance as warn iff margin_bp <= t -- the opposite sense from served_syms, "
    "informed by that exploratory 0.579/0.604 AUROC having already been seen, not blind" )

PUBLIC_SENTENCE_MARGIN_MISMATCH = (
    _MARGIN_BP_SEEN_CLAUSE + ": the asset tree available today does not reproduce the pre-registered "
    "92-instance population (§5.4.1's fingerprint, reused unchanged), so no margin_bp number under "
    "this procedure is reported as measured on it, and §5.5's re-score has not been run." )


def _public_sentence_margin_fail( grain, g ):
    return ( _MARGIN_BP_SEEN_CLAUSE + ", it does not reach the band (false-warn <= 0.20 at "
            "miss-recall >= 0.50) on %s: AUROC %s [%s, %s] (§5.2 rung: %s), and no threshold clears "
            "both floors together. Per §5.5, lane/for-margin-resolution is CLOSED: no second "
            "attempt, no new sample; only the zeroing-mechanism finding (deriveForConfidence zeroes "
            "margin_pct on hitCeiling) survives, as a doc note, not as code." %
            ( grain, _fmt3( g["auroc"] ), _fmt3( g["auroc_ci_lo"] ), _fmt3( g["auroc_ci_hi"] ),
             g["auroc_band_5_2"] or "n/a" ) )


def _public_sentence_margin_pass( grain, chosen, op_ci, grain_honesty ):
    fw, rc = op_ci["false_warn"], op_ci["recall"]
    if grain_honesty["other_safe"]:
        other_verdict = "also meets the band and the fire-rate ceiling"
    elif grain_honesty["other_band"]:
        other_verdict = "meets the band but only above the 25% fire-rate ceiling"
    else:
        other_verdict = "does not meet the band"
    return ( _MARGIN_BP_SEEN_CLAUSE + ", at threshold t=%d (warn iff margin_bp <= t) it reaches "
            "false-warn=%.3f [%s, %s] and miss-recall=%.3f [%s, %s] on %s (%d/%d and %d/%d bootstrap "
            "resamples usable) -- inside the pre-registered band and within the 25%% fire-rate "
            "ceiling (warns on %.1f%% of the 92). At its own best threshold, %s %s. Per §5.5, this "
            "single pre-committed re-score PASSES: lane/for-margin-resolution becomes eligible for "
            "review and landing -- not itself 'shippable' yet (per §5.3's SR-3, an in-sample result "
            "on one 92-row sample still licenses only 'worth replicating' until §5.2's independent "
            "replication, at this same frozen threshold and orientation, is run), but no longer "
            "closed by §5.5." %
            ( chosen["threshold"], chosen["false_warn"], _fmt3( fw["ci_lo"] ), _fmt3( fw["ci_hi"] ),
             chosen["recall"], _fmt3( rc["ci_lo"] ), _fmt3( rc["ci_hi"] ), grain,
             fw["n_resamples"], BOOTSTRAP_RESAMPLES, rc["n_resamples"], BOOTSTRAP_RESAMPLES,
             chosen["warn_rate"] * 100.0, grain_honesty["other_grain"], other_verdict ) )


def _public_sentence_margin_fire_rate_rejected( grain, best_band_only ):
    return ( _MARGIN_BP_SEEN_CLAUSE + ", it reaches the band at t=%d (warn iff margin_bp <= t) "
            "(false-warn=%.3f, miss-recall=%.3f on %s) -- but that threshold warns on %.1f%% of the "
            "92, above the 25%% fire-rate ceiling (SR-1). §5.5 requires band met AND SR-1 met for a "
            "PASS; band-met-alone is `pass_fire_rate_rejected`, not a PASS, so lane/for-margin-"
            "resolution is CLOSED: no second attempt, no new sample; only the zeroing-mechanism "
            "finding survives, as a doc note, not as code." %
            ( best_band_only["threshold"], best_band_only["false_warn"], best_band_only["recall"],
             grain, best_band_only["warn_rate"] * 100.0 ) )


def score_margin_bp( summary, rows ):
    """§5.5's pre-committed, exactly-ONE margin_bp re-score. Same shape and same four outcomes as
    `score_served_syms` (this function is the direction/statistic-generalised twin of that one, not
    a rewrite of its logic) but: statistic=`margin_bp` (not `served_syms`), direction="le" (not
    "ge"), orientation=-1 (not +1) -- MARGIN_BP_DIRECTION/MARGIN_BP_ORIENTATION above, both frozen by
    §5.5. Band, gating grain, fingerprint check, bootstrap seed/resamples: all UNCHANGED from
    served_syms's own (§5.5: "the same band …, the same gating grain …, the same §5.4.4 threshold
    procedure … substituting margin_bp for served_syms").

    Caller contract (§5.5, second branch only): call this ONLY once, and only after confirming (a)
    served_syms's own §5.4 run reached "fail" or "pass_fire_rate_rejected" -- never after a real
    "pass" ("pass" CLOSES the lane per §5.5's first branch without any re-score existing to run --
    and (b) `rows` come from `lane/for-margin-resolution`'s own binary run on the SAME asset tree
    §5.4's non-pass used (§5.5's C2-ruling reading: "same asset tree … lane-binary run must itself
    reproduce §5.4.1's fingerprint"). This function itself only checks the fingerprint (population,
    not provenance) -- it has no way to check which binary produced `rows` or which prior run's
    outcome licensed calling it; those are the caller's (and the report's) responsibility, exactly as
    the served_syms report above must name asset tree and binary sha itself."""
    fp_ok, fp_detail = check_fingerprint( summary, rows )
    out = dict( fingerprint_ok=fp_ok, fingerprint=fp_detail, statistic=MARGIN_BP_STATISTIC,
               direction=MARGIN_BP_DIRECTION, orientation=MARGIN_BP_ORIENTATION,
               gating_grain=GATING_GRAIN,
               band=dict( false_warn_max=FALSE_WARN_MAX, recall_min=RECALL_MIN,
                         fire_rate_ceiling=FIRE_RATE_CEILING ),
               auroc_band_5_2=dict( meets=AUROC_MEETS_5_2, weak=AUROC_WEAK_5_2,
                                    refutation=AUROC_REFUTATION_5_2 ),
               asset_tree=summary.get( "meta", {} ).get( "assets" ),
               binary_version=summary.get( "meta", {} ).get( "binary_version" ) )
    if not fp_ok:
        out["outcome"] = "fingerprint_mismatch"
        out["public_sentence"] = PUBLIC_SENTENCE_MARGIN_MISMATCH
        return out

    n = len( rows )
    grains = {}
    for grain in ( "file_hit", "func_hit" ):
        labels = [ not r[grain] for r in rows ]
        scores = [ MARGIN_BP_ORIENTATION * r[MARGIN_BP_STATISTIC] for r in rows ]
        auc = auroc( labels, scores )
        ci_lo, ci_hi, n_res = bootstrap_auroc_ci( rows, grain, statistic=MARGIN_BP_STATISTIC,
                                                  orientation=MARGIN_BP_ORIENTATION )
        table = _sweep_dir( labels, [ r[MARGIN_BP_STATISTIC] for r in rows ], MARGIN_BP_DIRECTION )
        grains[grain] = dict( n=n, misses=sum( labels ), auroc=auc,
                              auroc_ci_lo=ci_lo, auroc_ci_hi=ci_hi, auroc_ci_resamples=n_res,
                              auroc_band_5_2=auroc_band_5_2( auc ), sweep=table )
    out["grains"] = grains

    op = choose_operating_point( grains[GATING_GRAIN]["sweep"], n, direction=MARGIN_BP_DIRECTION )
    out["band_met"] = op["band_met"]
    out["sr1_met"] = op["sr1_met"]
    out["chosen_threshold"] = op["chosen"]
    out["best_band_only_threshold"] = op["best_band_only"]

    if op["band_met"] and op["sr1_met"]:
        chosen = op["chosen"]
        op_ci = bootstrap_operating_point_ci( rows, GATING_GRAIN, chosen["threshold"],
                                              statistic=MARGIN_BP_STATISTIC,
                                              direction=MARGIN_BP_DIRECTION )
        out["operating_point_ci"] = op_ci
        other_grain = "file_hit" if GATING_GRAIN == "func_hit" else "func_hit"
        other_sweep = grains[other_grain]["sweep"]
        other_band = any( r["band"] for r in other_sweep )
        other_safe = any( r["safe"] for r in other_sweep )
        out["grain_honesty"] = dict( gating_grain=GATING_GRAIN, gating_grain_pass=True,
                                     other_grain=other_grain,
                                     other_band=other_band, other_safe=other_safe,
                                     other_grain_pass=other_safe )
        out["outcome"] = "pass"
        out["pass"] = True
        out["lane_fate"] = "eligible for review and landing"
        out["public_sentence"] = _public_sentence_margin_pass( GATING_GRAIN, chosen, op_ci,
                                                                out["grain_honesty"] )
    elif op["band_met"]:
        out["outcome"] = "pass_fire_rate_rejected"
        out["pass"] = False
        out["lane_fate"] = "CLOSED"
        out["public_sentence"] = _public_sentence_margin_fire_rate_rejected(
            GATING_GRAIN, op["best_band_only"] )
    else:
        out["outcome"] = "fail"
        out["pass"] = False
        out["lane_fate"] = "CLOSED"
        out["public_sentence"] = _public_sentence_margin_fail( GATING_GRAIN, grains[GATING_GRAIN] )
    return out
