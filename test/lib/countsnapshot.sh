# countsnapshot.sh — sourced by the gates that compare a published total with the tree.
#
# Since 2026-11-02 (GEN-DOCS-MERGE) every total the docs publish is the dated snapshot docs/counts.tsv
# (docs/counts_snapshot.py says why: two open PRs that each add a gate or a cap must not both rewrite one
# line). A gate that compares a published total therefore compares it with the snapshot, and reports the
# live value beside it; `python3 docs/counts_snapshot.py check` is where snapshot == live is asserted.
#
# countsSnapshotValue ROOT KEY: prints the snapshot's value for KEY. Exit 0 found; 1 the tree has no
# docs/counts.tsv (a synthetic tree: compare with the live value, as before); 2 the file exists but has no
# such key or no `taken` date (a gate FAILS on 2 — an unreadable snapshot is never "no snapshot").
#
# The file is read by docs/counts_snapshot.py's own read() (one parser, so this helper refuses exactly what the
# generators refuse: a malformed or duplicate line anywhere, a second `taken`, an impossible date, totals that
# do not add up); a tree whose docs/ has no counts_snapshot.py is read as 2.
countsSnapshotValue() {
    local f="$1/docs/counts.tsv"
    [ -f "$f" ] || return 1
    [ -f "$1/docs/counts_snapshot.py" ] || return 2
    python3 -B -c '
import sys
sys.path.insert( 0, sys.argv[ 1 ] + "/docs" )
import counts_snapshot
try:
    snap = counts_snapshot.read( sys.argv[ 1 ] )
except SystemExit as e:
    sys.stderr.write( "%s\n" % e ); sys.exit( 2 )
v = ( snap or {} ).get( sys.argv[ 2 ], "" )
if v == "":
    sys.exit( 2 )
print( v )' "$1" "$2" || return 2
}
