#!/usr/bin/env bash
# legobundlecheck.sh — §P3: the bundle's <lego> block must carry the SAME identity as the standalone
# --lego verb, and must be SCOPED to the task it was asked about.
#
#   test/legobundlecheck.sh                         # uses build/ripwire on this repo + test/legofix
#   RIPWIRE_BIN=asan/ripwire test/legobundlecheck.sh
#
# Two defects, one block:
#
#   1) IDENTITY LOSS. `--lego=Shape` prints p= on <iface> and every <impl>; the same rows embedded in
#      `--for`'s bundle printed n= alone. The repo has two genuinely different `Circle`s (one in
#      test/archmetricsfix/src/app/app.cpp, one in test/legofix/shapes.h) — with p= dropped they render
#      as a DUPLICATED ROW and the reader cannot tell them apart. The bundle form of a verb must never
#      carry less identity than its standalone form.
#
#   2) NO QUERY SCOPE. The block was ranked but never FILTERED: `--for="cache invalidation"` returned
#      Shape, Animal, IGreeter, BitfieldCase, Wolf, Base, Draw, Outer, Nested, Vehicle — ten of ten from
#      unrelated test/*fix/ fixtures. The fix keeps an interface only when it, or one of its
#      implementors, intersects the bundle's own resolved surface (the top-N ranked symbols and their
#      files); when nothing intersects, NO <lego> block is emitted at all. Absence is the honest shape
#      here — there is nothing to disclose, and ten irrelevant interfaces are worse than none.
#
# Assertions:
#   1) scope (the RED anchor): `--for="cache invalidation"` on this repo emits no fixture interface —
#      pre-change it emitted 10 ifaces / 14 impls including Shape, Animal, IGreeter.
#   2) scope, generally: in ANY bundle, every <iface>/<impl> p= must be a file the SAME bundle ranked
#      (a <f p=> in its <sigs>), so a reader can always tie a lego row back to the task's surface.
#   3) identity: every <iface>/<impl> row emitted in a bundle carries p=.
#   4) a task that genuinely resolves onto an interface still GETS it — `--for` naming Shape/Circle/
#      Square keeps <iface n="Shape">, and its two same-named Circle impls are distinguishable by p=.
#      (Positive case is repo-real: the filter must pass a hit through a 700-file corpus, not just a
#      fixture-sized one.)
#   5) the STANDALONE verb's p= identity is untouched by the §P3 bundle-scoping fix: --lego=Shape on
#      test/legofix carries the same iface/impl/method identity as before, just root-relative p= (RE-
#      PINNED "test/legofix/shapes.h" → "shapes.h" ×3, R-E 2026-08-17 harvest: root-relative paths for
#      ALL verbs — --lego threads the same rootPrefix as every other verb this lane touched, and a
#      single-root run root-relativizes regardless of whether the root arg was relative or absolute).
#      This one embedded golden is deliberate — the standalone form is the REFERENCE the bundle is now
#      required to match, so a change to it beyond the expected root-relative reshaping is exactly what
#      must be noticed.
#   6) determinism (twice → byte-identical) + well-formed XML.
#   7) mutation-check: an assertion known to be false must FAIL (the gate discriminates).
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "legobundlecheck: BIN=$BIN"

OFFTASK="cache invalidation"
ONTASK="Circle Square shape area implementors"

"$BIN" . --no-cache --for="$OFFTASK" >"$TMP/off.xml"  2>/dev/null
"$BIN" . --no-cache --for="$ONTASK"  >"$TMP/on.xml"   2>/dev/null
"$BIN" . --no-cache --for="$ONTASK"  >"$TMP/on2.xml"  2>/dev/null

for f in off on; do
    [ -s "$TMP/$f.xml" ] || no "bundle $f.xml is empty — the rest of this gate is meaningless"
done

# the <lego>…</lego> block of a bundle (empty string when the block is absent, which is a legal answer)
legoblock(){ grep -o '<lego>.*</lego>' "$1" || true; }

OFFLEGO="$( legoblock "$TMP/off.xml" )"
ONLEGO="$( legoblock "$TMP/on.xml" )"

# ── 1) scope: an off-task query must not surface unrelated fixture interfaces ─────────────────────────
# Pre-change these five were all present for "cache invalidation"; the honest post-change answer for this
# query is NO <lego> block at all (nothing in the repo's interface set touches the task's surface).
BADIFACE=0
for i in Shape Animal IGreeter Wolf Vehicle BitfieldCase Base Draw Outer Nested; do
    printf '%s' "$OFFLEGO" | grep -q "<iface n=\"$i\"" && { BADIFACE=1; echo "      off-task lego row: <iface n=\"$i\">"; }
done
[ "$BADIFACE" = 0 ] \
    && ok "--for=\"$OFFTASK\": no unrelated fixture interface in <lego> ($( [ -z "$OFFLEGO" ] && echo "block absent" || echo "block present but scoped" ))" \
    || no "--for=\"$OFFTASK\": <lego> still lists fixture interfaces unrelated to the task (§P3 filter missing)"

# ── 2) scope, generally: every lego p= is a file the same bundle ranked ───────────────────────────────
scopecheck(){
    python3 - "$1" "$2" <<'PY'
import re, sys
xml   = open(sys.argv[1]).read()
label = sys.argv[2]
lego  = re.search(r'<lego>.*?</lego>', xml, re.S)
if not lego:
    print("ABSENT no <lego> block (the honest empty-surface shape)")
    sys.exit(0)
sigs   = re.search(r'<sigs.*?</sigs>', xml, re.S)
ranked = set( re.findall(r'<f p="([^"]+)"', sigs.group(0) if sigs else '') )
rows   = re.findall(r'<(?:iface|impl)\b[^>]*>', lego.group(0))
if not rows:
    print("FAIL <lego> present but has no iface/impl rows")
    sys.exit(1)
missingPath = [ r for r in rows if ' p="' not in r ]
if missingPath:
    print("FAIL %d of %d rows carry no p= (e.g. %s)" % ( len(missingPath), len(rows), missingPath[0] ))
    sys.exit(1)
offSurface = sorted( { p for r in rows for p in re.findall(r' p="([^"]+)"', r) } - ranked )
if offSurface:
    print("FAIL %d lego path(s) outside the bundle's ranked files: %s" % ( len(offSurface), offSurface[:4] ))
    sys.exit(1)
print("OK %d rows, all p= within the %d ranked files" % ( len(rows), len(ranked) ))
PY
}
for v in off on; do
    OUT="$( scopecheck "$TMP/$v.xml" "$v" )"
    case "$OUT" in
        OK*|ABSENT*) ok "--for ($v-task) lego scope+identity: $OUT" ;;
        *)         no "--for ($v-task) lego scope+identity: $OUT" ;;
    esac
done

# ── 3) identity: p= on every emitted row (asserted where rows actually exist) ─────────────────────────
[ -n "$ONLEGO" ] \
    && ok "--for=\"$ONTASK\": <lego> block present (the positive case has rows to check)" \
    || no "--for=\"$ONTASK\": <lego> block absent — the filter dropped a genuinely on-task interface"
printf '%s' "$ONLEGO" | grep -Eq '<iface n="[^"]*" p="[^"]*"' \
    && ok "bundle <iface> carries p= (identity parity with --lego)" \
    || no "bundle <iface> has no p= — the bundle carries less identity than the standalone verb (§P3)"
printf '%s' "$ONLEGO" | grep -Eq '<impl n="[^"]*" p="[^"]*"/>' \
    && ok "bundle <impl> carries p= (identity parity with --lego)" \
    || no "bundle <impl> has no p= — the bundle carries less identity than the standalone verb (§P3)"

# ── 4) the on-task interface survives, and its two same-named impls are distinguishable ──────────────
printf '%s' "$ONLEGO" | grep -q '<iface n="Shape"' \
    && ok "--for=\"$ONTASK\": Shape kept (the filter passes a genuine hit through)" \
    || no "--for=\"$ONTASK\": Shape dropped — the filter is too aggressive"
NCIRCLE="$( printf '%s' "$ONLEGO" | grep -o '<impl n="Circle" p="[^"]*"' | sort -u | wc -l | tr -d ' ' )"
NCIRCLEROWS="$( printf '%s' "$ONLEGO" | grep -o '<impl n="Circle"' | wc -l | tr -d ' ' )"
if [ "$NCIRCLEROWS" -gt 1 ]; then
    [ "$NCIRCLE" = "$NCIRCLEROWS" ] \
        && ok "the $NCIRCLEROWS Circle rows are distinguishable by p= (no duplicated-looking row)" \
        || no "$NCIRCLEROWS Circle rows collapse to $NCIRCLE distinct p= — identity still lost (§P3)"
else
    ok "only $NCIRCLEROWS Circle row in this bundle (nothing to disambiguate)"
fi

# ── 5) the STANDALONE verb is byte-identical to the pre-change (post-root-relative) reference ──────────
# RE-PINNED 2026-08-19 (R-E CORRECTION): the reference gained root="test/legofix" on <ctx>. The 2026-08-17
# landing made packLego's p= root-relative and disclosed the root NOWHERE, so this document served relative
# paths against a root it never named — the one thing --lego's p= exists to let you do (open the file) is
# undoable without it. Every other byte of the reference is unchanged, which is what this arm is for.
"$BIN" test/legofix --no-cache --lego=Shape >"$TMP/standalone" 2>/dev/null
printf '%s' '<ctx root="test/legofix"><lego><iface n="Shape" p="shapes.h" implementors="2"><m pure="1">virtual double area() const = 0</m><m pure="1">virtual void draw() const = 0</m><impl n="Circle" p="shapes.h"/><impl n="Square" p="shapes.h"/></iface></lego></ctx>' >"$TMP/standalone.golden"
cmp -s "$TMP/standalone" "$TMP/standalone.golden" \
    && ok "--lego=Shape standalone byte-identical to the reference output (bundle-only change)" \
    || no "--lego=Shape standalone CHANGED — the §P3 fix must touch the bundle embedding only: $( cat "$TMP/standalone" )"

# ── 6) determinism + well-formed XML ─────────────────────────────────────────────────────────────────
cmp -s "$TMP/on.xml" "$TMP/on2.xml" \
    && ok "determinism --for (byte-identical, $( wc -c <"$TMP/on.xml" | tr -d ' ' ) B)" \
    || no "determinism --for (non-deterministic output)"
if command -v xmllint >/dev/null 2>&1; then
    for v in off on; do
        xmllint --noout "$TMP/$v.xml" 2>/dev/null \
            && ok "xml well-formed (--for $v-task)" || no "xml malformed (--for $v-task)"
    done
    xmllint --noout "$TMP/standalone" 2>/dev/null \
        && ok "xml well-formed (--lego=Shape)" || no "xml malformed (--lego=Shape)"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

# ── 7) mutation-check: a deliberately-wrong assertion MUST fail ──────────────────────────────────────
printf '%s' "$ONLEGO" | grep -q '<impl n="Triangle"' \
    && no "mutation-check: matched a Triangle impl that does not exist (gate is broken)" \
    || ok "mutation-check: absent Triangle correctly not matched (gate discriminates)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
