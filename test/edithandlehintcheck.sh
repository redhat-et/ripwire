#!/usr/bin/env bash
# edithandlehintcheck.sh — A4: the tool's own post-edit advice is a command that actually runs.
#
# THE BUG THIS GATE PINS. After a successful CLI edit, runCliEdit printed
#
#   ripwire edit: applied atomically; verify with --edit-check=<the argument you passed>, ...
#
# echoing the caller's own `sym` back. That is wrong two ways. A handle-addressed edit
# (--replace-symbol-body=sym#<16hex>@<16hex>, the form --grep --handles mints) printed a handle, and
# --edit-check does not accept handles — so following the tool's own printed instruction failed EVERY time.
# And a bare name narrowed by --edit-target-file printed the bare name, which sends --edit-check to a
# different same-named definition in another file. The advice's second half was vaguer still: "run
# --affected on the receipt's file", i.e. go parse the JSON yourself.
#
# The advice now names the RESOLVED file:symbol the engine actually wrote to, for both follow-ups.
#
# ARMS — each one EXECUTES the printed command rather than pattern-matching it, which is the whole point:
#   1. handle-addressed edit → the printed --edit-check runs and resolves the definition.
#   2. the printed --affected runs and names the edited file.
#   3. name-addressed edit narrowed by --edit-target-file → the advice points at THAT file's definition,
#      not the same-named one in the other file.
#   4. the advice never contains a sym# handle.
#
# Usage: test/edithandlehintcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

echo "edithandlehintcheck: BIN=$BIN"

mkdir -p "$TMP/template"
cat >"$TMP/template/a.py" <<'PY'
def alpha( x ):
    return x + 1   # UNIQUE_ALPHA_MARKER


def beta( x ):
    return alpha( x ) * 2
PY
cat >"$TMP/template/b.py" <<'PY'
def alpha( x ):
    return x + 100
PY
printf 'def alpha( x ):\n    return 42\n' >"$TMP/pay"

# pull the two follow-up commands back out of the advice line the binary printed.
advice_editcheck(){ grep -o -- '--edit-check=[^, ]*' "$1" | head -1; }
advice_affected(){  grep -o -- '--affected=[^, ]*'   "$1" | head -1; }
: >"$TMP/1.ec.err"; : >"$TMP/1.af.err"     # so a skipped arm's diagnostic read is not a missing-file error

echo
echo "=== 1-2. a handle-addressed edit prints follow-ups that RUN ==="
W1="$TMP/handle"; cp -R "$TMP/template" "$W1"
# grep a token that occurs in exactly ONE definition, so the handle deterministically addresses alpha and
# the payload (which redefines alpha) leaves the name the advice will print still present afterwards.
H="$( "$BIN" "$W1" --grep=UNIQUE_ALPHA_MARKER --handles 2>/dev/null | grep -o 'sym#[0-9a-f]*@[0-9a-f]*' | head -1 )"
[ -n "$H" ] && ok "minted an edit handle to address the edit with" \
             || { no "could not mint an edit handle — --grep --handles produced none"; H="sym#0@0"; }
"$BIN" "$W1" --replace-symbol-body="$H" --edit-payload="$TMP/pay" >"$TMP/1.out" 2>"$TMP/1.err"
grep -q '"applied"' "$TMP/1.out" \
    && ok "the handle-addressed edit applied" \
    || no "the handle-addressed edit failed: $( head -1 "$TMP/1.err" )"

EC="$( advice_editcheck "$TMP/1.err" )"
AF="$( advice_affected  "$TMP/1.err" )"
case "$EC" in
    *'sym#'*)      no "the advice still echoes the sym# handle back: $EC";;
    '')            no "the advice printed no --edit-check follow-up";;
    *a.py:alpha)   ok "the advice names the RESOLVED definition, not the handle ($EC)";;
    *)             no "the advice names something other than the resolved definition: $EC";;
esac
if [ -n "$EC" ] && "$BIN" "$W1" "$EC" 2>"$TMP/1.ec.err" | grep -q '<edit-check'; then
    ok "the printed --edit-check command runs and resolves"
else
    no "the printed --edit-check command fails: $( head -1 "$TMP/1.ec.err" )"
fi
if [ -n "$AF" ] && "$BIN" "$W1" "$AF" 2>"$TMP/1.af.err" | grep -q '<affected'; then
    ok "the printed --affected command runs"
else
    no "the printed --affected command fails or was not printed: $( head -1 "$TMP/1.af.err" )"
fi

echo
echo "=== 3. a name narrowed by --edit-target-file points at THAT file's definition ==="
W2="$TMP/narrow"; cp -R "$TMP/template" "$W2"
"$BIN" "$W2" --replace-symbol-body=alpha --edit-target-file=b.py --edit-payload="$TMP/pay" \
    >"$TMP/2.out" 2>"$TMP/2.err"
EC2="$( advice_editcheck "$TMP/2.err" )"
case "$EC2" in
    *b.py*) ok "the advice names the file the edit actually landed in ($EC2)";;
    '')     no "the advice printed no --edit-check follow-up";;
    *)      no "the advice does not name the edited file, so it points at the wrong definition: $EC2";;
esac
if [ -n "$EC2" ] && "$BIN" "$W2" "$EC2" 2>/dev/null | grep -q '<edit-check'; then
    ok "that file-qualified --edit-check runs"
else
    no "that file-qualified --edit-check does not run"
fi

echo
echo "=== 4. no advice line ever carries a raw handle ==="
if grep -q 'sym#' "$TMP/1.err" "$TMP/2.err"; then
    no "an advice line still carries a sym# handle"
else
    ok "no advice line carries a sym# handle"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
