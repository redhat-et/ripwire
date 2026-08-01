#!/usr/bin/env bash
# columnarcheck.sh — PHASE 4 gate (lever 1): the opt-in columnar --format for the
# FLAT list verbs (--callers/--callees/--uses/--impact).
#
# The flat list verbs pay ~69% structural XML overhead: per-row `<s t= n= p= />` markup + the same file PATH
# repeated on every row. --format=columnar re-encodes the SAME data as a <paths> table (int refs) + parallel
# name/line/kind arrays — measured 31-42% real-token cut. GUARD (from the literature): columnar hits 0% on
# NESTED data, so it is applied ONLY to the tabular list verbs, NEVER the nested map. Default --format=xml is
# byte-identical (G4 + every existing consumer intact).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/columnarcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "columnarcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# a verb with several rows on this repo (many callers/impact/uses).
VERB_CALLERS="--callers=escapeXml"
VERB_IMPACT="--impact=escapeXml"
VERB_USES="--uses=escapeXml"

# ── #1: default (no --format) is BYTE-IDENTICAL to explicit --format=xml, for every flat verb ──────────
xid=1
for V in "$VERB_CALLERS" "$VERB_IMPACT" "$VERB_USES"; do
    "$BIN" src $V --no-cache >"$TMP/def" 2>/dev/null
    "$BIN" src $V --format=xml --no-cache >"$TMP/xml" 2>/dev/null
    diff -q "$TMP/def" "$TMP/xml" >/dev/null || { echo "    differs: $V"; xid=0; }
done
[ "$xid" = 1 ] && ok "default == --format=xml byte-identical for --callers/--impact/--uses (golden-neutral)" \
    || no "default and --format=xml differ for some flat verb"

# ── #2: columnar is MATERIALLY SMALLER (bytes) than xml on a multi-row verb ────────────────────────────
XB=$( "$BIN" src "$VERB_USES" --no-cache 2>/dev/null | wc -c | tr -d ' ' )
CB=$( "$BIN" src "$VERB_USES" --format=columnar --no-cache 2>/dev/null | wc -c | tr -d ' ' )
{ [ "$XB" -gt 0 ] && [ "$CB" -lt "$XB" ] && [ $(( (XB - CB) * 100 / XB )) -ge 20 ]; } \
    && ok "columnar --uses materially smaller: ${XB}B -> ${CB}B ($(( (XB-CB)*100/XB ))% off, >=20%)" \
    || no "columnar --uses not >=20% smaller (${XB}B -> ${CB}B)"

# ── #3: ROUND-TRIP — columnar carries the SAME symbol set (same names, same lines) as xml, just re-encoded.
#    Extract the sorted (name,line) multiset from each form and require them equal. ────────────────────────
# xml form: <s ... n="NAME" p="path:LINE"/>  →  NAME<TAB>LINE
xml_set(){ "$BIN" src "$1" --format=xml --no-cache 2>/dev/null \
    | grep -oE '<s [^>]*n="[^"]*" p="[^"]*:[0-9]+"' \
    | sed -E 's/.*n="([^"]*)" p="[^"]*:([0-9]+)"/\1\t\2/' | sort; }
# columnar form: zip the <name> and <line> arrays.
col_set(){ "$BIN" src "$1" --format=columnar --no-cache 2>/dev/null > "$TMP/col.xml"
    python3 - "$TMP/col.xml" <<'PY'
import sys, re
t = open(sys.argv[1], encoding='utf-8', errors='replace').read()
def arr(tag):
    m = re.search(r'<%s>(.*?)</%s>' % (tag, tag), t, re.S)
    return m.group(1).split(',') if m and m.group(1) != '' else []
names = arr('name'); lines = arr('line')
rows = sorted('%s\t%s' % (n, l) for n, l in zip(names, lines))
print('\n'.join(rows))
PY
}
rt=1
for V in "$VERB_CALLERS" "$VERB_IMPACT"; do
    xml_set "$V" >"$TMP/xset" ; col_set "$V" >"$TMP/cset"
    diff -q "$TMP/xset" "$TMP/cset" >/dev/null || { echo "    round-trip mismatch: $V"; diff "$TMP/xset" "$TMP/cset" | head; rt=0; }
done
[ "$rt" = 1 ] && ok "columnar round-trips the SAME (name,line) symbol set as xml (--callers/--impact)" \
    || no "columnar dropped/added/reordered symbols vs xml"

# ── #4: DETERMINISM — a columnar run is byte-identical twice ────────────────────────────────────────────
"$BIN" src "$VERB_USES" --format=columnar --no-cache >"$TMP/c1" 2>/dev/null
"$BIN" src "$VERB_USES" --format=columnar --no-cache >"$TMP/c2" 2>/dev/null
diff -q "$TMP/c1" "$TMP/c2" >/dev/null \
    && ok "columnar deterministic: two runs byte-identical" \
    || no "columnar NON-deterministic"

# ── #5: the NESTED MAP is never re-encoded by --format=columnar (0% acc on nested data) ─────────────────
# STRENGTHENED this arm: the map used to be byte-identical under --format=columnar,
# i.e. the flag was accepted and silently ignored — indistinguishable from a typo, and the exact class §P15.3
# declared extinct. The map is still never re-encoded; the combination now REFUSES (exit 1) instead of
# pretending to have applied, which is the stronger form of the same guarantee.
"$BIN" src --format=columnar --no-cache >"$TMP/m_col" 2>"$TMP/m_col_err"; rc_col=$?
{ [ "$rc_col" -eq 1 ] && [ ! -s "$TMP/m_col" ] && grep -q 'format=columnar' "$TMP/m_col_err"; } \
    && ok "the default map REFUSES --format=columnar (exit 1, names the flag; map never re-encoded)" \
    || no "the default map under --format=columnar: exit=$rc_col, stdout=$( wc -c <"$TMP/m_col" )B — expected a loud refusal"

# ── #6: columnar output is well-formed XML (still G4-clean; a <paths> table + <cols> arrays) ────────────
if command -v xmllint >/dev/null 2>&1; then
    lint=1
    for V in "$VERB_CALLERS" "$VERB_IMPACT" "$VERB_USES"; do
        "$BIN" src $V --format=columnar --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null || { echo "    malformed: $V"; lint=0; }
    done
    [ "$lint" = 1 ] && ok "columnar output well-formed XML for all flat verbs" || no "columnar output malformed for some verb"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── #7: (optional) real-token savings report — informational (tiktoken not a build dep) ─────────────────
if python3 -c 'import tiktoken' >/dev/null 2>&1; then
    python3 - "$BIN" <<'PY'
import sys, subprocess, tiktoken
b=sys.argv[1]; enc=tiktoken.get_encoding("o200k_base")
for v in ["--callers=escapeXml","--impact=escapeXml","--uses=escapeXml"]:
    x=subprocess.run([b,"src",v,"--no-cache"],capture_output=True).stdout.decode("utf-8","replace")
    c=subprocess.run([b,"src",v,"--format=columnar","--no-cache"],capture_output=True).stdout.decode("utf-8","replace")
    xt,ct=len(enc.encode(x)),len(enc.encode(c))
    print(f"  INFO  {v}: xml={xt}tok -> columnar={ct}tok  ({(xt-ct)*100//xt}% off)")
PY
else
    printf '  SKIP  tiktoken savings report (tiktoken not installed)\n'
fi

# §A10.10 + V2-4: the --help wording claimed a flat "~50%+ fewer tokens", but the measured savings across
# the four flat verbs range 15.6%-60.9% (--uses amortizes the least), and small results are strictly
# LARGER (the paths/cols scaffold has a fixed cost: --callers=parseArgs measured +119.6%). The corrected
# text names the range, scopes it to multi-row results, and discloses the small-result floor — both
# halves asserted so neither can silently regress to a one-sided claim.
HELP="$( "$BIN" --help 2>&1 )"
printf '%s' "$HELP" | grep -q '15-60% fewer tokens on multi-row results' \
    && ok "--help states the measured 15-60% range for --format=columnar, not a flat 50%+ floor (§A10.10)" \
    || no "--help still claims a flat ~50%+ savings figure for --format=columnar"
printf '%s' "$HELP" | grep -q 'can be LARGER' \
    && ok "--help disclose the small-result floor (V2-4: scaffold cost can exceed the savings)" \
    || no "--help lacks the V2-4 small-result caveat (can be LARGER)"
printf '%s' "$HELP" | grep -q '50%+ fewer tokens' \
    && no "--help still contains the stale flat ~50%+ columnar claim" \
    || ok "--help no longer contains the stale flat ~50%+ columnar claim"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
