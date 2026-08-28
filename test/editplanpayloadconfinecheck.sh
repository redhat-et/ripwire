#!/usr/bin/env bash
# editplanpayloadconfinecheck.sh — A5: an edit plan may only read payloads that sit beside it, and the
# dry-run receipt shows which bytes each operation will read. Plus A7: a QUOTED version is not numeric 1.
#
# THE BUG THIS GATE PINS (A5). editplan::siblingPath returned the payload verbatim when it was absolute, and
# otherwise joined it to the plan's directory with no normalization. So a plan could say
#
#   {"op":"replace_symbol_body","target":"alpha","payload":"../../../../etc/hosts"}
#
# and that file's bytes were spliced into a source file, reported as an ordinary success. This is a READ
# escape only — no write ever lands outside the crawl root, which is why it is LOW and not a write hole —
# but a plan arriving from a shared repo, a PR, or another agent could quietly bake a secret into a file the
# next commit publishes. And the --dry-run receipt, the thing a human reads BEFORE --apply, named the op,
# the target and the file, but never the payload, so the review could not have caught it either.
#
# ARMS:
#   1. a "../" escape refuses, and the message names the path it actually RESOLVED (not the spelling the
#      plan wrote, which is the whole point — the spelling is what disguised it).
#   2. an ABSOLUTE payload path refuses.
#   3. a SYMLINK sitting inside the plan directory but pointing out of it refuses — the case a purely
#      lexical check would wave through.
#   4. a NON-EXISTENT escape refuses as an escape, not as a mere read failure — the case realpath cannot
#      judge, so a purely realpath-based check would mis-report it.
#   5. an ordinary payload beside the plan still works, under BOTH a relative and an absolute plan path
#      (the symlinked-prefix false positive: /tmp vs /private/tmp must not read as an escape).
#   6. the dry-run receipt carries payload_path for every operation.
#   7. every refusal leaves the corpus byte-identical, and no secret byte reaches it.
#   8. (A7) {"version":"1"} — the JSON string — is refused, as the spec and the refusal text both say
#      NUMERIC 1. findRawValue strips quotes, so `1` and `"1"` both arrived as text=="1" and the string
#      form slipped through a rule the message claimed to enforce.
#
# Usage: test/editplanpayloadconfinecheck.sh [BIN]
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

echo "editplanpayloadconfinecheck: BIN=$BIN"

hashcorpus(){ ( cd "$1" && find . -type f -print | LC_ALL=C sort | xargs shasum -a 256 ) | shasum -a 256; }

D="$TMP/w"
mkdir -p "$D/corpus" "$D/plans" "$D/secret"
printf 'def alpha( x ):\n    return x + 1\n' >"$D/corpus/a.py"
printf 'RIPWIRE_GATE_SECRET_MARKER=abc123\n' >"$D/secret/creds.txt"
printf 'def alpha( x ):\n    return 42\n' >"$D/plans/good"
ln -s ../secret/creds.txt "$D/plans/link"

plan(){ printf '{"version":%s,"edits":[{"op":"replace_symbol_body","target":"alpha","payload":"%s"}]}\n' "$2" "$3" >"$D/plans/$1.json"; }
plan escape 1 '../secret/creds.txt'
plan abs     1 '/etc/hosts'
plan sym     1 'link'
plan gone    1 '../../../nope'
plan good    1 'good'
plan qver    '"1"' 'good'

BEFORE="$( hashcorpus "$D/corpus" )"
POISONED=0

# Run a plan against a PRISTINE corpus and leave stdout/stderr in $TMP/<tag>.{out,err}; echo the exit code.
#
# The reset is not tidiness. Against the pre-fix binary the very first arm SUCCEEDS and splices a secret into
# a.py, which deletes the symbol every later arm targets — so without this every subsequent arm fails with
# "symbol 'alpha' not found" and the gate's red output says nothing about the property it was testing. Each
# arm must be independently diagnosable on a broken binary, or its red state is not evidence. Any arm that
# leaves the corpus changed sets POISONED, which arm 7 reports.
# Sets the globals RC and POISONED. Deliberately NOT called through $( ... ): a command substitution is a
# subshell, so the POISONED write would be discarded and arm 7 would report clean over a corpus that had
# just been overwritten — verified while writing this gate.
RC=0
runplan(){
    tag="$1"; planpath="$2"; mode="$3"
    printf 'def alpha( x ):\n    return x + 1\n' >"$D/corpus/a.py"
    ( cd "$D" && "$BIN" corpus --edit-plan="$planpath" "$mode" ) >"$TMP/$tag.out" 2>"$TMP/$tag.err"
    RC=$?
    [ "$BEFORE" = "$( hashcorpus "$D/corpus" )" ] || POISONED=1
    grep -rq 'RIPWIRE_GATE_SECRET_MARKER' "$D/corpus" && POISONED=2
    return 0
}

echo
echo "=== 1. a '../' escape refuses, naming the RESOLVED path ==="
runplan escape plans/escape.json --apply
[ "$RC" != 0 ] \
    && ok "the '../' escape refuses" \
    || no "the '../' escape was accepted"
grep -q 'outside the plan' "$TMP/escape.err" \
    && ok "the refusal explains the rule" \
    || no "the refusal does not explain the rule: $( head -1 "$TMP/escape.err" )"
grep -q "resolves to '/.*secret/creds.txt'" "$TMP/escape.err" \
    && ok "the refusal names the path it actually resolved" \
    || no "the refusal does not name the resolved path: $( head -1 "$TMP/escape.err" )"

echo
echo "=== 2. an absolute payload path refuses ==="
runplan abs plans/abs.json --apply
[ "$RC" != 0 ] \
    && ok "an absolute payload path refuses" \
    || no "an absolute payload path was accepted"
grep -q 'outside the plan' "$TMP/abs.err" \
    && ok "the absolute-path refusal explains the rule" \
    || no "the absolute-path refusal does not explain the rule"

echo
echo "=== 3. a symlink inside the plan dir pointing outside refuses ==="
runplan sym plans/sym.json --apply
[ "$RC" != 0 ] \
    && ok "a symlinked payload escaping the plan dir refuses" \
    || no "a symlinked payload escaped the plan dir"
grep -q "resolves to '/.*secret/creds.txt'" "$TMP/sym.err" \
    && ok "the refusal names the symlink's real target" \
    || no "the refusal does not name the symlink's target: $( head -1 "$TMP/sym.err" )"

echo
echo "=== 4. a non-existent escape refuses AS an escape ==="
runplan gone plans/gone.json --apply
[ "$RC" != 0 ] \
    && ok "a non-existent escaping payload refuses" \
    || no "a non-existent escaping payload was accepted"
grep -q 'outside the plan' "$TMP/gone.err" \
    && ok "it refuses as an escape, not as a plain read failure" \
    || no "it refuses for the wrong reason: $( head -1 "$TMP/gone.err" )"

echo
echo "=== 5. an ordinary payload beside the plan still works, relative AND absolute plan path ==="
runplan good plans/good.json --dry-run
[ "$RC" = 0 ] \
    && ok "a payload beside the plan is accepted (relative plan path)" \
    || no "a legitimate payload was refused: $( head -1 "$TMP/good.err" )"
runplan goodabs "$D/plans/good.json" --dry-run
[ "$RC" = 0 ] \
    && ok "a payload beside the plan is accepted (absolute plan path)" \
    || no "a legitimate payload was refused under an absolute plan path: $( head -1 "$TMP/goodabs.err" )"

echo
echo "=== 6. the dry-run receipt shows what each operation will READ ==="
python3 - "$TMP/good.out" >"$TMP/6.v" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read().strip()
if not raw:
    print("MISSING (the plan produced no receipt at all)"); raise SystemExit
r = json.loads(raw)
ops = r.get("operations", [])
paths = [o.get("payload_path") for o in ops]
print("OK " + ",".join(map(str, paths)) if ops and all(p for p in paths) else "MISSING " + repr(paths))
PY
grep -q '^OK' "$TMP/6.v" \
    && ok "every operation names its resolved payload path ($( cat "$TMP/6.v" ))" \
    || no "the receipt does not name the payload each op will read: $( cat "$TMP/6.v" )"

echo
echo "=== 7. across every arm above, no refused plan wrote anything ==="
# POISONED is set by runplan itself, immediately after each invocation, so a write is attributed to the arm
# that made it rather than to whatever happens to run last.
case "$POISONED" in
    0) ok "no plan in this gate changed the corpus";;
    2) no "a plan spliced the secret marker into the corpus";;
    *) no "a plan modified the corpus";;
esac

echo
echo "=== 8. (A7) a QUOTED version is not numeric 1 ==="
runplan qver plans/qver.json --dry-run
[ "$RC" != 0 ] \
    && ok '{"version":"1"} refuses' \
    || no '{"version":"1"} was accepted where the spec says numeric 1'
grep -q 'numeric version 1' "$TMP/qver.err" \
    && ok "the refusal names the numeric-version rule" \
    || no "the refusal does not name the rule: $( head -1 "$TMP/qver.err" )"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
