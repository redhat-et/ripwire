#!/usr/bin/env bash
# usescheck.sh — the ABS-3 reference / use-site index gate (--uses=SYM + --external-surface).
#
#   test/usescheck.sh                        # uses build/ripwire on test/usesfix
#   RIPWIRE_BIN=asan/ripwire test/usescheck.sh
#
# The fixture test/usesfix (store.h + store.cpp) exercises EVERY use-site role:
#   import   #include "store.h"  (store.cpp:9)
#   extends  Widget : Base       (store.cpp:12)
#   call     counter() :21 · compute() :23 · printf() :24 (printf is external)
#   write    total = / += / ++   on store.cpp:20,21,22   (total is ALSO read — the precision probe)
#   read     total used as a value on store.cpp:20,23,24
# The gate asserts: the exact use-sites with the correct ROLE + file:line; the read-vs-write precision
# (a var both read AND written); the external-surface set-difference (contains `printf`, excludes every
# in-corpus-defined name); determinism (run twice, byte-identical); cache transparency (warm == cold);
# and XML well-formedness. Exits non-zero on any failure. Does NOT edit test/regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/usesfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]   || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ]|| { echo "no test/usesfix dir — fixture missing"; exit 2; }

echo "usescheck: BIN=$BIN  CORPUS=$CORPUS"

# helper: run --uses=SYM and emit one "role basename:line" line per use-site (path reduced to its
# basename so the assertions are independent of where the corpus lives — abs vs repo-relative).
uses(){ "$BIN" "$CORPUS" --uses="$1" --no-cache 2>/dev/null | grep -o 'role="[a-z]*" p="[^"]*"' \
        | sed -E 's/role="([a-z]*)" p="([^"]*\/)?([^"/]*)"/\1 \3/'; }
# helper: assert a specific "role basename:line" is present in a --uses=SYM result
has_site(){ uses "$1" | grep -qxF "$2"; }

# ── 1) determinism — same input, byte-identical use-site index run-to-run ──────────────────────────────
"$BIN" "$CORPUS" --uses=total --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --uses=total --no-cache >"$TMP/b" 2>/dev/null
diff -q "$TMP/a" "$TMP/b" >/dev/null && ok "determinism (byte-identical, $(wc -c <"$TMP/a" | tr -d ' ') B)" || no "determinism (non-deterministic output)"

# ── 2) EXACT use-site set for `total` — the read/write precision probe (read AND written) ───────────────
#    total is: WRITE on 20,21,22 and READ on 20,23,24. The same line 20 (`total = total + 1`) is BOTH.
WANT_TOTAL="$( printf 'read store.cpp:20\nwrite store.cpp:20\nwrite store.cpp:21\nwrite store.cpp:22\nread store.cpp:23\nread store.cpp:24\n' | sort )"
GOT_TOTAL="$( uses total | sort )"
if [ "$GOT_TOTAL" = "$WANT_TOTAL" ]; then
    ok "total use-sites exact (read+write on 20; write 21,22; read 23,24)"
else
    no "total use-site set mismatch"; printf '    want:\n%s\n    got:\n%s\n' "$WANT_TOTAL" "$GOT_TOTAL"
fi

# ── 2b) the precision check spelled out: writes are WRITE, reads are READ (a mislabel is a real bug) ────
has_site total "write store.cpp:21" && ok "write site labeled write (total += counter() @21)" || no "total @21 not labeled write"
has_site total "write store.cpp:22" && ok "write site labeled write (total++ @22)"            || no "total @22 not labeled write"
has_site total "read store.cpp:24"  && ok "read site labeled read (printf arg total @24)"     || no "total @24 not labeled read"
# the both-read-and-written line: line 20 must carry BOTH a read and a write
{ has_site total "read store.cpp:20" && has_site total "write store.cpp:20"; } \
    && ok "line 20 is BOTH read AND write (total = total + 1)" || no "line 20 missing read+write pair"

# ── 3) each remaining role on its exact line: call / import / extends ───────────────────────────────────
has_site counter "call store.cpp:21"  && ok "call role: counter() @21"          || { no "counter() call @21 missing"; uses counter; }
has_site compute "call store.cpp:23"  && ok "call role: compute() @23"          || { no "compute() call @23 missing"; uses compute; }
has_site store   "import store.cpp:9"  && ok 'import role: #include "store.h" @9' || { no "include import @9 missing"; uses store; }
has_site Base    "extends store.cpp:12" && ok "extends role: Widget : Base @12"  || { no "Widget:Base extends @12 missing"; uses Base; }

# ── 3b) a write must NOT be reported as a read and vice-versa (no role leakage on `total`) ──────────────
uses total | grep -qxF "read store.cpp:21"  && { no "line 21 (a WRITE) wrongly also reported as read"; } || ok "no spurious read on write-only line 21"
uses total | grep -qxF "write store.cpp:24" && { no "line 24 (a READ) wrongly also reported as write"; } || ok "no spurious write on read-only line 24"

# ── 3c) a definition's OWN name is NOT a use-site (def names must not leak as reads) ────────────────────
#    `compute` is defined (store.h decl + store.cpp def) and called ONCE (line 23) → exactly one use-site.
NCOMPUTE="$( "$BIN" "$CORPUS" --uses=compute --no-cache 2>/dev/null | grep -o 'count="[0-9]*"' | grep -o '[0-9]*' )"
[ "$NCOMPUTE" = "1" ] && ok "definition name not counted as a use (compute count=1, the call only)" || { no "compute use-count=${NCOMPUTE:-?} (expected 1 — def name leaked?)"; uses compute; }

# ── 4) external flag on --uses: printf is external (no in-corpus def), counter is NOT ───────────────────
"$BIN" "$CORPUS" --uses=printf  --no-cache 2>/dev/null | grep -q 'external="1"' && ok 'printf marked external="1" (no in-corpus def)' || no "printf not marked external"
"$BIN" "$CORPUS" --uses=counter --no-cache 2>/dev/null | grep -q 'external="0"' && ok 'counter marked external="0" (defined in store.h)'  || no "counter wrongly marked external"

# ── 5) external-surface set-difference: contains the external name, EXCLUDES every in-corpus-defined name ─
SURF="$( "$BIN" "$CORPUS" --external-surface --no-cache 2>/dev/null | grep -o 'n="[A-Za-z_][A-Za-z0-9_]*"' | sed 's/n="//;s/"$//' | sort -u )"
printf '%s\n' "$SURF" | grep -qxF "printf" && ok "external-surface CONTAINS the external name (printf)" || { no "external-surface missing printf"; printf '    surface: %s\n' "$SURF"; }
miss=0
for d in compute counter Base Widget run; do
    printf '%s\n' "$SURF" | grep -qxF "$d" && { no "external-surface WRONGLY contains in-corpus-defined name: $d"; miss=1; }
done
[ "$miss" -eq 0 ] && ok "external-surface EXCLUDES every in-corpus-defined name (set-difference correct)"

# ── 5b) §P11.9: --external-surface splits per REFERENCING-FILE language — a name called from BOTH a
# C file and a Bash file (e.g. printf) must NOT merge into one row; each language gets its own <x>,
# and the per-lang refs must sum back to what a single merged row would have shown pre-fix.
LANGFIX="$ROOT/test/extsurflangfix"
LSURF="$( "$BIN" "$LANGFIX" --external-surface --no-cache 2>/dev/null )"
printf '%s' "$LSURF" | xmllint --noout - >/dev/null 2>&1 && ok "extsurflangfix xml well-formed" || no "extsurflangfix xml malformed: $LSURF"
PRINTF_ROWS="$( printf '%s' "$LSURF" | grep -oE '<x n="printf"[^/]*/>' )"
PRINTF_ROW_COUNT="$( printf '%s\n' "$PRINTF_ROWS" | grep -c '<x ' || true )"
[ "$PRINTF_ROW_COUNT" = "2" ] && ok "--external-surface: printf splits into 2 rows (one per referencing language)" \
                              || no "--external-surface: printf did not split into 2 lang rows (got $PRINTF_ROW_COUNT): $LSURF"
printf '%s\n' "$PRINTF_ROWS" | grep -q 'lang="c"'  && ok "--external-surface: printf's C-file call carries lang=\"c\""  || no "--external-surface: no lang=\"c\" printf row: $PRINTF_ROWS"
printf '%s\n' "$PRINTF_ROWS" | grep -q 'lang="sh"' && ok "--external-surface: printf's Bash call carries lang=\"sh\"" || no "--external-surface: no lang=\"sh\" printf row: $PRINTF_ROWS"
SUMMED_REFS="$( printf '%s\n' "$PRINTF_ROWS" | grep -oE 'refs="[0-9]+"' | grep -oE '[0-9]+' | awk '{s+=$1} END{print s}' )"
[ "$SUMMED_REFS" = "2" ] && ok "--external-surface: printf's per-lang refs sum to 2 (the pre-split combined total)" \
                         || no "--external-surface: printf's per-lang refs summed to '$SUMMED_REFS', expected 2"
LTOTAL="$( printf '%s' "$LSURF" | grep -oE 'names="[0-9]+"' | grep -oE '[0-9]+' )"
LROWS="$( printf '%s\n' "$LSURF" | grep -oE '<x ' | wc -l | tr -d ' ' )"
[ "$LTOTAL" = "$LROWS" ] && ok "--external-surface: names= (total) reconciles with the actual post-split row count ($LROWS)" \
                         || no "--external-surface: names=\"$LTOTAL\" does not match emitted row count $LROWS"

# ── 6) cache transparency — a warm --cache run must equal a cold --no-cache run (round-trips role+line) ─
rm -f "$TMP/c.bin"
"$BIN" "$CORPUS" --uses=total --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null   # cold: builds the cache
"$BIN" "$CORPUS" --uses=total --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null   # warm: reads it back
COLDNC="$( "$BIN" "$CORPUS" --uses=total --no-cache 2>/dev/null )"            # ground truth (no cache at all)
diff -q "$TMP/cold" "$TMP/warm" >/dev/null && printf '%s' "$COLDNC" | diff -q "$TMP/warm" - >/dev/null \
    && ok "cache transparency (warm == cold; role+line round-trip through FileFacts)" \
    || { no "cache transparency broken (--cache changes --uses output)"; diff "$TMP/cold" "$TMP/warm" | head -4; }
# same for the external surface (it also reads the cached refs)
rm -f "$TMP/c2.bin"
"$BIN" "$CORPUS" --external-surface --cache="$TMP/c2.bin" >"$TMP/es_cold" 2>/dev/null
"$BIN" "$CORPUS" --external-surface --cache="$TMP/c2.bin" >"$TMP/es_warm" 2>/dev/null
diff -q "$TMP/es_cold" "$TMP/es_warm" >/dev/null && ok "external-surface cache transparency (warm == cold)" || no "external-surface warm != cold"

# ── 7) XML well-formed: --uses and --external-surface must pass xmllint (skip if absent) ────────────────
if command -v xmllint >/dev/null 2>&1; then
    "$BIN" "$CORPUS" --uses=total --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null && ok "--uses xml well-formed" || no "--uses xml malformed"
    "$BIN" "$CORPUS" --external-surface --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null && ok "--external-surface xml well-formed" || no "--external-surface xml malformed"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
