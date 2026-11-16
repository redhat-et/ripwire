#!/usr/bin/env bash
# lstiercapcheck.sh — the map inventory tier's <ls> ROW ceiling: the row list is bounded, the cut walks a
# priority order rather than path order, and it discloses itself in both dialects.
#
# WHY. The <inv> tier (src/mapinventory.h) prints one <ls p= n= f=> row per directory over the unshown files.
# Its two runaway guards bound the NAMES inside a row (kInventoryNameCeiling) and the ENTRIES above them
# (kInventoryEntryCap); before this gate neither bounded the number of ROWS. Measured on 2026-11-15 over 15
# repos: the ranked map holds within 16,879-27,664 B across a 10x range of repository size while <ls> runs
# 2,670 B (tmux) to 192,484 B (vscode) — 82.4 % of the vscode document. 2,102 of vscode's 2,534 rows were
# count-only (a path and a number, 52 % of the whole document) and 959 of those said n="1". The registration,
# its bands and what it does NOT claim are in docs/EVALS.md ("the map inventory tier's <ls> rows are
# unbounded", PRE-REGISTERED 2026-11-15).
#
# WHAT IS GATED, AND WHY EACH ARM CAN FAIL ON ITS OWN. docs/METHODOLOGY.md §9.1 names path order as the one
# order a cut may never walk, so a row ceiling without a priority order would turn a bounded answer into a
# chop. The fixture is therefore GENERATED in $TMP with path order deliberately ANTI-correlated with size:
# the smallest count-only directory sorts first (aa_small_01) and the largest sorts last (zz_big_60). A cap
# that kept a path-order prefix would keep aa_small_01 and drop zz_big_60, so arm (B2) fails on it; a cap
# with no order at all fails (B). The named directories are given alphabetically LATE names for the same
# reason: arm (C) is the registration's Band 1 (zero named code files lost) and a path-order cut fails it.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FAILED=0
fail() { printf '  FAIL  %s\n' "$*"; FAILED=$(( FAILED + 1 )); }
ok()   { if printf '  PASS  %s\n' "$*"; then return 0; else FAILED=$(( FAILED + 1 )); printf '  FAIL  could not write the PASS line for: %s\n' "$*"; return 0; fi; }
[ -x "$BIN" ] || { echo "lstiercapcheck: no binary at $BIN — build first"; exit 2; }
echo "lstiercapcheck: BIN=$BIN"

# The constants this gate reads from the source, so a change to either is a change to this gate's arithmetic.
SRC="$ROOT/src/mapinventory.h"
CO_CAP="$(  sed -n 's/.*kInventoryCountOnlyCap *= *\([0-9]*\).*/\1/p' "$SRC" | head -1 )"
DIR_CAP="$( sed -n 's/.*kInventoryDirCap *= *\([0-9]*\).*/\1/p'       "$SRC" | head -1 )"
if [ -n "$CO_CAP" ] && [ -n "$DIR_CAP" ]; then
    ok "(0) the caps are declared in mapinventory.h: count-only=$CO_CAP total=$DIR_CAP"
else
    fail "(0) kInventoryCountOnlyCap / kInventoryDirCap are not declared in src/mapinventory.h"
    echo "lstiercapcheck: FAILED=$FAILED"; exit 1
fi

# ── the generated fixture ───────────────────────────────────────────────────────────────────────────────────
# 60 count-only directories: aa_small_01 .. zz_big_60, holding 1..60 doc files, so size ASCENDS with path.
FIX="$TMP/tree"
mkdir -p "$FIX"
NCO=60
i=1
while [ "$i" -le "$NCO" ]; do
    if   [ "$i" -lt 20 ]; then pre=aa_small
    elif [ "$i" -lt 40 ]; then pre=mm_mid
    else                       pre=zz_big
    fi
    d="$FIX/$( printf '%s_%02d' "$pre" "$i" )"
    mkdir -p "$d"
    j=1
    while [ "$j" -le "$i" ]; do printf 'doc %d\n' "$j" > "$d/note_$j.md"; j=$(( j + 1 )); done
    i=$(( i + 1 ))
done
# 5 NAMED directories (code files, alphabetically late) and one ranked-into file at the root so the tier arms
mkdir -p "$FIX/src"
printf 'int top(void);\nint top(void){ return helper_a() + helper_b(); }\nint helper_a(void){ return 1; }\nint helper_b(void){ return 2; }\n' > "$FIX/src/top.c"
for n in 1 2 3 4 5; do
    d="$FIX/$( printf 'yy_named_%d' "$n" )"
    mkdir -p "$d"
    printf 'int named_fn_%d(void){ return %d; }\n' "$n" "$n" > "$d/mod_$n.c"
done

# The directory rows the tier CAN print: one per directory holding an UNSHOWN file. At --top-k=1 exactly one file
# is shown (src/top.c, the only file in src/), so src/ holds no unshown file and contributes no row: 60 + 5 + 1 - 1.
# The premise is asserted below from the answer's own listed= rather than assumed.
NDIRS=$(( NCO + 5 + 1 - 1 ))
run() { "$BIN" "$FIX" --no-cache --top-k=1 "$@" 2>"$TMP/err"; }
run >"$TMP/map"; rc=$?
run --legend=full >"$TMP/mapfull" 2>/dev/null   # files= carries a VALUE only in the full dialect (arm D)
[ "$rc" -eq 0 ] && [ -s "$TMP/map" ] || { echo "lstiercapcheck: the map run failed (rc=$rc)"; cat "$TMP/err"; exit 1; }
run --json >"$TMP/json"
run --legend=full >"$TMP/full"

# the tier, isolated — located by a QUOTED attribute value, because the legend COMMENT spells "<inv listed=
# unlisted=>" in prose and a bare "<inv" match starts inside it (this cost one inverted readout on 2026-11-15)
INV="$( grep -o '<inv listed="[0-9][^>]*>.*</inv>' "$TMP/map" )"
[ -n "$INV" ] || { echo "lstiercapcheck: no <inv> element on a --top-k=1 map of $NDIRS directories"; exit 1; }
LSROWS="$( printf '%s' "$INV" | grep -o '<ls p="[^"]*"[^>]*/>' )"
NROWS="$(  printf '%s\n' "$LSROWS" | grep -c '<ls ' )"
NAMEDROWS="$( printf '%s\n' "$LSROWS" | grep -c ' f="' || true )"
CONLY="$( printf '%s\n' "$LSROWS" | grep -v ' f="' || true )"
NCONLY="$( printf '%s\n' "$CONLY" | grep -c '<ls ' || true )"

# (A) the row list is BOUNDED — the defect this gate exists for
if [ "$NROWS" -le "$DIR_CAP" ]; then ok "(A) $NROWS <ls> rows is within the $DIR_CAP total backstop"; else fail "(A) $NROWS <ls> rows exceeds the $DIR_CAP backstop"; fi
if [ "$NCONLY" -le "$CO_CAP" ]; then ok "(A2) $NCONLY count-only rows is within the $CO_CAP allowance"; else fail "(A2) $NCONLY count-only rows exceeds the $CO_CAP allowance (unbounded row list)"; fi

# (A3) the cut DISCLOSES itself, with dirs_total re-derived OUTSIDE the binary (the fixture's own directory count)
if printf '%s' "$INV" | grep -q 'dirs_capped="1"'; then ok "(A3) dirs_capped=\"1\" is present on a cut tier"; else fail "(A3) the row list was cut with no dirs_capped=\"1\" — a silent cut (METHODOLOGY §9 principle 3)"; fi
GOT_TOTAL="$( printf '%s' "$INV" | sed -n 's/.*dirs_total="\([0-9]*\)".*/\1/p' )"
if [ "$GOT_TOTAL" = "$NDIRS" ]; then ok "(A4) dirs_total=$GOT_TOTAL equals the fixture's own $NDIRS directories"; else fail "(A4) dirs_total=[$GOT_TOTAL] but the fixture holds $NDIRS directories"; fi

# (A5) the premise NDIRS rests on: exactly one file is shown at --top-k=1, so exactly one directory drops out
if [ "$( printf '%s' "$INV" | sed -n 's/.*<inv listed="\([0-9]*\)".*/\1/p' )" = "1" ]; then ok "(A5) listed=1 — one file shown, so src/ contributes no row and dirs_total must be $NDIRS"; else fail "(A5) listed= is not 1, so this gate's dirs_total arithmetic no longer holds"; fi

# (B) PRIORITY ORDER: every count-only row kept has n= >= every count-only row cut. The fixture's sizes are
# 1..60 and the allowance is $CO_CAP, so the smallest kept size must be exactly 60 - CO_CAP + 1.
MINKEPT="$( printf '%s\n' "$CONLY" | sed -n 's/.*<ls p="[^"]*" n="\([0-9]*\)".*/\1/p' | sort -n | head -1 )"
WANTMIN=$(( NCO - CO_CAP + 1 ))
if [ "$MINKEPT" = "$WANTMIN" ]; then ok "(B) the kept count-only rows are the $CO_CAP largest (smallest kept n=$MINKEPT)"; else fail "(B) smallest kept count-only n=[$MINKEPT], want $WANTMIN — the cut did not walk size order"; fi

# (B2) the kept set is NOT a path-order prefix: the fixture's largest directory sorts LAST and its smallest FIRST
if printf '%s' "$INV" | grep -q '<ls p="zz_big_60"'; then ok "(B2) zz_big_60 survives although path order puts it last"; else fail "(B2) zz_big_60 was cut — the cut walked path order (METHODOLOGY §9.1)"; fi
if printf '%s' "$INV" | grep -q '<ls p="aa_small_01"'; then fail "(B2b) aa_small_01 (1 file) survives although 59 larger directories exist — a path-order prefix"; else ok "(B2b) aa_small_01 is cut, as the smallest count-only directory"; fi

# (B3) the SURVIVORS are re-sorted to path order, so the tier's documented emit order is unchanged
printf '%s\n' "$LSROWS" | sed -n 's/<ls p="\([^"]*\)".*/\1/p' >"$TMP/paths"
if LC_ALL=C sort -c "$TMP/paths" 2>/dev/null; then ok "(B3) the surviving rows are emitted in path order"; else fail "(B3) the surviving rows are not in path order"; fi

# (C) BAND 1 — zero named code files lost. All five named directories must survive a cut of 60 others.
MISSING=
for n in 1 2 3 4 5; do
    printf '%s' "$INV" | grep -q "<ls p=\"yy_named_$n\"[^>]* f=\"[^\"]*mod_$n\.c" || MISSING="$MISSING yy_named_$n"
done
if [ -z "$MISSING" ]; then ok "(C) every named-code directory survives the cut (Band 1: zero named files lost)"; else fail "(C) named directories lost to the cut:$MISSING"; fi

# (D) the accounting invariant holds through a cut: the cut removes ROWS, never files from listed+unlisted.
# Read from the FULL dialect: files= carries a value only there (in the compact map it survives as legend prose
# with no value, so the compact <inv>'s own "sum = files=" clause cannot be checked against the same answer).
L="$( printf '%s' "$INV" | sed -n 's/.*<inv listed="\([0-9]*\)".*/\1/p' )"
U="$( printf '%s' "$INV" | sed -n 's/.*unlisted="\([0-9]*\)".*/\1/p' )"
FILES="$( grep -o 'files=[0-9][0-9]*' "$TMP/mapfull" | head -1 | cut -d= -f2 )"
if [ -n "$L" ] && [ -n "$U" ] && [ "$(( L + U ))" = "$FILES" ]; then ok "(D) listed($L) + unlisted($U) = files=$FILES through a row cut"; else fail "(D) listed($L) + unlisted($U) != files=[$FILES]"; fi

# (E) the cut is RECOVERABLE, not a dead end (§9.1): dirs_next= must be present, run, and reach a cut directory
NEXT="$( printf '%s' "$INV" | sed -n 's/.*dirs_next="\([^"]*\)".*/\1/p' | sed 's/&quot;/"/g; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g' )"
if [ -n "$NEXT" ]; then
    ok "(E) dirs_next= is present on a cut tier"
    # shellcheck disable=SC2086
    if "$BIN" "$FIX" --no-cache $NEXT >"$TMP/next" 2>"$TMP/nexterr" && [ -s "$TMP/next" ]; then
        ok "(E2) dirs_next= runs on the same root and answers"
        if grep -q 'aa_small_01' "$TMP/next"; then ok "(E3) dirs_next= reaches a directory the cut removed"; else fail "(E3) dirs_next= ran but does not reach the cut directory aa_small_01"; fi
    else
        fail "(E2) dirs_next= [$NEXT] did not run: $( head -2 "$TMP/nexterr" )"
    fi
else
    fail "(E) the row list was cut with no dirs_next= — a dead-end cut (METHODOLOGY §9.1)"
fi

# (F) JSON parity — the tier is ONE selection both dialects render, so both carry the cut
if grep -q '"dirs_capped":true' "$TMP/json" && grep -q "\"dirs_total\":$NDIRS" "$TMP/json" && grep -q '"dirs_next":"' "$TMP/json"; then
    ok "(F) the JSON dialect carries dirs_capped / dirs_total / dirs_next"
else
    fail "(F) the JSON dialect does not disclose the row cut"
fi
JROWS="$( grep -o '"ls":\[' "$TMP/json" >/dev/null 2>&1 && true; grep -o '{"p":"[^"]*","n":[0-9]*' "$TMP/json" | grep -c . || true )"
if [ "${JROWS:-0}" -ge "$NROWS" ]; then ok "(F2) the JSON tier carries at least the XML tier's $NROWS rows"; else fail "(F2) JSON rows [$JROWS] fewer than XML rows $NROWS"; fi

# (G) the attribute is DOCUMENTED where the reader meets it — a clause written only into the emitter ships
# undocumented, which is how implementors= nearly shipped silently (2026-11-12)
if grep -q 'dirs_capped' "$TMP/map"; then
    if grep -o '<!--.*-->' "$TMP/map" | grep -q 'dirs_capped'; then ok "(G) the default (compact) legend documents dirs_capped"; else fail "(G) dirs_capped is emitted but absent from the compact legend — register the row in src/compactlegend.h, not only in the emitter"; fi
fi
if grep -q 'dirs_capped' "$TMP/full"; then ok "(G2) the full legend documents dirs_capped"; else fail "(G2) dirs_capped is absent from --legend=full"; fi

# (H) NO CUT, NO VOCABULARY: a tier under both caps must carry none of the three attributes
if "$BIN" "$ROOT/test/mapinvfix" --no-cache --top-k=3 >"$TMP/small" 2>/dev/null; then
    if grep -q 'dirs_capped\|dirs_total\|dirs_next' "$TMP/small"; then fail "(H) the small fixture's uncut tier claims a row cut"; else ok "(H) an uncut tier carries no dirs_capped / dirs_total / dirs_next"; fi
else
    fail "(H) the map of test/mapinvfix did not run"
fi

echo "lstiercapcheck: FAILED=$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
