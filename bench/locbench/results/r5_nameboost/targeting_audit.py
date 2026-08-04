#!/usr/bin/env python3
# targeting_audit.py — r5_nameboost amendment-2 targeting audit (PREREG.md, 2026-08-04 amendments).
#
# THE QUESTION (the r4 lesson: score-adjacent is not gold-adjacent — its chooser never picked gold at
# any setting, making the whole grid moot): BEFORE any grid cell runs, does the nameboost TRIGGER —
# a query token of length >= minTokLen whose subtoken sequence matches a gold-symbol name at camel/
# snake boundaries, on a symbol that already carries positive conceptual-route lexical score — actually
# FIRE on gold, for the train instances whose gold is CURRENTLY MISSED? And how often does it fire on
# non-gold (the precision proxy: fired non-gold symbols compete for the maxLifted ladder slots)?
#
# GATE (pre-registered): if gold fire-rate on the missed set is under 20% at EVERY registered
# minTokLen (grid registers {4,5}), the round is dead before the grid — archive and stop.
#
# Two gold-fire readings are both reported, because "gold symbol" has a strict and a metric-relevant
# form; the GATE is evaluated on (A), the file-level reading, since the round's primary metric is
# multi-file strict FILE@10 and a lift of ANY symbol residing in a missed gold file is what moves it:
#   (A) file-level  — trigger fires on >=1 positive-evidence symbol residing in a MISSED gold file
#                     (a primary gold file at rank >= 10 or absent from the --for arm's ranking);
#   (B) func-level  — trigger fires on >=1 covered gold FUNCTION itself (subset of A in practice).
#
# FAITHFULNESS CONTRACT: the subtokenizer below mirrors src/lexical.h subtokens() BYTE-FOR-BYTE
# (processes UTF-8 bytes; non-ASCII bytes are separators; a flush happens before EVERY uppercase byte,
# so acronym letters drop as <2-byte singletons; tokens < 2 bytes are dropped). Query raw tokens are
# maximal [A-Za-z0-9_]+ byte runs, lowercased; minTokLen applies to the RAW token length. Positive
# evidence = score s > 0 in the full `--query --no-route --format=candidates --top-k=1000000000`
# export (the conceptual-route BM25 the --for lens uses; tier multipliers are (0,1] shrink-only, so
# s>0 is route-equivalent). The C++ mechanism, if the gate passes, must implement EXACTLY these
# semantics — this file is their registration.
#
# Usage:
#   python3 targeting_audit.py --train-json train_base.json --work-dir <same as baseline run> \
#       --ripwire /path/to/build/ripwire --out-json audit.json
import argparse, json, pathlib, re, subprocess, sys
import xml.etree.ElementTree as ET

HERE = pathlib.Path( __file__ ).resolve()
sys.path.insert( 0, str( HERE.parents[2] ) )   # bench/locbench — for run_locbench reuse
import run_locbench as rl

MIN_TOK_LENS = ( 4, 5 )   # the registered grid's minTokLen axis — no post-hoc growth


def subtokens_cpp( s ):
    """Mirror of src/lexical.h subtokens(): byte-wise over UTF-8, camel/snake/digit-boundary split,
    lowercase, drop tokens shorter than 2 bytes. A flush precedes EVERY uppercase byte (cur holds
    lowercased bytes, so the C++ 'previous byte is uppercase' continuation test is never true)."""
    out, cur = [], []
    for b in s.encode( "utf-8" ):
        upper = 0x41 <= b <= 0x5A
        lower = 0x61 <= b <= 0x7A
        digit = 0x30 <= b <= 0x39
        if not ( upper or lower or digit ):
            if len( cur ) >= 2: out.append( bytes( cur ).decode( "ascii" ) )
            cur = []
            continue
        if upper and cur:
            if len( cur ) >= 2: out.append( bytes( cur ).decode( "ascii" ) )
            cur = []
        cur.append( b + 0x20 if upper else b )
    if len( cur ) >= 2: out.append( bytes( cur ).decode( "ascii" ) )
    return out


def query_raw_tokens( query, min_tok_len ):
    """Maximal ASCII [A-Za-z0-9_]+ runs, lowercased, RAW length >= min_tok_len, with a non-empty
    subtoken expansion. Occurrence-deduped (the trigger is existential, not frequency-weighted)."""
    toks = []
    for m in re.finditer( rb"[A-Za-z0-9_]+", query.encode( "utf-8" ) ):
        raw = m.group( 0 )
        if len( raw ) < min_tok_len: continue
        low = raw.lower().decode( "ascii" )
        if low not in toks and subtokens_cpp( low ): toks.append( low )
    return toks


def contiguous_subseq( needle, hay ):
    n, h = len( needle ), len( hay )
    if n == 0 or n > h: return False
    return any( hay[i:i + n] == needle for i in range( h - n + 1 ) )


def fires( qtok_subs, name_subs_cache, name ):
    subs = name_subs_cache.get( name )
    if subs is None:
        subs = subtokens_cpp( name ); name_subs_cache[name] = subs
    return any( contiguous_subseq( qs, subs ) for qs in qtok_subs )


def parse_scored_candidates( xml, repo_path ):
    """run_locbench.parse_candidates (the ONE path-normalization implementation) + the s= score attribute
    (needed for the positive-evidence guard) and the root's route=. Rows come back in document order from
    both parses, so the zip is positional identity."""
    out = rl.parse_candidates( xml, repo_path )
    root = ET.fromstring( xml )
    for c, row in zip( root.findall( "cand" ), out ):
        row["score"] = float( c.attrib.get( "s", "0" ) )
    return out, root.attrib.get( "route", "" )


def run_ripwire( binary, repo_path, flags ):
    r = subprocess.run( [ binary, str( repo_path ) ] + flags, capture_output=True, text=True, timeout=600 )
    if r.returncode != 0:
        raise SystemExit( f"ripwire failed rc={r.returncode} flags={flags[:1]}: {r.stderr[:300]}" )
    return r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--train-json", required=True )
    ap.add_argument( "--work-dir", required=True )
    ap.add_argument( "--ripwire", required=True )
    ap.add_argument( "--query-chars", type=int, default=1200 )   # must match the baseline run
    ap.add_argument( "--top-k", type=int, default=200 )          # must match the baseline arm invocation
    ap.add_argument( "--out-json", default="" )
    a = ap.parse_args()

    base = json.load( open( a.train_json ) )
    assert base["split"] == "train", "targeting audit is train-only (held-out untouched)"
    work = pathlib.Path( a.work_dir )
    rows = json.loads( ( work / "datasets" / "rows_czlll__Loc-Bench_V1_test_560.json" ).read_text() )
    stmt_of = { r["instance_id"]: r.get( "problem_statement", "" ) for r in rows }

    missed = [ r for r in base["instances"]
               if not ( r["arms"]["for"]["file_worst"] is not None and r["arms"]["for"]["file_worst"] < 10 ) ]
    print( f"# train n={len(base['instances'])}, strict-file@10 missed set n={len(missed)}", file=sys.stderr )

    name_subs_cache = {}
    per_instance = []
    for k, r in enumerate( missed ):
        inst_id = r["instance_id"]
        repo_path = work / "repos" / r["repo"].replace( "/", "__" )
        rich = work / "indexes" / ( inst_id.replace( "/", "__" ) + ".rich.ripwirecache" )
        if not repo_path.exists() or not rich.exists():
            raise SystemExit( f"{inst_id}: missing checkout or rich cache (run the baseline first)" )
        query = " ".join( stmt_of[inst_id].split() )[: a.query_chars]

        # which primary gold files did the --for arm actually MISS (rank None or >= 10)?
        for_xml = run_ripwire( a.ripwire, repo_path, [ f"--for={query}", f"--top-k={a.top_k}",
                                                       "--format=candidates", f"--cache={rich}" ] )
        for_cands, for_route = parse_scored_candidates( for_xml, repo_path )
        ranked_files = rl.ranked_files_from_candidates( for_cands )

        # conceptual-route universe with scores: positive evidence + every symbol's name
        uni_xml = run_ripwire( a.ripwire, repo_path, [ f"--query={query}", "--no-route",
                                                       "--format=candidates", "--top-k=1000000000",
                                                       f"--cache={rich}" ] )
        uni, _ = parse_scored_candidates( uni_xml, repo_path )
        universe_files = sorted( { c["path"] for c in uni } )

        franks = rl.file_ranks( ranked_files, r["primary_files"], universe_files )
        missed_files = { rl.norm_path( g ) for g, fr in zip( r["primary_files"], franks )
                         if fr is None or fr >= 10 }

        gold_fn = { ( rl.norm_path( gf ), gn ) for gf, gs, gn in r.get( "covered", [] ) }
        row = dict( instance_id=inst_id, repo=r["repo"], for_route=for_route,
                    n_primary=len( r["primary_files"] ), missed_files=sorted( missed_files ), by_mintok={} )
        for mt in MIN_TOK_LENS:
            qsubs = [ subtokens_cpp( t ) for t in query_raw_tokens( query, mt ) ]
            gold_file_fire = gold_func_fire = 0
            nongold_fired = pos_nongold = 0
            for c in uni:
                if c["score"] <= 0.0: continue
                in_missed_gold = c["path"] in missed_files
                is_gold_func = ( c["path"], c["name"] ) in gold_fn
                hit = fires( qsubs, name_subs_cache, c["name"] )
                if in_missed_gold:
                    if hit: gold_file_fire += 1
                else:
                    pos_nongold += 1
                    if hit: nongold_fired += 1
                if is_gold_func and hit: gold_func_fire += 1
            row["by_mintok"][str( mt )] = dict(
                gold_file_fired_syms=gold_file_fire, gold_func_fired=gold_func_fire,
                nongold_fired_syms=nongold_fired, positive_nongold_syms=pos_nongold )
        per_instance.append( row )
        print( f"[{k+1}/{len(missed)}] {inst_id} route={for_route} missed_files={len(missed_files)} "
               + " ".join( f"mt{m}:goldF{row['by_mintok'][m]['gold_file_fired_syms']}"
                           f"/ng{row['by_mintok'][m]['nongold_fired_syms']}" for m in row["by_mintok"] ),
               file=sys.stderr )

    # ── report ──────────────────────────────────────────────────────────────
    n = len( per_instance )
    summary = {}
    print( f"\ntargeting audit — r5_nameboost amendment 2 (train, missed set n={n})" )
    for mt in MIN_TOK_LENS:
        m = str( mt )
        gf = sum( 1 for r in per_instance if r["by_mintok"][m]["gold_file_fired_syms"] > 0 )
        gn = sum( 1 for r in per_instance if r["by_mintok"][m]["gold_func_fired"] > 0 )
        fired_ng = [ r["by_mintok"][m]["nongold_fired_syms"] for r in per_instance ]
        pos_ng = [ r["by_mintok"][m]["positive_nongold_syms"] for r in per_instance ]
        rate_syms = [ f / p for f, p in zip( fired_ng, pos_ng ) if p > 0 ]
        gold_among_fired = [ r["by_mintok"][m]["gold_file_fired_syms"]
                             / ( r["by_mintok"][m]["gold_file_fired_syms"] + r["by_mintok"][m]["nongold_fired_syms"] )
                             for r in per_instance
                             if r["by_mintok"][m]["gold_file_fired_syms"] + r["by_mintok"][m]["nongold_fired_syms"] > 0 ]
        summary[m] = dict(
            gold_fire_rate_file=gf / n if n else 0.0, gold_fire_rate_func=gn / n if n else 0.0,
            mean_nongold_fired_syms=sum( fired_ng ) / n if n else 0.0,
            mean_nongold_fire_rate=sum( rate_syms ) / len( rate_syms ) if rate_syms else 0.0,
            mean_gold_share_of_fired=sum( gold_among_fired ) / len( gold_among_fired ) if gold_among_fired else 0.0 )
        s = summary[m]
        print( f"  minTokLen={mt}: gold fire-rate (file-level, THE GATE) {100*s['gold_fire_rate_file']:.1f}%"
               f"  (func-level {100*s['gold_fire_rate_func']:.1f}%)" )
        print( f"               non-gold: mean {s['mean_nongold_fired_syms']:.1f} fired symbols/instance"
               f" ({100*s['mean_nongold_fire_rate']:.1f}% of positive-evidence non-gold);"
               f" mean gold share of fired {100*s['mean_gold_share_of_fired']:.1f}%" )
    gate_pass = any( summary[str( mt )]["gold_fire_rate_file"] >= 0.20 for mt in MIN_TOK_LENS )
    print( f"\nGATE (>=20% gold fire-rate on the missed set at any registered minTokLen): "
           f"{'PASS - the grid may run' if gate_pass else 'FAIL - the round is dead before the grid'}" )

    if a.out_json:
        pathlib.Path( a.out_json ).write_text( json.dumps(
            dict( gate_pass=gate_pass, n_missed=n, summary=summary, instances=per_instance ), indent=2 ) )
        print( f"wrote {a.out_json}" )
    return 0 if gate_pass else 4


if __name__ == "__main__":
    sys.exit( main() )
