#!/usr/bin/env bash
# grephandlecheck.sh — grep can mint stable, freshness-pinned handles for an unambiguous enclosing symbol.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

mkdir -p "$TMP/src"
cat >"$TMP/src/a.cpp" <<'CPP'
int alpha( int x )
{
    return x + 7;
}

int beta( int x )
{
    return alpha( x );
}
CPP

echo "grephandlecheck: BIN=$BIN"
"$BIN" "$TMP" --grep='return x' --handles >"$TMP/one" 2>"$TMP/one.err" || no "--grep --handles failed"
HANDLE="$( sed -n 's/.* h="\(sym#[0-9a-f]*@[0-9a-f]*\)".*/\1/p' "$TMP/one" | head -1 )"
[ -n "$HANDLE" ] && ok "unique enclosing symbol carries a handle" || no "unique enclosing symbol has no handle"
printf '%s' "$HANDLE" | grep -Eq '^sym#[0-9a-f]{16}@[0-9a-f]{16}$' \
    && ok "handle uses the stable content-addressed shape" \
    || no "handle shape is malformed: $HANDLE"
"$BIN" "$TMP" --grep='return x' --handles >"$TMP/two" 2>/dev/null
cmp -s "$TMP/one" "$TMP/two" \
    && ok "identical trees mint byte-identical handle output" \
    || no "handle output is not deterministic"

cat >"$TMP/replacement" <<'CPP'
int alpha( int x )
{
    return x + 19;
}
CPP
if "$BIN" "$TMP" --replace-symbol-body="$HANDLE" --edit-payload="$TMP/replacement" >"$TMP/edit.out" 2>"$TMP/edit.err"; then
    ok "grep handle flows directly into the CLI edit engine"
else
    no "handle-targeted edit failed: $( head -1 "$TMP/edit.err" )"
fi
grep -q '"resolved_from_handle":"sym#' "$TMP/edit.out" \
    && ok "edit receipt discloses handle resolution" \
    || no "edit receipt omits handle provenance"
grep -q 'return x + 19;' "$TMP/src/a.cpp" \
    && ok "handle-targeted replacement lands on the enclosing definition" \
    || no "handle-targeted replacement missed its definition"

STALE="$( "$BIN" "$TMP" --grep='return x' --handles 2>/dev/null | sed -n 's/.* h="\(sym#[0-9a-f]*@[0-9a-f]*\)".*/\1/p' | head -1 )"
printf '\n// external change\n' >>"$TMP/src/a.cpp"
BEFORE_STALE="$( shasum -a 256 "$TMP/src/a.cpp" )"
if "$BIN" "$TMP" --replace-symbol-body="$STALE" --edit-payload="$TMP/replacement" >"$TMP/stale.out" 2>"$TMP/stale.err"; then
    no "stale handle unexpectedly edited the file"
else
    ok "stale handle refuses"
fi
grep -q 'stale edit handle' "$TMP/stale.err" \
    && ok "stale refusal explains how to refresh" \
    || no "stale refusal is not specific"
[ "$BEFORE_STALE" = "$( shasum -a 256 "$TMP/src/a.cpp" )" ] \
    && ok "stale-handle refusal leaves the file byte-identical" \
    || no "stale-handle refusal modified the file"

if "$BIN" "$TMP" --handles >"$TMP/alone" 2>"$TMP/alone.err"; then
    no "bare --handles unexpectedly succeeded"
else
    ok "bare --handles refuses"
fi
grep -q -- '--grep.*--regex' "$TMP/alone.err" \
    && ok "bare-handle refusal names the required search verb" \
    || no "bare-handle refusal does not explain the modifier"

mkdir -p "$TMP/amb"
printf 'int twin(){ return 11; }\n' >"$TMP/amb/a.cpp"
printf 'int twin(){ return 11; }\n' >"$TMP/amb/b.cpp"
"$BIN" "$TMP/amb" --grep='return 11' --handles >"$TMP/amb.out" 2>/dev/null
grep -q 'defs="2"' "$TMP/amb.out" \
    && ok "same-named definitions remain disclosed as ambiguous" \
    || no "ambiguous enclosing definition count is missing"
if grep -q ' h="sym#' "$TMP/amb.out"; then
    no "ambiguous enclosing symbol received an unsafe single handle"
else
    ok "ambiguous enclosing symbol receives no unsafe single handle"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
