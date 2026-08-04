#!/usr/bin/env python3
# reaudit_exact.py — r5_nameboost amendment-2 targeting audit, SECOND PASS: the same gold fire-rate
# question, answered by the PRODUCTION predicate instead of the Python mirror.
#
# The first pass (targeting_audit.py, archived in audit.json) gated the round with a Python mirror of the
# trigger whose positive-evidence proxy (universe score > 0) is LOOSER than the implemented guard
# (body/doc evidence net of the symbol's own name-echo — see src/nameboost.h). This pass re-runs the
# missed set through the real mechanism's RIPWIRE_NAMEBOOST_AUDIT stderr tap, so the archived fire-rate
# is the one the grid actually runs under. Same gate: >= 20% at some registered minTokLen, else the
# round is dead before the grid.
#
# Usage:
#   python3 reaudit_exact.py --audit-json audit.json --work-dir <baseline work dir> \
#       --ripwire /path/to/build/ripwire --out-json reaudit.json
import argparse, json, pathlib, subprocess, sys

MIN_TOK_LENS = ( 4, 5 )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--audit-json", required=True, help="first-pass audit.json (missed set + missed_files)" )
    ap.add_argument( "--work-dir", required=True )
    ap.add_argument( "--ripwire", required=True )
    ap.add_argument( "--query-chars", type=int, default=1200 )
    ap.add_argument( "--top-k", type=int, default=200 )
    ap.add_argument( "--out-json", default="" )
    a = ap.parse_args()

    first = json.load( open( a.audit_json ) )
    work = pathlib.Path( a.work_dir )
    rows = json.loads( ( work / "datasets" / "rows_czlll__Loc-Bench_V1_test_560.json" ).read_text() )
    stmt_of = { r["instance_id"]: r.get( "problem_statement", "" ) for r in rows }

    per_instance = []
    for k, r in enumerate( first["instances"] ):
        inst_id = r["instance_id"]
        repo_path = work / "repos" / r["repo"].replace( "/", "__" )
        rich = work / "indexes" / ( inst_id.replace( "/", "__" ) + ".rich.ripwirecache" )
        query = " ".join( stmt_of[inst_id].split() )[: a.query_chars]
        missed = set( r["missed_files"] )
        row = dict( instance_id=inst_id, by_mintok={} )
        for mt in MIN_TOK_LENS:
            env = dict( RIPWIRE_NAMEBOOST=f"{mt},1", RIPWIRE_NAMEBOOST_AUDIT="1" )
            import os
            proc = subprocess.run( [ a.ripwire, str( repo_path ), f"--for={query}", f"--top-k={a.top_k}",
                                     "--format=candidates", f"--cache={rich}" ],
                                   capture_output=True, text=True, timeout=600, env={ **os.environ, **env } )
            if proc.returncode != 0:
                raise SystemExit( f"{inst_id}: ripwire rc={proc.returncode}: {proc.stderr[:300]}" )
            fired = []
            for line in proc.stderr.splitlines():
                if line.startswith( "nameboost-audit:\t" ):
                    _, path, name = line.split( "\t", 2 )
                    fired.append( ( path, name ) )
            gold_fired = sum( 1 for p, _ in fired if p in missed )
            row["by_mintok"][str( mt )] = dict( fired=len( fired ), gold_file_fired_syms=gold_fired,
                                                nongold_fired_syms=len( fired ) - gold_fired )
        per_instance.append( row )
        print( f"[{k+1}/{len(first['instances'])}] {inst_id} "
               + " ".join( f"mt{m}:goldF{row['by_mintok'][m]['gold_file_fired_syms']}"
                           f"/fired{row['by_mintok'][m]['fired']}" for m in row["by_mintok"] ), file=sys.stderr )

    n = len( per_instance )
    summary = {}
    print( f"\nexact-predicate targeting re-audit (production trigger, train missed set n={n})" )
    for mt in MIN_TOK_LENS:
        m = str( mt )
        gf = sum( 1 for r in per_instance if r["by_mintok"][m]["gold_file_fired_syms"] > 0 )
        mean_ng = sum( r["by_mintok"][m]["nongold_fired_syms"] for r in per_instance ) / n if n else 0.0
        summary[m] = dict( gold_fire_rate_file=gf / n if n else 0.0, mean_nongold_fired_syms=mean_ng )
        print( f"  minTokLen={mt}: gold fire-rate (file-level, THE GATE) {100*summary[m]['gold_fire_rate_file']:.1f}%; "
               f"mean non-gold fired {mean_ng:.1f} symbols/instance" )
    gate_pass = any( summary[str( mt )]["gold_fire_rate_file"] >= 0.20 for mt in MIN_TOK_LENS )
    print( f"\nGATE: {'PASS - the grid may run' if gate_pass else 'FAIL - the round is dead before the grid'}" )
    if a.out_json:
        pathlib.Path( a.out_json ).write_text( json.dumps(
            dict( gate_pass=gate_pass, n_missed=n, summary=summary, instances=per_instance ), indent=2 ) )
        print( f"wrote {a.out_json}" )
    return 0 if gate_pass else 4


if __name__ == "__main__":
    sys.exit( main() )
