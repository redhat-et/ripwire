#!/usr/bin/env bash
# forrowfeaturescheck.sh — ROW-FEATURE-DUMP (src/forrowfeatures.h): RIPWIRE_ROW_FEATURES=<path> makes --for append one TSV line per row it
# ranked or printed, the ranker's internals beside the answer's placement; the answer itself never changes.
#
# ONE generated Python tree (widget.py: a head and 14 same-file siblings, so SIBLING-DEMOTE turns deep rows into pointers; a type with
# members; other.py: more helpers). ARMS
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
#   (j)  a posture the dump does not read (--json) says so on stderr and writes nothing; stdout + rc are the unset run's
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
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
for i in range( 1, 6 ):
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
check( all( int( r["lens_rank"] ) > len( cand ) or r["lens_rank"] == "0" for r in rows if r["cand"] == "0" ), "(c) cand=0 lines rank past the cut" )
# (s) the sum
lifts = [ c for c in COLS if c.startswith( "d_" ) and c != "d_pos" ]
def summed( r ):
    return float( r["lex"] ) + sum( float( r[c] ) for c in lifts )
check( all( abs( summed( r ) - float( r["score"] ) ) <= 1e-4 * max( 1.0, abs( float( r["score"] ) ) ) for r in rows if r["node"] != "-1" ),
       "(s) score = lex + the d_* lifts on every resolved line" )
# (p) pointers
ptrs = re.findall( r'<t p="([^"]*)" sym="([^"]*)" r="(\d+)"', text )
pl = { ( r["name"], r["r"] ): r for r in rows if r["printed"] == "pointer" }
check( ptrs and all( ( s, rk ) in pl for p, s, rk in ptrs ), "(p) each of the %d pointers with r= has a printed=pointer line" % len( ptrs ) )
check( all( pl[( s, rk )]["demote"] == "demoted" for p, s, rk in ptrs if ( s, rk ) in pl ), "(p) the SIBLING-DEMOTE pointers read demote=demoted" )
# (k) verdicts
VERD = { "not_sigs", "top_rank", "K6_noted", "K1_mem", "K7_slot", "no_same_file", "K2_hop_callee", "K3_owner_near", "K4_call_path", "K5_same_as", "demoted" }
drows = [ r for r in rows if r["printed"] == "row" and r["ans_tag"] == "d" and r["section"] == "sigs" ]
check( drows and all( r["demote"] in VERD for r in drows ), "(k) every <sigs> <d> line carries a verdict from the closed set" )
check( all( r["demote"] == "top_rank" for r in drows if 0 < int( r["d_pos"] ) <= 10 ), "(k) d_pos <= 10 reads top_rank" )
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

# (v) VALIDATE, (w) write failure, (j) a posture not dumped
mkdir -p "$TMP/adir"
run dir "RIPWIRE_ROW_FEATURES=$TMP/adir" . --no-cache "--for=$TASK"
if same2 off dir && grep -q 'RIPWIRE_ROW_FEATURES: the path is a directory' "$TMP/dir.err" && [ -z "$( ls -A "$TMP/adir" )" ]; then ok "(v) a directory: stdout + rc unchanged, disclosed, nothing written"; else no "(v) the directory path"; fi
run empty "RIPWIRE_ROW_FEATURES=" . --no-cache "--for=$TASK"
if same2 off empty && grep -q 'RIPWIRE_ROW_FEATURES: the value is not a file path' "$TMP/empty.err"; then ok "(v) an empty value: stdout + rc unchanged, disclosed"; else no "(v) the empty value"; fi
run wfail "RIPWIRE_ROW_FEATURES=$TMP/no/such/dir/rows.tsv" . --no-cache "--for=$TASK"
if same2 off wfail && grep -q 'RIPWIRE_ROW_FEATURES: could not write the file' "$TMP/wfail.err"; then ok "(w) a failed write: stdout + rc unchanged, disclosed"; else no "(w) the failed write (rc $( cat "$TMP/wfail.rc" ), stderr: $( head -c 300 "$TMP/wfail.err" ))"; fi
run joff "" . --no-cache --json "--for=$TASK"
run jon "RIPWIRE_ROW_FEATURES=$TMP/json.tsv" . --no-cache --json "--for=$TASK"
if same2 joff jon && grep -q 'is not dumped: nothing written' "$TMP/jon.err" && [ ! -e "$TMP/json.tsv" ]; then ok "(j) --json: stdout + rc unchanged, disclosed, nothing written"; else no "(j) the --json posture"; fi

[ "$fail" = 0 ] && echo "forrowfeaturescheck: OK" || echo "forrowfeaturescheck: FAIL"
exit "$fail"
