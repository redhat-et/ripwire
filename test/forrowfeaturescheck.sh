#!/usr/bin/env bash
# forrowfeaturescheck.sh — ROW-FEATURE-DUMP (src/forrowfeatures.h): RIPWIRE_ROW_FEATURES=<path> makes --for append one TSV line per row it
# ranked or printed, the ranker's internals beside the answer's placement; the answer itself never changes.
#
# ONE generated Python tree (widget.py: a head and 14 same-file siblings, so SIBLING-DEMOTE turns deep rows into pointers; a type with
# members; other.py: 40 more helpers, so some ranked rows fall past the candidate cut). ARMS
#   (u)  byte identity: stdout, stderr and rc are the same with the variable unset and set, on two tasks
#   (h)  schema: line 1 is `# ripwire.row_features/v1 columns=N`, line 2 the N column names (this list), every line N fields
#   (o)  the printed=row lines, in file order, are the answer's rows (grader_fix_1107: <d>, <y>, <s>, non-`used` <u> outside
#        comments) in output order: same tag, n= and file, ans_pos 1..K
#   (c)  the ranked candidates: lens_rank 1..(number of cand=1 lines) each once, cand=1 exactly on them
#   (s)  score = lex + the d_* lift columns (tolerance band); (s2) on a task naming widget.py and a symbol, the mention anchor's lift
#        rides d_mention / d_file_subject (non-zero on some line) and the sum still holds
#   (p)  every tail pointer that kept its r= has a printed=pointer line; the SIBLING-DEMOTE ones read demote=demoted
#   (k)  every <sigs> <d> row line carries a SIBLING-DEMOTE verdict from the closed set; d_pos <= 10 reads top_rank
#   (a)  a second call appends its lines under the same two header lines (the header is written once)
#   (v)  VALIDATE: a directory or an empty value writes nothing, says so on stderr, and stdout + rc are the unset run's
#   (w)  a write that fails (the directory does not exist) is disclosed on stderr; stdout + rc are the unset run's
#   (j)  a posture the dump does not read (--json; j2: the three RIPWIRE_NO_ switches that turn the capture off, a posture the old
#        notice's list did not name) says so in one generic notice and writes nothing; stdout + rc are the unset run's
#   (x)  an answer not captured whole (RIPWIRE_FAULT_CHARGE_BUFFER=1: no buffer) writes nothing and says so; stdout + rc are the
#        fault-only run's. The switch exists only on a non-NDEBUG build: the arm detects it from the fault-only run's own notice and
#        SKIPs (never PASSes) without it
#   (U)  test/forrowfeatures_unit.cpp: rowfeat_detail::fileRanks with a fileId past the file table, compiled with the standard
#        library's bounds checks on (an out-of-range index aborts the driver), plus an in-range control
# Every negative arm counts what it saw (notices, lines, cases) and FAILs on zero.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
. "$ROOT/test/lib/cxxflags.sh"   # the ONE flags.make parse, for (U)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forrowfeaturescheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset RIPWIRE_ROW_FEATURES
TASK='how does parse widget config work'
TASK2='widget config variant helpers'

python3 - "$TMP/py" <<'PY' || { echo "fixture generator failed"; exit 2; }
import os, sys
d = sys.argv[1]; os.makedirs( d, exist_ok = True )
s = '''def parse_widget_config(path):
    """Parse the widget config file."""
    data = widget_config_reader(path)
    return widget_config_check(data)


def widget_config_reader(path):
    """Read the widget config bytes."""
    return path


def widget_config_check(data):
    """Check the widget config."""
    return data


class WidgetVault:
    """Holds parsed widget config values."""

    def widget_config_get(self, key):
        return key

    def widget_config_put(self, key, value):
        return value

'''
for i in range( 1, 15 ):
    s += '''
def widget_config_variant_%02d(path):
    """Variant %d of the widget config parser."""
    return path

''' % ( i, i )
open( os.path.join( d, "widget.py" ), "w" ).write( s )
o = ""
for i in range( 1, 41 ):
    o += '''
def other_widget_config_helper_%d(x):
    """Widget config helper %d."""
    return x

''' % ( i, i )
open( os.path.join( d, "other.py" ), "w" ).write( o )
PY
cd "$TMP/py" || exit 2

run(){ # run OUTSTEM [env assignment] -- args...: stdout, stderr, rc into $TMP/OUTSTEM.{out,err,rc}
    local stem="$1"; shift
    local envset="$1"; shift
    if [ -n "$envset" ]; then env "$envset" "$BIN" "$@" >"$TMP/$stem.out" 2>"$TMP/$stem.err"; else "$BIN" "$@" >"$TMP/$stem.out" 2>"$TMP/$stem.err"; fi
    echo $? >"$TMP/$stem.rc"
}
same3(){ cmp -s "$TMP/$1.out" "$TMP/$2.out" && cmp -s "$TMP/$1.err" "$TMP/$2.err" && cmp -s "$TMP/$1.rc" "$TMP/$2.rc"; }
same2(){ cmp -s "$TMP/$1.out" "$TMP/$2.out" && cmp -s "$TMP/$1.rc" "$TMP/$2.rc"; }

TSV="$TMP/rows.tsv"
run off ""                               . --no-cache "--for=$TASK"
run on "RIPWIRE_ROW_FEATURES=$TSV"       . --no-cache "--for=$TASK"
run off2 ""                              . --no-cache "--for=$TASK2"
run on2 "RIPWIRE_ROW_FEATURES=$TMP/rows2.tsv" . --no-cache "--for=$TASK2"
[ "$( cat "$TMP/off.rc" )" = 0 ] || no "(u) the unset run exits $( cat "$TMP/off.rc" )"
if same3 off on && same3 off2 on2; then ok "(u) stdout, stderr and rc identical with the variable unset and set (two tasks)"; else no "(u) the answer changed with RIPWIRE_ROW_FEATURES set"; fi
[ -s "$TSV" ] || no "(u) the set run wrote no file"

python3 - "$TSV" "$TMP/on.out" "$TASK" <<'PY' || fail=1
import re, sys
tsv, ans, task = sys.argv[1], open( sys.argv[2] ).read(), sys.argv[3]
COLS = ( "task node name scope file line kind printed ans_pos ans_tag section d_pos r lens_rank cand score lex tier "
         "d_anchor d_mention d_file_subject d_path_upstream d_siblift d_pool d_expand d_cochange d_doc_mention "
         "head_dist anchor_dist head_edge head_prov reach_prov same_file same_dir file_rank name_terms any_terms name_idf any_idf "
         "path_terms terms def_count demote row_source head_rr" ).split()
bad = 0
def check( cond, what ):
    global bad
    print( "  %s  %s" % ( "PASS" if cond else "FAIL", what ) ); bad += 0 if cond else 1
lines = open( tsv ).read().split( "\n" )
check( lines[0] == "# ripwire.row_features/v1 columns=%d" % len( COLS ), "(h) line 1 is the schema line (%r)" % lines[0] )
check( lines[1].split( "\t" ) == COLS, "(h) line 2 is the %d column names" % len( COLS ) )
body = [ l for l in lines[2:] if l ]
rows = [ dict( zip( COLS, l.split( "\t" ) ) ) for l in body ]
check( all( len( l.split( "\t" ) ) == len( COLS ) for l in body ) and rows, "(h) every one of %d lines has %d fields" % ( len( body ), len( COLS ) ) )
check( all( r["task"] == task for r in rows ), "(h) the task column is the task" )
# (o) the answer's rows, grader_fix_1107.top_rows' rule
ATTR = re.compile( r'([\w:-]+)="([^"]*)"' )
ANSROW = re.compile( r'<(d|y|s|u)((?:\s+[\w:-]+="[^"]*")*)\s*/?>' )
text = re.sub( r"<!--.*?-->", " ", ans, flags = re.S )
want = []
for m in ANSROW.finditer( text ):
    a = dict( ATTR.findall( m.group( 2 ) ) )
    if m.group( 1 ) == "u" and a.get( "v" ) == "used":
        continue
    want.append( ( m.group( 1 ), a.get( "n", "" ), a.get( "p", "" ).split( ":" )[0] ) )
got = [ ( r["ans_tag"], r["name"], r["file"] ) for r in rows if r["printed"] == "row" ]
check( got == want and len( want ) >= 10, "(o) the %d printed=row lines are the answer's %d rows in output order" % ( len( got ), len( want ) ) )
check( [ int( r["ans_pos"] ) for r in rows if r["printed"] == "row" ] == list( range( 1, len( want ) + 1 ) ), "(o) ans_pos runs 1..%d" % len( want ) )
# (c) candidates
cand = [ r for r in rows if r["cand"] == "1" ]
ranks = sorted( int( r["lens_rank"] ) for r in cand )
check( cand and ranks == list( range( 1, len( cand ) + 1 ) ), "(c) the %d cand=1 lines hold lens_rank 1..%d once each" % ( len( cand ), len( cand ) ) )
past = [ r for r in rows if r["cand"] == "0" ]
check( past and all( int( r["lens_rank"] ) > len( cand ) or r["lens_rank"] == "0" for r in past ), "(c) the %d cand=0 lines rank past the cut" % len( past ) )
# (s) the sum
lifts = [ c for c in COLS if c.startswith( "d_" ) and c != "d_pos" ]
def summed( r ):
    return float( r["lex"] ) + sum( float( r[c] ) for c in lifts )
resolved = [ r for r in rows if r["node"] != "-1" ]
check( resolved and all( abs( summed( r ) - float( r["score"] ) ) <= 1e-4 * max( 1.0, abs( float( r["score"] ) ) ) for r in resolved ),
       "(s) score = lex + the d_* lifts on all %d resolved lines" % len( resolved ) )
# (p) pointers
ptrs = re.findall( r'<t p="([^"]*)" sym="([^"]*)" r="(\d+)"', text )
pl = { ( r["name"], r["r"] ): r for r in rows if r["printed"] == "pointer" }
check( ptrs and all( ( s, rk ) in pl for p, s, rk in ptrs ), "(p) each of the %d pointers with r= has a printed=pointer line" % len( ptrs ) )
dem = [ pl[( s, rk )] for p, s, rk in ptrs if ( s, rk ) in pl ]
check( dem and all( r["demote"] == "demoted" for r in dem ), "(p) the %d SIBLING-DEMOTE pointers read demote=demoted" % len( dem ) )
# (k) verdicts
VERD = { "not_sigs", "top_rank", "K6_noted", "K1_mem", "K7_slot", "no_same_file", "K2_hop_callee", "K3_owner_near", "K4_call_path", "K5_same_as", "demoted" }
drows = [ r for r in rows if r["printed"] == "row" and r["ans_tag"] == "d" and r["section"] == "sigs" ]
check( drows and all( r["demote"] in VERD for r in drows ), "(k) all %d <sigs> <d> lines carry a verdict from the closed set" % len( drows ) )
top = [ r for r in drows if 0 < int( r["d_pos"] ) <= 10 ]
check( top and all( r["demote"] == "top_rank" for r in top ), "(k) the %d lines at d_pos <= 10 read top_rank" % len( top ) )
sys.exit( 1 if bad else 0 )
PY

# (s2) a task the mention anchor lifts: its lift is a column, and the sum holds
TASK3='how does widget.py parse_widget_config work'
run on4 "RIPWIRE_ROW_FEATURES=$TMP/rows4.tsv" . --no-cache "--for=$TASK3"
python3 - "$TMP/rows4.tsv" <<'PY' || fail=1
import csv, sys
rows = list( csv.DictReader( [ l for l in open( sys.argv[1] ).read().split( "\n" ) if l and not l.startswith( "# " ) ], delimiter = "\t", quoting = csv.QUOTE_NONE ) )
lifts = [ c for c in rows[0] if c.startswith( "d_" ) and c != "d_pos" ]
moved = [ r for r in rows if any( float( r[c] ) != 0.0 for c in ( "d_mention", "d_file_subject" ) ) ]
ok = all( abs( float( r["lex"] ) + sum( float( r[c] ) for c in lifts ) - float( r["score"] ) ) <= 1e-4 * max( 1.0, abs( float( r["score"] ) ) ) for r in rows if r["node"] != "-1" )
print( "  %s  (s2) %d lines carry a mention-anchor lift and score = lex + the lifts on all %d" % ( "PASS" if moved and ok else "FAIL", len( moved ), len( rows ) ) )
sys.exit( 0 if moved and ok else 1 )
PY

# (a) a second call appends under one header
run on3 "RIPWIRE_ROW_FEATURES=$TSV" . --no-cache "--for=$TASK2"
heads="$( grep -c '^# ripwire.row_features/v1' "$TSV" )"; names="$( grep -c '^task	node	' "$TSV" )"
if [ "$heads" = 1 ] && [ "$names" = 1 ] && grep -q "^$TASK2	" "$TSV" && grep -q "^$TASK	" "$TSV"; then ok "(a) the second call appended its lines under the one header"; else no "(a) header lines $heads/$names or a call's lines missing"; fi

# (v) VALIDATE, (w) write failure, (j) a posture not dumped, (x) an answer not captured whole: each counts the notices it saw
seen(){ grep -c "$2" "$TMP/$1.err" | tr -d ' '; }   # seen STEM TEXT: how many stderr lines of run STEM carry TEXT
mkdir -p "$TMP/adir"
run dir "RIPWIRE_ROW_FEATURES=$TMP/adir" . --no-cache "--for=$TASK"
n="$( seen dir 'RIPWIRE_ROW_FEATURES: the path is a directory' )"
if same2 off dir && [ "$n" -ge 1 ] && [ -z "$( ls -A "$TMP/adir" )" ]; then ok "(v) a directory: stdout + rc unchanged, $n notice(s), nothing written"; else no "(v) the directory path ($n notices)"; fi
run empty "RIPWIRE_ROW_FEATURES=" . --no-cache "--for=$TASK"
n="$( seen empty 'RIPWIRE_ROW_FEATURES: the value is not a file path' )"
if same2 off empty && [ "$n" -ge 1 ]; then ok "(v) an empty value: stdout + rc unchanged, $n notice(s)"; else no "(v) the empty value ($n notices)"; fi
run wfail "RIPWIRE_ROW_FEATURES=$TMP/no/such/dir/rows.tsv" . --no-cache "--for=$TASK"
n="$( seen wfail 'RIPWIRE_ROW_FEATURES: could not write the file' )"
if same2 off wfail && [ "$n" -ge 1 ]; then ok "(w) a failed write: stdout + rc unchanged, $n notice(s)"; else no "(w) the failed write (rc $( cat "$TMP/wfail.rc" ), $n notices, stderr: $( head -c 300 "$TMP/wfail.err" ))"; fi
NOTDUMPED='does not print the captured XML answer the dump reads: nothing written'
run joff "" . --no-cache --json "--for=$TASK"
run jon "RIPWIRE_ROW_FEATURES=$TMP/json.tsv" . --no-cache --json "--for=$TASK"
n="$( seen jon "$NOTDUMPED" )"
if same2 joff jon && [ "$n" -ge 1 ] && [ ! -e "$TMP/json.tsv" ]; then ok "(j) --json: stdout + rc unchanged, $n notice(s), nothing written"; else no "(j) the --json posture ($n notices)"; fi
SW='RIPWIRE_NO_FILE_SYMS=1 RIPWIRE_NO_ONE_SIDE_REACH=1 RIPWIRE_NO_SIBLING_DEMOTE=1'
env $SW "$BIN" . --no-cache "--for=$TASK" >"$TMP/swoff.out" 2>"$TMP/swoff.err"; echo $? >"$TMP/swoff.rc"
env $SW "RIPWIRE_ROW_FEATURES=$TMP/sw.tsv" "$BIN" . --no-cache "--for=$TASK" >"$TMP/swon.out" 2>"$TMP/swon.err"; echo $? >"$TMP/swon.rc"
n="$( seen swon "$NOTDUMPED" )"
if same2 swoff swon && [ "$n" -ge 1 ] && [ ! -e "$TMP/sw.tsv" ]; then ok "(j2) the capture switched off: stdout + rc unchanged, $n generic notice(s), nothing written"; else no "(j2) the switched-off capture ($n notices)"; fi
RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" . --no-cache "--for=$TASK" >"$TMP/xoff.out" 2>"$TMP/xoff.err"; echo $? >"$TMP/xoff.rc"
if [ "$( seen xoff 'could not buffer the answer' )" -ge 1 ]; then
    RIPWIRE_FAULT_CHARGE_BUFFER=1 RIPWIRE_ROW_FEATURES="$TMP/x.tsv" "$BIN" . --no-cache "--for=$TASK" >"$TMP/xon.out" 2>"$TMP/xon.err"; echo $? >"$TMP/xon.rc"
    n="$( seen xon 'RIPWIRE_ROW_FEATURES: the answer was not captured whole' )"
    if same2 xoff xon && [ "$n" -ge 1 ] && [ ! -e "$TMP/x.tsv" ]; then ok "(x) an uncaptured answer: stdout + rc are the fault-only run's, $n notice(s), nothing written"
    else no "(x) an uncaptured answer: $n notice(s), file $( [ -e "$TMP/x.tsv" ] && echo "written ($( grep -vc '^#' "$TMP/x.tsv" | tr -d ' ' ) lines)" || echo absent )"; fi
else
    printf '  SKIP  (x) RIPWIRE_FAULT_CHARGE_BUFFER injects nothing in this binary (NDEBUG): CI'"'"'s plain leg proves this arm\n'
fi

# (U) the fileRanks unit driver, compiled with the flags CMake used for $BIN plus the standard library's bounds checks
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"; LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
if [ ! -f "$FLAGS_MK" ] || [ ! -f "$LINK_TXT" ]; then
    no "(U) cannot find CMake flags under $BUILD_DIR: the unit arm needs a CMake-built binary"
elif ! cxxflags_load "$FLAGS_MK"; then
    no "(U) cannot parse $FLAGS_MK without executing it"
else
    CXX="$( awk 'NR==1{ print $1; exit }' "$LINK_TXT" )"
    [ -n "$CXX" ] && command -v "$CXX" >/dev/null 2>&1 || CXX="$( command -v c++ || command -v clang++ )"
    DIAG_OBJ="$BUILD_DIR/CMakeFiles/ripwire.dir/src/infra/diagnostics.cpp.o"
    DIAG_LINK=(); [ -f "$DIAG_OBJ" ] && DIAG_LINK=( "$DIAG_OBJ" )
    if "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_DEBUG -D_GLIBCXX_ASSERTIONS \
         "${CXX_INCLUDES[@]}" -I"$ROOT/src" "$ROOT/test/forrowfeatures_unit.cpp" "${DIAG_LINK[@]}" -o "$TMP/rowfeat_unit" >"$TMP/u_build.log" 2>&1; then
        "$TMP/rowfeat_unit" >"$TMP/u_run.log" 2>&1; urc=$?
        n="$( grep -c '  PASS' "$TMP/u_run.log" | tr -d ' ' )"
        if [ "$urc" = 0 ] && [ "$n" -ge 1 ]; then ok "(U) forrowfeatures_unit: $n case(s) hold"
        else no "(U) forrowfeatures_unit rc=$urc, $n case(s) passed:"; grep -E 'FAIL|assert|Assertion|out of bounds|out-of-range|index' "$TMP/u_run.log" | head -4 | sed 's/^/        /'; fi
    else
        no "(U) forrowfeatures_unit does not compile:"; grep -m4 -E 'error' "$TMP/u_build.log" | sed 's/^/        /'
    fi
fi

[ "$fail" = 0 ] && echo "forrowfeaturescheck: OK" || echo "forrowfeaturescheck: FAIL"
exit "$fail"
