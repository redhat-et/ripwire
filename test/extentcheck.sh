#!/usr/bin/env bash
# extentcheck.sh — THE EXTENT/SCOPE HONESTY DETECTOR (0.6.0). A derailed parse must not publish its
# guesses as facts.
#
# The defect this gate exists for (measured 2026-09-10 on a BSL-licensed C++ corpus, reproduced here with
# fresh identifiers): a run of structs whose LAST member is a macro invocation with no semicolon
# (`declare_name(X)` right before `};`). tree-sitter-cpp recovers each as a field declaration missing its
# `;`, dissolves the earlier structs into an ERROR region, and lets the last struct's body swallow every
# definition up to the enclosing namespace's closing brace. ripwire then filed free functions under that
# struct's scope (`id=…::IndiaError::drainQueue`), typed them `method`, and — in the larger corpus, where a
# swallowing struct became the RETURN TYPE of a later function — summed 5,000 lines into one function's
# cx/ccx. Map rows carried no warning; --hotspots ranked the garbage complexity first.
#
# MINIMAL SHAPE, measured by bisection on the pre-change binary: an anonymous namespace + TWO such structs
# + any definition after them. One struct does not reproduce; semicolons after the invocations remove it.
# The fixture uses nine (the corpus had nine) so the recovery takes the whole-file ERROR root, the harder
# case for precision: a clean class and a clean function sit INSIDE that same ERROR root and must stay clean.
# The macro is spelled in LOWERCASE on purpose: since the member-macro re-parse (src/macroreparse.h,
# test/macroreparsecheck.sh) the ALL-CAPS spelling of this run is REPAIRED, not merely disclosed, and the re-parse
# deliberately leaves a lowercase invocation alone — so this is the shape that still derails.
#
# THE RULES (src/extentsuspect.h; the reason codes a row's extent_suspect= carries, in this order):
#   name  — a definition's own name lies outside its own signature span (a span adopted from another node).
#   head  — C family: a definition lies in a BODIED definition's signature span, wholly before that definition's
#           own name (the return-type position); the whole top-level extent tree holding it is marked (the
#           containers' extents are the corrupted ones). The name bound came from measurement: valid C++ puts local
#           structs and vexing-parse locals inside lambdas in a constructor's member-initializer list — after the
#           name — and the unbounded rule flagged them (unit case "R3 definitions in a signature AFTER the name").
#   scope — C++: filed under C:: while physically inside a different class, C defined in the same file.
#   error — the parse recovered a CLASS whose own body holds an error inside an ERROR region (extraction
#           bit, cached), or a C++ method with no scope inside one; every definition inside such a class too.
# name and scope have no producer the vendored grammars accept today; the unit arm (U) pins them on
# synthetic extents so the next span change cannot break them unseen.
#
# DISCLOSURE, NEVER DELETION: rows stay. Arms:
#   (A) the leak fixture: the four swallowed functions and the swallowing struct carry extent_suspect=error;
#       the clean class/function/macro beside them do not; header extent_suspect_syms= equals the flagged
#       row count; the legend DEFINES both (name immediately followed by `=`, the house predicate).
#   (B) the signature-swallow shape (legal C): the function and the struct in its return type carry head.
#   (C) the dissolved-container shape: the scopeless `method` rows carry error.
#   (D) --for (name-exact → auto body walk): the <d> and <b> rows carry it, legend defines it.
#   (E) --expand: the <b> row carries it, legend defines it.
#   (F) --skipped: each file holding flagged symbols has an <h> row (why=…extent-suspect, even on a clean
#       parse), extent_suspect_syms= per row, extent_suspect_files= on the root, legend defines all.
#   (G) --hotspots: a flagged symbol's complexity is EXCLUDED, never ranked — ccx= re-derives from the
#       unflagged rows of --metrics, top= is never a flagged symbol, the row discloses extent_suspect_syms=,
#       a file with nothing trustworthy left is counted in unranked_extent_suspect= and the partition still
#       sums to files=. EVERY `… = files=` equation the legend states names each bucket it sums and holds on the
#       emitted counts — the unconditional header comment spelled three terms beside a nonzero fourth (CodeRabbit
#       #135; red on f5948b69: 59 PASS / 1 FAIL, that equation alone). A zero-bucket control (plain.cpp alone)
#       carries no extent_suspect byte, and with RIPWIRE_BASE_BIN its --hotspots document is byte-identical.
#   (H) CONTROL + MUTATION: the same leak file with the semicolons added — no leak, and not one byte of the
#       new vocabulary on any surface. With RIPWIRE_BASE_BIN (a pre-change build) the control's outputs are
#       byte-compared against it.
#   (I) determinism: two runs byte-identical; a cold cache write and the warm read agree, and the warm read
#       still carries the error reason (the extraction bit survives the cache round trip).
#   (J) --json map: the row key and the header key.
#   (K) xmllint on every XML capture.
#   (U) the unit driver test/extentsuspect_unit.cpp, compiled with the flags CMake used for $BIN.
#
# Load-bearing: on the pre-change binary (A)(B)(C)(D)(E)(F)(G)(J)(U) FAIL and (H)(I)(K) pass — recorded in
# the landing commit. A manual mutation of each rule (return early from its block in extentsuspect.h) reds
# its (U) case and, for head/error, its shell arm.
#
#   bash test/extentcheck.sh                          # build/ripwire
#   bash test/extentcheck.sh build_base/ripwire       # or RIPWIRE_BIN=... — both seams honored
#   RIPWIRE_BASE_BIN=/path/to/pre/ripwire bash test/extentcheck.sh   # adds the control byte-identity arm

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "extentcheck: BIN=$BIN"

FIX="$ROOT/test/extentfix"
for f in leak.cpp head.c orphan.cpp plain.cpp control/leak.cpp; do
    [ -f "$FIX/$f" ] || { echo "missing fixture $FIX/$f"; exit 2; }
done
mkdir -p "$TMP/leak" "$TMP/head" "$TMP/orphan" "$TMP/ctl" "$TMP/hot"
cp "$FIX/leak.cpp" "$TMP/leak/"
cp "$FIX/head.c" "$TMP/head/"
cp "$FIX/orphan.cpp" "$TMP/orphan/"
cp "$FIX/control/leak.cpp" "$TMP/ctl/"
cp "$FIX/leak.cpp" "$FIX/head.c" "$FIX/orphan.cpp" "$FIX/plain.cpp" "$TMP/hot/"

XMLS=()
cap(){ local out="$1"; shift; "$BIN" "$@" >"$out" 2>/dev/null; XMLS+=( "$out" ); }

# row(FILE, NAME) — the first <s>/<d>/<b> opening tag naming n="NAME"
row(){ grep -oE "<(s|d|b) [^>]*n=\"$2\"[^>]*>" "$1" | head -1; }
# comments(FILE) — every <!-- … --> in the document, one per line (the legend a reader meets)
comments(){ python3 -c 'import re,sys; print("\n".join(re.findall(r"<!--.*?-->", open(sys.argv[1]).read(), re.S)))' "$1"; }
# defines(FILE, ATTR) — the legend spells ATTR immediately followed by `=` (not as a suffix of a longer name)
defines(){ comments "$1" | grep -qE "(^|[^A-Za-z_])$2="; }
reasonOf(){ printf '%s' "$1" | grep -oE ' extent_suspect="[^"]*"' | sed -E 's/.*="([^"]*)"/\1/'; }

# ── (A) the scope-leak shape ───────────────────────────────────────────────────────────────────────────
cap "$TMP/a.xml" "$TMP/leak" --no-cache
SWALLOWED="accumulateOrders clampQuantity hasLabel drainQueue"
leaked=0
for n in $SWALLOWED; do
    row "$TMP/a.xml" "$n" | grep -q "id=\"leak.cpp::IndiaError::$n\"" && leaked=$(( leaked + 1 ))
done
[ "$leaked" -eq 4 ] && ok "(A) the fixture still reproduces the leak: 4/4 free functions filed under IndiaError::" \
    || no "(A) the fixture no longer reproduces the leak ($leaked/4 under IndiaError::) — every other arm is testing nothing"
for n in $SWALLOWED IndiaError; do
    r="$( reasonOf "$( row "$TMP/a.xml" "$n" )" )"
    case ",$r," in *,error,*) ok "(A) $n carries extent_suspect with reason error ($r)";; *) no "(A) $n row lacks extent_suspect=…error…: $( row "$TMP/a.xml" "$n" )";; esac
done
for n in Ledger larger fileScopeHelper declare_name; do
    rr="$( row "$TMP/a.xml" "$n" )"
    if [ -z "$rr" ]; then
        no "(A) precision control $n is missing from the map"
    elif printf '%s' "$rr" | grep -q 'extent_suspect='; then
        no "(A) $n sits inside the same ERROR root but parsed cleanly — it must NOT be flagged: $rr"
    else
        ok "(A) $n (clean, inside the same ERROR root) is not flagged"
    fi
done
flaggedRows=$( grep -oE '<s [^>]* extent_suspect="[^"]*"' "$TMP/a.xml" | wc -l | tr -d ' ' )
hdrSyms=$( grep -oE '<!-- files=[^>]*-->' "$TMP/a.xml" | grep -oE ' extent_suspect_syms=[0-9]+' | sed 's/.*=//' )
[ -n "$hdrSyms" ] && [ "$hdrSyms" = "$flaggedRows" ] && [ "$flaggedRows" -gt 0 ] \
    && ok "(A) header extent_suspect_syms=$hdrSyms equals the $flaggedRows flagged rows" \
    || no "(A) header extent_suspect_syms='${hdrSyms:-absent}' vs $flaggedRows flagged rows"
defines "$TMP/a.xml" extent_suspect && defines "$TMP/a.xml" extent_suspect_syms \
    && ok "(A) the map legend defines extent_suspect= and extent_suspect_syms=" \
    || no "(A) the map legend does not define extent_suspect= / extent_suspect_syms= (define what you emit)"

# ── (B) the signature-swallow shape, spelled as legal C ───────────────────────────────────────────────
cap "$TMP/b.xml" "$TMP/head" --no-cache
for n in makePoint Point; do
    r="$( reasonOf "$( row "$TMP/b.xml" "$n" )" )"
    case ",$r," in *,head,*) ok "(B) $n carries extent_suspect with reason head ($r)";; *) no "(B) $n row lacks extent_suspect=…head…: $( row "$TMP/b.xml" "$n" )";; esac
done

# ── (C) the dissolved-container shape ─────────────────────────────────────────────────────────────────
cap "$TMP/c.xml" "$TMP/orphan" --no-cache
for n in add standalone another; do
    rr="$( row "$TMP/c.xml" "$n" )"
    r="$( reasonOf "$rr" )"
    if printf '%s' "$rr" | grep -q 't="method"'; then
        case ",$r," in *,error,*) ok "(C) scopeless method row $n carries extent_suspect with reason error";; *) no "(C) scopeless method row $n unflagged: $rr";; esac
    else
        no "(C) $n is no longer a scopeless method row — the fixture stopped reproducing: $rr"
    fi
done

# ── (D) --for, name-exact → the auto body walk ────────────────────────────────────────────────────────
cap "$TMP/d.xml" "$TMP/leak" --no-cache --for=clampQuantity
drow="$( grep -oE '<d [^>]*n="clampQuantity"[^>]*>' "$TMP/d.xml" | head -1 )"
brow="$( grep -oE '<b [^>]*n="clampQuantity"[^>]*>' "$TMP/d.xml" | head -1 )"
if [ -n "$( reasonOf "$drow" )" ]; then ok "(D) --for <d> row carries extent_suspect=\"$( reasonOf "$drow" )\""; else no "(D) --for <d> row lacks extent_suspect=: ${drow:-no <d> row}"; fi
if [ -n "$( reasonOf "$brow" )" ]; then ok "(D) --for <b> row carries extent_suspect=\"$( reasonOf "$brow" )\""; else no "(D) --for <b> row lacks extent_suspect=: ${brow:-no <b> row}"; fi
if defines "$TMP/d.xml" extent_suspect; then ok "(D) --for legend defines extent_suspect="; else no "(D) --for legend does not define extent_suspect="; fi

# ── (E) --expand ──────────────────────────────────────────────────────────────────────────────────────
cap "$TMP/e.xml" "$TMP/leak" --no-cache --expand=clampQuantity
erow="$( grep -oE '<b [^>]*n="clampQuantity"[^>]*>' "$TMP/e.xml" | head -1 )"
if [ -n "$( reasonOf "$erow" )" ]; then ok "(E) --expand <b> row carries extent_suspect=\"$( reasonOf "$erow" )\""; else no "(E) --expand <b> row lacks extent_suspect=: ${erow:-no <b> row}"; fi
if defines "$TMP/e.xml" extent_suspect; then ok "(E) --expand legend defines extent_suspect="; else no "(E) --expand legend does not define extent_suspect="; fi

# ── (F) --skipped: the file is findable, with its count ───────────────────────────────────────────────
cap "$TMP/f.xml" "$TMP/hot" --no-cache --skipped
cap "$TMP/fm.xml" "$TMP/hot" --no-cache --metrics
for p in leak.cpp head.c orphan.cpp; do
    h="$( grep -oE "<h p=\"$p\"[^>]*>" "$TMP/f.xml" | head -1 )"
    want=$( python3 - "$TMP/fm.xml" "$p" <<'PY'
import re, sys
doc = open(sys.argv[1]).read()
m = re.search(r'<f p="%s"[^>]*>(.*?)</f>' % re.escape(sys.argv[2]), doc, re.S)
print(len(re.findall(r'<s [^>]* extent_suspect="', m.group(1))) if m else -1)
PY
)
    got="$( printf '%s' "$h" | grep -oE 'extent_suspect_syms="[0-9]+"' | grep -oE '[0-9]+' )"
    if printf '%s' "$h" | grep -qE 'why="[^"]*extent-suspect' && [ -n "$got" ] && [ "$got" = "$want" ]; then
        ok "(F) --skipped <h p=\"$p\"> why=…extent-suspect extent_suspect_syms=$got (= its flagged map rows)"
    else
        no "(F) --skipped row for $p wrong or missing (want extent_suspect_syms=$want): ${h:-no <h> row}"
    fi
done
grep -q '<h p="plain.cpp"' "$TMP/f.xml" && no "(F) the clean plain.cpp got an <h> row" || ok "(F) the clean plain.cpp has no <h> row"
grep -qE '<skipped [^>]* extent_suspect_files="3"' "$TMP/f.xml" && ok "(F) root extent_suspect_files=\"3\"" \
    || no "(F) root extent_suspect_files= is not 3: $( grep -oE '<skipped [^>]*>' "$TMP/f.xml" | head -1 | cut -c1-400 )"
defines "$TMP/f.xml" extent_suspect_syms && defines "$TMP/f.xml" extent_suspect_files && comments "$TMP/f.xml" | grep -q 'extent-suspect' \
    && ok "(F) --skipped legend defines extent_suspect_syms=, extent_suspect_files= and why=extent-suspect" \
    || no "(F) --skipped legend misses extent_suspect_syms= / extent_suspect_files= / extent-suspect"

# ── (G) --hotspots: excluded, disclosed, partition intact ─────────────────────────────────────────────
if command -v git >/dev/null 2>&1; then
    git -C "$TMP/hot" init -q >/dev/null 2>&1
    git -C "$TMP/hot" add -A >/dev/null 2>&1
    git -C "$TMP/hot" -c user.name=extentcheck -c user.email=extentcheck@example.invalid -c commit.gpgsign=false commit -q -m fixture >/dev/null 2>&1
    cap "$TMP/g.xml" "$TMP/hot" --no-cache --hotspots
    python3 - "$TMP/g.xml" "$TMP/fm.xml" > "$TMP/g.out" <<'PY'
import re, sys
hot = open(sys.argv[1]).read()
mp  = open(sys.argv[2]).read()
def attrs(tag):
    return dict(re.findall(r'(\w+)="([^"]*)"', tag))
def fileRows(p):
    m = re.search(r'<f p="%s"[^>]*>(.*?)</f>' % re.escape(p), mp, re.S)
    return [attrs(t) for t in re.findall(r'<s [^>]*>', m.group(1))] if m else []
root = re.search(r'<hotspots [^>]*>', hot)
if not root:
    print("FAIL (G) no <hotspots> root"); sys.exit(0)
ra = attrs(root.group(0))
rows = {a['p']: a for a in (attrs(t) for t in re.findall(r'<f [^>]*/>', hot))}
for p in ('plain.cpp', 'leak.cpp'):
    if p not in rows:
        print("FAIL (G) %s is not ranked" % p); continue
    sy = [s for s in fileRows(p) if s.get('t') in ('fn', 'method')]
    trusted = [s for s in sy if 'extent_suspect' not in s]
    flagged = [s for s in sy if 'extent_suspect' in s]
    want = sum(int(s['ccx']) for s in trusted)
    got = int(rows[p]['ccx'])
    print(("PASS" if got == want else "FAIL") + " (G) %s ccx=%d re-derives from its %d unflagged fn/method rows (want %d)" % (p, got, len(trusted), want))
    k = rows[p].get('extent_suspect_syms')
    if flagged:
        print(("PASS" if k == str(len(flagged)) else "FAIL") + " (G) %s discloses extent_suspect_syms=%s (flagged fn/method: %d)" % (p, k, len(flagged)))
    else:
        print(("PASS" if k is None else "FAIL") + " (G) %s carries no extent_suspect_syms= (nothing flagged)" % p)
    flaggedNames = {s['n'] for s in flagged}
    print(("FAIL" if rows[p].get('top') in flaggedNames else "PASS") + " (G) %s top=%s is not a flagged symbol" % (p, rows[p].get('top')))
for p in ('head.c', 'orphan.cpp'):
    print(("FAIL" if p in rows else "PASS") + " (G) %s (every fn/method flagged) is not ranked on garbage complexity" % p)
ues = ra.get('unranked_extent_suspect')
print(("PASS" if ues == '2' else "FAIL") + " (G) unranked_extent_suspect=%s counts head.c + orphan.cpp" % ues)
parts = int(ra['ranked']) + int(ra['unranked_no_churn']) + int(ra['unranked_no_complexity']) + int(ues or 0)
print(("PASS" if parts == int(ra['files']) else "FAIL") + " (G) ranked+unranked_no_churn+unranked_no_complexity+unranked_extent_suspect=%d = files=%s" % (parts, ra['files']))
# the LEGEND's equation must be the partition the root emits (CodeRabbit #135): the unconditional header comment spelled
# three buckets beside a nonzero fourth, so one document stated two identities and one of them was false. EVERY
# "… = files=" the legend states must parse as a sum of buckets the root carries, name unranked_extent_suspect= while
# it is nonzero, and hold on these counts (a bucket absent from the root reads as 0 — the legend's own "Absent" rule).
legend = '\n'.join(re.findall(r'<!--.*?-->', hot, re.S))
stated = len(re.findall(r'= files=', legend))
eqs = re.findall(r'((?:\w+= \+ )+\w+=) = files=', legend)
print(("PASS" if stated > 0 and len(eqs) == stated else "FAIL") + " (G) the legend states %d files= equation(s), %d parse as a sum of buckets" % (stated, len(eqs)))
for eq in eqs:
    terms = re.findall(r'(\w+)=', eq)
    unknown = [t for t in terms if t not in ra and t != 'unranked_extent_suspect']
    total = sum(int(ra.get(t, 0)) for t in terms)
    names = 'unranked_extent_suspect' in terms
    good = not unknown and total == int(ra['files']) and (names or int(ues or 0) == 0)
    print(("PASS" if good else "FAIL") + " (G) legend '%s = files=' %s unranked_extent_suspect= and sums to %d vs files=%s%s"
          % (eq, "names" if names else "OMITS", total, ra['files'], (" (not on the root: %s)" % ",".join(unknown)) if unknown else ""))
PY
    while IFS= read -r line; do
        case "$line" in PASS*) ok "${line#PASS }";; *) no "${line#FAIL }";; esac
    done < "$TMP/g.out"
    defines "$TMP/g.xml" unranked_extent_suspect && defines "$TMP/g.xml" extent_suspect_syms \
        && ok "(G) --hotspots legend defines unranked_extent_suspect= and extent_suspect_syms=" \
        || no "(G) --hotspots legend misses unranked_extent_suspect= / extent_suspect_syms="
    # ZERO-BUCKET CONTROL: a git corpus with nothing flagged keeps every byte — the fourth bucket enters neither the root
    # nor any legend equation at 0 (a fix that always appended the term would red here), and with RIPWIRE_BASE_BIN the
    # whole --hotspots document is byte-identical to the pre-change build.
    mkdir -p "$TMP/hot0"
    cp "$FIX/plain.cpp" "$TMP/hot0/"
    git -C "$TMP/hot0" init -q >/dev/null 2>&1
    git -C "$TMP/hot0" add -A >/dev/null 2>&1
    git -C "$TMP/hot0" -c user.name=extentcheck -c user.email=extentcheck@example.invalid -c commit.gpgsign=false commit -q -m fixture >/dev/null 2>&1
    cap "$TMP/g0.xml" "$TMP/hot0" --no-cache --hotspots
    grep -q '<hotspots ' "$TMP/g0.xml" && ! grep -q 'extent_suspect' "$TMP/g0.xml" \
        && ok "(G) zero-bucket control: plain.cpp alone carries no extent_suspect byte on the root or in any legend equation" \
        || no "(G) zero-bucket control carries extent_suspect vocabulary (or no <hotspots> root): $( grep -oE 'unranked_no_complexity=[^.]*files=' "$TMP/g0.xml" | head -1 )"
    if [ -n "${RIPWIRE_BASE_BIN:-}" ] && [ -x "${RIPWIRE_BASE_BIN}" ]; then
        "$RIPWIRE_BASE_BIN" "$TMP/hot0" --no-cache --hotspots >"$TMP/base_g0.xml" 2>/dev/null
        cmp -s "$TMP/g0.xml" "$TMP/base_g0.xml" && ok "(G) zero-bucket control --hotspots is byte-identical to RIPWIRE_BASE_BIN" \
            || no "(G) zero-bucket control --hotspots differs from RIPWIRE_BASE_BIN"
    else
        echo "  SKIP  (G) zero-bucket --hotspots byte-identity vs a pre-change build (set RIPWIRE_BASE_BIN)"
    fi
else
    echo "  SKIP  (G) git unavailable"
fi

# ── (H) control + mutation: the semicolons remove the leak AND every byte of the new vocabulary ────────
cap "$TMP/h_map.xml" "$TMP/ctl" --no-cache
cap "$TMP/h_met.xml" "$TMP/ctl" --no-cache --metrics
cap "$TMP/h_for.xml" "$TMP/ctl" --no-cache --for=clampQuantity
cap "$TMP/h_exp.xml" "$TMP/ctl" --no-cache --expand=clampQuantity
cap "$TMP/h_skp.xml" "$TMP/ctl" --no-cache --skipped
"$BIN" "$TMP/ctl" --no-cache --json >"$TMP/h_json" 2>/dev/null
ctlLeak=0
for n in $SWALLOWED; do
    row "$TMP/h_map.xml" "$n" | grep -q 'IndiaError::' && ctlLeak=$(( ctlLeak + 1 ))
done
if [ "$ctlLeak" -eq 0 ]; then ok "(H) mutation: with the semicolons, 0/4 functions leak into IndiaError::"; else no "(H) the control still leaks $ctlLeak/4 — it is not a control"; fi
if grep -l 'extent_suspect\|extent-suspect' "$TMP"/h_* >/dev/null 2>&1; then
    no "(H) the control carries the new vocabulary: $( grep -l 'extent_suspect\|extent-suspect' "$TMP"/h_* | xargs -n1 basename | tr '\n' ' ' )"
else
    ok "(H) the control carries none of extent_suspect / extent-suspect on map, --metrics, --for, --expand, --skipped, --json"
fi
if [ -n "${RIPWIRE_BASE_BIN:-}" ] && [ -x "${RIPWIRE_BASE_BIN}" ]; then
    for spec in "h_map.xml:" "h_met.xml:--metrics" "h_for.xml:--for=clampQuantity" "h_exp.xml:--expand=clampQuantity" "h_skp.xml:--skipped" "h_json:--json"; do
        out="${spec%%:*}"; flag="${spec#*:}"
        "$RIPWIRE_BASE_BIN" "$TMP/ctl" --no-cache $flag >"$TMP/base_$out" 2>/dev/null
        cmp -s "$TMP/$out" "$TMP/base_$out" && ok "(H) control ${flag:-map} is byte-identical to RIPWIRE_BASE_BIN" \
            || no "(H) control ${flag:-map} differs from RIPWIRE_BASE_BIN"
    done
else
    echo "  SKIP  (H) byte-identity vs a pre-change build (set RIPWIRE_BASE_BIN)"
fi

# ── (I) determinism, and the extraction bit across the cache ──────────────────────────────────────────
"$BIN" "$TMP/leak" --no-cache --metrics >"$TMP/i1.xml" 2>/dev/null
"$BIN" "$TMP/leak" --no-cache --metrics >"$TMP/i2.xml" 2>/dev/null
if cmp -s "$TMP/i1.xml" "$TMP/i2.xml"; then ok "(I) two cold runs are byte-identical"; else no "(I) two cold runs differ"; fi
"$BIN" "$TMP/leak" --cache="$TMP/ext.cache" --metrics >"$TMP/i_cold.xml" 2>/dev/null
"$BIN" "$TMP/leak" --cache="$TMP/ext.cache" --metrics >"$TMP/i_warm.xml" 2>/dev/null
XMLS+=( "$TMP/i1.xml" "$TMP/i_cold.xml" "$TMP/i_warm.xml" )
if cmp -s "$TMP/i_cold.xml" "$TMP/i_warm.xml"; then ok "(I) the cache-writing run and the warm read are byte-identical"; else no "(I) cold and warm cache runs differ"; fi
grep -q 'extent_suspect="error"' "$TMP/i_warm.xml" && ok "(I) the warm read still carries extent_suspect=\"error\" (the recovered bit rides the cache record)" \
    || no "(I) the warm read lost the error reason — the recovered bit did not survive the cache"

# ── (J) --json map ────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$TMP/leak" --no-cache --json >"$TMP/j.json" 2>/dev/null
python3 - "$TMP/j.json" > "$TMP/j.out" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("FAIL (J) --json does not parse: %s" % e); sys.exit(0)
rows = [s for f in d.get('r', []) for s in f.get('s', [])]
byName = {s.get('n'): s for s in rows}
cq = byName.get('clampQuantity', {})
print(("PASS" if cq.get('extent_suspect') == 'error' else "FAIL") + " (J) clampQuantity carries \"extent_suspect\":\"error\" (got %r)" % cq.get('extent_suspect'))
led = byName.get('Ledger', {})
print(("PASS" if 'extent_suspect' not in led else "FAIL") + " (J) Ledger carries no extent_suspect key")
n = sum(1 for s in rows if 'extent_suspect' in s)
print(("PASS" if d.get('extent_suspect_syms') == n and n > 0 else "FAIL") + " (J) header \"extent_suspect_syms\":%r equals %d flagged rows" % (d.get('extent_suspect_syms'), n))
PY
while IFS= read -r line; do
    case "$line" in PASS*) ok "${line#PASS }";; *) no "${line#FAIL }";; esac
done < "$TMP/j.out"

# ── (K) well-formedness ───────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    bad=0
    for x in "${XMLS[@]}"; do
        [ -s "$x" ] || continue
        xmllint --noout "$x" 2>/dev/null || { bad=1; no "(K) $( basename "$x" ) is not well-formed XML"; }
    done
    [ "$bad" -eq 0 ] && ok "(K) all ${#XMLS[@]} XML captures are well-formed"
else
    echo "  SKIP  (K) xmllint unavailable"
fi

# ── (U) the rule-level unit driver ────────────────────────────────────────────────────────────────────
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"
LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
if [ ! -f "$FLAGS_MK" ] || [ ! -f "$LINK_TXT" ]; then
    no "(U) cannot find CMake flags under $BUILD_DIR — the unit arm needs a CMake-built binary"
else
    # The compiler CMake drove (link.txt's first token), never a guess — jsonwalkcheck.sh's recipe and reason.
    CXX="$( awk 'NR==1{ print $1; exit }' "$LINK_TXT" )"
    [ -n "$CXX" ] && command -v "$CXX" >/dev/null 2>&1 || CXX="$( command -v c++ || command -v clang++ )"
    eval "CXX_FLAGS=(    $( grep -m1 '^CXX_FLAGS ='    "$FLAGS_MK" | sed 's/^CXX_FLAGS =//' ) )"
    eval "CXX_DEFINES=(  $( grep -m1 '^CXX_DEFINES ='  "$FLAGS_MK" | sed 's/^CXX_DEFINES =//' ) )"
    eval "CXX_INCLUDES=( $( grep -m1 '^CXX_INCLUDES =' "$FLAGS_MK" | sed 's/^CXX_INCLUDES =//' ) )"
    # VERIFY's debug arm reports through the diagnostics TU, so the driver links that one object (when present).
    DIAG_OBJ="$BUILD_DIR/CMakeFiles/ripwire.dir/src/infra/diagnostics.cpp.o"
    DIAG_LINK=(); [ -f "$DIAG_OBJ" ] && DIAG_LINK=( "$DIAG_OBJ" )
    if "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" "${CXX_INCLUDES[@]}" -I"$ROOT/src" \
         "$ROOT/test/extentsuspect_unit.cpp" "${DIAG_LINK[@]}" -o "$TMP/extentsuspect_unit" >"$TMP/u_build.log" 2>&1; then
        if "$TMP/extentsuspect_unit" >"$TMP/u_run.log" 2>&1; then
            ok "(U) extentsuspect_unit: $( grep -c '  PASS' "$TMP/u_run.log" | tr -d ' ' ) rule cases hold"
        else
            no "(U) extentsuspect_unit failed:"; grep FAIL "$TMP/u_run.log" | head -8 | sed 's/^/        /'
        fi
    else
        no "(U) extentsuspect_unit does not compile:"; grep -m4 -E 'error' "$TMP/u_build.log" | sed 's/^/        /'
    fi
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
