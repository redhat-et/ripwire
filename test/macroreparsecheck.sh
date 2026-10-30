#!/usr/bin/env bash
# macroreparsecheck.sh — THE MEMBER-MACRO RE-PARSE (0.6.0): the root-cause mitigation behind the extent detector's
# largest finding. test/extentcheck.sh DISCLOSES a derailed parse; this gate proves the commonest derailment is now
# REPAIRED, and that nothing else moved.
#
# The defect. A function-like macro invoked with no trailing `;` as the last member of a class/struct/union body
# (`NAME_OF(Foo)` right before `};`) is read by tree-sitter-cpp — and tree-sitter-c, and tree-sitter-objc — as a field
# declaration missing its `;`. With several such structs in a row the earlier ones dissolve into an ERROR region and
# the last one's body runs on until some later `}`: free functions come out as `method` rows under that struct, a
# struct can become a later function's RETURN TYPE (its lines summed into that function's cx/ccx), and in C whole
# functions vanish into ERROR nodes. Measured on a BSL-licensed C++ corpus: 472 of one file's 487 definitions flagged.
#
# The mitigation (src/macroreparse.h, wired in ingest_sidecap.h adoptMemberMacroReparse). Only for a C-family file
# whose FIRST parse holds error BYTES: scan for semicolon-less ALL-CAPS function-like invocations that stand alone on
# their line directly inside a class/struct/union body, replace exactly those bytes with spaces (newlines kept, so
# every offset and line is unchanged), re-parse, and ADOPT the second tree only when it holds STRICTLY FEWER error
# bytes. Extraction runs on the adopted tree against the ORIGINAL bytes. Disclosed per file (--skipped <h> row:
# why=…macro-blanked, macro_blanked="N") and in the headers (macro_blanked_files=, map + --skipped + --json).
#
# Arms:
#   (A) the seven leak fixtures (anonymous namespace, plain, lambda+structured binding, C, ObjC, CUDA, and one that
#       keeps an unrelated error): no extent_suspect anywhere; every free function is t="fn" and filed under no struct;
#       every struct is present under its own name.
#   (B) complexity: each free function's t/id/cx/ccx equals the SEMICOLON form of the same file (built at run time).
#   (C) --skipped: an <h> row per leak file with why=…macro-blanked and macro_blanked= = its invocation-line count;
#       err= is the ADOPTED tree's: 0 and no degraded-parse where the repair is complete, degraded-parse and err>0 on
#       the fixture that keeps an unrelated error; root macro_blanked_files=; the legend defines what it emits.
#   (D) map header macro_blanked_files= (legend-defined) and its --json twin.
#   (E) --uses=MACRO keeps every invocation site as a use (role=type, as the unrepaired parse recorded it): each
#       invocation line of the C++ fixtures is listed; with RIPWIRE_BASE_BIN the site sets equal the base binary's.
#   (F) CONTROLS — the semicolon form, a clean file, and a file whose unrelated error blanking cannot reduce (first
#       tree KEPT: err="2" stays): none carries the new vocabulary on map/--metrics/--skipped/--for/--expand/--hotspots/
#       --json; with RIPWIRE_BASE_BIN every one of those outputs is byte-identical to the base binary's.
#   (G) with RIPWIRE_BASE_BIN: the leak fixtures still REPRODUCE the defect on the base binary (else (A) tests nothing).
#   (H) determinism: two cold runs byte-identical; a cache-writing run and the warm read agree (lean and rich), and the
#       warm read still carries macro_blanked= (the per-file count rides the cache record).
#   (I) xmllint on every XML capture.
#   (RS) the Rust layer (src/rustusebounds.h): precise-capturing use<..> bounds — see the section's own header.
#   (U) the unit driver test/macroreparse_unit.cpp (scanner shapes incl. the Rust layer, offset-preserving blank, adoption rule).
#
# Load-bearing, and the two mutations it exists for (recorded in the landing commit, re-runnable by hand):
#   never adopt (adoptsReparse returns false)          -> (A)(B)(C)(D)(E)(H-warm) FAIL
#   adopt regardless (adoptsReparse returns true)      -> (F) FAIL on control/unrelated.cpp (err 2 -> 1, macro_blanked=)
#
#   bash test/macroreparsecheck.sh                          # build/ripwire
#   bash test/macroreparsecheck.sh build_base/ripwire       # or RIPWIRE_BIN=... — both seams honored
#   RIPWIRE_BASE_BIN=/path/to/pre/ripwire bash test/macroreparsecheck.sh   # adds (E) parity, (F) byte-identity, (G)
#   RIPWIRE_RUST_BASE_BIN=/path/to/pre-rust-layer/ripwire bash test/macroreparsecheck.sh   # adds (RS3) byte-identity, (RS4)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
. "$ROOT/test/lib/cxxflags.sh"                          # the ONE flags.make parse (CWE-78: never eval a generated file)

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "macroreparsecheck: BIN=$BIN"
BASE="${RIPWIRE_BASE_BIN:-}"
if [ -n "$BASE" ] && [ ! -x "$BASE" ]; then
    echo "RIPWIRE_BASE_BIN=$BASE is not executable"; exit 2
fi

FIX="$ROOT/test/macroreparsefix"
LEAKS="leak_anon.cpp leak_plain.cpp leak_lambda.cpp leak_c.c leak_objc.m leak_cuda.cu leak_partial.cpp"
for f in $LEAKS control/semi.cpp control/clean.cpp control/unrelated.cpp; do
    [ -f "$FIX/$f" ] || { echo "missing fixture $FIX/$f"; exit 2; }
done
mkdir -p "$TMP/leak" "$TMP/twin" "$TMP/semi" "$TMP/clean" "$TMP/unrel"
for f in $LEAKS; do cp "$FIX/$f" "$TMP/leak/"; done
cp "$FIX/control/semi.cpp" "$TMP/semi/"
cp "$FIX/control/clean.cpp" "$TMP/clean/"
cp "$FIX/control/unrelated.cpp" "$TMP/unrel/"

# The invocation lines, and the semicolon twin of every leak file — ONE regex for both, so (B)'s twin and (C)'s
# expected count can never describe two different populations. `#` lines (the #define) never match.
python3 - "$TMP/leak" "$TMP/twin" > "$TMP/invocations.tsv" <<'PY'
import os, re, sys
src, dst = sys.argv[1], sys.argv[2]
inv = re.compile(r'^(\s*[A-Z_][A-Z0-9_]*\(.*\))\s*$')
for name in sorted(os.listdir(src)):
    lines = open(os.path.join(src, name)).read().split('\n')
    out, hits = [], []
    for i, line in enumerate(lines, 1):
        m = inv.match(line)
        if m:
            hits.append(i)
            out.append(m.group(1) + ';')
        else:
            out.append(line)
    open(os.path.join(dst, name), 'w').write('\n'.join(out))
    print('%s\t%d\t%s' % (name, len(hits), ','.join(map(str, hits))))
PY

XMLS=()
cap(){ local out="$1"; shift; "$BIN" "$@" >"$out" 2>/dev/null; XMLS+=( "$out" ); }
comments(){ python3 -c 'import re,sys; print("\n".join(re.findall(r"<!--.*?-->", open(sys.argv[1]).read(), re.S)))' "$1"; }
defines(){ comments "$1" | grep -qE "(^|[^A-Za-z_])$2="; }
readrows(){ while IFS= read -r line; do case "$line" in PASS*) ok "${line#PASS }";; *) no "${line#FAIL }";; esac; done < "$1"; }

# ── (A) scoping: every free function is a free function again ─────────────────────────────────────────────────
cap "$TMP/a_met.xml" "$TMP/leak" --no-cache --metrics
cap "$TMP/a_map.xml" "$TMP/leak" --no-cache
cap "$TMP/b_twin.xml" "$TMP/twin" --no-cache --metrics
cat > "$TMP/expect.py" <<'PY'
# file -> (free functions, structs). leak_objc.m lists NO structs: the Objective-C tags query does not extract a C
# `struct` definition even from a clean .m file (measured on the pre-change binary: `struct beacon {…};` + a function in
# plain.m yields only the function; the same bytes as plain.c yield both) — so its functions are the whole claim.
EXPECT = {
    'leak_anon.cpp':    (['tallyCargo', 'berthIsFree', 'clearManifest'], ['HarborFault', 'InletFault', 'JettyFault', 'KeelFault']),
    'leak_plain.cpp':   (['countMoorings', 'sumDraft'],                 ['LanternRecord', 'MooringRecord', 'NavigatorRecord']),
    'leak_lambda.cpp':  (['weighHarvest', 'gradeYield', 'afterOrchard'], ['OrchardError', 'PastureError', 'QuarryError']),
    'leak_c.c':         (['sum_rations', 'reset_tally'],                 ['ration', 'satchel', 'trailmap']),
    'leak_objc.m':      (['brightest', 'zero_bearing'],                  []),
    'leak_cuda.cu':     (['blockCount'],                                 ['RiverKernel', 'StreamKernel', 'TideKernel']),
    'leak_partial.cpp': (['portCount', 'ferryFare'],                     ['UplandFault', 'ValleyFault', 'WillowFault']),
}
import re
def attrs(tag):
    return dict(re.findall(r'(\w+)="([^"]*)"', tag))
def fileRows(doc, p):
    m = re.search(r'<f p="%s"[^>]*>(.*?)</f>' % re.escape(p), doc, re.S)
    return [attrs(t) for t in re.findall(r'<s [^>]*>', m.group(1))] if m else None
PY
python3 - "$TMP/a_met.xml" "$TMP/a_map.xml" "$TMP" > "$TMP/a.out" <<'PY'
import sys
sys.path.insert(0, sys.argv[3])
from expect import EXPECT, attrs, fileRows
met, mp = open(sys.argv[1]).read(), open(sys.argv[2]).read()
print(("PASS" if 'extent_suspect' not in met and 'extent_suspect' not in mp else "FAIL")
      + " (A) no extent_suspect on any --metrics or map row/header of the seven leak fixtures")
for p, (fns, structs) in sorted(EXPECT.items()):
    rows = fileRows(met, p)
    if rows is None:
        print("FAIL (A) %s has no --metrics block" % p); continue
    byName = {}
    for r in rows:
        byName.setdefault(r.get('n'), []).append(r)
    for fn in fns:
        rs = byName.get(fn, [])
        bad = [r for r in rs if r.get('t') != 'fn' or any(('::%s::' % s) in r.get('id', '') for s in structs)]
        print(("PASS" if len(rs) == 1 and not bad else "FAIL")
              + " (A) %s: %s is one t=\"fn\" row filed under no struct (got %s)" % (p, fn, [(r.get('t'), r.get('id')) for r in rs]))
    missing = [s for s in structs if s not in byName]
    print(("PASS" if not missing else "FAIL") + " (A) %s: every struct is extracted under its own name (missing %s)" % (p, missing))
PY
readrows "$TMP/a.out"

# ── (B) complexity equals the semicolon form ──────────────────────────────────────────────────────────────────
python3 - "$TMP/a_met.xml" "$TMP/b_twin.xml" "$TMP" > "$TMP/b.out" <<'PY'
import sys
sys.path.insert(0, sys.argv[3])
from expect import EXPECT, fileRows
got, twin = open(sys.argv[1]).read(), open(sys.argv[2]).read()
for p, (fns, _structs) in sorted(EXPECT.items()):
    g, t = fileRows(got, p) or [], fileRows(twin, p) or []
    for fn in fns:
        gr = [r for r in g if r.get('n') == fn]
        tr = [r for r in t if r.get('n') == fn]
        keys = ('t', 'id', 'cx', 'ccx')
        gv = [tuple(r.get(k) for k in keys) for r in gr]
        tv = [tuple(r.get(k) for k in keys) for r in tr]
        print(("PASS" if gv and gv == tv else "FAIL") + " (B) %s: %s t/id/cx/ccx %s == semicolon form %s" % (p, fn, gv, tv))
PY
readrows "$TMP/b.out"

# ── (C) --skipped: which files, how many invocations, and what the adopted tree still holds ───────────────────
cap "$TMP/c.xml" "$TMP/leak" --no-cache --skipped
python3 - "$TMP/c.xml" "$TMP/invocations.tsv" > "$TMP/c.out" <<'PY'
import re, sys
doc = open(sys.argv[1]).read()
inv = {l.split('\t')[0]: int(l.split('\t')[1]) for l in open(sys.argv[2]).read().splitlines()}
def attrs(tag):
    return dict(re.findall(r'(\w+)="([^"]*)"', tag))
rows = {a['p']: a for a in (attrs(t) for t in re.findall(r'<h [^>]*/>', doc)) if 'p' in a}   # the legend spells `<h p= why= .../>` too
for p, n in sorted(inv.items()):
    r = rows.get(p)
    if r is None:
        print("FAIL (C) %s has no <h> row" % p); continue
    why = r.get('why', '').split(',')
    print(("PASS" if 'macro-blanked' in why and r.get('macro_blanked') == str(n) else "FAIL")
          + " (C) %s: why=%s macro_blanked=%s (want macro-blanked, %d invocation lines)" % (p, r.get('why'), r.get('macro_blanked'), n))
    if p == 'leak_partial.cpp':
        print(("PASS" if 'degraded-parse' in why and int(r.get('err', '0')) > 0 else "FAIL")
              + " (C) %s: the adopted tree still holds an error and the row says so (why=%s err=%s)" % (p, r.get('why'), r.get('err')))
    else:
        print(("PASS" if 'degraded-parse' not in why and r.get('err') == '0' else "FAIL")
              + " (C) %s: the adopted tree is clean and the row says so (why=%s err=%s)" % (p, r.get('why'), r.get('err')))
root = re.search(r'<skipped [^>]*>', doc)
ra = attrs(root.group(0)) if root else {}
print(("PASS" if ra.get('macro_blanked_files') == str(len(inv)) else "FAIL")
      + " (C) root macro_blanked_files=%s (want %d)" % (ra.get('macro_blanked_files'), len(inv)))
degradedRows = sum(1 for a in rows.values() if 'degraded-parse' in a.get('why', '').split(','))
print(("PASS" if ra.get('degraded_parse') == str(degradedRows) else "FAIL")
      + " (C) root degraded_parse=%s counts the rows whose ADOPTED tree still has errors (%d)" % (ra.get('degraded_parse'), degradedRows))
PY
readrows "$TMP/c.out"
defines "$TMP/c.xml" macro_blanked && defines "$TMP/c.xml" macro_blanked_files && comments "$TMP/c.xml" | grep -q 'macro-blanked' \
    && ok "(C) --skipped legend defines macro_blanked=, macro_blanked_files= and why=macro-blanked" \
    || no "(C) --skipped legend misses macro_blanked= / macro_blanked_files= / macro-blanked (define what you emit)"

# ── (D) the map header and its --json twin ────────────────────────────────────────────────────────────────────
hdrK="$( grep -oE '<!-- files=[^>]*-->' "$TMP/a_map.xml" | grep -oE ' macro_blanked_files=[0-9]+' | sed 's/.*=//' )"
nLeaks=$( printf '%s\n' $LEAKS | wc -l | tr -d ' ' )
if [ "$hdrK" = "$nLeaks" ]; then ok "(D) map header macro_blanked_files=$hdrK"; else no "(D) map header macro_blanked_files='${hdrK:-absent}' (want $nLeaks)"; fi
if defines "$TMP/a_map.xml" macro_blanked_files; then ok "(D) the map legend defines macro_blanked_files="; else no "(D) the map legend does not define macro_blanked_files="; fi
"$BIN" "$TMP/leak" --no-cache --json >"$TMP/d.json" 2>/dev/null
python3 - "$TMP/d.json" "$nLeaks" > "$TMP/d.out" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("FAIL (D) --json does not parse: %s" % e); sys.exit(0)
print(("PASS" if d.get('macro_blanked_files') == int(sys.argv[2]) else "FAIL")
      + " (D) --json header \"macro_blanked_files\":%r (want %s)" % (d.get('macro_blanked_files'), sys.argv[2]))
PY
readrows "$TMP/d.out"

# ── (E) --uses=MACRO keeps every invocation site ──────────────────────────────────────────────────────────────
cap "$TMP/e_new.xml" "$TMP/leak" --no-cache --uses=NAME_OF
python3 - "$TMP/e_new.xml" "$TMP/invocations.tsv" > "$TMP/e.out" <<'PY'
import re, sys
doc = open(sys.argv[1]).read()
sites = set(re.findall(r'<u [^>]*p="([^"]+)"', doc))
for line in open(sys.argv[2]).read().splitlines():
    p, n, lines = line.split('\t')
    if p not in ('leak_anon.cpp', 'leak_lambda.cpp', 'leak_cuda.cu', 'leak_partial.cpp'):
        continue   # the NAME_OF files; the C/ObjC fixtures use FIELD_TAIL, leak_plain uses TAG_KIND
    want = {'%s:%s' % (p, l) for l in lines.split(',')}
    print(("PASS" if want <= sites else "FAIL") + " (E) --uses=NAME_OF lists every invocation line of %s (missing %s)" % (p, sorted(want - sites)))
PY
readrows "$TMP/e.out"
if [ -n "$BASE" ]; then
    for m in NAME_OF TAG_KIND FIELD_TAIL; do
        "$BIN"  "$TMP/leak" --no-cache --uses=$m 2>/dev/null | grep -oE '<u [^>]*p="[^"]+"' | grep -oE 'p="[^"]+"' | sort -u >"$TMP/e_new_$m"
        "$BASE" "$TMP/leak" --no-cache --uses=$m 2>/dev/null | grep -oE '<u [^>]*p="[^"]+"' | grep -oE 'p="[^"]+"' | sort -u >"$TMP/e_base_$m"
        cmp -s "$TMP/e_new_$m" "$TMP/e_base_$m" && ok "(E) --uses=$m site set equals the base binary's ($( wc -l <"$TMP/e_new_$m" | tr -d ' ' ) sites)" \
            || no "(E) --uses=$m site set differs from the base binary's: $( diff "$TMP/e_base_$m" "$TMP/e_new_$m" | grep -E '^[<>]' | tr '\n' ' ' )"
    done
else
    echo "  SKIP  (E) site-set parity vs a pre-change build (set RIPWIRE_BASE_BIN)"
fi

# ── (F) controls: nothing moves ───────────────────────────────────────────────────────────────────────────────
if command -v git >/dev/null 2>&1; then
    for d in semi clean unrel; do
        git -C "$TMP/$d" init -q >/dev/null 2>&1
        git -C "$TMP/$d" add -A >/dev/null 2>&1
        git -C "$TMP/$d" -c user.name=macroreparsecheck -c user.email=macroreparsecheck@example.invalid -c commit.gpgsign=false commit -q -m fixture >/dev/null 2>&1
    done
fi
for spec in "semi:tallyCargo" "clean:totalToll" "unrel:relayCount"; do
    d="${spec%%:*}"; fn="${spec#*:}"
    for surf in "map:" "met:--metrics" "skp:--skipped" "for:--for=$fn" "exp:--expand=$fn" "hot:--hotspots" "json:--json"; do
        tag="${surf%%:*}"; flag="${surf#*:}"
        "$BIN" "$TMP/$d" --no-cache $flag >"$TMP/f_${d}_$tag" 2>/dev/null
        [ "$tag" = json ] || XMLS+=( "$TMP/f_${d}_$tag" )
        if [ -n "$BASE" ]; then
            "$BASE" "$TMP/$d" --no-cache $flag >"$TMP/fb_${d}_$tag" 2>/dev/null
            cmp -s "$TMP/f_${d}_$tag" "$TMP/fb_${d}_$tag" && ok "(F) control $d ${flag:-map} is byte-identical to RIPWIRE_BASE_BIN" \
                || no "(F) control $d ${flag:-map} differs from RIPWIRE_BASE_BIN"
        fi
    done
    if grep -l 'macro_blanked\|macro-blanked' "$TMP"/f_${d}_* >/dev/null 2>&1; then
        no "(F) control $d carries the new vocabulary: $( grep -l 'macro_blanked\|macro-blanked' "$TMP"/f_${d}_* | xargs -n1 basename | tr '\n' ' ' )"
    else
        ok "(F) control $d carries no macro_blanked / macro-blanked on map, --metrics, --skipped, --for, --expand, --hotspots, --json"
    fi
done
[ -n "$BASE" ] || echo "  SKIP  (F) byte-identity vs a pre-change build (set RIPWIRE_BASE_BIN)"
unrelRow="$( grep -oE '<h p="unrelated.cpp"[^>]*>' "$TMP/f_unrel_skp" | head -1 )"
printf '%s' "$unrelRow" | grep -q 'why="degraded-parse" err="2"' \
    && ok "(F) control unrel keeps its FIRST tree: why=\"degraded-parse\" err=\"2\" (blanking could not reduce the error bytes)" \
    || no "(F) control unrel did not keep its first tree (an adopt-regardless mutation drops err to 1): ${unrelRow:-no <h> row}"

# ── (G) the leak fixtures reproduce the defect on the base binary ─────────────────────────────────────────────
if [ -n "$BASE" ]; then
    "$BASE" "$TMP/leak" --no-cache --metrics >"$TMP/g_base.xml" 2>/dev/null
    python3 - "$TMP/g_base.xml" "$TMP" > "$TMP/g.out" <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
from expect import EXPECT, fileRows
doc = open(sys.argv[1]).read()
for p, (fns, structs) in sorted(EXPECT.items()):
    rows = fileRows(doc, p) or []
    wrong = [fn for fn in fns if [r.get('t') for r in rows if r.get('n') == fn] != ['fn']
             or any(('::%s::' % s) in r.get('id', '') for r in rows if r.get('n') == fn for s in structs)]
    print(("PASS" if wrong else "FAIL") + " (G) %s reproduces on the base binary: %s mis-scoped, mis-kinded or lost" % (p, wrong))
PY
    readrows "$TMP/g.out"
else
    echo "  SKIP  (G) reproduction on a pre-change build (set RIPWIRE_BASE_BIN)"
fi

# ── (H) determinism, and the per-file count across the cache ──────────────────────────────────────────────────
"$BIN" "$TMP/leak" --no-cache --skipped >"$TMP/h1.xml" 2>/dev/null
"$BIN" "$TMP/leak" --no-cache --skipped >"$TMP/h2.xml" 2>/dev/null
if cmp -s "$TMP/h1.xml" "$TMP/h2.xml"; then ok "(H) two cold --skipped runs are byte-identical"; else no "(H) two cold --skipped runs differ"; fi
"$BIN" "$TMP/leak" --cache="$TMP/lean.cache" --skipped >"$TMP/h_cold.xml" 2>/dev/null
"$BIN" "$TMP/leak" --cache="$TMP/lean.cache" --skipped >"$TMP/h_warm.xml" 2>/dev/null
XMLS+=( "$TMP/h1.xml" "$TMP/h_cold.xml" "$TMP/h_warm.xml" )
if cmp -s "$TMP/h_cold.xml" "$TMP/h_warm.xml"; then ok "(H) lean: the cache-writing run and the warm read are byte-identical"; else no "(H) lean: cold and warm cache runs differ"; fi
grep -q 'macro_blanked="4"' "$TMP/h_warm.xml" && ok "(H) the warm read still carries macro_blanked= (the count rides the cache record)" \
    || no "(H) the warm read lost macro_blanked= — the per-file count did not survive the cache"
"$BIN" "$TMP/leak" --cache="$TMP/rich.cache" --uses=NAME_OF >"$TMP/h_rcold.xml" 2>/dev/null
"$BIN" "$TMP/leak" --cache="$TMP/rich.cache" --uses=NAME_OF >"$TMP/h_rwarm.xml" 2>/dev/null
cmp -s "$TMP/h_rcold.xml" "$TMP/h_rwarm.xml" && cmp -s "$TMP/h_rwarm.xml" "$TMP/e_new.xml" \
    && ok "(H) rich: --uses cold-cache, warm-cache and --no-cache runs are byte-identical" || no "(H) rich: --uses differs across cold/warm/no-cache"

# ── (RS) the Rust layer: precise-capturing use<..> bounds (src/rustusebounds.h) ────────────────────────────────
# An EMPTY `+ use<>` bound (Rust 1.82 precise capturing) collapses a whole Rust file into one root ERROR node on the
# vendored grammar (zed: 25 files, err_ratio=1.000), so every associated fn loses its impl owner. The fix blanks the
# bounds, re-parses and adopts under the same strictly-fewer-error-bytes rule. Arms:
#   RS1 each capture fixture's methods bind as Type::method with t="method" sc=<impl type> at the ORIGINAL line.
#   RS2 --skipped: why="use-bounds-blanked" use_bounds_blanked="1" err="0" (the adopted parse is clean), root
#      use_bounds_blanked_files="2", the legend defines the vocabulary it emits.
#   RS3 controls (clean, non-empty forms that already parse, spellings only in comment/string/raw string/r#use, and a
#      bound whose re-parse cannot reduce an unrelated error): no use_bounds_blanked anywhere; rust_kept keeps its error.
#      The string/comment/raw-string controls prove "not adopted", not "the scanner skipped the text" (a scanner that
#      blanked a string could not reduce error bytes either): the lexer's literal handling is pinned by the (U) unit cases.
#      With RIPWIRE_RUST_BASE_BIN: map, --skipped and --callers over the controls are byte-identical to that binary.
#   RS4 with RIPWIRE_RUST_BASE_BIN: the capture fixtures still REPRODUCE the collapse on the base binary (else RS1/RS2 test nothing).
#   RS5 a cache-writing run and the warm read agree, and the warm read still carries use_bounds_blanked=.
# Mutations: never adopt -> RS1 RS2 RS5 FAIL; adopt regardless -> RS3 FAIL on rust_kept (use_bounds_blanked= appears).
RFIX="$FIX/rust"
# The Rust layer's base is a binary built BEFORE it (RIPWIRE_RUST_BASE_BIN), not RIPWIRE_BASE_BIN, which names a binary
# from before the member-macro re-parse itself (arm G): one binary rarely predates both.
RBASE="${RIPWIRE_RUST_BASE_BIN:-}"
if [ -n "$RBASE" ] && [ ! -x "$RBASE" ]; then
    no "(RS) RIPWIRE_RUST_BASE_BIN=$RBASE is not executable"; RBASE=""
fi
mkdir -p "$TMP/rcap" "$TMP/rctl"
cp "$RFIX/capture_plus.rs" "$RFIX/capture_split.rs" "$TMP/rcap/" || no "(RS) capture fixtures missing under $RFIX"
cp "$RFIX/control/rust_clean.rs" "$RFIX/control/rust_forms.rs" "$RFIX/control/rust_unrelated.rs" "$RFIX/control/rust_kept.rs" "$TMP/rctl/" \
    || no "(RS) control fixtures missing under $RFIX/control"
# RS1 — owner, kind and line: --expand=Owner::name must bind (the selector's owner IS the def's stored scope) and its
# <b> row carries t="method" at the ORIGINAL line; the map row carries sc=Owner.
cap "$TMP/r1_map.xml" "$TMP/rcap" --no-cache
for spec in capture_plus.rs:Pane:save_item capture_plus.rs:Pane:close_item capture_plus.rs:Workspace:new_local \
            capture_split.rs:Buffer:edit capture_split.rs:Editor:backspace; do
    file="${spec%%:*}"; rest="${spec#*:}"; owner="${rest%%:*}"; name="${rest#*:}"
    want_line="$( grep -n "pub fn $name(" "$TMP/rcap/$file" | head -1 | cut -d: -f1 )"
    "$BIN" "$TMP/rcap" --no-cache "--expand=$owner::$name" >"$TMP/r1_$name.xml" 2>/dev/null; rc=$?
    XMLS+=( "$TMP/r1_$name.xml" )
    if [ "$rc" -eq 0 ] && [ -n "$want_line" ] && grep -q "<b t=\"method\" l=\"$want_line\" p=\"$file\" n=\"$name\"" "$TMP/r1_$name.xml" \
       && grep -q "<s t=\"method\" n=\"$name\" sc=\"$owner\"" "$TMP/r1_map.xml"; then
        ok "(RS1) $owner::$name binds: t=method sc=$owner at $file:$want_line"
    else
        no "(RS1) $owner::$name did not bind as method of $owner at $file:${want_line:-?} (rc=$rc): $( grep -o '<b [^>]*>' "$TMP/r1_$name.xml" | tail -1 )"
    fi
done
# RS2 — the disclosure
cap "$TMP/r2.xml" "$TMP/rcap" --no-cache --skipped
for file in capture_plus.rs capture_split.rs; do
    row="$( grep -o "<h p=\"$file\"[^>]*>" "$TMP/r2.xml" )"
    case "$row" in
        *'why="use-bounds-blanked"'*'err="0"'*'use_bounds_blanked="1"'*) ok "(RS2) $file: why=use-bounds-blanked err=0 use_bounds_blanked=1" ;;
        *) no "(RS2) $file row wrong or missing: ${row:-<none>}" ;;
    esac
done
grep -q '<skipped [^>]*use_bounds_blanked_files="2"' "$TMP/r2.xml" && ok "(RS2) root use_bounds_blanked_files=\"2\"" \
    || no "(RS2) root lacks use_bounds_blanked_files=\"2\": $( grep -o '<skipped [^>]*>' "$TMP/r2.xml" | cut -c1-300 )"
grep -q 'why=use-bounds-blanked on an <h> row' "$TMP/r2.xml" && grep -q 'use_bounds_blanked_files= on the root' "$TMP/r2.xml" \
    && ok "(RS2) the legend defines why=use-bounds-blanked, use_bounds_blanked= and use_bounds_blanked_files=" || no "(RS2) the legend does not define the new vocabulary"
# RS3 — controls carry none of it; rust_kept keeps its first tree
cap "$TMP/r3_skipped.xml" "$TMP/rctl" --no-cache --skipped
cap "$TMP/r3_map.xml" "$TMP/rctl" --no-cache
cap "$TMP/r3_callers.xml" "$TMP/rctl" --no-cache --callers=Editor::backspace
if grep -q 'use_bounds_blanked\|use-bounds-blanked' "$TMP/r3_skipped.xml" "$TMP/r3_map.xml" "$TMP/r3_callers.xml"; then
    no "(RS3) a control carries the new vocabulary: $( grep -o '<h [^>]*use_bounds[^>]*>' "$TMP/r3_skipped.xml" | head -3 | tr '\n' ' ' )"
else
    ok "(RS3) no control carries use_bounds_blanked / use-bounds-blanked (skipped, map, callers)"
fi
kept="$( grep -o '<h p="rust_kept.rs"[^>]*>' "$TMP/r3_skipped.xml" )"
case "$kept" in
    *'why="degraded-parse"'*) ok "(RS3) rust_kept.rs keeps its first parse: $kept" ;;
    *) no "(RS3) rust_kept.rs should stay degraded-parse with no blank: ${kept:-<none>}" ;;
esac
if [ -n "$RBASE" ]; then
    for v in skipped map callers; do
        case "$v" in skipped) args=( --skipped ) ;; map) args=() ;; callers) args=( --callers=Editor::backspace ) ;; esac
        "$RBASE" "$TMP/rctl" --no-cache ${args[@]+"${args[@]}"} >"$TMP/r3_base_$v.xml" 2>/dev/null
        cmp -s "$TMP/r3_base_$v.xml" "$TMP/r3_$v.xml" && ok "(RS3) controls: $v byte-identical to the base binary" \
            || no "(RS3) controls: $v differs from the base binary"
    done
    # RS4 — the premise: the base binary still collapses the capture fixtures
    "$RBASE" "$TMP/rcap" --no-cache --skipped >"$TMP/r4.xml" 2>/dev/null
    n="$( grep -c 'err_ratio="1.000"' <( grep -o '<h p="capture_[a-z]*.rs"[^>]*>' "$TMP/r4.xml" ) )"
    [ "$n" = "2" ] && ok "(RS4) base binary: both capture fixtures parse as one whole-file ERROR (err_ratio=1.000)" \
        || no "(RS4) base binary does not reproduce the collapse ($n of 2 at err_ratio=1.000) — RS1/RS2 test nothing"
    "$RBASE" "$TMP/rcap" --no-cache --callers=Pane::save_item >/dev/null 2>&1 && no "(RS4) base binary already binds Pane::save_item" \
        || ok "(RS4) base binary: Pane::save_item does not bind"
else
    echo "  SKIP  (RS3 byte-identity, RS4) RIPWIRE_RUST_BASE_BIN unset"
fi
# RS5 — the count rides the cache record
"$BIN" "$TMP/rcap" --cache="$TMP/r.cache" --skipped >"$TMP/r5_cold.xml" 2>/dev/null
"$BIN" "$TMP/rcap" --cache="$TMP/r.cache" --skipped >"$TMP/r5_warm.xml" 2>/dev/null
XMLS+=( "$TMP/r5_cold.xml" "$TMP/r5_warm.xml" )
if cmp -s "$TMP/r5_cold.xml" "$TMP/r5_warm.xml"; then
    ok "(RS5) cache-writing run and warm read are byte-identical"
else
    no "(RS5) cold and warm cache runs differ"
fi
grep -q 'use_bounds_blanked="1"' "$TMP/r5_warm.xml" && ok "(RS5) the warm read still carries use_bounds_blanked=" \
    || no "(RS5) the warm read lost use_bounds_blanked= — the per-file count did not survive the cache"

# ── (I) well-formedness ───────────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    bad=0
    for x in "${XMLS[@]}"; do
        [ -s "$x" ] || continue
        xmllint --noout "$x" 2>/dev/null || { bad=1; no "(I) $( basename "$x" ) is not well-formed XML"; }
    done
    [ "$bad" -eq 0 ] && ok "(I) all ${#XMLS[@]} XML captures are well-formed"
else
    echo "  SKIP  (I) xmllint unavailable"
fi

# ── (U) the unit driver ───────────────────────────────────────────────────────────────────────────────────────
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"
LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
if [ ! -f "$FLAGS_MK" ] || [ ! -f "$LINK_TXT" ]; then
    no "(U) cannot find CMake flags under $BUILD_DIR — the unit arm needs a CMake-built binary"
else
    # The compiler CMake drove (link.txt's first token), never a guess — extentcheck.sh's recipe and reason.
    CXX="$( awk 'NR==1{ print $1; exit }' "$LINK_TXT" )"
    [ -n "$CXX" ] && command -v "$CXX" >/dev/null 2>&1 || CXX="$( command -v c++ || command -v clang++ )"
    # The flags parse is SHARED and shlex-based, never `eval`: test/lib/cxxflags.sh carries the CWE-78
    # reachability chain, the measured table of which shapes execute, and the proof arms relayed below.
    cxxflags_load "$FLAGS_MK" \
        || no "cannot parse $FLAGS_MK without executing it (see the cxxflags: line on stderr)"

    # ── the parse's own proof ─────────────────────────────────────────────────────────────────────────
    # Three claims, none of which the others imply: the eval spelling this replaced DOES execute a
    # payload (without that control the rest is vacuous), this parse executes nothing, and it neutralises
    # the payload rather than silently DROPPING it. Each shape gets its own key and its own control —
    # several on one flags line mask each other into a false all-clear (test/lib/cxxflags.sh, arm P6).
    cxxflags_selfproof "$TMP/cxxflags" "$FLAGS_MK" > "$TMP/cxxflags.rows" 2>&1 || true
    while IFS= read -r _row; do             # a redirect, never a pipe: a pipeline subshell loses fail=1
        case "$_row" in
            PASS*) ok "${_row#PASS }" ;;
            NOTE*) printf '  NOTE  %s\n' "${_row#NOTE }" ;;
            FAIL*) no "${_row#FAIL }" ;;
        esac
    done < "$TMP/cxxflags.rows"
    DIAG_OBJ="$BUILD_DIR/CMakeFiles/ripwire.dir/src/infra/diagnostics.cpp.o"
    DIAG_LINK=(); [ -f "$DIAG_OBJ" ] && DIAG_LINK=( "$DIAG_OBJ" )
    if "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" "${CXX_INCLUDES[@]}" -I"$ROOT/src" \
         "$ROOT/test/macroreparse_unit.cpp" "${DIAG_LINK[@]}" -o "$TMP/macroreparse_unit" >"$TMP/u_build.log" 2>&1; then
        if "$TMP/macroreparse_unit" >"$TMP/u_run.log" 2>&1; then
            ok "(U) macroreparse_unit: $( grep -c '  PASS' "$TMP/u_run.log" | tr -d ' ' ) cases hold"
        else
            no "(U) macroreparse_unit failed:"; grep FAIL "$TMP/u_run.log" | head -12 | sed 's/^/        /'
        fi
    else
        no "(U) macroreparse_unit does not compile:"; grep -m4 -E 'error' "$TMP/u_build.log" | sed 's/^/        /'
    fi
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
