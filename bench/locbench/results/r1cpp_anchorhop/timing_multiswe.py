#!/usr/bin/env python3
# timing_multiswe.py — R1-cpp perf-tier timing protocol over the Multi-SWE C++ held-out set
# (GATE_DECISION_r1cpp.md "Timing protocol"). Standalone on purpose: run_multiswe.py is the QUALITY
# harness and is not modified for the perf tier.
#
# Per held-out instance, per arm (baseline = RIPWIRE_NO_ANCHORHOP=1, candidate = default env):
#   * 5 warm production-bundle runs (`--for=<query>` + the instance's rich cache) → wall samples
#   * 1 cold run (`--no-cache`) → cold wall
#   * token ceiling = run_locbench.estimated_output_tokens( warm payload ) (+ raw bytes beside it)
# Arms run back-to-back per instance (paired design, drift-neutral); the whole script must run alone
# on the machine. Reuses run_multiswe's own checkout() + cache-key naming so the quality run's caches
# are the ones timed. Warm payload determinism is asserted across the 5 samples (zero-silent-skip).
#
# USAGE:
#   RIPWIRE=./build/ripwire python3 timing_multiswe.py --work-dir <same as quality run> \
#       --json-out timing_heldout.json [--lang cpp] [--dataset-lock ../../..../multiswe/dataset.lock]
import argparse, json, pathlib, statistics, subprocess, sys, time

HERE = pathlib.Path( __file__ ).resolve().parent
ROOT = HERE.parent.parent.parent.parent            # bench/locbench/results/r1cpp_anchorhop → repo root
sys.path.insert( 0, str( ROOT / "bench" / "locbench" ) )
import run_locbench as lb    # noqa: E402
sys.path.insert( 0, str( ROOT / "bench" / "multiswe" ) )
import run_multiswe as ms    # noqa: E402


def run_arm( repo_path, flags, env_extra ):
    import os
    env = dict( os.environ ); env.update( env_extra )
    t0 = time.perf_counter()
    r  = subprocess.run( [ lb.CTX, str( repo_path ) ] + flags, capture_output=True, text=True, env=env, timeout=600 )
    return r.stdout, ( time.perf_counter() - t0 ), r.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument( "--dataset-lock", default=str( ROOT / "bench" / "multiswe" / "dataset.lock" ) )
    ap.add_argument( "--lang", default="cpp" )
    ap.add_argument( "--work-dir", required=True, help="SAME work dir as the quality run (reuses checkouts + rich caches)" )
    ap.add_argument( "--query-chars", type=int, default=1200 )
    ap.add_argument( "--warm-samples", type=int, default=5 )
    ap.add_argument( "--json-out", required=True )
    a = ap.parse_args()

    lock      = json.loads( pathlib.Path( a.dataset_lock ).read_text() )
    instances = lock["instances_by_lang"][a.lang]
    work      = pathlib.Path( a.work_dir )
    repos_dir = work / "repos"; index_dir = work / "indexes"
    arms      = [ ( "baseline", { "RIPWIRE_NO_ANCHORHOP": "1" } ), ( "candidate", {} ) ]

    rows = []
    for idx, inst in enumerate( instances ):
        iid = inst["instance_id"]; query = inst["query"][ : a.query_chars ]
        repo_path = ms.checkout( inst["org"], inst["repo"], inst["base_sha"], repos_dir, {}, False )
        if repo_path is None: raise SystemExit( f"{iid}: CHECKOUT FAIL (zero-silent-skip contract)" )
        cache_key  = f"{inst['org']}__{inst['repo']}__{inst['base_sha']}"
        rich_cache = index_dir / f"{cache_key}.rich.ripwirecache"
        if not rich_cache.exists():
            base = index_dir / cache_key
            _, _, irc = lb.run_ctx( repo_path, [ f"--index-out={base}", "--top-k=1", "--no-cache" ] )
            if irc != 0 or not rich_cache.exists(): raise SystemExit( f"{iid}: INDEX FAIL rc={irc}" )

        row = dict( instance_id=iid, org=inst["org"], repo=inst["repo"], base_sha=inst["base_sha"], arms={} )
        for arm_name, env_extra in arms:
            payloads, walls = [], []
            for _ in range( a.warm_samples ):
                xml, wall, rc = run_arm( repo_path, [ f"--for={query}", f"--cache={rich_cache}" ], env_extra )
                if rc != 0: raise SystemExit( f"{iid}: WARM FAIL arm={arm_name} rc={rc}" )
                payloads.append( xml ); walls.append( wall )
            if len( set( payloads ) ) != 1: raise SystemExit( f"{iid}: NON-DETERMINISTIC warm payload arm={arm_name}" )
            _, cold_wall, crc = run_arm( repo_path, [ f"--for={query}", "--no-cache" ], env_extra )
            if crc != 0: raise SystemExit( f"{iid}: COLD FAIL arm={arm_name} rc={crc}" )
            sw = sorted( walls )
            row["arms"][arm_name] = dict(
                warm_walls=[ round( w, 4 ) for w in walls ],
                wall_median=round( statistics.median( walls ), 4 ),
                wall_p95=round( sw[ max( 0, -( -95 * len( sw ) // 100 ) - 1 ) ], 4 ),   # rank-based p95 of the samples
                cold_wall=round( cold_wall, 4 ),
                output_bytes=len( payloads[0].encode( "utf-8" ) ),
                output_tokens_ceiling=lb.estimated_output_tokens( payloads[0] ) )
        rows.append( row )
        print( f"[{idx+1}/{len(instances)}] {iid} "
               + " ".join( f"{k}: warm={v['wall_median']:.3f}s cold={v['cold_wall']:.3f}s tok={v['output_tokens_ceiling']}"
                           for k, v in row["arms"].items() ), file=sys.stderr )

    pathlib.Path( a.json_out ).write_text( json.dumps( dict(
        protocol=f"{a.warm_samples} warm (rich cache) + 1 cold (--no-cache) production --for per arm per instance; arms baseline(RIPWIRE_NO_ANCHORHOP=1)/candidate back-to-back per instance; run alone",
        dataset_lock_sha256=lock.get( "content_sha256", "" ), lang=a.lang, n=len( rows ), instances=rows ), indent=1 ) )
    print( f"wrote {a.json_out} ({len(rows)} instances)" )


if __name__ == "__main__":
    main()
