#!/usr/bin/env bash
# agentloopeditsuitecheck.sh — the EDIT-PATH terminality suite's contract (terminality round A, 2026-09-05,
# lane E): bench/agentloop/run_editsuite.py + bench/agentloop/editsuite/.
#
# The suite measures whether, after a ripwire edit verb returns its receipt, an agent on a runner WITHOUT a
# Read-before-edit policy (codex exec / opencode run) still reads the target file or re-runs --edit-check.
# The band is pre-registered in docs/EVALS.md ("Terminality round A", lane E). This gate is HERMETIC — no
# runner, no model, no network — and pins the four things a live run's numbers rest on:
#
#   1. the suite's shape and its oracle: 12 tasks (6 replace-body, 3 insert, 3 multi-edit plan) over the
#      committed fixture; expected/ is derivable from tasks.json + fixture/ by plain string ops (never
#      ripwire); oracle.sh says pass / ws-only / fail on byte-equality and can tell the three apart;
#   2. the isolation recipe is REUSED from run_agentloop.py, not copied: prepare_environment (ephemeral
#      HOME/XDG + the logging shim first on PATH), build_harness_command, sh — and sh() makes the child's
#      $PWD agree with its cwd (opencode roots its native read/glob/edit tools at $PWD; the first live run
#      of this suite edited the committed fixture through that split);
#   3. arm order ALTERNATES per task and the two arms of one task are adjacent in the run matrix;
#   4. the JSONL accounting on FIXTURE events: the post-edit window is classified per EVALS T2
#      (policy-read of the target / sweep / redundant --edit-check / native re-edit), the ripwire call is
#      recognised by its command word (a path containing "ripwire" is not a call), and the emitted meter
#      rows carry the round's row shape (v, ts, seq, session, repo, tag, tool, class, family, agent,
#      surface, target, detail).
#
# Usage: bash test/agentloopeditsuitecheck.sh            (RIPWIRE_BIN=… to point at another binary)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "agentloopeditsuitecheck: no binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "agentloopeditsuitecheck: python3 required"; exit 2; }
[ -f "$ROOT/bench/agentloop/run_editsuite.py" ] || { echo "agentloopeditsuitecheck: suite missing"; exit 2; }
echo "agentloopeditsuitecheck: BIN=$BIN"

# ── 1. shape + oracle (shell-side, because oracle.sh is a shell contract) ─────────────────────────────
SUITE="$ROOT/bench/agentloop/editsuite"
( cd "$SUITE" && python3 gen_expected.py --check >"$TMP/gen.txt" 2>&1 ) \
    && ok "(1) expected/ is derivable from tasks.json + fixture/ by plain string ops ($( tail -1 "$TMP/gen.txt" ))" \
    || { no "(1) expected/ does not match what gen_expected.py derives"; cat "$TMP/gen.txt"; }
W="$TMP/w"; rm -rf "$W"; cp -R "$SUITE/fixture" "$W"
bash "$SUITE/oracle.sh" r1 "$W" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "(1) oracle: the pristine fixture FAILS task r1 (rc=1)" || no "(1) oracle on the pristine fixture returned $rc, want 1"
cp "$SUITE/expected/r1/geometry.cpp.expected" "$W/geometry.cpp"
bash "$SUITE/oracle.sh" r1 "$W" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "(1) oracle: the expected bytes PASS task r1 (rc=0)" || no "(1) oracle on the expected bytes returned $rc, want 0"
printf '\n' >> "$W/geometry.cpp"
bash "$SUITE/oracle.sh" r1 "$W" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "(1) oracle: one extra trailing newline is ws-only (rc=2), never a pass" || no "(1) oracle on a trailing-newline variant returned $rc, want 2"
rm -rf "$W"; cp -R "$SUITE/fixture" "$W"; cp "$SUITE/expected/p2/stats.py.expected" "$W/stats.py"
bash "$SUITE/oracle.sh" p2 "$W" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "(1) oracle: a plan task with only one of its two files edited FAILS" || no "(1) oracle on a half-applied plan returned $rc, want 1"

# ── 2–4. the python contract ───────────────────────────────────────────────────────────────────────────
python3 - "$ROOT" "$BIN" "$TMP" >"$TMP/out.txt" 2>&1 <<'PY'
import json, os, pathlib, subprocess, sys
root, ripwire_bin, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert( 0, str( pathlib.Path( root ) / "bench" / "agentloop" ) )
import run_editsuite as E
import run_agentloop as R
def ok( m ): print( "PASS " + m )
def no( m ): print( "FAIL " + m )

# 1b. shape
tasks = E.load_tasks()
kinds = [ t["kind"] for t in tasks ]
( ok if len( tasks ) == 12 else no )( "(1) 12 tasks (%d)" % len( tasks ) )
( ok if kinds.count( "replace" ) == 6 else no )( "(1) 6 replace-body tasks (%d)" % kinds.count( "replace" ) )
( ok if kinds.count( "insert_before" ) + kinds.count( "insert_after" ) == 3 else no )( "(1) 3 insert tasks" )
( ok if kinds.count( "plan" ) == 3 and all( len( t["ops"] ) >= 2 for t in tasks if t["kind"] == "plan" ) else no )( "(1) 3 multi-edit plan tasks, each with >= 2 ops" )
( ok if all( ( E.SUITE / "expected" / t["id"] ).is_dir() for t in tasks ) else no )( "(1) every task has an expected/ tree" )

# 2. isolation is REUSED, not copied
( ok if E.R is R else no )( "(2) run_editsuite drives run_agentloop's runner code (import, not a copy)" )
src = ( pathlib.Path( root ) / "bench" / "agentloop" / "run_editsuite.py" ).read_text()
dup = [ n for n in ( "def prepare_opencode_environment", "def prepare_codex_environment", "def ephemeral_run_home",
                     "def install_ripwire_shim", "def build_opencode_command", "def build_codex_command" ) if n in src ]
( ok if not dup else no )( "(2) no runner-isolation function is re-defined in run_editsuite.py%s" % ( "" if not dup else ": " + ", ".join( dup ) ) )
( ok if all( n in src for n in ( "R.prepare_environment(", "R.build_harness_command(", "R.sh(" ) ) else no )(
    "(2) run_one_edit calls R.prepare_environment / R.build_harness_command / R.sh" )
env, run_home, shim = R.prepare_environment( "opencode", tmp, "edit-r1", "ripwire_edit", 1, ripwire_bin )
( ok if env.get( "HOME" ) and env["HOME"].startswith( tmp ) and env.get( "OPENCODE_DISABLE_CLAUDE_CODE" ) == "1" else no )(
    "(2) the opencode environment is the isolated one (HOME under the work dir, CLAUDE.md disabled)" )
( ok if env["PATH"].split( os.pathsep )[0] == str( pathlib.Path( shim ).parent ) else no )( "(2) the logging shim is first on PATH" )
sub = pathlib.Path( tmp ) / "pwdprobe"; sub.mkdir( exist_ok=True )
p = R.sh( [ "sh", "-c", "printf %s \"$PWD\"" ], cwd=str( sub ), env=dict( os.environ ) )
( ok if p.stdout == str( sub ) else no )( "(2) sh(cwd=X) sets the child's \$PWD to X (opencode roots native tools at \$PWD): got %r" % p.stdout )

# 3. alternating arm order, arms adjacent
cells = E.matrix( tasks )
( ok if len( cells ) == 24 else no )( "(3) 12 tasks x 2 arms = 24 cells (%d)" % len( cells ) )
firsts = [ cells[ 2 * i ][1] for i in range( 12 ) ]
( ok if firsts == [ "ripwire_edit", "native_edit" ] * 6 else no )( "(3) arm order alternates per task: %s" % ",".join( f[:1] for f in firsts ) )
( ok if all( cells[ 2 * i ][0]["id"] == cells[ 2 * i + 1 ][0]["id"] and cells[ 2 * i ][1] != cells[ 2 * i + 1 ][1] for i in range( 12 ) ) else no )(
    "(3) each task's two arms are adjacent in the run order" )

# the prompts: the ripwire arm names the shim and says the receipt already carries the post-check; the native arm forbids ripwire
t = tasks[0]
pr = E.build_edit_prompt( t, "ripwire_edit", 1, "/x/shim/ripwire", "" )
pn = E.build_edit_prompt( t, "native_edit", 1, "/x/shim/ripwire", "" )
( ok if "/x/shim/ripwire" in pr and "--replace-symbol-body=area_of_triangle" in pr and "edit_check" in pr and "tests_to_run" in pr else no )(
    "(3) the ripwire-arm prompt names the shim, the verb and the receipt's edit_check/tests_to_run" )
( ok if "Do not use ripwire" in pn and "--replace-symbol-body" not in pn else no )( "(3) the native-arm prompt forbids ripwire and names no ripwire verb" )
( ok if t["new_text"] in pr and t["new_text"] in pn else no )( "(3) both arms carry the byte-exact new definition" )
tp = [ x for x in tasks if x["kind"] == "plan" ][0]
pp = E.build_edit_prompt( tp, "ripwire_edit", 1, "/x/shim/ripwire", "" )
( ok if "--edit-plan=" in pp and "--apply" in pp and '"version":1' in pp else no )( "(3) the plan task's ripwire prompt names --edit-plan --apply with a version:1 plan" )

# 4. the accounting, on fixture events
SHIM = "/w/opencode-home/ripwire_edit/edit-r1-1/shim/ripwire"
def oc( tool, **inp ):
    return { "type": "tool_use", "part": { "tool": tool, "state": { "status": "completed", "input": inp } } }
def stream( events ):
    return "\n".join( json.dumps( e ) for e in events ) + "\n"
files, syms = [ "geometry.cpp" ], [ "area_of_triangle" ]
ev = [ oc( "bash", command="ls -la /home/me/ripwire-wt-x/" ),                                     # a PATH containing ripwire: not a call
       oc( "bash", command="printf 'x' | %s . --replace-symbol-body=area_of_triangle --edit-target-file=geometry.cpp --edit-payload=-" % SHIM ),
       oc( "read", filePath="/w/repos/r1/geometry.cpp" ),                                              # policy-read of the TARGET
       oc( "bash", command="%s . --edit-check=geometry.cpp:area_of_triangle" % SHIM ),                # redundant check
       oc( "read", filePath="/w/repos/r1/geometry.h" ),                                                # sweep: another file
       oc( "edit", filePath="/w/repos/r1/geometry.cpp", oldString="a", newString="b" ),                # native re-edit of the target
       oc( "bash", command="git diff -- geometry.cpp" ),
       oc( "bash", command="sed -n '1,30p' geometry.cpp" ) ]                                           # 6th post call: outside the 5-window
calls = E.walk_tool_calls( "opencode", stream( ev ) )
( ok if len( calls ) == 8 else no )( "(4) walk_tool_calls keeps every tool_use in order (%d)" % len( calls ) )
cl = E.classify_all( calls, files, syms )
classes = [ c["class"] for c in cl ]
want = [ "find", "ripwire-edit", "read", "ripwire-edit-check", "read", "native-edit", "git-diff", "read" ]
( ok if classes == want else no )( "(4) classes: %s" % ",".join( classes ) )
( ok if cl[0]["family"] == "native" and cl[1]["family"] == "ripwire" else no )( "(4) a path containing 'ripwire' is not a ripwire call; the shim invocation is" )
( ok if cl[2]["target"] == "geometry.cpp" and cl[4]["target"] == "" and cl[5]["target"] == "geometry.cpp" else no )( "(4) target= names the target file only when the call names it" )
idx = E.edit_call_index( cl, "ripwire_edit", files )
( ok if idx == 1 else no )( "(4) the window hangs off the FIRST ripwire edit verb (index %s)" % idx )
w = E.window_verdict( cl, idx )
checks = [ ( w["post_edit_count"] == 6, "post_edit_count=6 (%s)" % w["post_edit_count"] ),
           ( w["window_count"] == 5, "window_count=5 (the 5-call meter window)" ),
           ( w["policy_read_window"] == 1 and w["policy_read_total"] == 2, "policy reads: 1 in window, 2 total (the sed -n past the window is counted in the total only)" ),
           ( w["redundant_check_window"] == 1, "redundant --edit-check on the same symbol counted" ),
           ( w["sweep_window"] == 2, "sweep: the other-file read + the native re-edit (2)" ),
           ( w["native_edit_after"] == 1, "native re-edit of the target counted" ),
           ( w["git_diff_after"] == 1, "git diff after the edit counted (reported, not a verdict)" ),
           ( w["terminal_band"] is False and w["terminal_t2"] is False, "not terminal under either definition" ) ]
for good, msg in checks:
    ( ok if good else no )( "(4) " + msg )
# a clean window: the edit, then nothing
cl2 = E.classify_all( E.walk_tool_calls( "opencode", stream( ev[1:2] ) ), files, syms )
w2 = E.window_verdict( cl2, E.edit_call_index( cl2, "ripwire_edit", files ) )
( ok if w2["terminal_band"] and w2["terminal_t2"] and w2["post_edit_count"] == 0 else no )( "(4) edit-then-stop is TERMINAL under both definitions" )
# --edit-check on a DIFFERENT symbol is not a redundant check
cl3 = E.classify_all( E.walk_tool_calls( "opencode", stream( ev[1:2] + [ oc( "bash", command="%s . --edit-check=geometry.cpp:perimeter" % SHIM ) ] ) ), files, syms )
( ok if cl3[1]["class"] == "ripwire-cli" and E.window_verdict( cl3, 0 )["redundant_check_total"] == 0 else no )( "(4) --edit-check on another symbol is ripwire-cli, not a redundant check" )
# no edit at all
w4 = E.window_verdict( cl[ :1 ], E.edit_call_index( cl[ :1 ], "ripwire_edit", files ) )
( ok if w4["terminal_band"] is False and w4["post_edit_count"] == 0 else no )( "(4) a run that never edited is not terminal (nothing to be terminal after)" )
# native arm: the window hangs off the native edit of the target
cln = E.classify_all( E.walk_tool_calls( "opencode", stream( [ oc( "read", filePath="/w/r/geometry.cpp" ), oc( "edit", filePath="/w/r/geometry.cpp", oldString="a", newString="b" ), oc( "bash", command="cat geometry.cpp" ) ] ) ), files, syms )
( ok if E.edit_call_index( cln, "native_edit", files ) == 1 and E.window_verdict( cln, 1 )["policy_read_total"] == 1 else no )( "(4) native arm: window hangs off the native edit; a cat of the target after it is a policy read" )
# a 2-op task: the window opens after the SECOND edit of the arm's kind (the task's own second op is not a re-edit)
cl2op = E.classify_all( E.walk_tool_calls( "opencode", stream( [ oc( "edit", filePath="/w/r/geometry.cpp", oldString="a", newString="b" ), oc( "edit", filePath="/w/r/geometry.cpp", oldString="c", newString="d" ), oc( "read", filePath="/w/r/geometry.cpp" ) ] ) ), files, syms )
( ok if E.edit_call_index( cl2op, "native_edit", files, ops=2 ) == 1 and E.window_verdict( cl2op, 1 )["native_edit_after"] == 0 and E.window_verdict( cl2op, 1 )["policy_read_total"] == 1 else no )(
    "(4) a 2-op task's window opens after the 2nd native edit: no self re-edit counted, the read after it is" )
clpl = E.classify_all( E.walk_tool_calls( "opencode", stream( [ oc( "bash", command="%s . --edit-plan=/tmp/p/plan.json --apply" % SHIM ), oc( "read", filePath="/w/r/geometry.cpp" ) ] ) ), files, syms )
( ok if E.edit_call_index( clpl, "ripwire_edit", files, ops=3 ) == 0 else no )( "(4) one --edit-plan --apply is the whole N-op edit: the window opens right after it" )
# a --dry-run before the --apply is the E3 PREVIEW, not the edit: the window hangs off the apply
clpv = E.classify_all( E.walk_tool_calls( "opencode", stream( [ oc( "bash", command="%s . --edit-plan=/tmp/p/plan.json --dry-run" % SHIM ), oc( "bash", command="%s . --edit-plan=/tmp/p/plan.json --apply" % SHIM ) ] ) ), files, syms )
( ok if [ c["class"] for c in clpv ] == [ "ripwire-preview", "ripwire-edit" ] and E.edit_call_index( clpv, "ripwire_edit", files, ops=2 ) == 1 else no )(
    "(4) --edit-plan --dry-run is ripwire-preview; the window opens after the --apply (%s)" % ",".join( c["class"] for c in clpv ) )
# codex stream: shell-only, cat/sed -n of the target is a read
cx = [ { "type": "item.completed", "item": { "type": "command_execution", "command": "%s . --insert-after-symbol=trace --edit-target-file=matrix.cpp --edit-payload=/tmp/p" % SHIM } },
       { "type": "item.completed", "item": { "type": "command_execution", "command": [ "bash", "-lc", "sed -n '20,40p' matrix.cpp" ] } },
       { "type": "item.completed", "item": { "type": "reasoning" } } ]
clx = E.classify_all( E.walk_tool_calls( "codex-exec", stream( cx ) ), [ "matrix.cpp" ], [ "trace" ] )
( ok if [ c["class"] for c in clx ] == [ "ripwire-edit", "read" ] and clx[1]["target"] == "matrix.cpp" else no )( "(4) codex stream: command_execution items only; sed -n of the target is a policy read" )
# meter rows
rec = E.make_record( t, "ripwire_edit", 1, "opencode", "opencode/big-pickle", started_unix=0.0, repo_dir="/w/repos/r1" )
rows = E.meter_rows( rec, cl )
need = [ "v", "ts", "seq", "session", "repo", "tag", "tool", "class", "family", "agent", "surface", "target", "detail" ]
( ok if rows and all( all( k in r for k in need ) for r in rows ) else no )( "(4) every meter row carries %s" % ",".join( need ) )
( ok if rows and rows[0]["agent"] == "opencode" and rows[0]["surface"] == "cli" and rows[0]["tag"] == "ripwire" and [ r["seq"] for r in rows ] == list( range( 1, len( rows ) + 1 ) ) else no )(
    "(4) rows carry agent=<runner>, surface=cli, tag=ripwire and a 1-based seq" )
( ok if all( len( r["detail"] ) <= 200 for r in rows ) else no )( "(4) detail is capped at 200 bytes (the meter's own cap)" )
# the summary reads the band off records
recs = [ dict( rec, status="ok", oracle="pass", edit_call_index=1, window=w ), dict( rec, run_id="x", status="ok", oracle="pass", edit_call_index=0, window=w2 ) ]
s = E.summarize( recs )[ ( "opencode", "ripwire_edit" ) ]
( ok if s["n"] == 2 and s["terminal_band"] == 1 and s["pass"] == 2 and s["policy_reads"] == 2 and s["redundant_checks"] == 1 else no )(
    "(4) summarize: n=2 terminal_band=1 pass=2 policy_reads=2 redundant_checks=1 (%r)" % { k: s[k] for k in ( "n", "terminal_band", "pass", "policy_reads", "redundant_checks" ) } )
PY
grep -E '^(PASS|FAIL) ' "$TMP/out.txt" | sed 's/^PASS /  PASS  /; s/^FAIL /  FAIL  /'
grep -q '^FAIL ' "$TMP/out.txt" && fail=1
grep -qE '^(PASS|FAIL) ' "$TMP/out.txt" || { no "the python contract block produced no verdicts"; cat "$TMP/out.txt"; }

[ "$fail" = 0 ] && echo "agentloopeditsuitecheck: ALL PASS" || echo "agentloopeditsuitecheck: FAILURES ABOVE"
exit "$fail"
