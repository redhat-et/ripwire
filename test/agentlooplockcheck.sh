#!/usr/bin/env bash
# agentlooplockcheck.sh — the tasks.lock split-contract gate (bench/agentloop/).
#
# WHY THIS GATE EXISTS. The B4 harness's whole claim to train/test hygiene is one sentence: every
# locked SWE-bench-Lite instance comes from a repo that is HELD-OUT under LocBench's
# frozen_partition(). Until 2026-08-20 nothing re-checked that sentence after generation time: the
# committed lock carried a perfectly valid content_sha256 over a task list that froze
# `pydata/xarray` — a LocBench-TRAIN repo — as eligible, and the 2026-08-05 pilot ran one of its
# instances. Hash-of-list proves the file wasn't hand-edited; it says nothing about whether the list
# was generated under the right rule. This gate asserts the closed loop:
#
#   1. The two frozen_partition() copies (bench/locbench/run_locbench.py, the authority, and
#      bench/agentloop/select_tasks.py, the verbatim copy) agree on the full SWE-bench-Lite repo
#      universe — the salt-drift check the copy's comment promises "at review time" now has teeth.
#   2. The COMMITTED tasks.lock passes run_agentloop.py's load_tasks_lock() (hash AND partition),
#      and an independent re-derivation finds no TRAIN repo among its instances.
#   3. FAIL-CLOSED, both loaders: a lock whose content hash is CORRECT but which freezes a TRAIN-repo
#      instance is refused by load_tasks_lock() — with a partition message, not a hash message — and
#      a results file carrying a TRAIN-repo record is refused by analyze.py. A hand-edited lock
#      (hash mismatch) still refuses too.
#   4. QUESTIONS-mode results (local scenario trees, repos that are not SWE-bench at all) are exempt
#      from the partition check — a false refusal there would break the E1 bank for no hygiene gain.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
AL="$ROOT/bench/agentloop"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "agentlooplockcheck: python3 required"; exit 2; }
[ -f "$AL/tasks.lock" ]      || { echo "agentlooplockcheck: no lock at $AL/tasks.lock"; exit 2; }
[ -f "$AL/select_tasks.py" ] || { echo "agentlooplockcheck: no select_tasks.py"; exit 2; }

# ── 1. the two frozen_partition() copies agree over the whole SWE-bench-Lite repo universe ─────────
if python3 - "$ROOT" <<'EOF'
import sys
root = sys.argv[1]
sys.path.insert( 0, root + "/bench/locbench" ); sys.path.insert( 0, root + "/bench/agentloop" )
import run_locbench, select_tasks
REPOS = [ "astropy/astropy", "django/django", "matplotlib/matplotlib", "mwaskom/seaborn",
          "pallets/flask", "psf/requests", "pydata/xarray", "pylint-dev/pylint",
          "pytest-dev/pytest", "scikit-learn/scikit-learn", "sphinx-doc/sphinx", "sympy/sympy" ]
diverged = [ r for r in REPOS if run_locbench.frozen_partition( r ) != select_tasks.frozen_partition( r ) ]
sys.exit( 1 if diverged else 0 )
EOF
then ok "frozen_partition copies agree (run_locbench.py vs select_tasks.py, all 12 repos)"
else no "frozen_partition copies DIVERGED — the split salt/rule drifted between the two files"
fi

# ── 2. the committed lock passes the loader, and an independent re-derivation finds no TRAIN repo ──
if python3 - "$ROOT" <<'EOF'
import sys
root = sys.argv[1]; sys.path.insert( 0, root + "/bench/agentloop" )
import run_agentloop
run_agentloop.load_tasks_lock( root + "/bench/agentloop/tasks.lock" )
EOF
then ok "committed tasks.lock accepted by load_tasks_lock (hash + partition)"
else no "committed tasks.lock REFUSED by load_tasks_lock"
fi

if python3 - "$ROOT" <<'EOF'
import hashlib, json, sys
root = sys.argv[1]
lock = json.load( open( root + "/bench/agentloop/tasks.lock" ) )
# independent of both python modules on purpose: the rule, restated from run_locbench.py by hand
part = lambda r: "train" if hashlib.sha256( ( "ripwire-a7-v2\0" + r.lower() ).encode() ).digest()[0] < 128 else "heldout"
bad = sorted( { i["repo"] for i in lock["instances"] if part( i["repo"] ) != "heldout" } )
if bad:
    print( "TRAIN repos frozen in the committed lock:", bad )
sys.exit( 1 if bad else 0 )
EOF
then ok "committed lock is repo-disjoint from LocBench train (independent re-derivation)"
else no "committed lock freezes a LocBench-TRAIN repo"
fi

# ── 3a. fail-closed: correct hash + TRAIN-repo instance => load_tasks_lock refuses, on PARTITION ───
python3 - "$ROOT" "$TMP" <<'EOF'
import hashlib, json, sys
root, tmp = sys.argv[1], sys.argv[2]
lock = json.load( open( root + "/bench/agentloop/tasks.lock" ) )
lock["instances"] = lock["instances"][:2] + [ dict( instance_id="pydata__xarray-3364",
    repo="pydata/xarray", base_commit="863e49066ca4d61c9adfe62aca3bf21b90e1af8c" ) ]
canon = [ dict( instance_id=i["instance_id"], repo=i["repo"], base_commit=i["base_commit"] )
          for i in sorted( lock["instances"], key=lambda x: x["instance_id"] ) ]
blob = json.dumps( canon, sort_keys=True, separators=( ",", ":" ) ).encode( "utf-8" )
lock["content_sha256"] = hashlib.sha256( blob ).hexdigest()   # a VALID hash over a contract-violating list
open( tmp + "/train.lock", "w" ).write( json.dumps( lock ) )
EOF
msg="$( python3 - "$ROOT" "$TMP" <<'EOF' 2>&1
import sys
root, tmp = sys.argv[1], sys.argv[2]; sys.path.insert( 0, root + "/bench/agentloop" )
import run_agentloop
run_agentloop.load_tasks_lock( tmp + "/train.lock" )
print( "ACCEPTED" )
EOF
)"
if printf '%s' "$msg" | grep -q "ACCEPTED"; then
    no "TRAIN-repo lock with a VALID content hash was ACCEPTED — hash-of-list is standing in for the partition check"
elif printf '%s' "$msg" | grep -qi "hash mismatch"; then
    no "TRAIN-repo lock refused for the WRONG reason (hash) — the fixture hash should be valid: $msg"
elif printf '%s' "$msg" | grep -qi "TRAIN"; then
    ok "TRAIN-repo lock refused on the partition, hash notwithstanding"
else
    no "TRAIN-repo lock refused with an unrecognized message: $msg"
fi

# ── 3b. fail-closed: the hand-edit (hash mismatch) refusal still works ─────────────────────────────
python3 - "$ROOT" "$TMP" <<'EOF'
import json, sys
root, tmp = sys.argv[1], sys.argv[2]
lock = json.load( open( root + "/bench/agentloop/tasks.lock" ) )
lock["instances"][0]["base_commit"] = "0" * 40   # hand-edit; content_sha256 left stale
open( tmp + "/edited.lock", "w" ).write( json.dumps( lock ) )
EOF
if python3 - "$ROOT" "$TMP" <<'EOF' >/dev/null 2>&1
import sys
root, tmp = sys.argv[1], sys.argv[2]; sys.path.insert( 0, root + "/bench/agentloop" )
import run_agentloop
run_agentloop.load_tasks_lock( tmp + "/edited.lock" )
EOF
then no "hand-edited lock (stale content hash) was ACCEPTED"
else ok "hand-edited lock (stale content hash) still refused"
fi

# ── 3c. fail-closed: analyze.py refuses a results file carrying a TRAIN-repo record ────────────────
python3 - "$TMP" <<'EOF'
import json, sys
tmp = sys.argv[1]
rec = dict( instance_id="pydata__xarray-3364", repo="pydata/xarray", arm="baseline", seed=1,
            status="not_implemented" )
out = dict( schema="ripwire-agentloop-results-v3", tasks_lock_content_sha256="f" * 64, records=[ rec ] )
open( tmp + "/train-results.json", "w" ).write( json.dumps( out ) )
EOF
if python3 "$AL/analyze.py" --results "$TMP/train-results.json" >/dev/null 2>&1; then
    no "analyze.py ACCEPTED a results file with a LocBench-TRAIN record"
else ok "analyze.py refused a results file with a LocBench-TRAIN record"
fi

# ── 4. QUESTIONS-mode results are exempt: local repo names are not SWE-bench repos ─────────────────
python3 - "$TMP" <<'EOF'
import json, sys
tmp = sys.argv[1]
# "ripwire" hashes wherever it hashes — the point is the questions: marker must bypass the check
rec = dict( instance_id="E1-01", repo="ripwire", arm="baseline", seed=1, status="not_implemented" )
out = dict( schema="ripwire-agentloop-results-v3", tasks_lock_content_sha256="questions:bank.tsv",
            records=[ rec ] )
open( tmp + "/questions-results.json", "w" ).write( json.dumps( out ) )
EOF
if python3 "$AL/analyze.py" --results "$TMP/questions-results.json" >/dev/null 2>&1; then
    ok "QUESTIONS-mode results exempt from the partition check"
else no "QUESTIONS-mode results were refused — the partition check is firing outside the SWE-bench universe"
fi

[ "$fail" -eq 0 ] && { echo "agentlooplockcheck: ALL PASS"; exit 0; }
echo "agentlooplockcheck: FAILURES"; exit 1
