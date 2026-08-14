#!/usr/bin/env bash
# skipreasoncheck.sh — the skip TAXONOMY: `--skipped` names WHY each file is absent, and the default
# map header names the languages the index could not see at all.
#
# Why this gate exists. `--skipped` itemized exactly ONE drop reason — oversize. Every other way a file
# leaves the corpus was invisible:
#   * a file dropped by --exclude was simply gone (no row, no count);
#   * a file whose EXTENSION has no grammar was gone the same way — and that is the load-bearing one,
#     because it is how a whole LANGUAGE disappears. On facebook/infer (11 923 files, ~60% OCaml) the
#     default map header gave zero indication that the repo's primary language contributed nothing;
#     the top-ranked symbols were meaningless test fixtures. `oversize="0"` read as "index complete".
# That is the honesty contract's own failure mode: a zero that means "none exists" rather than "none
# found". This gate pins the taxonomy — one why= per drop class — and the header's unindexed= roll-up.
#
# Arms:
#   (0) presence guards — the fixture really contains each drop class the arms below assert
#   (1) why= vocabulary — oversize / excluded / unsupported-ext each appear on the right path
#   (2) reconciliation — indexed= + oversize= + excluded= = the candidate population the crawl
#       ENUMERATED, and unsupported_ext= counts the source/text-looking files outside it
#   (3) unindexed= header — a tree whose bulk is .ml says so on the DEFAULT map, with a per-ext count
#   (4) asset denylist — .png/.zip do NOT enter unindexed= (disclosed rule: binary/asset extensions)
#   (5) zero means none found — a corpus with nothing dropped emits no unindexed= attribute at all
#       (purely additive, G5/G4: the default map over a fully-indexable tree stays byte-identical)
#   (6) determinism — two --skipped runs, byte-identical
#   (7) well-formedness (G4) — --skipped pipes clean through xmllint when xmllint is available
#
# Usage:  bash test/skipreasoncheck.sh      [RIPWIRE_BIN=path/to/binary]
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "skipreasoncheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── fixture ──────────────────────────────────────────────────────────────────────────────────────────
# corpus/: one indexable .cpp, one OVERSIZE .cpp (>1K), one EXCLUDED .cpp (file-level --exclude match),
#          three .ml (no grammar — the "whole language is invisible" case), one .mli, one .png asset.
mkdir -p "$TMP/corpus"
printf 'int keepThisSymbol( void ) { return 1; }\n' > "$TMP/corpus/keep.cpp"
{ printf '// filler\n'; for i in $( seq 1 80 ); do printf 'int filler_%d( void ) { return %d; }\n' "$i" "$i"; done; } > "$TMP/corpus/big.cpp"
printf 'int generatedThing( void ) { return 2; }\n' > "$TMP/corpus/vendorgen.cpp"
for i in 1 2 3; do printf 'let ocamlFn%d x = x + %d\n' "$i" "$i" > "$TMP/corpus/mod$i.ml"; done
printf 'val ocamlSig : int -> int\n' > "$TMP/corpus/mod1.mli"
printf '\211PNG\r\n\032\n binary-ish payload\n' > "$TMP/corpus/logo.png"

cd "$TMP"   # crawl arg `corpus` → rows spell p="corpus/..." machine-independently

# ── (0) presence guards ──────────────────────────────────────────────────────────────────────────────
bigBytes="$( wc -c < "$TMP/corpus/big.cpp" | tr -d ' ' )"
[ "$bigBytes" -gt 1024 ] && ok "(0) big.cpp exceeds the 1K ceiling ($bigBytes B)" \
                         || no "(0) big.cpp does NOT exceed 1024 B ($bigBytes B) — fixture broken"
[ "$( ls "$TMP"/corpus/*.ml | wc -l | tr -d ' ' )" -eq 3 ] && ok "(0) fixture has 3 .ml files" \
                         || no "(0) fixture does not have 3 .ml files — arm (3) would pass by finding nothing"
[ -f "$TMP/corpus/logo.png" ] && ok "(0) fixture has an asset file (logo.png)" \
                         || no "(0) fixture lost logo.png — arm (4) would pass by finding nothing"

# ── (1) why= vocabulary ──────────────────────────────────────────────────────────────────────────────
"$BIN" corpus --skipped --max-file-size=1K --exclude=vendorgen --no-cache > "$TMP/sk.xml" 2>/dev/null

hasrow(){ # hasrow <path-substr> <why>
  python3 - "$TMP/sk.xml" "$1" "$2" <<'PY'
import re,sys
x=open(sys.argv[1]).read(); p=sys.argv[2]; w=sys.argv[3]
for m in re.finditer(r'<f\b[^>]*/>', x):
    r=m.group(0)
    if p in r and ('why="%s"'%w) in r:
        sys.exit(0)
sys.exit(1)
PY
}
hasrow 'corpus/big.cpp'      oversize        && ok '(1) big.cpp     row carries why="oversize"'        || no '(1) NO why="oversize" row for corpus/big.cpp'
hasrow 'corpus/vendorgen.cpp' excluded       && ok '(1) vendorgen.cpp row carries why="excluded"'      || no '(1) NO why="excluded" row for corpus/vendorgen.cpp'
hasrow 'corpus/mod1.ml'      unsupported-ext && ok '(1) mod1.ml     row carries why="unsupported-ext"' || no '(1) NO why="unsupported-ext" row for corpus/mod1.ml'
grep -q 'p="corpus/keep.cpp"' "$TMP/sk.xml" && no '(1) keep.cpp is INDEXED — it must not appear as a skip row' \
                                            || ok '(1) the indexed file (keep.cpp) has no skip row'

# ── (2) reconciliation ───────────────────────────────────────────────────────────────────────────────
attr(){ python3 - "$1" "$2" <<'PY'
import re,sys
x=open(sys.argv[1]).read(); m=re.search(r'<skipped\b[^>]*>',x)
if not m: print(""); raise SystemExit(0)
a=re.search(r'\b%s="([^"]*)"'%sys.argv[2], m.group(0))
print(a.group(1) if a else "")
PY
}
IDX="$( attr "$TMP/sk.xml" indexed )"
OVR="$( attr "$TMP/sk.xml" oversize )"
EXC="$( attr "$TMP/sk.xml" excluded )"
UNS="$( attr "$TMP/sk.xml" unsupported_ext )"
echo "    indexed=$IDX oversize=$OVR excluded=$EXC unsupported_ext=$UNS"
if [ -n "$IDX" ] && [ -n "$OVR" ] && [ -n "$EXC" ] && [ "$(( IDX + OVR + EXC ))" -eq 3 ]; then
  ok "(2) indexed+oversize+excluded = 3 (the enumerated .cpp candidate population)"
else
  no "(2) reconciliation broken: indexed=$IDX oversize=$OVR excluded=$EXC (want sum 3)"
fi
[ "$UNS" = "4" ] && ok "(2) unsupported_ext=4 (3 .ml + 1 .mli; the .png asset is excluded by the disclosed rule)" \
                 || no "(2) unsupported_ext=$UNS, want 4"

# ── (3) unindexed= on the DEFAULT map ────────────────────────────────────────────────────────────────
"$BIN" corpus --no-cache > "$TMP/map.xml" 2>/dev/null
UNIDX="$( python3 - "$TMP/map.xml" <<'PY'
import re,sys
x=open(sys.argv[1]).read(); m=re.search(r'unindexed="([^"]*)"',x)
print(m.group(1) if m else "")
PY
)"
echo "    unindexed=\"$UNIDX\""
case "$UNIDX" in
  *ml:3*) ok '(3) default map header discloses unindexed="…ml:3…" — the invisible language says so' ;;
  *)      no "(3) default map header has no ml:3 in unindexed= (got \"$UNIDX\")" ;;
esac

# ── (4) asset denylist ───────────────────────────────────────────────────────────────────────────────
case "$UNIDX" in
  *png*) no '(4) .png entered unindexed= — assets must be excluded by the disclosed rule' ;;
  *)     ok '(4) .png is NOT counted in unindexed= (asset extension)' ;;
esac

# ── (5) zero means none found: a fully-indexable tree emits no unindexed= at all ─────────────────────
mkdir -p "$TMP/clean"
printf 'int cleanOne( void ) { return 1; }\n' > "$TMP/clean/a.cpp"
printf 'def clean_two():\n    return 2\n'     > "$TMP/clean/b.py"
"$BIN" clean --no-cache > "$TMP/clean.xml" 2>/dev/null
grep -q 'unindexed=' "$TMP/clean.xml" && no '(5) unindexed= emitted on a fully-indexable tree — not additive' \
                                      || ok '(5) no unindexed= attribute when nothing is unindexed (byte-identical default)'

# ── (6) determinism ──────────────────────────────────────────────────────────────────────────────────
"$BIN" corpus --skipped --max-file-size=1K --exclude=vendorgen --no-cache > "$TMP/sk2.xml" 2>/dev/null
cmp -s "$TMP/sk.xml" "$TMP/sk2.xml" && ok '(6) two --skipped runs are byte-identical' \
                                    || no '(6) --skipped output is NOT deterministic'

# ── (7) well-formedness ──────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$TMP/sk.xml" 2>/dev/null && ok '(7) --skipped is well-formed XML' \
                                            || no '(7) --skipped is NOT well-formed XML'
  xmllint --noout "$TMP/map.xml" 2>/dev/null && ok '(7) the map carrying unindexed= is well-formed XML' \
                                             || no '(7) the map carrying unindexed= is NOT well-formed XML'
else
  echo "  SKIP  (7) xmllint unavailable"
fi

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }
