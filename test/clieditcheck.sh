#!/usr/bin/env bash
# clieditcheck.sh — the preferred CLI exposes the same transaction-safe symbol edit engine as MCP.
# Every mutation is confined to a scratch corpus; refusals are proven by whole-corpus hashes.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

mkdir -p "$TMP/template"
cat >"$TMP/template/a.cpp" <<'CPP'
int alpha( int x )
{
    return x + 1;
}

int beta( int x )
{
    return alpha( x ) * 2;
}
CPP
hashcorpus(){ ( cd "$1" && find . -type f -print | LC_ALL=C sort | xargs shasum -a 256 ) | shasum -a 256; }

echo "clieditcheck: BIN=$BIN"
W="$TMP/replace"; cp -R "$TMP/template" "$W"
cat >"$TMP/replacement" <<'CPP'
int alpha( int x )
{
    return x + 7;
}
CPP
if "$BIN" "$W" --replace-symbol-body=alpha --edit-payload="$TMP/replacement" >"$TMP/out" 2>"$TMP/err"; then
    ok "replace-symbol-body succeeds through the CLI"
else
    no "replace-symbol-body failed: $( head -1 "$TMP/err" )"
fi
grep -q '"applied":"replace_symbol_body"' "$TMP/out" \
    && ok "success receipt identifies the shared edit operation" \
    || no "success receipt does not identify replace_symbol_body"
grep -q 'return x + 7;' "$W/a.cpp" \
    && ok "replacement bytes landed at alpha's definition" \
    || no "replacement bytes did not land"
grep -q 'return alpha( x ) \* 2;' "$W/a.cpp" \
    && ok "bytes outside alpha's span were preserved" \
    || no "replacement damaged beta"

W2="$TMP/stdin"; cp -R "$TMP/template" "$W2"
printf '// inserted marker' | "$BIN" "$W2" --insert-before-symbol=beta --edit-payload=- >"$TMP/stdin.out" 2>"$TMP/stdin.err"
python3 - "$W2/a.cpp" <<'PY' >"$TMP/stdin.check"
import sys
s = open(sys.argv[1], encoding="utf-8").read()
print("OK" if "// inserted marker\nint beta" in s else "BAD")
PY
[ "$( cat "$TMP/stdin.check" )" = OK ] \
    && ok "stdin payload is inserted with the documented newline seam" \
    || no "stdin payload/newline seam is wrong"

W2b="$TMP/after"; cp -R "$TMP/template" "$W2b"
printf '// tail marker' | "$BIN" "$W2b" --insert-after-symbol=alpha --edit-payload=- >"$TMP/after.out" 2>"$TMP/after.err"
python3 - "$W2b/a.cpp" <<'PY' >"$TMP/after.check"
import sys
s = open(sys.argv[1], encoding="utf-8").read()
print("OK" if "\n// tail marker" in s and s.index("// tail marker") < s.index("int beta") else "BAD")
PY
[ "$( cat "$TMP/after.check" )" = OK ] \
    && ok "insert-after lands between alpha and beta with the newline seam" \
    || no "insert-after placement/seam is wrong"

W3="$TMP/amb"; mkdir -p "$W3"
printf 'int twin(){ return 1; }\n' >"$W3/a.cpp"
printf 'int twin(){ return 2; }\n' >"$W3/b.cpp"
printf 'int twin(){ return 3; }\n' >"$TMP/twin"
BEFORE="$( hashcorpus "$W3" )"
if "$BIN" "$W3" --replace-symbol-body=twin --edit-payload="$TMP/twin" >"$TMP/amb.out" 2>"$TMP/amb.err"; then
    no "ambiguous edit unexpectedly succeeded"
else
    ok "ambiguous edit refuses"
fi
grep -q 'ambiguous' "$TMP/amb.err" \
    && ok "ambiguity refusal explains the problem" \
    || no "ambiguity refusal does not explain the problem"
[ "$BEFORE" = "$( hashcorpus "$W3" )" ] \
    && ok "ambiguity refusal leaves the corpus byte-identical" \
    || no "ambiguity refusal modified the corpus"
if "$BIN" "$W3" --replace-symbol-body=twin --edit-target-file=b.cpp --edit-payload="$TMP/twin" >"$TMP/amb2.out" 2>"$TMP/amb2.err"; then
    ok "--edit-target-file resolves the same-named ambiguity"
else
    no "--edit-target-file disambiguation failed: $( head -1 "$TMP/amb2.err" )"
fi
grep -q 'return 3;' "$W3/b.cpp" && grep -q 'return 1;' "$W3/a.cpp" \
    && ok "disambiguated edit lands in b.cpp only" \
    || no "disambiguated edit touched the wrong file"

W4="$TMP/missing"; cp -R "$TMP/template" "$W4"; BEFORE="$( hashcorpus "$W4" )"
if "$BIN" "$W4" --replace-symbol-body=alpha >"$TMP/missing.out" 2>"$TMP/missing.err"; then
    no "edit without --edit-payload unexpectedly succeeded"
else
    ok "edit without --edit-payload refuses"
fi
grep -q -- '--edit-payload' "$TMP/missing.err" \
    && ok "missing-payload refusal names the required flag" \
    || no "missing-payload refusal does not name --edit-payload"
[ "$BEFORE" = "$( hashcorpus "$W4" )" ] \
    && ok "missing-payload refusal leaves the corpus byte-identical" \
    || no "missing-payload refusal modified the corpus"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
