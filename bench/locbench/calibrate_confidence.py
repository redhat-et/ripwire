#!/usr/bin/env python3
# calibrate_confidence.py — is the `confidence=`/`margin_pct=` pair that rides every `--for` root
# CALIBRATED against whether the served answer actually contains the gold?
#
# WHY THIS EXISTS. `--for` discloses how sharp its own ranked head is (docs/LINEAGE.md, the Agent
# Retrieval Bench row: no retriever tells the caller when its ranking is untrustworthy). Disclosure
# is only worth the bytes it costs if the disclosure TRACKS the truth — if `confidence="high"` and
# `confidence="low"` answers are right equally often, the attribute is decoration. The ARB rounds
# scored that signal against ARB's own unanswerable-query splits and recorded a negative. This is
# the OTHER half of the same question, on a different corpus and a different task: on LocBench
# (arXiv 2503.09089's localization set), where every query IS answerable and the only thing that
# varies is whether ripwire's served head found the gold.
#
# WHAT IT MEASURES, precisely. Per held-out instance: one default `ripwire <repo> --for="<issue>"`
# run — no `--top-k`, no `--adaptive`, the bundle an agent actually gets — parsed for
#   (a) the root's `confidence=` / `margin_pct=` / `coverage=` / `dropped_positive=`, and
#   (b) whether a gold file / gold function appears anywhere in the SERVED head.
# Grading the served head (not a 200-deep candidate list) is the point: `confidence=` is a claim
# about the head, so the head is what it has to be right about.
#
# WHAT IT DOES NOT CLAIM. `confidence=` is a two-valued label and `margin_pct=` is a score, not a
# probability. There is therefore no ECE here and no Brier score: with no declared mapping from the
# signal to P(hit), "calibration error" has no referent. What CAN be measured without inventing a
# mapping is (1) the per-band hit rate with an interval, (2) the reliability table over margin bins,
# and (3) discrimination (AUROC) of the registered ARB score. Those three are what this prints.
#
# COMMENSURABILITY. The score function, the AUROC, the confusion matrix and the threshold sweep are
# IMPORTED from bench/arb/score_abstention_calibration.py rather than re-derived, so a LocBench
# number and an ARB number can never disagree about what "the registered rule" means. The held-out
# split and the gold/hit definitions are imported from bench/locbench/run_locbench.py for the same
# reason — this script owns no definition that another artifact also owns.
#
# OFFLINE BY CONTRACT. Nothing here fetches. It reads an asset tree that a previous
# `run_locbench.py --work-dir` left on disk (`<assets>/datasets`, `<assets>/repos`), verifies the
# frozen 560-row dataset hash, and scores only instances whose checkout is provably AT the
# instance's base_commit (run_locbench.py's own `.ripwire_at_<sha>` marker). Every instance that is
# not scored lands in a NAMED skip bucket and is printed — an absent snapshot is a disclosed floor,
# never a silent drop. Indexes are written to --cache-dir (a scratch dir of your choosing), never
# back into the asset tree.
#
# USAGE
#   python3 bench/locbench/calibrate_confidence.py --assets <locbench work dir> \
#       --cache-dir <scratch> [--split heldout] [--json-out out.json] [--md-out tables.md]
#   RIPWIRE=<path to binary> is honored (same env var as run_locbench.py).
#
# Deterministic given (asset tree, split, binary): no LLM, no RNG, stable instance order.
import argparse, collections, hashlib, json, os, pathlib, subprocess, sys, time
import xml.etree.ElementTree as ET

HERE = pathlib.Path( __file__ ).resolve().parent
REPO = HERE.parent.parent
sys.path.insert( 0, str( HERE ) )
sys.path.insert( 0, str( REPO / "bench" / "arb" ) )

import run_locbench as LB                                   # split, gold, parse, path normalisation
import run_arb                                              # run_bin: the same invocation the ARB adapter makes
from score_abstention_calibration import auroc, confusion, prf, sweep_thresholds   # the registered statistics

FROZEN_ROWS = "rows_czlll__Loc-Bench_V1_test_560.json"
FROZEN_SHA  = "5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97"

# margin bins for the reliability table. Fixed here, before any row is read, so the table cannot be
# re-binned afterwards into whichever shape flatters the signal.
MARGIN_BINS = ( ( 0, 0 ), ( 1, 20 ), ( 21, 40 ), ( 41, 60 ), ( 61, 80 ), ( 81, 100 ) )


# ── the signal under test ────────────────────────────────────────────────────
def root_attrs( xml ):
    """The `--for` root's own facts. ElementTree on the root element only: attribute values carry XML
    escapes, and a regex over a 7 KB bundle would also match the legend comment that QUOTES them."""
    root = ET.fromstring( xml )
    if root.tag != "ctx":
        raise ValueError( "unexpected root <%s>" % root.tag )
    def as_int( key ):
        v = root.attrib.get( key )
        try:
            return int( v )
        except ( TypeError, ValueError ):
            return None
    return dict( confidence=root.attrib.get( "confidence" ), margin_pct=as_int( "margin_pct" ),
                 coverage=as_int( "coverage" ), dropped_positive=as_int( "dropped_positive" ),
                 est_tokens=as_int( "est_tokens" ), route=root.attrib.get( "route" ) )


def served_head( xml ):
    """The bundle's own three populations, kept apart on purpose.

    `<sigs><d p= n= r=>` is the RANKED HEAD — the thing `confidence=` makes a claim about ("the
    ranked head's largest relative score drop"), so it is what the headline metric grades.
    `<tail><t p=>` is the file-grain tail: paths the bundle names without a signature. `<hops><h>`
    is the neighbourhood. Both are in front of the caller, so a file appearing there is not nothing
    — but crediting them to `confidence=` would grade the attribute against text it does not
    describe. They are reported as the separate, more lenient `bundle_*` population instead.

    Parsed with ElementTree over the real tree rather than the older regex scrape in
    run_locbench.py, which keys on a `<f p=...>` grouping that the current `--for` shape does not
    emit — a scrape that silently returns an empty head, and therefore a clean-looking 0% hit rate,
    is exactly the failure this measurement could not survive."""
    root = ET.fromstring( xml )
    head = [ ( d.attrib.get( "p", "" ), d.attrib.get( "n", "" ),
               int( d.attrib["r"] ) if d.attrib.get( "r", "" ).isdigit() else None )
             for sigs in root.iter( "sigs" ) for d in sigs.findall( "d" ) ]
    tail = [ t.attrib.get( "p", "" ) for tl in root.iter( "tail" ) for t in tl.findall( "t" ) ]
    hops = [ ( h.attrib.get( "p", "" ), h.attrib.get( "n", "" ) )
             for hp in root.iter( "hops" ) for h in hp.findall( "h" ) ]
    return head, tail, hops


def arb_score( confidence, margin_pct ):
    """The ARB registration's combined score, restated over two plain arguments so this script can
    reuse it on a row shape that registration never saw. The RULE is the registration's, verbatim:
    low -> 0.0, high -> 1 + margin/100. Higher = the ranking claims to be sharper."""
    if confidence == "low":
        return 0.0
    if confidence == "high":
        return 1.0 + ( margin_pct or 0 ) / 100.0
    return None


# ── intervals ────────────────────────────────────────────────────────────────
def wilson( hits, n, z = 1.959963985 ):
    """Wilson score interval. Chosen over the normal approximation because several cells here are
    small and at least one is expected to sit near a rate of 1.0, where the normal interval leaves
    the unit interval and stops meaning anything."""
    if n == 0:
        return ( None, None )
    p = hits / n
    denom = 1.0 + z * z / n
    centre = ( p + z * z / ( 2 * n ) ) / denom
    half = z * ( ( p * ( 1 - p ) / n + z * z / ( 4 * n * n ) ) ** 0.5 ) / denom
    return ( max( 0.0, centre - half ), min( 1.0, centre + half ) )


def newcombe( h1, n1, h2, n2 ):
    """Newcombe's method for the DIFFERENCE of two proportions, built from the two Wilson intervals.
    Reported because the headline claim of this measurement is a difference ("high answers hit more
    often than low ones"), and a difference needs its own interval — two overlapping single-group
    intervals are not a test of it."""
    if n1 == 0 or n2 == 0:
        return ( None, None )
    l1, u1 = wilson( h1, n1 )
    l2, u2 = wilson( h2, n2 )
    d = h1 / n1 - h2 / n2
    return ( d - ( ( h1 / n1 - l1 ) ** 2 + ( u2 - h2 / n2 ) ** 2 ) ** 0.5,
             d + ( ( u1 - h1 / n1 ) ** 2 + ( h2 / n2 - l2 ) ** 2 ) ** 0.5 )


# ── run ──────────────────────────────────────────────────────────────────────
# Gold in one of these is gold ripwire's parser could in principle have emitted. A gold file outside
# the set is not a ranking failure and is counted apart rather than folded into the denominator.
RIPWIRE_EXTENSIONS = frozenset( ( ".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs", ".cpp", ".cc",
                                  ".h", ".hpp", ".swift", ".m", ".mm", ".java", ".rb", ".sh",
                                  ".bash", ".md" ) )


# The five knobs every per-instance step needs, carried as one value. A namedtuple rather than a
# class with an __init__: the five-positional signature it replaces is how a cache dir and an asset
# dir get swapped at one call site and nowhere else, and a hand-written __init__ that only assigns
# its arguments is a body this repository already has one copy of (bench/recalleval's Label) — its
# own --quality-delta said so, which is the check working.
RunConfig = collections.namedtuple( "RunConfig", "binary cache_dir query_chars limit verbose" )


def ripwire( cfg, repo_dir, flags ):
    """(stdout, returncode), or (None, None) when the invocation timed out.

    The invocation itself is `run_arb.run_bin` — the ARB adapter's own helper, imported rather than
    re-typed. Its 600 s ceiling is therefore this harness's ceiling too, which is the right coupling:
    a LocBench row and an ARB row are then produced by literally the same call, and a LocBench number
    cannot drift from an ARB number through a private copy of "how we run the binary". A timeout is
    handed back as a NAMED outcome instead of an exception so one slow repository buckets itself
    rather than ending a 92-instance run."""
    try:
        code, out, _err = run_arb.run_bin( cfg.binary, str( repo_dir ), flags )
    except subprocess.TimeoutExpired:
        return None, None
    return out, code


def load_rows( assets ):
    """The frozen 560-row slice, hash-verified. Refuses rather than fetches: a harness that quietly
    downloads a dataset is a harness whose corpus can change between two runs of the same command."""
    rows_path = assets / "datasets" / FROZEN_ROWS
    if not rows_path.is_file():
        raise SystemExit( "calibrate_confidence: no %s under %s/datasets — point --assets at a "
                          "run_locbench.py --work-dir that already holds the frozen 560-row slice "
                          "(this script never fetches)" % ( FROZEN_ROWS, assets ) )
    actual = hashlib.sha256( rows_path.read_bytes() ).hexdigest()
    if actual != FROZEN_SHA:
        raise SystemExit( "calibrate_confidence: frozen LocBench rows hash mismatch: expected %s, got %s"
                          % ( FROZEN_SHA, actual ) )
    return json.loads( rows_path.read_text() )


def eligibility( inst, assets, split ):
    """(repo_dir, gold) when this instance can be scored, else (None, the skip bucket it belongs in).
    Every reason an instance is not scored is decided HERE, in one place, and is named — the caller
    only counts. That is what makes the skip table a disclosure rather than a residual."""
    if LB.frozen_partition( inst["repo"] ) != split:
        return None, "wrong_split"
    repo_dir = assets / "repos" / inst["repo"].replace( "/", "__" )
    # run_locbench.py writes this marker only after a successful checkout OF THIS SHA, and one
    # directory serves a repository, so the marker is the only honest proof that the tree on disk is
    # the tree this instance is about. A bare directory is NOT evidence.
    if not ( repo_dir / ( ".ripwire_at_" + inst["base_commit"] ) ).is_file():
        return None, "no_snapshot"
    gold_files, gold_funcs, _added = LB.gold_for_instance( inst, "locbench" )
    if not gold_files:
        return None, "no_gold"
    if not ( { os.path.splitext( f )[1] for f in gold_files } & RIPWIRE_EXTENSIONS ):
        return None, "non_ripwire_language"
    return repo_dir, ( gold_files, gold_funcs )


def instance_index( inst, repo_dir, cfg ):
    """The per-instance index, built once into cfg.cache_dir. None on failure (the caller buckets it).
    Built rather than reused from the asset tree on purpose: an index there may predate the current
    cache format, and letting the binary rewrite it would mutate the evidence this run is scored on."""
    base = cfg.cache_dir / inst["instance_id"].replace( "/", "__" )
    rich = pathlib.Path( str( base ) + ".rich.ripwirecache" )
    if rich.exists():
        return rich
    _out, rc = ripwire( cfg, repo_dir, [ "--index-out=%s" % base, "--top-k=1", "--no-cache" ] )
    if rc != 0 or not rich.exists():
        print( "# INDEX FAIL %s rc=%s" % ( inst["instance_id"], rc ), file=sys.stderr )
        return None
    return rich


def universe( repo_dir, query, rich, cfg ):
    """(indexable_gold_predicate_input, candidates): the flat, globally-ranked candidate list over the
    WHOLE index. It answers a question the served head cannot — was the gold indexed at all — because
    a miss on a gold symbol the parser never emitted is a parser limit, and folding the two together
    would let a parse gap masquerade as a calibration gap."""
    out, rc = ripwire( cfg, repo_dir, [ "--query=%s" % query, "--format=candidates",
                                        "--top-k=1000000000", "--cache=%s" % rich ] )
    try:
        return LB.parse_candidates( out, str( repo_dir ) ) if rc == 0 else []
    except Exception:                                            # noqa: BLE001 — an empty universe is
        return []                                                # reported as 0 coverage, never as a hit


def grade( gold, head, tail, hops ):
    """The four grains, kept as four. They disagree, which is the point: one signal cannot be
    calibrated without first fixing which grain of "correct" it is a claim about."""
    gold_files, gold_funcs = gold
    gold_norm = { LB.norm_path( g ) for g in gold_files }
    head_files = { LB.norm_path( p ) for p, _n, _r in head }
    bundle_files = head_files | { LB.norm_path( p ) for p in tail } | { LB.norm_path( p ) for p, _n in hops }
    head_syms = { ( LB.norm_path( p ), n ) for p, n, _r in head }
    gold_ranks = [ r for p, _n, r in head if r is not None and LB.norm_path( p ) in gold_norm ]
    return dict( gold_files=sorted( gold_norm ), n_gold_funcs=len( gold_funcs ),
                 served_syms=len( head ), served_files=len( head_files ), bundle_files=len( bundle_files ),
                 first_gold_rank=min( gold_ranks ) if gold_ranks else None,
                 file_hit=bool( gold_norm & head_files ),
                 all_file_hit=bool( gold_norm ) and gold_norm <= head_files,
                 func_hit=any( ( LB.norm_path( f ), n ) in head_syms for f, _s, n in gold_funcs ),
                 bundle_file_hit=bool( gold_norm & bundle_files ) )


def measure_instance( inst, repo_dir, gold, cfg ):
    """(row, None) or (None, skip bucket). THE measured invocation is the default `--for` and nothing
    else: no --top-k, no --adaptive, no budget — the bundle an agent is actually handed."""
    rich = instance_index( inst, repo_dir, cfg )
    if rich is None:
        return None, "index_fail"
    query = " ".join( inst.get( "problem_statement", "" ).split() )[:cfg.query_chars]
    t0 = time.perf_counter()
    out, rc = ripwire( cfg, repo_dir, [ "--for=%s" % query, "--cache=%s" % rich ] )
    wall = time.perf_counter() - t0
    if rc is None:
        print( "# TIMEOUT %s" % inst["instance_id"], file=sys.stderr )
        return None, "timeout"
    if rc != 0:
        print( "# FOR FAIL %s rc=%d" % ( inst["instance_id"], rc ), file=sys.stderr )
        return None, "for_fail"
    try:
        attrs = root_attrs( out )
        head, tail, hops = served_head( out )
    except Exception as e:                                       # noqa: BLE001 — bucketed, never silent
        print( "# PARSE FAIL %s: %s" % ( inst["instance_id"], e ), file=sys.stderr )
        return None, "parse_fail"

    uni_cands = universe( repo_dir, query, rich, cfg )
    universe_files = sorted( { c["path"] for c in uni_cands } )
    row = dict( instance_id=inst["instance_id"], repo=inst["repo"], wall=round( wall, 3 ),
                indexable_gold_file=any( LB.norm_path( g ) in universe_files for g in gold[0] ),
                covered_gold_funcs=len( LB.covered( uni_cands, gold[1], universe_files ) if uni_cands else [] ),
                **grade( gold, head, tail, hops ), **attrs )
    row["score"] = arb_score( attrs["confidence"], attrs["margin_pct"] )
    return row, None


def scored_instances( assets, split, cfg ):
    """The scored rows and the named skip buckets. Every instance in the dataset lands in exactly one
    of the two."""
    skips = dict( wrong_split=0, no_snapshot=0, non_ripwire_language=0, index_fail=0, for_fail=0,
                  parse_fail=0, no_gold=0, timeout=0 )
    out = []
    for inst in load_rows( assets ):
        repo_dir, verdict = eligibility( inst, assets, split )
        if repo_dir is None:
            skips[verdict] += 1
            continue
        row, reason = measure_instance( inst, repo_dir, verdict, cfg )
        if row is None:
            skips[reason] += 1
            continue
        out.append( row )
        if cfg.verbose:
            print( "# [%d] %s conf=%s margin=%s file_hit=%s func_hit=%s" %
                   ( len( out ), row["instance_id"], row["confidence"], row["margin_pct"],
                     row["file_hit"], row["func_hit"] ), file=sys.stderr )
        if cfg.limit and len( out ) >= cfg.limit:
            break
    return out, skips


# ── tables ───────────────────────────────────────────────────────────────────
def band_table( rows, metric ):
    """hit rate per confidence band, with a Wilson interval and the difference with a Newcombe one."""
    table = {}
    for band in ( "high", "low" ):
        cell = [ r for r in rows if r["confidence"] == band ]
        hits = sum( 1 for r in cell if r[metric] )
        lo, hi = wilson( hits, len( cell ) )
        table[band] = dict( n=len( cell ), hits=hits,
                            rate=( hits / len( cell ) if cell else None ), ci_lo=lo, ci_hi=hi )
    h, l = table["high"], table["low"]
    if h["n"] and l["n"]:
        d_lo, d_hi = newcombe( h["hits"], h["n"], l["hits"], l["n"] )
        table["difference"] = dict( value=h["rate"] - l["rate"], ci_lo=d_lo, ci_hi=d_hi,
                                    excludes_zero=bool( d_lo is not None and ( d_lo > 0 or d_hi < 0 ) ) )
    else:
        table["difference"] = dict( value=None, ci_lo=None, ci_hi=None, excludes_zero=False )
    return table


def reliability_table( rows, metric ):
    """Empirical hit rate per margin_pct bin. Deliberately NOT called a calibration curve: the x axis
    is a sharpness score, not a predicted probability, so the diagonal a calibration plot is read
    against does not exist here. What the table can show is MONOTONICITY — does a bigger claimed
    margin buy a higher hit rate — and that is what it is for."""
    out = []
    for lo, hi in MARGIN_BINS:
        cell = [ r for r in rows if r["margin_pct"] is not None and lo <= r["margin_pct"] <= hi ]
        hits = sum( 1 for r in cell if r[metric] )
        w_lo, w_hi = wilson( hits, len( cell ) )
        out.append( dict( bin="%d-%d" % ( lo, hi ) if lo != hi else str( lo ), lo=lo, hi=hi,
                          n=len( cell ), hits=hits,
                          rate=( hits / len( cell ) if cell else None ), ci_lo=w_lo, ci_hi=w_hi,
                          high=sum( 1 for r in cell if r["confidence"] == "high" ) ) )
    return out


def discrimination( rows, metric ):
    """AUROC of the registered ARB score against the MISS class, plus the default operating point
    (abstain iff confidence=="low") scored as a miss detector. Positive class is "miss" so a higher
    AUROC always means "the signal sees trouble coming", identically to the ARB rounds."""
    usable = [ r for r in rows if r["score"] is not None ]
    labels = [ not r[metric] for r in usable ]                # True == miss == should have warned
    scores = [ -r["score"] for r in usable ]                  # higher == more miss evidence
    n_pos = sum( 1 for y in labels if y )
    out = dict( n=len( usable ), misses=n_pos, hits=len( usable ) - n_pos, auroc=None )
    if n_pos and n_pos < len( usable ):
        out["auroc"] = auroc( labels, scores )
        best, table = sweep_thresholds( labels, scores )
        out["best_f1"] = best
        out["sweep_size"] = len( table )
    dop = prf( *confusion( labels, [ 0.0 if r["confidence"] == "low" else 1.0 for r in usable ], 0.0 ) )
    out["dop"] = dop                                          # recall = misses warned; false_abstain_rate = hits warned
    return out


def secondary_signals( rows, metric ):
    """EXPLORATORY and decides nothing. Two other facts the `--for` root already ships — `coverage=`
    (how much of the query the corpus could match) and `dropped_positive=` (positively-scored
    symbols the budget cut) — scored as miss detectors on the same rows, by the same AUROC.

    They are listed under their own heading, and the word EXPLORATORY is in this docstring and in
    the emitted table, because picking whichever of three signals wins on the finished table and
    then calling it the hypothesis is the failure mode the ARB rounds registered against. Anything
    here that looks promising has to be re-measured under its own registration before it is a
    finding, let alone a behavior."""
    usable = [ r for r in rows if r[metric] is not None ]
    labels = [ not r[metric] for r in usable ]
    out = {}
    for name, extract, direction in ( ( "coverage", lambda r: r["coverage"], -1 ),
                                      ( "dropped_positive", lambda r: r["dropped_positive"], +1 ),
                                      ( "margin_pct_alone", lambda r: r["margin_pct"], -1 ) ):
        pairs = [ ( y, extract( r ) ) for y, r in zip( labels, usable ) if extract( r ) is not None ]
        if not pairs:
            out[name] = dict( n=0, auroc=None, exploratory=True )
            continue
        ys = [ y for y, _ in pairs ]
        ss = [ direction * v for _, v in pairs ]
        n_pos = sum( 1 for y in ys if y )
        out[name] = dict( n=len( pairs ), misses=n_pos, exploratory=True,
                          auroc=auroc( ys, ss ) if 0 < n_pos < len( ys ) else None )
    return out


def fmt_rate( cell ):
    if cell.get( "rate" ) is None:
        return "n/a"
    return "%.3f [%.3f, %.3f]" % ( cell["rate"], cell["ci_lo"], cell["ci_hi"] )


GRAINS = ( ( "file_hit", "a gold FILE is in the served head" ),
           ( "func_hit", "a gold FUNCTION is in the served head" ),
           ( "all_file_hit", "EVERY gold file is in the served head" ),
           ( "bundle_file_hit", "a gold FILE is named anywhere in the bundle (head, tail or hops)" ) )


def md_num( v, spec = "%.3f" ):
    """One formatter for every optional number in the tables. `n/a` means the statistic was not
    computable on these rows (a single-class cell, an absent attribute) — never a zero."""
    return spec % v if v is not None else "n/a"


def md_band_sections( summary ):
    """One `confidence=` table per grain. The grains are listed in GRAINS rather than inline so the
    markdown and the TSV emit the same four, in the same order, from one list."""
    L = []
    for metric, title in GRAINS:
        t = summary["bands"][metric]
        L += [ "### `confidence=` vs %s" % title, "",
               "| confidence | n | hits | hit rate [95% Wilson] |", "| --- | --- | --- | --- |" ]
        L += [ "| %s | %d | %d | %s |" % ( b, t[b]["n"], t[b]["hits"], fmt_rate( t[b] ) ) for b in ( "high", "low" ) ]
        d = t["difference"]
        L.append( "" )
        L.append( "difference (high - low): n/a (a band is empty)" if d["value"] is None else
                  "difference (high - low): **%+.3f** [%+.3f, %+.3f] — %s" %
                  ( d["value"], d["ci_lo"], d["ci_hi"],
                    "excludes 0" if d["excludes_zero"] else "**includes 0**" ) )
        L.append( "" )
    return L


def md_signal_sections( summary ):
    """Reliability, discrimination, and the exploratory block — the three tables about the SIGNAL, as
    opposed to the four about the grains."""
    L = [ "### Reliability over `margin_pct=` bins (metric: a gold file in the served head)", "",
          "| margin_pct | n | of which confidence=high | hits | hit rate [95% Wilson] |",
          "| --- | --- | --- | --- | --- |" ]
    L += [ "| %s | %d | %d | %d | %s |" % ( b["bin"], b["n"], b["high"], b["hits"], fmt_rate( b ) )
           for b in summary["reliability"]["file_hit"] ]
    L += [ "", "### Discrimination — can the signal pick out the misses?", "",
           "| metric | n | misses | AUROC (positive class = miss) | DOP recall | DOP false-warn rate |",
           "| --- | --- | --- | --- | --- | --- |" ]
    for metric in ( "file_hit", "func_hit" ):
        d = summary["discrimination"][metric]
        L.append( "| %s | %d | %d | %s | %s | %s |" %
                  ( metric, d["n"], d["misses"], md_num( d["auroc"] ),
                    md_num( d["dop"]["recall"] ), md_num( d["dop"]["false_abstain_rate"] ) ) )
    L += [ "", "### EXPLORATORY — two other root facts as miss detectors (decides nothing)", "",
           "| signal | n | AUROC vs a missed gold file | AUROC vs a missed gold function |",
           "| --- | --- | --- | --- |" ]
    for name in ( "coverage", "dropped_positive", "margin_pct_alone" ):
        f, u = summary["secondary"]["file_hit"][name], summary["secondary"]["func_hit"][name]
        L.append( "| `%s` | %d | %s | %s |" % ( name, f["n"], md_num( f["auroc"] ), md_num( u["auroc"] ) ) )
    return L + [ "" ]


def md_miss_section( summary ):
    """Where the misses live — the table that separates a parser limit from a ranking one, and prices
    the false warnings against the misses they bought."""
    c = summary["miss_composition"]
    return [ "### Where the misses live", "", "| population | n |", "| --- | --- |",
             "| scored | %d |" % summary["n_scored"],
             "| gold file never indexed (a parser limit, not a ranking one) | %d |" % c["gold_unindexable"],
             "| gold file indexed but not in the served head | %d |" % c["indexed_but_missed"],
             "| of those, warned (`confidence=low`) | %d |" % c["indexed_missed_and_warned"],
             "| gold file in the served head | %d |" % c["file_hits"],
             "| of those, warned (`confidence=low`) — the false-warn cost | %d |" % c["hit_but_warned"], "" ]


def markdown( summary ):
    m = summary["meta"]
    L = [ "<!-- generated by bench/locbench/calibrate_confidence.py — do not hand-edit -->", "",
          "Corpus: LocBench %s split, %d instances scored, binary `%s`." %
          ( m["split"], summary["n_scored"], m["binary_version"] ), "",
          "### Skipped, by reason (zero-silent-skip)", "", "| reason | n |", "| --- | --- |" ]
    L += [ "| %s | %d |" % ( k, v ) for k, v in sorted( summary["skips"].items() ) ]
    return "\n".join( L + [ "" ] + md_band_sections( summary ) + md_signal_sections( summary )
                       + md_miss_section( summary ) )


def print_metric_lines( summary, rows ):
    """The greppable TSV surface, same convention as run_arb.py's `ARB\tcalib\t...` lines. Split out
    of main() so main() is argument handling and file writing, and this is the report."""
    for line in ( "n_scored\t%d" % len( rows ),
                  "file_hit_overall\t%.4f" % summary["overall"]["file_hit"],
                  "func_hit_overall\t%.4f" % summary["overall"]["func_hit"],
                  "confidence_high\t%d" % summary["overall"]["confidence_high"],
                  "confidence_low\t%d" % ( len( rows ) - summary["overall"]["confidence_high"] ) ):
        print( "LOCBENCH\tcalib\t%s" % line )
    for metric, _title in GRAINS:
        t = summary["bands"][metric]
        for band in ( "high", "low" ):
            print( "LOCBENCH\tcalib\t%s_%s\t%s\t(n=%d)" % ( metric, band, fmt_rate( t[band] ), t[band]["n"] ) )
        d = t["difference"]
        print( "LOCBENCH\tcalib\t%s_difference\t%s" % ( metric,
               "n/a" if d["value"] is None else "%+.4f [%+.4f, %+.4f] excludes_zero=%s"
               % ( d["value"], d["ci_lo"], d["ci_hi"], d["excludes_zero"] ) ) )
    for metric in ( "file_hit", "func_hit" ):
        print( "LOCBENCH\tcalib\t%s_auroc\t%s" % ( metric, md_num( summary["discrimination"][metric]["auroc"], "%.4f" ) ) )


def main():
    ap = argparse.ArgumentParser( description="is --for's confidence=/margin_pct= calibrated against "
                                              "whether the served head holds the gold? (LocBench, offline)" )
    ap.add_argument( "--assets", required=True,
                     help="a run_locbench.py --work-dir already on disk (needs datasets/ and repos/); never fetched" )
    ap.add_argument( "--cache-dir", required=True,
                     help="scratch dir for per-instance indexes — never the asset tree (this script must not rewrite it)" )
    ap.add_argument( "--split", default="heldout", choices=[ "all", "train", "heldout" ] )
    ap.add_argument( "--query-chars", type=int, default=1200, help="issue prefix used as the query (run_locbench.py's default)" )
    ap.add_argument( "--limit", type=int, default=0, help="stop after N scored instances (0 = every one on disk)" )
    ap.add_argument( "--json-out", default="" )
    ap.add_argument( "--md-out", default="" )
    ap.add_argument( "--verbose", action="store_true" )
    a = ap.parse_args()

    binary = os.environ.get( "RIPWIRE", str( REPO / "build" / "ripwire" ) )
    assets = pathlib.Path( a.assets ).expanduser().resolve()
    cache_dir = pathlib.Path( a.cache_dir ).expanduser().resolve()
    if cache_dir == assets or assets in cache_dir.parents:
        raise SystemExit( "calibrate_confidence: --cache-dir must live OUTSIDE --assets (the asset tree is "
                          "evidence; a run that rewrites it cannot be re-run against the same bytes)" )
    cache_dir.mkdir( parents=True, exist_ok=True )
    ver = subprocess.run( [ binary, "--version" ], capture_output=True, text=True )
    if ver.returncode != 0:
        raise SystemExit( "calibrate_confidence: no working binary at %s (set RIPWIRE=)" % binary )
    binary_version = ver.stdout.strip().splitlines()[0] if ver.stdout.strip() else "unknown"

    print( "# calibrate_confidence — assets=%s split=%s binary=%s" % ( assets, a.split, binary ), file=sys.stderr )
    rows, skips = scored_instances( assets, a.split,
                                    RunConfig( binary, cache_dir, a.query_chars, a.limit, a.verbose ) )
    if not rows:
        raise SystemExit( "calibrate_confidence: nothing scored — skips: %s" % skips )

    file_hits = sum( 1 for r in rows if r["file_hit"] )
    miss_composition = dict(
        gold_unindexable=sum( 1 for r in rows if not r["indexable_gold_file"] ),
        indexed_but_missed=sum( 1 for r in rows if r["indexable_gold_file"] and not r["file_hit"] ),
        indexed_missed_and_warned=sum( 1 for r in rows if r["indexable_gold_file"] and not r["file_hit"]
                                       and r["confidence"] == "low" ),
        file_hits=file_hits,
        hit_but_warned=sum( 1 for r in rows if r["file_hit"] and r["confidence"] == "low" ) )

    summary = dict(
        meta=dict( split=a.split, assets=str( assets ), query_chars=a.query_chars,
                   binary_version=binary_version, dataset_sha256=FROZEN_SHA,
                   invocation="ripwire <repo> --for=<issue prefix> (default flags; no --top-k)" ),
        n_scored=len( rows ), skips=skips,
        overall=dict( file_hit=file_hits / len( rows ),
                      func_hit=sum( 1 for r in rows if r["func_hit"] ) / len( rows ),
                      all_file_hit=sum( 1 for r in rows if r["all_file_hit"] ) / len( rows ),
                      confidence_high=sum( 1 for r in rows if r["confidence"] == "high" ) ),
        bands={ m: band_table( rows, m ) for m in ( "file_hit", "func_hit", "all_file_hit", "bundle_file_hit" ) },
        reliability={ m: reliability_table( rows, m ) for m in ( "file_hit", "func_hit" ) },
        discrimination={ m: discrimination( rows, m ) for m in ( "file_hit", "func_hit" ) },
        secondary={ m: secondary_signals( rows, m ) for m in ( "file_hit", "func_hit" ) },
        miss_composition=miss_composition, instances=rows )

    print_metric_lines( summary, rows )

    if a.json_out:
        pathlib.Path( a.json_out ).write_text( json.dumps( summary, indent=2, sort_keys=True ) )
        print( "LOCBENCH\tcalib\tjson\t%s" % a.json_out )
    if a.md_out:
        pathlib.Path( a.md_out ).write_text( markdown( summary ) + "\n" )
        print( "LOCBENCH\tcalib\tmarkdown\t%s" % a.md_out )


if __name__ == "__main__":
    main()
