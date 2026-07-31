#!/usr/bin/env bash
# selectorchaincheck.sh — the §P8 "contract-level" seam gate: the natural verb CHAINS must not lose
# information at the handoff.
#
# Three seams, one gate:
#
#   (1) --expand / --outline accept the `file:name` selector every sibling verb already accepts.
#       --callers/--impact/--uses/--hotspots/... emit `n=` + `p=` and nothing else; the documented chain is
#       `--callers=X` → pick a row → fetch that body. Through a BARE name that chain is ambiguous (`main`
#       is 37 symbols in this tree); the disambiguator is sitting right there in `p=`. Before this gate,
#       `--expand=src/graph.h:rankGraphTeleport` was parsed as a LINE RANGE, warned "malformed range", and
#       then refused the leftover `src/graph.h` as a typo'd symbol name.
#       Grammar (documented in --help):
#           NAME                    whole body                     (unchanged)
#           NAME:START-END          body slice                     (unchanged)
#           FILE:NAME               file-qualified selector         (NEW)
#           FILE:LINE:NAME          ditto, a pasted `p="path:line"` locator + the row's n=   (NEW)
#           FILE:NAME:START-END     selector AND slice              (NEW)
#       Disambiguation rule: the text after the LAST ':' decides. A NUMBER or N-M is a range (or, bare,
#       the pre-existing degrade path); anything else makes the whole token a selector, resolved through
#       the SAME resolveAllByNameQualified() --callers/--callees/--impact use — one rule, one resolver.
#
#   (2) --affected / --situ / --test-gate accept `path:line`. --hotspots/--clones/--grep/--lint/
#       --quality-delta all emit `path:line` as their PRIMARY locator, so a hotspot row could not be
#       pasted into --affected. A trailing `:N` / `:N-M` locator is now stripped off each file argument.
#
#   (3) --outline's refusal names --outline (§P10 X7: it named --expand, because both route through
#       parseExpandToken).
#
# Byte-identity: every PLAIN form (bare name, NAME:START-END, path, ./path, the default map) must be
# byte-identical to the PRE-CHANGE binary. Set RIPWIRE_BASE_BIN=<path to the pre-change ripwire> to run
# that arm; it SKIPs (loudly) when unset, so the gate is still useful in CI.
#
# Usage:  test/selectorchaincheck.sh   |   RIPWIRE_BIN=asan/ripwire test/selectorchaincheck.sh
#         RIPWIRE_BASE_BIN=/tmp/ripwire.pre test/selectorchaincheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASE="${RIPWIRE_BASE_BIN:-}"
fail=0
ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "selectorchaincheck: BIN=$BIN  BASE=${BASE:-<unset>}"

# Warm one shared cache in our own scratch TMPDIR so the ~40 invocations below stay fast and hermetic.
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
run(){     ( cd "$ROOT" && TMPDIR="$TMP" "$BIN"  . "$@" ); }
runbase(){ ( cd "$ROOT" && TMPDIR="$TMP" "$BASE" . "$@" ); }
run --top-k=1 >/dev/null 2>&1     # prime the cache

# bodies: the p= of every emitted <b>/<o> element, sorted
bset(){ printf '%s' "$1" | grep -oE '<[bo] [^>]*p="[^"]*"' | grep -oE 'p="[^"]*"' | sort | tr '\n' ' '; }
bcnt(){ printf '%s' "$1" | grep -o '<b t=' | wc -l | tr -d ' '; }
ocnt(){ printf '%s' "$1" | grep -o '<o t=' | wc -l | tr -d ' '; }

# ── (a) FILE:NAME selects the symbol, and equals the bare-name form when the name is unambiguous ──────
A_Q="$( run --top-k=0 --expand=src/graph.h:rankGraphTeleport 2>/dev/null )"
A_B="$( run --top-k=0 --expand=rankGraphTeleport            2>/dev/null )"
case "$A_Q" in
  *'n="rankGraphTeleport"'*'PROFILE_SCOPE_DESCRIBE'*) ok "(a) --expand=src/graph.h:rankGraphTeleport returns that symbol's BODY" ;;
  *) no "(a) --expand=src/graph.h:rankGraphTeleport did not return the body (got ${#A_Q} bytes)" ;;
esac
[ -n "$A_Q" ] && [ "$A_Q" = "$A_B" ] \
  && ok "(a) FILE:NAME == bare NAME when unambiguous (byte-identical)" \
  || no "(a) FILE:NAME differs from the bare-name form for an unambiguous symbol"

# ── (b) the CANONICAL CHAIN: --callers=X → pick a row (n= + p="path:line") → --expand=<p>:<n> ─────────
# Exactly what §P8 says is impossible today. The row's p= carries a LINE, so this also exercises the
# path:line strip inside the selector's file half.
C="$( run --callers=rankGraphTeleport 2>/dev/null )"
ROW="$( printf '%s' "$C" | tr '<' '\n' | grep -m1 -E '^s t=' )"
RN="$( printf '%s' "$ROW" | grep -oE 'n="[^"]*"' | head -1 | sed 's/n="//;s/"//' )"
RP="$( printf '%s' "$ROW" | grep -oE 'p="[^"]*"' | head -1 | sed 's/p="//;s/"//' )"
if [ -n "$RN" ] && [ -n "$RP" ]; then
    CH="$( run --top-k=0 "--expand=$RP:$RN" 2>/dev/null )"
    RPF="${RP%:*}"                                   # the row locator minus its :line
    { [ "$( bcnt "$CH" )" = 1 ] && printf '%s' "$CH" | grep -q "p=\"$RPF\"" && printf '%s' "$CH" | grep -q "n=\"$RN\""; } \
      && ok "(b) chain --callers=rankGraphTeleport → --expand=$RP:$RN → exactly that one def" \
      || no "(b) chain --expand=$RP:$RN did not resolve to exactly $RPF's $RN (bodies=$( bcnt "$CH" ))"
else
    no "(b) could not read a caller row out of --callers=rankGraphTeleport"
fi

# ── (b2) an OVERLOADED name: `empty` has 3 defs; the selector must pick exactly one ───────────────────
E_ALL="$( run --top-k=0 --expand=empty              2>/dev/null )"
E_ONE="$( run --top-k=0 --expand=src/notes.h:empty  2>/dev/null )"
{ [ "$( bcnt "$E_ALL" )" -ge 3 ] && [ "$( bcnt "$E_ONE" )" = 1 ] && printf '%s' "$E_ONE" | grep -q 'p="./src/notes.h"'; } \
  && ok "(b2) overloaded 'empty': bare=$( bcnt "$E_ALL" ) defs, src/notes.h:empty = exactly 1 (notes.h)" \
  || no "(b2) overload disambiguation wrong (bare=$( bcnt "$E_ALL" ) qualified=$( bcnt "$E_ONE" ))"

# ── (b3) FILE:NAME:START-END — selector AND slice compose ────────────────────────────────────────────
S_Q="$( run --top-k=0 --expand=src/notes.h:empty:1-1 2>/dev/null )"
S_P="$( run --top-k=0 --expand=empty:1-1             2>/dev/null )"
{ [ "$( bcnt "$S_Q" )" = 1 ] && printf '%s' "$S_Q" | grep -q 'lines="1-1' ; } \
  && ok "(b3) --expand=FILE:NAME:START-END slices the SELECTED def (lines=1-1, 1 body)" \
  || no "(b3) FILE:NAME:START-END did not compose (bodies=$( bcnt "$S_Q" ))"
printf '%s' "$S_P" | grep -q 'lines="1-1' \
  && ok "(b3) plain NAME:START-END still slices (unchanged)" \
  || no "(b3) plain NAME:START-END regressed"

# ── (c) --outline takes the same selector, and its refusal names --outline (§P10 X7) ─────────────────
O_ONE="$( run --top-k=0 --outline=src/notes.h:empty 2>/dev/null )"
{ [ "$( ocnt "$O_ONE" )" = 1 ] && printf '%s' "$O_ONE" | grep -q 'p="./src/notes.h"'; } \
  && ok "(c) --outline=src/notes.h:empty → exactly the notes.h def" \
  || no "(c) --outline selector wrong (outlines=$( ocnt "$O_ONE" ))"
OERR="$( run --top-k=0 --outline=nosuch.h:zzznotasymbol 2>&1 >/dev/null )"
case "$OERR" in
  *'--expand'*) no "(c) --outline's refusal still names --expand (X7): $OERR" ;;
  *'--outline=nosuch.h:zzznotasymbol'*) ok "(c) --outline refusal names --outline and echoes the SELECTOR" ;;
  *) no "(c) --outline refusal did not echo the selector: $OERR" ;;
esac

# ── (d) --affected accepts a pasted `path:line` locator ───────────────────────────────────────────────
D_L="$( run --affected=src/graph.h:1148 2>/dev/null )"
D_P="$( run --affected=src/graph.h      2>/dev/null )"
tset(){ printf '%s' "$1" | grep -oE '<test p="[^"]*"' | sort | tr '\n' ' '; }
{ [ -n "$( tset "$D_P" )" ] && [ "$( tset "$D_L" )" = "$( tset "$D_P" )" ]; } \
  && ok "(d) --affected=src/graph.h:1148 ≡ --affected=src/graph.h (same test set)" \
  || no "(d) --affected path:line ≠ path (line=[$( tset "$D_L" )] plain=[$( tset "$D_P" )])"
D_R="$( run --affected=src/graph.h:1148-1200 2>/dev/null )"
[ "$( tset "$D_R" )" = "$( tset "$D_P" )" ] \
  && ok "(d) --affected=path:N-M also strips the locator" \
  || no "(d) --affected=path:N-M not stripped"

# ── (d2) the same strip on --situ / --test-gate (the other file-list verbs) ───────────────────────────
sline(){ printf '%s' "$1" | head -1; }
T_L="$( run --situ=src/graph.h:1148 2>/dev/null )"; T_P="$( run --situ=src/graph.h 2>/dev/null )"
[ -n "$T_P" ] && [ "$T_L" = "$T_P" ] \
  && ok "(d2) --situ=src/graph.h:1148 ≡ --situ=src/graph.h" \
  || no "(d2) --situ path:line ≠ path ($( sline "$T_L" ) vs $( sline "$T_P" ))"
G_L="$( run --test-gate=src/graph.h:1148 2>/dev/null )"; G_P="$( run --test-gate=src/graph.h 2>/dev/null )"
[ -n "$G_P" ] && [ "$G_L" = "$G_P" ] \
  && ok "(d2) --test-gate=src/graph.h:1148 ≡ --test-gate=src/graph.h" \
  || no "(d2) --test-gate path:line ≠ path"

# ── (e) a MISSING selector refuses, naming the selector (not the leftover half), exit 1, empty stdout ─
EOUT="$( run --top-k=0 --expand=nosuch.h:foo 2>"$TMP/e.err" )"; erc=$?
EERR="$( cat "$TMP/e.err" )"
{ [ "$erc" = 1 ] && [ -z "$EOUT" ] && printf '%s' "$EERR" | grep -q 'nosuch.h:foo'; } \
  && ok "(e) --expand=nosuch.h:foo refuses (exit 1, empty stdout) naming the SELECTOR" \
  || no "(e) missing-selector refusal wrong (exit=$erc stdout=${#EOUT}B err=$EERR)"
case "$EERR" in
  *'malformed range'*) no "(e) still reports a 'malformed range' for a FILE:NAME selector" ;;
  *) ok "(e) no bogus 'malformed range' warning for a FILE:NAME selector" ;;
esac
# a genuinely malformed RANGE must still degrade-and-warn, unchanged
MERR="$( run --top-k=0 --expand=rankGraphTeleport:5-x 2>&1 >/dev/null )"
case "$MERR" in
  *'malformed range'*) ok "(e) a real malformed range (NAME:5-x) still degrades with its warning" ;;
  *) no "(e) lost the malformed-range degrade path: $MERR" ;;
esac

# ── (f) byte-identity of every PLAIN form vs the pre-change binary ────────────────────────────────────
if [ -n "$BASE" ] && [ -x "$BASE" ]; then
    bid=0
    for args in "--top-k=1" \
                "--top-k=0 --expand=rankGraphTeleport" \
                "--top-k=0 --expand=rankGraphTeleport:5-10" \
                "--top-k=0 --expand=./src/graph.h::rankGraphTeleport" \
                "--top-k=0 --outline=empty" \
                "--affected=src/graph.h" \
                "--affected=./src/graph.h" \
                "--situ=src/graph.h"
    do
        # shellcheck disable=SC2086
        run     $args >"$TMP/new.out" 2>"$TMP/new.err"; nrc=$?
        # shellcheck disable=SC2086
        runbase $args >"$TMP/old.out" 2>"$TMP/old.err"; orc=$?
        if ! cmp -s "$TMP/new.out" "$TMP/old.out" || [ "$nrc" != "$orc" ]; then
            no "(f) NOT byte-identical to the pre-change binary: ripwire . $args (exit $nrc vs $orc)"; bid=1
        fi
    done
    [ "$bid" = 0 ] && ok "(f) all 8 plain forms byte-identical to the pre-change binary"
else
    skip "(f) byte-identity vs pre-change binary (set RIPWIRE_BASE_BIN=<path>)"
fi

# ── (g) determinism + G4 on the new forms ────────────────────────────────────────────────────────────
[ "$( run --top-k=0 --expand=src/graph.h:rankGraphTeleport 2>/dev/null )" = "$A_Q" ] \
  && ok "(g) selector form deterministic (byte-identical run-to-run)" || no "(g) selector form non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    { printf '%s' "$A_Q" | xmllint --noout - 2>/dev/null && printf '%s' "$O_ONE" | xmllint --noout - 2>/dev/null \
      && printf '%s' "$D_L" | xmllint --noout - 2>/dev/null; } \
      && ok "(g) G4: selector-form output well-formed XML" || no "(g) G4: selector-form output malformed"
else
    skip "(g) G4 xmllint (not installed)"
fi

# ── (h) --help documents the grammar ─────────────────────────────────────────────────────────────────
H="$( "$BIN" --help 2>&1 )"
printf '%s' "$H" | grep -q 'FILE:NAME' \
  && ok "(h) --help documents the FILE:NAME selector grammar" \
  || no "(h) --help does not document FILE:NAME"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
