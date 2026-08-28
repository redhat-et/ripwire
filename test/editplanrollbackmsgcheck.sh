#!/usr/bin/env bash
# editplanrollbackmsgcheck.sh — A3: an edit-plan commit failure says what actually happened to the tree.
#
# THE BUG THIS GATE PINS. The failure message was unconditional:
#
#   edit-plan commit failed; prior files rolled back
#
# but the rollback loop is `while( written > 0 )`, a no-op when the failure lands on the FIRST file — the
# commonest case, since whatever makes a write fail (a read-only directory, a full disk, a permissions
# change) usually applies to the first write too. So the plan surface's most likely refusal claimed a
# rollback that never ran, over files that were never written. An agent reading it cannot tell which of the
# two worlds it is in without going and diffing the tree by hand, which is what a refusal exists to spare it.
#
# HOW A WRITE FAILURE IS INJECTED. mcpedit::atomicWrite creates "<path>.<pid>.tmp" in the target's own
# DIRECTORY, so chmod 0555 on that directory fails the write while leaving the file readable — the plan
# preflights (read + byte-hash) fine and then fails at commit, which is exactly the path under test. Files
# commit in disk-path order, so corpus/a/ is written before corpus/b/ and either can be the failing one.
#
# ARMS:
#   1. failure on the FIRST file  → says no files were written; names the file; both files byte-identical.
#   2. failure on the SECOND file → says N prior files rolled back, with the count; the first file is
#      restored to its ORIGINAL bytes (proving the rollback the message claims actually ran).
#   3. neither message may be the other's: arm 1 must NOT claim a rollback, arm 2 must NOT claim none.
#
# NOT GATED, and stated rather than silently skipped: the THIRD branch — rollback itself failing, the loud
# "inspect files immediately" message — is not reachable from a shell gate. It needs the first file's write
# to succeed and its rollback (the same bytes, same path, same directory, milliseconds later) to fail, which
# no permission or filesystem state a test can set will produce. It is covered by inspection only.
#
# Skipped as inconclusive when run as root: root ignores the directory mode, so no write ever fails.
#
# Usage: test/editplanrollbackmsgcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ "$( id -u )" != 0 ] || { echo "SKIP: running as root — a read-only directory cannot fail a write"; exit 0; }

echo "editplanrollbackmsgcheck: BIN=$BIN"

# a two-file corpus in two directories, so exactly one of the two writes can be made to fail.
build_corpus(){
    local d="$1"
    mkdir -p "$d/corpus/a" "$d/corpus/b" "$d/plans"
    printf 'def one():\n    return 1\n' >"$d/corpus/a/one.py"
    printf 'def two():\n    return 2\n' >"$d/corpus/b/two.py"
    printf 'def one():\n    return 111\n' >"$d/plans/p1"
    printf 'def two():\n    return 222\n' >"$d/plans/p2"
    cat >"$d/plans/plan.json" <<'JSON'
{"version":1,"edits":[{"op":"replace_symbol_body","target":"one","payload":"p1"},
                      {"op":"replace_symbol_body","target":"two","payload":"p2"}]}
JSON
}

# run the plan with $2 made read-only; leaves stderr in $TMP/<tag>.err and re-opens the directory after.
run_with_readonly(){
    local d="$1" ro="$2" tag="$3"
    ( cd "$d" && "$BIN" corpus >/dev/null 2>&1 )        # warm the index while everything is writable
    chmod 0555 "$d/$ro"
    ( cd "$d" && "$BIN" corpus --edit-plan=plans/plan.json --apply ) >"$TMP/$tag.out" 2>"$TMP/$tag.err"
    printf '%s' "$?" >"$TMP/$tag.rc"
    chmod 0755 "$d/$ro"
}

echo
echo "=== 1. failure on the FIRST file: nothing was written, and it says so ==="
D1="$TMP/first"; build_corpus "$D1"
run_with_readonly "$D1" corpus/a first
[ "$( cat "$TMP/first.rc" )" != 0 ] \
    && ok "a failing first write refuses (non-zero exit)" \
    || no "a failing first write reported success"
grep -q 'no files were written' "$TMP/first.err" \
    && ok "the message states that no files were written" \
    || no "the message does not state that no files were written: $( head -1 "$TMP/first.err" )"
grep -q 'one\.py' "$TMP/first.err" \
    && ok "the message names the file the commit failed on" \
    || no "the message does not name the failing file"
grep -q 'rolled back' "$TMP/first.err" \
    && no "the message still claims a rollback that never ran" \
    || ok "the message no longer claims a rollback that never ran"
grep -q 'return 1$' "$D1/corpus/a/one.py" && grep -q 'return 2$' "$D1/corpus/b/two.py" \
    && ok "both files are byte-identical to their originals" \
    || no "a file changed despite the refusal"

echo
echo "=== 2. failure on the SECOND file: the prior file is rolled back, and counted ==="
D2="$TMP/second"; build_corpus "$D2"
run_with_readonly "$D2" corpus/b second
[ "$( cat "$TMP/second.rc" )" != 0 ] \
    && ok "a failing later write refuses (non-zero exit)" \
    || no "a failing later write reported success"
grep -q '1 prior file rolled back' "$TMP/second.err" \
    && ok "the message counts the files it rolled back" \
    || no "the message does not count the rolled-back files: $( head -1 "$TMP/second.err" )"
grep -q 'two\.py' "$TMP/second.err" \
    && ok "the message names the file the commit failed at" \
    || no "the message does not name the failing file"
grep -q 'no files were written' "$TMP/second.err" \
    && no "a real rollback wrongly reports that nothing was written" \
    || ok "a real rollback is not described as 'nothing written'"
# the load-bearing assertion: the claimed rollback actually happened.
grep -q 'return 1$' "$D2/corpus/a/one.py" \
    && ok "the first file was restored to its original bytes" \
    || no "the first file kept the plan's bytes — the claimed rollback did not run"
grep -q 'return 2$' "$D2/corpus/b/two.py" \
    && ok "the file that failed is untouched" \
    || no "the failing file was modified"

echo
echo "=== 3. the two messages are distinguishable ==="
if [ "$( cat "$TMP/first.err" )" = "$( cat "$TMP/second.err" )" ]; then
    no "both failure modes still emit the identical message"
else
    ok "the two failure modes emit different messages"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
