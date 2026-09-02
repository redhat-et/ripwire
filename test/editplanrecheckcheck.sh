#!/usr/bin/env bash
# editplanrecheckcheck.sh — A6: the plan commit re-verifies each file's bytes immediately before ITS OWN
# write, and says so in the receipt.
#
# THE ASYMMETRY THIS GATE PINS. `--edit-plan --apply` used to re-check freshness for ALL files in one loop
# and then write ALL files in a second loop. For file N the interval between its own recheck and its own
# write therefore spanned the fsync of every earlier file: on a K-file plan the LAST file's stale-detection
# window was the whole prior-write duration. The single-edit path deliberately does the opposite — mcpedit.h
# re-hashes immediately before its rename, and its own comment says that "collapses the lost-update window
# to the tiny gap between this re-hash and the rename". The newer plan surface reintroduced, wider, exactly
# the residual the older path was written to minimize.
#
# HONESTY ABOUT WHAT IS AND IS NOT PROVEN HERE. No lost update was ever captured: two independent audit
# lenses tried and neither reproduced one, because it is timing-dependent. The finding rests on verified code
# asymmetry, not on an observed clobber. Correspondingly, this gate does NOT stage a race — a deterministic
# one needs a write-slowing seam the code does not expose, and a sleep-based one would be flaky in CI and
# prove nothing on a fast machine. It gates the OBSERVABLE CONTRACT instead:
#
#   1. the receipt states recheck_before_each_write in BOTH modes (dry-run and apply), so removing the
#      behavior silently also removes a public claim a reader can check;
#   2. the added per-write read does not break the ordinary multi-file commit (the real regression risk of
#      putting a read inside the write loop);
#   3. the two per-file safety claims stay together — a receipt that promises rollback but not the recheck
#      would be the pre-fix shape wearing the post-fix wording.
#
# Advisory EditLocks still serialize a cooperating ripwire writer either way; the exposure this closes is a
# NON-cooperating external writer (an editor or formatter saving mid-commit).
#
# Usage: test/editplanrecheckcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

echo "editplanrecheckcheck: BIN=$BIN"

D="$TMP/w"
mkdir -p "$D/corpus/a" "$D/corpus/b" "$D/plans"
printf 'def one():\n    return 1\n' >"$D/corpus/a/one.py"
printf 'def two():\n    return 2\n' >"$D/corpus/b/two.py"
printf 'def one():\n    return 111\n' >"$D/plans/p1"
printf 'def two():\n    return 222\n' >"$D/plans/p2"
cat >"$D/plans/plan.json" <<'JSON'
{"version":1,"edits":[{"op":"replace_symbol_body","target":"one","payload":"p1"},
                      {"op":"replace_symbol_body","target":"two","payload":"p2"}]}
JSON

echo
echo "=== 1. the dry-run receipt states the per-write recheck ==="
( cd "$D" && "$BIN" corpus --edit-plan=plans/plan.json --dry-run ) >"$TMP/dry.out" 2>"$TMP/dry.err"
python3 - "$TMP/dry.out" >"$TMP/dry.v" <<'PY'
import json, sys
try:
    r = json.load(open(sys.argv[1], encoding="utf-8"))
except (json.JSONDecodeError, OSError) as e:
    # F-17: a defective binary's non-JSON (or missing) stdout must fail this arm's grep cleanly, not
    # dump a raw traceback ahead of the FAIL line — the traceback carried no information the "NO ..."
    # line below doesn't already state.
    print("NO unparseable stdout: " + str(e))
else:
    print("YES" if r.get("recheck_before_each_write") is True else "NO " + repr(r.get("recheck_before_each_write")))
PY
grep -q '^YES' "$TMP/dry.v" \
    && ok "dry-run receipt carries recheck_before_each_write:true" \
    || no "dry-run receipt does not carry recheck_before_each_write: $( cat "$TMP/dry.v" )"

echo
echo "=== 2. the apply receipt states it too, and the commit still lands every file ==="
( cd "$D" && "$BIN" corpus --edit-plan=plans/plan.json --apply ) >"$TMP/app.out" 2>"$TMP/app.err"
python3 - "$TMP/app.out" >"$TMP/app.v" <<'PY'
import json, sys
try:
    r = json.load(open(sys.argv[1], encoding="utf-8"))
except (json.JSONDecodeError, OSError) as e:
    # F-17: same non-JSON-stdout guard as arm 1 — both lines downstream still get a value to grep against.
    print("NO unparseable stdout: " + str(e))
    print("APPLIED None FILES None ROLLBACK None")
else:
    print("YES" if r.get("recheck_before_each_write") is True else "NO " + repr(r.get("recheck_before_each_write")))
    print("APPLIED", r.get("applied"), "FILES", r.get("files"), "ROLLBACK", r.get("rollback_on_write_error"))
PY
head -1 "$TMP/app.v" | grep -q '^YES' \
    && ok "apply receipt carries recheck_before_each_write:true" \
    || no "apply receipt does not carry recheck_before_each_write: $( head -1 "$TMP/app.v" )"
grep -q 'APPLIED 2 FILES 2 ROLLBACK True' "$TMP/app.v" \
    && ok "the per-write read did not break the ordinary two-file commit" \
    || no "the two-file commit regressed: $( tail -1 "$TMP/app.v" )"
grep -q 'return 111' "$D/corpus/a/one.py" && grep -q 'return 222' "$D/corpus/b/two.py" \
    && ok "both files carry their new bytes" \
    || no "a file did not receive its edit"

echo
echo "=== 3. the two per-file safety claims travel together ==="
# rollback_on_write_error without recheck_before_each_write is the pre-fix shape: a receipt that promises to
# undo a bad write but not to notice someone else's good one.
python3 - "$TMP/app.out" >"$TMP/pair.v" <<'PY'
import json, sys
try:
    r = json.load(open(sys.argv[1], encoding="utf-8"))
except (json.JSONDecodeError, OSError) as e:
    # F-17: same guard — an unparseable receipt is UNPAIRED by construction, not a crash.
    print("UNPAIRED unparseable stdout: " + str(e))
else:
    rb, rc = r.get("rollback_on_write_error"), r.get("recheck_before_each_write")
    print("PAIRED" if rb is True and rc is True else "UNPAIRED rollback=%r recheck=%r" % (rb, rc))
PY
grep -q '^PAIRED' "$TMP/pair.v" \
    && ok "rollback and per-write recheck are both claimed" \
    || no "the two per-file safety claims disagree: $( cat "$TMP/pair.v" )"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
