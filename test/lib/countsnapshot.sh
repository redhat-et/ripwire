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
countsSnapshotValue() {
    local f="$1/docs/counts.tsv"
    [ -f "$f" ] || return 1
    awk -F'\t' 'NF == 2 && $1 == "taken" && $2 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { t = 1 }
                NF == 2 && $1 == k { v = $2; n++ }
                END { if( !t || n != 1 || v == "" ) exit 2; print v }' k="$2" "$f"
}
