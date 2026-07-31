#!/usr/bin/env bash
# abicheck.sh — the gate for `--stray-content --abi`, the cross-branch ABI-BREAK check (src/abicheck.h).
#
#   test/abicheck.sh
#   CTXPACK_BIN=asan/ctxpack test/abicheck.sh
#
# The fixture is BUILT here, not committed (same reasoning as crossrefcheck.sh): the verb reads git refs,
# so the corpus has to be a real repository with a real ref graph. Fixed author/committer dates keep it
# byte-reproducible. The motivating bug (IDEAS_fieldNotes_2026-07-24.md §5 / the task this file gates):
# a branch adds one field to a dual-compile uniform struct, the merge is textually clean, and `--layout`
# (one index, the working tree) and `--stray-content` (line-granular) each miss it alone.
#
# The synthetic ref graph, one branch per case the honesty contract requires:
#   feat-abi-break        — ADDS a field to the pinned struct                   -> kind="drift", exit 2
#   feat-reformat         — touches the SAME file, reorders/reflows comments,
#                           the struct itself is byte-for-byte unchanged        -> stays QUIET (quiet=)
#   feat-abi-vanish       — renames the struct away entirely on that branch     -> kind="absent"
#   feat-abi-unmodelled   — adds a BITFIELD member (unmodellable)               -> kind="unknown", never "same"
# …plus the r25 TRIAGE cases, each of which used to read as a bare kind="drift" row:
#   feat-abi-rename       — same size, same slots, same types, DIFFERENT field
#                           names                                               -> kind="rename", excluded by
#                                                                                  default, printed by --detail
#   feat-abi-repack       — same SIZE, different slot partition (two shorts ->
#                           one int at the same offset)                         -> stays kind="drift"
#   feat-abi-stale        — never touches shader.h at all; the LIVE LINE moves
#                           the struct out from under it                        -> the ref is out of the
#                                                                                  authored scope (head_only=)
#   feat-abi-sidecar      — touches shader.h (a comment) while the live line
#                           moved the struct                                    -> kind="head-moved", counted
#
# The base is NOT HEAD here: main advances by one commit (widening Uniforms) AFTER the branches fork, which
# is what makes the authorship distinction observable at all — every branch below now disagrees with HEAD,
# and only the ones that AUTHORED the disagreement may be reported as a break.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "abicheck: git unavailable — skipping"; exit 0; }

R="$TMP/repo"; mkdir -p "$R"
export GIT_AUTHOR_NAME=ctxpack GIT_AUTHOR_EMAIL=ctxpack@example.invalid
export GIT_COMMITTER_NAME=ctxpack GIT_COMMITTER_EMAIL=ctxpack@example.invalid
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
g(){ git -C "$R" "$@" >/dev/null 2>&1; }

g init -q -b main
g config commit.gpgsign false

# ── the base commit: every branch forks HERE — a pinned two-float uniform, the dual-compile shape ──────
cat > "$R/shader.h" <<'EOF'
#pragma once
// Uniforms — a dual-compile CPU/GPU contract. Two floats, pinned by the static_assert below.
struct Uniforms
{
    float x;
    float y;
};
static_assert( sizeof( Uniforms ) == 8, "uniform GPU contract" );
EOF
# A SECOND contract, the one the LIVE LINE will move after every branch has forked. It is what makes the
# authorship distinction observable: after the final commit on main, every branch below disagrees with HEAD
# about Sidecar, and only the ones that AUTHORED a change may be reported.
# OddBall is a bitfield — HEAD itself cannot model it, so it is the unmodelable= counter's own fixture
# (previously a silent `continue`).
cat > "$R/sidecar.h" <<'EOF'
#pragma once
struct Sidecar
{
    float a;
    float b;
};
struct OddBall
{
    unsigned int f : 3;
};
EOF
printf 'nothing structural here\n' > "$R/notes.txt"
g add shader.h sidecar.h notes.txt
g commit -qm base

# ── feat-abi-break: adds ONE field — the motivating bug. Merges textually clean; only a computed-layout
#    diff catches it. ────────────────────────────────────────────────────────────────────────────────
g checkout -qb feat-abi-break
cat > "$R/shader.h" <<'EOF'
#pragma once
struct Uniforms
{
    float x;
    float y;
    float z;   // added on this branch — silently widens the GPU contract
};
static_assert( sizeof( Uniforms ) == 8, "uniform GPU contract" );
EOF
g commit -qam "add z to Uniforms"

# ── feat-reformat: touches the SAME file, but the struct's bytes do not change at all — must stay quiet.
g checkout -q main
g checkout -qb feat-reformat
cat > "$R/shader.h" <<'EOF'
#pragma once
// Uniforms — a dual-compile CPU/GPU contract.
//
// (reflowed comment, no field change at all)
struct Uniforms
{
    float x;   // unchanged
    float y;   // unchanged
};
static_assert( sizeof( Uniforms ) == 8, "uniform GPU contract" );
EOF
g commit -qam "reflow comments only"

# ── feat-abi-vanish: renames the struct away on this branch — the ref-side lexical locator must report
#    absent, never silently "same". ─────────────────────────────────────────────────────────────────
g checkout -q main
g checkout -qb feat-abi-vanish
cat > "$R/shader.h" <<'EOF'
#pragma once
struct UniformsV2
{
    float x;
    float y;
};
static_assert( sizeof( UniformsV2 ) == 8, "uniform GPU contract (renamed)" );
EOF
g commit -qam "rename Uniforms away"

# ── feat-abi-unmodelled: adds a BITFIELD member — the ref-side copy cannot be modelled at all, so the
#    honesty contract requires kind="unknown", never "same". ──────────────────────────────────────────
g checkout -q main
g checkout -qb feat-abi-unmodelled
cat > "$R/shader.h" <<'EOF'
#pragma once
struct Uniforms
{
    float x;
    float y;
    unsigned int flags : 4;   // unmodellable — bit allocation/order is implementation-defined
};
static_assert( sizeof( Uniforms ) == 8, "uniform GPU contract" );
EOF
g commit -qam "add a bitfield member"

# ── feat-abi-rename: same size, same slots, same TYPES — only the field NAMES move. Every byte stays
#    exactly where it was, so this is a source change, not a byte-contract one. ───────────────────────
g checkout -q main
g checkout -qb feat-abi-rename
cat > "$R/shader.h" <<'EOF'
#pragma once
struct Uniforms
{
    float a;
    float b;
};
static_assert( sizeof( Uniforms ) == 8, "uniform GPU contract" );
EOF
g commit -qam "rename the fields of Uniforms"

# ── feat-abi-repack: the SAME total size with a DIFFERENT slot partition (one float becomes two shorts at
#    the same offset). The other half of "rename is not resize": a same-size REPACK is still a real break.
g checkout -q main
g checkout -qb feat-abi-repack
cat > "$R/shader.h" <<'EOF'
#pragma once
struct Uniforms
{
    float x;
    unsigned short p;
    unsigned short q;
};
static_assert( sizeof( Uniforms ) == 8, "uniform GPU contract" );
EOF
g commit -qam "repack the second float as two shorts"

# ── feat-abi-stale: never opens sidecar.h at all. The live line moves Sidecar out from under it, so this
#    branch disagrees with HEAD about a struct it has never touched — out of the AUTHORED scope entirely.
g checkout -q main
g checkout -qb feat-abi-stale
printf 'still nothing structural here\n' > "$R/notes.txt"
g commit -qam "edit a non-source file only"

# ── feat-abi-sidecar: touches sidecar.h (a comment) while the live line changes Sidecar's bytes. In scope,
#    but the branch authored no shape change -> kind="head-moved", counted and excluded, not a break. ──
g checkout -q main
g checkout -qb feat-abi-sidecar
cat > "$R/sidecar.h" <<'EOF'
#pragma once
// a comment this branch added; the struct below is byte-for-byte the base's
struct Sidecar
{
    float a;
    float b;
};
struct OddBall
{
    unsigned int f : 3;
};
EOF
g commit -qam "comment sidecar.h without touching the contract"

# ── the LIVE LINE moves, AFTER every branch has forked. This is the whole point of the fixture: from here
#    on, every branch above disagrees with HEAD about Sidecar, and none of them authored it. ───────────
g checkout -q main
cat > "$R/sidecar.h" <<'EOF'
#pragma once
struct Sidecar
{
    float a;
    float b;
    float c;
};
struct OddBall
{
    unsigned int f : 3;
};
EOF
g commit -qam "widen Sidecar on the live line"

echo "abicheck: BIN=$BIN  REPO=$R"

# attr ELEMENT ATTR -> the attribute on the FIRST matching element ("" if absent)
attr(){ printf '%s' "$S" | tr '<' '\n' | grep "^$1" | head -1 | sed -n "s/.* $2=\"\([^\"]*\)\".*/\1/p"; }

# ── 0) refusals: --abi requires --stray-content; --abi on a non-git root refuses ────────────────────────
"$BIN" "$ROOT/test/fixture" --abi >/dev/null 2>&1
[ $? -eq 1 ] && ok "bare --abi (no --stray-content) refuses loudly (exit 1)" || no "bare --abi did not exit 1"
mkdir -p "$TMP/plain"; printf 'int main(){return 0;}\n' > "$TMP/plain/m.cpp"
"$BIN" "$TMP/plain" --stray-content --abi >/dev/null 2>&1
[ $? -eq 1 ] && ok "--stray-content --abi on a non-git root refuses loudly (exit 1)" || no "--stray-content --abi on a non-git root did not exit 1"

# ── 1) the real run: exit code, determinism, xmllint ──────────────────────────────────────────────────
"$BIN" "$R" --stray-content --abi >"$TMP/a" 2>/dev/null; rc=$?
"$BIN" "$R" --stray-content --abi >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" && ok "abi determinism (byte-identical)" || no "abi output is non-deterministic"
[ "$rc" -eq 2 ] && ok "exit 2 (a real drift is present)" || no "exit code was $rc, want 2 (feat-abi-break is a real drift)"
S="$( cat "$TMP/a" )"
OUT="$TMP/a"

# The FULL view: --detail=N lifts the per-ref display cap AND prints the kinds the default triage counts
# but does not list. Everything the default view excludes has to be reachable through exactly this lever.
"$BIN" "$R" --stray-content --abi --detail=1 >"$TMP/full" 2>/dev/null
"$BIN" "$R" --stray-content --abi --detail=1 >"$TMP/full2" 2>/dev/null
cmp -s "$TMP/full" "$TMP/full2" && ok "abi --detail determinism (byte-identical)" || no "abi --detail output is non-deterministic"

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/a" 2>/dev/null && ok "abi XML well-formed" || no "abi XML malformed"
else
    ok "xmllint unavailable — well-formedness skipped"
fi
[ "$( grep -c '' "$TMP/a" )" -le 1 ] && ok "output is minified (no stray newlines)" || no "output contains newlines outside CDATA"

# python helper: print the <ref name="X" ...>...</ref> slice, or nothing if absent.
# slicefrom FILE NAME reads any file; refslice NAME is the default (capped) view.
slicefrom(){ python3 - "$1" "$2" <<'PY'
import sys
xml = open(sys.argv[1]).read()
name = sys.argv[2]
key = '<ref name="%s"' % name
start = xml.find(key)
if start == -1:
    sys.exit(0)
end = xml.find('</ref>', start) + len('</ref>')
print(xml[start:end])
PY
}
refslice(){ slicefrom "$OUT" "$1"; }
fullslice(){ slicefrom "$TMP/full" "$1"; }

# ── 2) feat-abi-break: kind="drift", the size differs, z is the flagged field ────────────────────────
BREAK="$( refslice feat-abi-break )"
if [ -z "$BREAK" ]; then
    no "feat-abi-break: no <ref> row at all (the break was not detected)"
else
    printf '%s' "$BREAK" | grep -q 'n="Uniforms".*kind="drift"' \
        && ok 'feat-abi-break: Uniforms reported kind="drift"' \
        || { no "feat-abi-break: Uniforms row missing or not kind=drift"; printf '%s\n' "$BREAK"; }
    printf '%s' "$BREAK" | grep -q 'head_size="8" ref_size="12" size_differs="1"' \
        && ok "feat-abi-break: head_size=8 ref_size=12 size_differs=1" \
        || { no "feat-abi-break: size attributes wrong"; printf '%s\n' "$BREAK"; }
    printf '%s' "$BREAK" | grep -q '<d n="z" a="absent" b="float@8"/>' \
        && ok "feat-abi-break: field diff names z as the added field" \
        || { no "feat-abi-break: missing the z field diff row"; printf '%s\n' "$BREAK"; }
fi

# ── 3) feat-reformat: MUST stay quiet — no <ref> row, folded into merged= ────────────────────────────
REFORMAT="$( refslice feat-reformat )"
[ -z "$REFORMAT" ] && ok "feat-reformat: stays quiet (no ref row — reformat only, bytes unchanged)" \
                    || { no "feat-reformat: wrongly reported a difference"; printf '%s\n' "$REFORMAT"; }

# ── 4) feat-abi-vanish: kind="absent" — the struct's name is gone on that branch ──────────────────────
VANISH="$( refslice feat-abi-vanish )"
if [ -z "$VANISH" ]; then
    no "feat-abi-vanish: no <ref> row at all (want a kind=absent Uniforms row)"
else
    printf '%s' "$VANISH" | grep -q 'n="Uniforms".*kind="absent"' \
        && ok 'feat-abi-vanish: Uniforms reported kind="absent"' \
        || { no "feat-abi-vanish: Uniforms row missing or not kind=absent"; printf '%s\n' "$VANISH"; }
    printf '%s' "$VANISH" | grep -q ' ref_size='  \
        && no "feat-abi-vanish: ref_size printed for an absent struct (should be omitted)" \
        || ok "feat-abi-vanish: ref_size correctly omitted for kind=absent"
fi

# ── 5) feat-abi-unmodelled: kind="unknown", NEVER "same" — the honesty contract's own test ─────────────
UNMOD="$( refslice feat-abi-unmodelled )"
if [ -z "$UNMOD" ]; then
    no "feat-abi-unmodelled: no <ref> row at all (want a kind=unknown Uniforms row — must never read as same)"
else
    printf '%s' "$UNMOD" | grep -q 'n="Uniforms".*kind="unknown"' \
        && ok 'feat-abi-unmodelled: Uniforms reported kind="unknown" (never "same")' \
        || { no "feat-abi-unmodelled: Uniforms row missing or not kind=unknown"; printf '%s\n' "$UNMOD"; }
    printf '%s' "$UNMOD" | grep -q '<ref_caveat k="bitfield"' \
        && ok "feat-abi-unmodelled: the bitfield caveat rides along in ref_caveat (inherited, not dropped)" \
        || { no "feat-abi-unmodelled: bitfield ref_caveat missing"; printf '%s\n' "$UNMOD"; }
    printf '%s' "$UNMOD" | grep -q ' ref_size=' \
        && no "feat-abi-unmodelled: ref_size printed for an unmodellable ref (would read as a real 0-byte struct)" \
        || ok "feat-abi-unmodelled: ref_size correctly omitted for kind=unknown"
fi

# ── 6) rename is NOT resize: same slots + same types + different NAMES is excluded, not a drift row ────
RENAME="$( refslice feat-abi-rename )"
[ -z "$RENAME" ] && ok "feat-abi-rename: excluded from the default body (a rename is not a byte-contract break)" \
                  || { no "feat-abi-rename: printed a row in the DEFAULT view"; printf '%s\n' "$RENAME"; }
RENAME_FULL="$( fullslice feat-abi-rename )"
if [ -z "$RENAME_FULL" ]; then
    no "feat-abi-rename: --detail did not print the excluded row either (it must be REACHABLE, not dropped)"
else
    printf '%s' "$RENAME_FULL" | grep -q 'n="Uniforms".*kind="rename"' \
        && ok 'feat-abi-rename: --detail shows kind="rename"' \
        || { no "feat-abi-rename: --detail row is not kind=rename"; printf '%s\n' "$RENAME_FULL"; }
    printf '%s' "$RENAME_FULL" | grep -q 'head_size="8" ref_size="8" size_differs="0" size_delta="0"' \
        && ok "feat-abi-rename: sizes agree (8/8), size_delta=0" \
        || { no "feat-abi-rename: size attributes wrong for a rename"; printf '%s\n' "$RENAME_FULL"; }
fi

# ── 7) …and the other half: a same-SIZE REPACK stays a drift. Excluding renames must not excuse it. ────
REPACK="$( refslice feat-abi-repack )"
if [ -z "$REPACK" ]; then
    no "feat-abi-repack: no ref row (a same-size slot repack is still a real byte-contract break)"
else
    printf '%s' "$REPACK" | grep -q 'n="Uniforms".*kind="drift"' \
        && ok 'feat-abi-repack: same size, different slots -> kind="drift" (NOT rename)' \
        || { no "feat-abi-repack: not reported as drift"; printf '%s\n' "$REPACK"; }
    printf '%s' "$REPACK" | grep -q 'head_size="8" ref_size="8" size_differs="0"' \
        && ok "feat-abi-repack: size_differs=0 on a real break (the size is not the whole contract)" \
        || { no "feat-abi-repack: size attributes wrong"; printf '%s\n' "$REPACK"; }
fi

# ── 8) AUTHORSHIP: the live line moved Sidecar after every branch forked. A branch that never opened the
#      file is out of scope entirely; one that opened it without changing the contract is head-moved. ──
STALE="$( fullslice feat-abi-stale )"
[ -z "$STALE" ] && ok "feat-abi-stale: never reported (the ref never touched the path the live line moved)" \
                 || { no "feat-abi-stale: reported a struct it never authored a change to"; printf '%s\n' "$STALE"; }
SIDECAR="$( refslice feat-abi-sidecar )"
[ -z "$SIDECAR" ] && ok "feat-abi-sidecar: excluded from the default body (the LIVE LINE moved, not the branch)" \
                   || { no "feat-abi-sidecar: a head-moved row leaked into the default view"; printf '%s\n' "$SIDECAR"; }
SIDECAR_FULL="$( fullslice feat-abi-sidecar )"
if [ -z "$SIDECAR_FULL" ]; then
    no "feat-abi-sidecar: --detail did not print the head-moved row (it must be REACHABLE)"
else
    printf '%s' "$SIDECAR_FULL" | grep -q 'n="Sidecar".*kind="head-moved"' \
        && ok 'feat-abi-sidecar: --detail shows kind="head-moved"' \
        || { no "feat-abi-sidecar: --detail row is not kind=head-moved"; printf '%s\n' "$SIDECAR_FULL"; }
fi

# ── 9) the header counters: nothing is dropped without a number ───────────────────────────────────────
CAND="$( attr abi candidates )"
[ -n "$CAND" ] && [ "$CAND" -ge 1 ] 2>/dev/null \
    && ok "abi: candidates=$CAND (HEAD's Uniforms is located and counted)" \
    || no "abi: candidates missing or zero"
BROKEN="$( attr abi broken_refs )"
[ "$BROKEN" = "2" ] && ok "abi: broken_refs=2 (feat-abi-break + feat-abi-repack; nothing else counts)" \
                     || no "abi: broken_refs=$BROKEN, want 2 (rename/unknown/absent/head-moved must not count)"
for pair in "drift 2" "rename 1" "head-moved 1" "absent 1" "unknown 1"; do
    set -- $pair
    got="$( attr abi "$1" )"
    [ "$got" = "$2" ] && ok "abi: $1=\"$2\" on the header" || no "abi: header $1=\"$got\", want \"$2\""
done
EXCL="$( attr abi excluded )"
[ "$EXCL" = "2" ] && ok "abi: excluded=2 (the rename + the head-moved row, counted not dropped)" \
                   || no "abi: excluded=\"$EXCL\", want 2"
EXCLREFS="$( attr abi excluded_refs )"
[ "$EXCLREFS" = "2" ] && ok "abi: excluded_refs=2 (feat-abi-rename + feat-abi-sidecar have rows but list none)" \
                       || no "abi: excluded_refs=\"$EXCLREFS\", want 2"
UNMOD="$( attr abi unmodelable )"
[ -n "$UNMOD" ] && [ "$UNMOD" -ge 1 ] 2>/dev/null \
    && ok "abi: unmodelable=$UNMOD (OddBall's bitfield has no HEAD baseline — counted, not silently skipped)" \
    || no "abi: unmodelable=\"$UNMOD\", want >=1 (the skip must not be silent)"
HEADONLY="$( attr abi head_only )"
[ -n "$HEADONLY" ] && [ "$HEADONLY" -ge 1 ] 2>/dev/null \
    && ok "abi: head_only=$HEADONLY (sites the authorship narrowing dropped are counted)" \
    || no "abi: head_only=\"$HEADONLY\", want >=1 (the narrowing must not be silent)"

# rows = shown + dropped + excluded — the body and the header must reconcile exactly.
# §P8 vocabulary: the dropped-row COUNT used to be printed as capped=, the tool's only numeric use of an
# attribute that is a 0|1 BOOLEAN in every other verb. The count is dropped= now and capped= is the bit
# (see src/pageview.h, THE TRUNCATION VOCABULARY, rule 3), so this reconciliation reads dropped= and the
# bit is asserted separately below — an assertion that would have been vacuous while capped= held a count.
ROWS="$( attr abi rows )"; SHOWN="$( attr abi shown )"; DROPPED="$( attr abi dropped )"
if [ -n "$ROWS" ] && [ -n "$SHOWN" ] && [ -n "$DROPPED" ] && [ -n "$EXCL" ]; then
    SUM=$(( SHOWN + DROPPED + EXCL ))
    [ "$ROWS" = "$SUM" ] && ok "abi: rows=$ROWS reconciles as shown($SHOWN)+dropped($DROPPED)+excluded($EXCL)" \
                          || no "abi: rows=$ROWS but shown+dropped+excluded=$SUM (a row went missing)"
else
    no "abi: one of rows/shown/dropped/excluded is missing from the header"
fi
CAPPED="$( attr abi capped )"
case "$CAPPED:$DROPPED" in
    0:0 )  ok "abi: capped=\"0\" with dropped=0 (the truncation bit agrees with the count)" ;;
    1:0 )  no "abi: capped=\"1\" but dropped=0 (the bit claims a truncation the count denies)" ;;
    0:* )  no "abi: capped=\"0\" but dropped=$DROPPED (a silent cap — the bug this bit exists to close)" ;;
    1:* )  ok "abi: capped=\"1\" with dropped=$DROPPED (the truncation bit agrees with the count)" ;;
    * )    no "abi: capped=\"$CAPPED\" is not the 0|1 boolean the tool-wide vocabulary requires" ;;
esac

# every ref is accounted for: listed + quiet + excluded_refs + unrelated == refs
REFS="$( attr abi refs )"; QUIET="$( attr abi quiet )"; UNREL="$( attr abi unrelated )"
LISTED="$( grep -o '<ref name=' "$TMP/a" | wc -l | tr -d ' ' )"
SUMR=$(( LISTED + QUIET + EXCLREFS + UNREL ))
[ "$REFS" = "$SUMR" ] && ok "abi: refs=$REFS reconciles as listed($LISTED)+quiet($QUIET)+excluded_refs($EXCLREFS)+unrelated($UNREL)" \
                       || no "abi: refs=$REFS but the per-class ref counts sum to $SUMR"

# ── 10) --detail is the documented escape hatch, and --help says so ────────────────────────────────────
"$BIN" --help 2>&1 | grep -q 'kind="rename"' \
    && ok "--help documents kind=\"rename\"" || no "--help does not mention kind=\"rename\""
"$BIN" --help 2>&1 | grep -q 'EXCLUDED by default' \
    && ok "--help names what --abi excludes by default" || no "--help does not name the default exclusions"
"$BIN" --help 2>&1 | grep -q 'head-moved' \
    && ok "--help documents kind=\"head-moved\"" || no "--help does not mention kind=\"head-moved\""

[ $fail -eq 0 ] && echo "abicheck: ALL PASS" || echo "abicheck: FAILURES"
exit $fail
