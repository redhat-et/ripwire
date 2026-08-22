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
#   (8) BUILT-IN subtree prunes are counted too, and SEPARATELY from the user ones. Three prune paths
#       converge on `it.disable_recursion_pending()` in ingest.cpp — a --exclude match, the committed
#       denylist (ingest.h kCrawlSkipDirs), and the CMakeCache.txt build-output sentinel — but only the
#       FIRST incremented a counter. So `--skipped` on a tree with node_modules/ reported every counter
#       zero while whole subtrees had been dropped: the same "a zero that means none exists" failure the
#       arms above exist to close, one level up. pruned_dirs= is its OWN attribute, never folded into
#       excluded_dirs=, because the reader must be able to tell a policy prune (this build always does
#       this) from a prune THEY asked for (--exclude).
#   (9) BOTH header attributes arm (3) can produce — unindexed= and its unindexed_exts= cap bit — are
#       DEFINED somewhere in the tool's own output. The map legend is not that place and this arm does not
#       ask it to be: putting the clause there was tried and MEASURED, and on `src` at --max-tokens=500 the
#       map's fixed floor sits 7 bytes under its allowance (test/tokenbudgetcheck.sh arm #3), so no wording
#       fits. The --skipped legend is under no such budget and is where the definition lives; unindexed_exts=
#       had no definition anywhere, which is the half that was genuinely undefined. The arm ALSO pins the
#       negative — the map legend must stay byte-identical — so a future clause cannot land there silently.
#
# Usage:  bash test/skipreasoncheck.sh      [RIPWIRE_BIN=path/to/binary]
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
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

cd "$TMP"   # crawl arg `corpus` → root="corpus" + rows spell the bare relative path, machine-independently
# RE-PINNED 2026-08-19 (R-E CORRECTION): with the crawl arg `corpus`, p= used to repeat that prefix on
# every row; root-relative p= states it ONCE as root="corpus" and rows spell the bare relative path.
# Still machine-independent — that is why this script cds into $TMP and crawls a relative arg.

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
hasrow 'big.cpp'       oversize        && ok '(1) big.cpp     row carries why="oversize"'        || no '(1) NO why="oversize" row for corpus/big.cpp'
hasrow 'vendorgen.cpp' excluded       && ok '(1) vendorgen.cpp row carries why="excluded"'      || no '(1) NO why="excluded" row for corpus/vendorgen.cpp'
hasrow 'mod1.ml'       unsupported-ext && ok '(1) mod1.ml     row carries why="unsupported-ext"' || no '(1) NO why="unsupported-ext" row for corpus/mod1.ml'
grep -q 'p="keep.cpp"' "$TMP/sk.xml" && no '(1) keep.cpp is INDEXED — it must not appear as a skip row' \
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

# ── (8) built-in subtree prunes are counted, and counted apart from the user ones ────────────────────
# pruned/: one indexable .cpp at the top, three subtrees the CRAWL prunes by policy (node_modules and
# dist from kCrawlSkipDirs, buildout/ via the CMakeCache.txt build-output sentinel) and one the USER
# prunes (--exclude=genstuff). The two classes must land in two different counters.
mkdir -p "$TMP/pruned/node_modules/pkg" "$TMP/pruned/dist" "$TMP/pruned/buildout" "$TMP/pruned/genstuff"
printf 'int prunedKeep( void ) { return 1; }\n'  > "$TMP/pruned/keep.cpp"
printf 'int nodeThing( void ) { return 2; }\n'   > "$TMP/pruned/node_modules/pkg/m.cpp"
printf 'int distThing( void ) { return 3; }\n'   > "$TMP/pruned/dist/gen.cpp"
printf '# CMake cache stub\n'                    > "$TMP/pruned/buildout/CMakeCache.txt"
printf 'int builtThing( void ) { return 4; }\n'  > "$TMP/pruned/buildout/obj.cpp"
printf 'int genThing( void ) { return 5; }\n'    > "$TMP/pruned/genstuff/g.cpp"

# (8a) presence guard — the fixture really holds a file under each pruned subtree
[ -f "$TMP/pruned/node_modules/pkg/m.cpp" ] && [ -f "$TMP/pruned/dist/gen.cpp" ] && [ -f "$TMP/pruned/buildout/obj.cpp" ] \
    && ok "(8) fixture has a source file under each of the 3 built-in-pruned subtrees" \
    || no "(8) fixture is missing a pruned-subtree source file — the arms below would pass by finding nothing"

"$BIN" pruned --skipped --no-cache > "$TMP/prune_plain.xml" 2>/dev/null
PR_PLAIN="$( attr "$TMP/prune_plain.xml" pruned_dirs )"
EX_PLAIN="$( attr "$TMP/prune_plain.xml" excluded_dirs )"
echo "    (8) no --exclude: pruned_dirs=\"$PR_PLAIN\" excluded_dirs=\"$EX_PLAIN\""
if [ -n "$PR_PLAIN" ] && [ "$PR_PLAIN" -ge 3 ] 2>/dev/null; then
  ok "(8) built-in prunes are COUNTED — pruned_dirs=$PR_PLAIN (node_modules, dist, the CMakeCache sentinel)"
else
  no "(8) pruned_dirs=\"${PR_PLAIN:-absent}\" — built-in subtree prunes are invisible (want >= 3)"
fi
[ "$EX_PLAIN" = "0" ] && ok "(8) excluded_dirs=0 with no --exclude — a policy prune is never miscounted as a user one" \
                      || no "(8) excluded_dirs=\"$EX_PLAIN\" with no --exclude given — want 0"

"$BIN" pruned --skipped --exclude=genstuff --no-cache > "$TMP/prune_exc.xml" 2>/dev/null
PR_EXC="$( attr "$TMP/prune_exc.xml" pruned_dirs )"
EX_EXC="$( attr "$TMP/prune_exc.xml" excluded_dirs )"
echo "    (8) with --exclude=genstuff: pruned_dirs=\"$PR_EXC\" excluded_dirs=\"$EX_EXC\""
[ "$EX_EXC" = "1" ] && ok "(8) the USER prune still lands in excluded_dirs=1, separately" \
                    || no "(8) excluded_dirs=\"$EX_EXC\" under --exclude=genstuff — want 1"
[ -n "$PR_EXC" ] && [ "$PR_EXC" = "$PR_PLAIN" ] && ok "(8) pruned_dirs is unchanged by --exclude ($PR_EXC) — the two counters do not bleed" \
                    || no "(8) pruned_dirs moved from \"$PR_PLAIN\" to \"$PR_EXC\" when --exclude was added — the classes are folded together"

LEG_SK="$( python3 - "$TMP/prune_plain.xml" <<'PY'
import re,sys
x=open(sys.argv[1]).read(); m=re.match(r'\A(?:\s*<ctx>)?(?:\s*<!--.*?-->)+', x, re.S)
print(m.group(0) if m else "")
PY
)"
case "$LEG_SK" in
  *pruned_dirs=*) ok '(8) the skipped legend DEFINES pruned_dirs=' ;;
  *)              no '(8) the skipped legend never spells pruned_dirs= — a counter no reader can read' ;;
esac
# The UNKNOWN language must belong to the pruned_dirs CLAUSE, not merely be present somewhere in a legend
# that already says it about excluded_dirs= — otherwise this arm passes on the unfixed binary.
if printf '%s' "$LEG_SK" | python3 -c '
import re,sys
leg = sys.stdin.read()
m = re.search( r"pruned_dirs=", leg )
sys.exit( 0 if m and "UNKNOWN" in leg[ m.start() : m.start() + 320 ] else 1 )
'; then
  ok '(8) the pruned_dirs clause itself carries the "contents UNKNOWN, not zero" language'
else
  no '(8) the pruned_dirs clause does not say the contents are UNKNOWN — a pruned subtree is not an empty one'
fi

# ── (9) unindexed= and unindexed_exts= are both DEFINED, and the map floor stays where it was ────────
# The --skipped legend is the definition site (see the arm note in the header for the 7-byte measurement
# that keeps it out of the map legend). LEG_SK is that legend, already extracted for arm (8).
case "$LEG_SK" in
  *unindexed=*) ok '(9) the skipped legend defines unindexed=' ;;
  *)            no '(9) unindexed= is emitted (arm 3) and defined nowhere in the output' ;;
esac
case "$LEG_SK" in
  *unindexed_exts=*) ok '(9) the skipped legend defines unindexed_exts= (the TOP-6 cap bit)' ;;
  *)                 no '(9) unindexed_exts= is undefined everywhere — a cap disclosure no reader can read' ;;
esac
# The negative half: the MAP legend must not grow. Its leading comments are the v1 legend, any conditional
# clause, then the stats header — the stats header is DATA (it literally contains unindexed="ml:3"), so it
# is dropped before the check, or this arm could never see a clause land.
maplegOf(){ python3 - "$1" <<'PY'
import re,sys
x = open( sys.argv[1] ).read()
m = re.match( r'\A(?:\s*<!--.*?-->)+', x, re.S )
lead = m.group( 0 ) if m else ""
print( "".join( c for c in re.findall( r'<!--.*?-->', lead, re.S ) if not c.startswith( "<!-- files=" ) ) )
PY
}
MAPLEG="$( maplegOf "$TMP/map.xml" )"
case "$MAPLEG" in
  *unindexed*) no '(9) a clause defining unindexed= landed in the MAP legend — re-run tokenbudgetcheck arm #3 before keeping it (the floor had 7 B of headroom)' ;;
  *)           ok '(9) the map legend is unchanged — the --max-tokens floor keeps its headroom' ;;
esac

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }
