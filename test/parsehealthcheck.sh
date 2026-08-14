#!/usr/bin/env bash
# parsehealthcheck.sh — PARSE HEALTH: files that ARE indexed but whose extraction the tool cannot vouch for.
#
# Why this gate exists. The skip taxonomy (test/skipreasoncheck.sh) covers files the index does not
# CONTAIN. This gate covers the quieter lie: files the index contains and reports on as if they were
# understood. Run on a corpus of 252 deliberately-invalid Python files, `--skipped` reported
# oversize="0" — "index complete" — while every file was syntactically broken and every symbol drawn
# from it was garbage. Same for a minified bundle: one 400 KB line yields plausible-looking symbols
# with no relation to authored code.
#
# The two disclosure-only classes this gate pins (BOTH files stay INDEXED — nothing is newly dropped):
#   degraded-parse    — the file's tree-sitter parse contains ERROR / MISSING nodes. err= counts them,
#                       err_ratio= is the share of the file's BYTES covered by top-most ERROR spans.
#                       Deliberately NOT called "invalid syntax": tree-sitter error recovery is a
#                       parser-state fact, not a language conformance judgment (a valid file in a
#                       dialect the vendored grammar predates reads degraded too, and that is exactly
#                       the case a reader must be told about).
#   minified-suspect  — whitespace frequency under 0.07 across the leading sample (semgrep's published
#                       threshold). ws_freq= is disclosed so the reader can second-guess the threshold.
#
# Arms:
#   (0) presence guards — the fixture's broken files really are broken, the valid ones really parse
#   (1) degraded-parse across THREE languages (C++, Python, JavaScript): each truncated file gets a row
#       carrying err= and err_ratio=
#   (2) the VALID counterpart of each broken file reports NOTHING — no row, no err
#   (3) minified-suspect: the no-whitespace bundle gets a row with ws_freq=, and its ws_freq is < 0.07
#   (4) still indexed: a degraded file and the minified file are BOTH in files= and still contribute
#       symbols — this lane discloses, it never drops
#   (5) counts join the rows — degraded_parse= / minified_suspect= equal the rows emitted
#   (6) WARM CACHE: the second run over the same tree with a cache reports the SAME health. Health that
#       evaporates on a warm run is worse than no health at all (the auto-cache is the default path).
#   (7) determinism + well-formedness
#
# Usage:  bash test/parsehealthcheck.sh      [RIPWIRE_BIN=path/to/binary]
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
echo "parsehealthcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/corpus"

# ── fixture: one VALID + one TRUNCATED-MID-FUNCTION file per language, plus a minified bundle ────────
cat > "$TMP/corpus/goodcpp.cpp" <<'EOF'
int healthyCppFn( int x )
{
    if( x > 0 )
    {
        return x + 1;
    }
    return 0;
}
EOF
cat > "$TMP/corpus/brokencpp.cpp" <<'EOF'
int truncatedCppFn( int x )
{
    if( x > 0 )
    {
        return x +
EOF
cat > "$TMP/corpus/goodpy.py" <<'EOF'
def healthy_py_fn(x):
    if x > 0:
        return x + 1
    return 0
EOF
cat > "$TMP/corpus/brokenpy.py" <<'EOF'
def truncated_py_fn(x
    if x > 0
        return x +
EOF
cat > "$TMP/corpus/goodjs.js" <<'EOF'
function healthyJsFn( x ) {
    if ( x > 0 ) {
        return x + 1;
    }
    return 0;
}
EOF
cat > "$TMP/corpus/brokenjs.js" <<'EOF'
function truncatedJsFn( x ) {
    if ( x > 0 ) {
        return x +
EOF
# a minified bundle: >=256 B, essentially no whitespace, and perfectly VALID JS (so this arm cannot
# be satisfied by the degraded-parse machinery instead)
# NB: ONE `var` declaring a comma list, the way a real minifier emits it — 40 × `var vN=N;` carries 40
# mandatory spaces and lands at ws_freq 0.092, ABOVE the threshold. That near-miss is the reason arm (0)
# asserts the whitespace count instead of trusting the generator to look minified.
{ printf 'function minifiedEntry(){var '; for i in $( seq 1 40 ); do printf 'v%d=%d,' "$i" "$i"; done; printf 'vLast=0;return v1;}'; } > "$TMP/corpus/bundle.js"

cd "$TMP"

# ── (0) presence guards ──────────────────────────────────────────────────────────────────────────────
bundleBytes="$( wc -c < "$TMP/corpus/bundle.js" | tr -d ' ' )"
[ "$bundleBytes" -ge 256 ] && ok "(0) bundle.js is $bundleBytes B (>=256, the minified-suspect floor)" \
                           || no "(0) bundle.js is only $bundleBytes B — under the disclosure floor, arm (3) would pass blind"
# NB: python3, not `tr -dc '[:space:]'` — BSD tr does not honour the class inside a complemented
# delete set and silently counts letters instead (it read 42 "whitespace" bytes in a file with none).
bundleWs="$( python3 -c 'import sys;print(sum(1 for c in open(sys.argv[1],"rb").read() if c in b" \t\r\n\f\v"))' "$TMP/corpus/bundle.js" )"
bundleFreq="$( python3 -c 'import sys;print("%.4f"%(int(sys.argv[1])/int(sys.argv[2])))' "$bundleWs" "$bundleBytes" )"
python3 -c 'import sys;sys.exit(0 if float(sys.argv[1]) < 0.07 else 1)' "$bundleFreq" \
  && ok "(0) bundle.js whitespace frequency is $bundleFreq (under the 0.07 threshold)" \
  || no "(0) bundle.js whitespace frequency is $bundleFreq — NOT under 0.07, so arm (3) cannot fire"
grep -q 'return x +$' "$TMP/corpus/brokencpp.cpp" && ok "(0) brokencpp.cpp really is truncated mid-expression" \
                      || no "(0) brokencpp.cpp is no longer truncated — arm (1) would pass by finding nothing"

# ── run ──────────────────────────────────────────────────────────────────────────────────────────────
"$BIN" corpus --skipped --no-cache > "$TMP/h.xml" 2>/dev/null

hrow(){ # hrow <path-substr>  → prints the <h .../> row, empty if absent
  python3 - "$TMP/h.xml" "$1" <<'PY'
import re,sys
x=open(sys.argv[1]).read(); p=sys.argv[2]
for m in re.finditer(r'<h\b[^>]*/>', x):
    if p in m.group(0):
        print(m.group(0)); raise SystemExit(0)
print("")
PY
}
attr(){ python3 - "$1" "$2" <<'PY'
import re,sys
a=re.search(r'\b%s="([^"]*)"'%sys.argv[2], sys.argv[1])
print(a.group(1) if a else "")
PY
}
hattr(){ python3 - "$TMP/h.xml" "$1" <<'PY'
import re,sys
x=open(sys.argv[1]).read(); m=re.search(r'<skipped\b[^>]*>',x)
a=re.search(r'\b%s="([^"]*)"'%sys.argv[2], m.group(0)) if m else None
print(a.group(1) if a else "")
PY
}

# ── (1) degraded-parse across three languages ────────────────────────────────────────────────────────
for f in brokencpp.cpp brokenpy.py brokenjs.js; do
  row="$( hrow "corpus/$f" )"
  if [ -z "$row" ]; then
    no "(1) no parse-health row for corpus/$f"
    continue
  fi
  case "$row" in *degraded-parse*) ;; *) no "(1) corpus/$f row lacks why=\"degraded-parse\": $row"; continue ;; esac
  e="$( attr "$row" err )"; er="$( attr "$row" err_ratio )"
  if [ -n "$e" ] && [ "$e" -ge 1 ] 2>/dev/null && [ -n "$er" ]; then
    ok "(1) corpus/$f degraded-parse err=$e err_ratio=$er"
  else
    no "(1) corpus/$f row missing err=/err_ratio=: $row"
  fi
done

# ── (2) the valid counterparts report nothing ────────────────────────────────────────────────────────
for f in goodcpp.cpp goodpy.py goodjs.js; do
  row="$( hrow "corpus/$f" )"
  [ -z "$row" ] && ok "(2) corpus/$f reports no parse-health finding" \
                || no "(2) corpus/$f reported a finding it should not: $row"
done

# ── (3) minified-suspect ─────────────────────────────────────────────────────────────────────────────
row="$( hrow 'corpus/bundle.js' )"
if [ -z "$row" ]; then
  no '(3) no parse-health row for corpus/bundle.js'
else
  case "$row" in *minified-suspect*) ok '(3) bundle.js carries why="minified-suspect"' ;;
                 *) no "(3) bundle.js row lacks why=\"minified-suspect\": $row" ;; esac
  wf="$( attr "$row" ws_freq )"
  if [ -n "$wf" ] && python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) < 0.07 else 1)" "$wf"; then
    ok "(3) bundle.js discloses ws_freq=$wf (< 0.07)"
  else
    no "(3) bundle.js ws_freq missing or not under the threshold: '$wf'"
  fi
fi

# ── (4) still indexed — this lane discloses, it never drops ──────────────────────────────────────────
"$BIN" corpus --no-cache > "$TMP/map.xml" 2>/dev/null
grep -q 'p="corpus/brokencpp.cpp"' "$TMP/map.xml" && ok '(4) the degraded file is still in the map' \
                                                  || no '(4) the degraded file VANISHED from the map — this lane must not drop'
grep -q 'minifiedEntry' "$TMP/map.xml" && ok '(4) the minified bundle still contributes symbols' \
                                       || no '(4) the minified bundle contributes no symbols — this lane must not drop'

# ── (5) counts join the rows ─────────────────────────────────────────────────────────────────────────
D="$( hattr degraded_parse )"; M="$( hattr minified_suspect )"
dRows="$( grep -o '<h\b[^>]*degraded-parse[^>]*/>' "$TMP/h.xml" | wc -l | tr -d ' ' )"
mRows="$( grep -o '<h\b[^>]*minified-suspect[^>]*/>' "$TMP/h.xml" | wc -l | tr -d ' ' )"
[ -n "$D" ] && [ "$D" = "$dRows" ] && ok "(5) degraded_parse=$D equals the $dRows rows emitted" \
                                   || no "(5) degraded_parse=$D but $dRows rows emitted"
[ -n "$M" ] && [ "$M" = "$mRows" ] && ok "(5) minified_suspect=$M equals the $mRows rows emitted" \
                                   || no "(5) minified_suspect=$M but $mRows rows emitted"

# ── (6) warm cache keeps the health ──────────────────────────────────────────────────────────────────
CACHE="$TMP/warm.ripwirecache"
"$BIN" corpus --skipped --cache="$CACHE" > "$TMP/warm1.xml" 2>/dev/null
"$BIN" corpus --skipped --cache="$CACHE" > "$TMP/warm2.xml" 2>/dev/null
cmp -s "$TMP/warm1.xml" "$TMP/warm2.xml" && ok '(6) cold and warm --skipped agree (health survives the cache)' \
                                          || { no '(6) warm run DISAGREES with the cold run — health does not round-trip the cache'; diff "$TMP/warm1.xml" "$TMP/warm2.xml" | head -4; }
W="$( python3 - "$TMP/warm2.xml" <<'PY'
import re,sys
x=open(sys.argv[1]).read(); m=re.search(r'<skipped\b[^>]*>',x)
a=re.search(r'\bdegraded_parse="([^"]*)"', m.group(0)) if m else None
print(a.group(1) if a else "")
PY
)"
[ -n "$W" ] && [ "$W" -ge 3 ] 2>/dev/null && ok "(6) warm run still reports degraded_parse=$W" \
                                          || no "(6) warm run reports degraded_parse='$W' (want >=3)"

# ── (7) determinism + well-formedness ────────────────────────────────────────────────────────────────
"$BIN" corpus --skipped --no-cache > "$TMP/h2.xml" 2>/dev/null
cmp -s "$TMP/h.xml" "$TMP/h2.xml" && ok '(7) two runs are byte-identical' || no '(7) output is NOT deterministic'
if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$TMP/h.xml" 2>/dev/null && ok '(7) well-formed XML' || no '(7) NOT well-formed XML'
else
  echo "  SKIP  (7) xmllint unavailable"
fi

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }
