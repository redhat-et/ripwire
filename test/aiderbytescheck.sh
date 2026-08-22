#!/usr/bin/env bash
# aiderbytescheck.sh — the aider byte-capture contract (bench/headtohead/r4-2026-08-06/r4_worker.py).
#
# WHY THIS GATE EXISTS. The cost-per-answer lane found r4_aider.jsonl carrying 0/60 records with a
# "bytes" key at all. Root cause, at the aider branch's score_block() call: `extra={"n_idents": nid}`
# is keyword-only, so the positional `nbytes` slot before it was skipped and stayed at its None
# default — every other arm (codeseek/repowise/cbm/graphify) passes its byte count positionally.
# aider_rank() itself never computed a byte count in the first place: its transport is a FILE (the
# driver writes JSON to `outp` rather than stdout, deliberately, to keep aider's own progress/warning
# noise off the channel being parsed) so there was no `len(r.stdout)` to reach for.
#
# The fix: aider_rank() now measures os.path.getsize(outp) before unlinking it — the same "full
# serialized response body crossing the process boundary" measure every other arm's len(r.stdout)
# already is, just over a file instead of a pipe — and returns it as a 4th tuple element; both call
# sites (the personalized and no-personalization arms) pass it into score_block() positionally.
#
# This harness has no other test coverage (bench/headtohead/ predates the test/*check.sh convention),
# so this is the cheapest guard available: no aider install, no repo checkout, no network — timed() is
# monkeypatched to a fake that writes the driver's JSON payload directly, so aider_rank() itself runs
# for real and its returned byte count is checked against the payload's actual length.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
WORKER="$ROOT/bench/headtohead/r4-2026-08-06/r4_worker.py"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "aiderbytescheck: python3 required"; exit 2; }
[ -f "$WORKER" ] || { echo "aiderbytescheck: worker missing at $WORKER"; exit 2; }

RIPWIRE_REPO="$ROOT" python3 - "$ROOT" "$TMP" >"$TMP/out.txt" 2>&1 <<'PY'
import inspect, json, os, pathlib, sys

root, tmp = sys.argv[1], sys.argv[2]
sys.path.insert( 0, str( pathlib.Path( root ) / "bench" / "headtohead" / "r4-2026-08-06" ) )
import r4_worker as W

def ok( m ):  print( "PASS " + m )
def no( m ):  print( "FAIL " + m )

# ── 1. aider_rank() itself: a real run of the function, driver subprocess faked ─────────────────
payload = { "ranked": [ "a.py", "b.py" ], "wall": 0.01, "n_idents": 2 }
payload_bytes = json.dumps( payload ).encode( "utf-8" )

def fake_timed( args, cwd, timeout=7200, stdin_data=None, env=None ):
    outp = args[ -1 ]   # AIDER_DRIVER's argv: [python, -P, -c, DRIVER, repo_path, query, "0"/"1", outp]
    pathlib.Path( outp ).write_bytes( payload_bytes )
    class _R:
        returncode = 0
        stdout = ""
        stderr = ""
    return _R(), 0.01

W.timed = fake_timed
result = W.aider_rank( pathlib.Path( tmp ), "query text", [ "a.py", "b.py" ], personalize=True )
if len( result ) == 4:
    ok( "aider_rank() returns a 4-tuple (files, wall, n_idents, nbytes)" )
else:
    no( "aider_rank() returned %d values, expected 4: %r" % ( len( result ), result ) )
if len( result ) == 4:
    _files, _wall, nid, nbytes = result
    if nbytes == len( payload_bytes ):
        ok( "aider_rank()'s nbytes is the driver payload's exact serialized size (%d)" % nbytes )
    else:
        no( "aider_rank()'s nbytes=%r does not match the payload size %d" % ( nbytes, len( payload_bytes ) ) )
    if nid == 2:
        ok( "n_idents still parses correctly alongside the new nbytes slot" )
    else:
        no( "n_idents broke: got %r" % ( nid, ) )

# ── 2. score_block() actually records it when called positionally ────────────────────────────────
inst = dict( primary_files=[ "a.py" ], gold_files=[ "a.py" ] )
blk = W.score_block( [ "a.py" ], inst, [ "a.py", "b.py" ], 0.01, 12345, extra={ "n_idents": 2 } )
if blk.get( "bytes" ) == 12345:
    ok( "score_block(..., nbytes, extra=...) records bytes even with extra= also present" )
else:
    no( "score_block dropped nbytes when extra= was also passed: %r" % ( blk, ) )
# the exact shape of the ORIGINAL bug: nbytes omitted, extra passed by keyword only.
regressed = W.score_block( [ "a.py" ], inst, [ "a.py", "b.py" ], 0.01, extra={ "n_idents": 2 } )
if "bytes" not in regressed:
    ok( "confirms the bug shape: omitting the positional nbytes arg drops bytes from the record "
        "(this is what the aider call site used to do)" )
else:
    no( "score_block's nbytes default changed — this gate's bug-shape assumption is stale" )

# ── 3. the call sites themselves: main()'s aider branch passes nbytes positionally ──────────────
src = inspect.getsource( W.main )
aider_branch = src[ src.index( 'a.arm == "aider"' ) : ]
aider_branch = aider_branch[ : aider_branch.index( "except Exception" ) ]
if "f, w, nid, b = W.aider_rank" in aider_branch.replace( "aider_rank(", "W.aider_rank(" ) or \
   "f, w, nid, b = aider_rank" in aider_branch:
    ok( "main()'s aider branch unpacks aider_rank()'s 4th return value" )
else:
    no( "main()'s aider branch does not unpack a 4th (bytes) value from aider_rank(): %r"
        % ( aider_branch[ :200 ], ) )
if "score_block( f, inst, universe, w, b," in aider_branch:
    ok( "the personalized arm's score_block() call passes b (bytes) positionally" )
else:
    no( "the personalized arm's score_block() call no longer passes bytes positionally" )
if "score_block( f0, inst, universe, w0, b0" in aider_branch:
    ok( "the no-personalization arm's score_block() call passes b0 (bytes) positionally" )
else:
    no( "the no-personalization arm's score_block() call no longer passes bytes positionally" )
PY

while IFS= read -r line; do
    case "$line" in
        PASS*) ok "${line#PASS }" ;;
        FAIL*) no "${line#FAIL }" ;;
        *)     [ -n "$line" ] && printf '        %s\n' "$line" ;;
    esac
done < "$TMP/out.txt"

grep -q 'Traceback' "$TMP/out.txt" && no "python contract checks raised"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
