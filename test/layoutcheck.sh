#!/usr/bin/env bash
# layoutcheck.sh — the field-notes §5 gate for --layout=STRUCT, the CPU/GPU contract verb (src/layout.h).
#
#   test/layoutcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/layoutcheck.sh
#
# The fixture test/layoutfix/ carries one instance of every rule the model has to get right, and every
# case it has to REFUSE. Each expected number below was worked out by hand from the C alignment rules and
# is pinned in the fixture's own comments next to the struct:
#
#   pod.h        PadCase            char/int/char/double        -> 3 B and 7 B of interior pad, 24 B total
#                AlignCase          alignas( 32 ) over 8 B      -> 24 B of TRAILING pad, 32 B total
#                Slot/ArrayCase     Slot[ SLOT_COUNT ] + short  -> nested aggregate + #define extent, 36 B
#   packed.h     PackedAttrCase     attribute packed            -> MODELLED as align 1 throughout, 6 B
#                                   (its prose mentions the pragma below: the detector must not be fooled)
#   pragmapack.h PragmaPackedCase   #pragma pack in the file    -> REFUSED (modeled="0", pragma-pack caveat)
#   dualcompile  DualCompileUniforms  one macro, two #ifdef arms, both 2 B -> resolved, 8 B
#                AmbiguousMacroCase   two arms that DISAGREE                -> REFUSED, unsized field
#   unmodelled.h BitfieldCase / VirtualCase / DerivedCase / UnknownTypeCase -> each REFUSED with its caveat
#   conflict.h   WrongAssertCase    a sizeof tripwire that is WRONG on purpose -> agree="0", exit 2
#   mirror_*.h   MirrorUniforms     same name, DIFFERENT fields in two files  -> kind="drift", exit 2
#                TwinUniforms       same name, IDENTICAL in two files         -> mirror="match", exit 0
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/layoutfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "layoutcheck: BIN=$BIN  CORPUS=$CORPUS"

# run STRUCT -> the XML in $L, the exit code in $RC
L=""; RC=0
run(){ L="$( "$BIN" "$CORPUS" --layout="$1" --no-cache 2>/dev/null )"; RC=$?; }

# attr ELEMENT ATTR      -> the attribute on the FIRST matching element ("" if absent)
attr(){ printf '%s' "$L" | tr '<' '\n' | grep "^$1" | head -1 | sed -n "s/.* $2=\"\([^\"]*\)\".*/\1/p"; }
# field NAME ATTR        -> the attribute on the <f n="NAME"> row
field(){ printf '%s' "$L" | tr '<' '\n' | grep "^f n=\"$1\"" | head -1 | sed -n "s/.* $2=\"\([^\"]*\)\".*/\1/p"; }
# has REGEX              -> is there a line matching it
has(){ printf '%s' "$L" | tr '<' '\n' | grep -q "$1"; }

# expect_size STRUCT SIZE ALIGN
expect_size(){
    run "$1"
    { [ "$( attr 'def ' size )" = "$2" ] && [ "$( attr 'def ' align )" = "$3" ] && [ "$( attr 'def ' modeled )" = "1" ]; } \
        && ok "$1: size=$2 align=$3 (modelled)" \
        || { no "$1: size=$( attr 'def ' size ) align=$( attr 'def ' align ) modeled=$( attr 'def ' modeled ) (want $2/$3/1)"; printf '%s\n' "$L" | head -c 700; echo; }
}
# expect_field STRUCT FIELD OFFSET SIZE
expect_field(){
    run "$1"
    { [ "$( field "$2" off )" = "$3" ] && [ "$( field "$2" sz )" = "$4" ]; } \
        && ok "$1.$2 @ $3 ($4 B)" \
        || no "$1.$2 off=$( field "$2" off ) sz=$( field "$2" sz ) (want $3 / $4)"
}
# expect_refused STRUCT CAVEAT
expect_refused(){
    run "$1"
    { [ "$( attr 'def ' modeled )" = "0" ] && has "caveat k=\"$2\""; } \
        && ok "$1: REFUSED with caveat k=\"$2\" (no confidently wrong number)" \
        || { no "$1: modeled=$( attr 'def ' modeled ), caveats: $( printf '%s' "$L" | tr '<' '\n' | grep '^caveat' | tr '\n' ' ' )"; }
}

# ── 1) determinism ────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --layout=PadCase --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --layout=PadCase --no-cache >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" && ok "determinism (byte-identical)" || no "--layout is non-deterministic"

# ── 2) the padding case: interior pad before an over-aligned field ────────────────────────────────────
expect_size  PadCase 24 8
expect_field PadCase a 0 1
expect_field PadCase b 4 4
expect_field PadCase c 8 1
expect_field PadCase d 16 8
run PadCase
{ has 'pad bytes="3"' && has 'pad bytes="7"'; } \
    && ok "PadCase: both interior pads (3 B, 7 B) are reported, not just implied by the offsets" \
    || { no "PadCase: missing an explicit <pad bytes=..> row"; printf '%s\n' "$L" | tr '<' '\n' | grep -E '^(pad|f )'; }

# ── 3) the alignment case: alignas raises the SIZE via the trailing pad ───────────────────────────────
expect_size AlignCase 32 32
run AlignCase
{ [ "$( attr 'def ' alignas )" = "32" ] && [ "$( attr 'def ' tail_pad )" = "24" ] && has 'pad tail="24"'; } \
    && ok "AlignCase: alignas=32 recorded, 24 B of trailing pad reported" \
    || no "AlignCase: alignas=$( attr 'def ' alignas ) tail_pad=$( attr 'def ' tail_pad ) (want 32 / 24)"

# ── 4) nested aggregate + a #define array extent ──────────────────────────────────────────────────────
expect_size  Slot 8 4
expect_size  ArrayCase 36 4
expect_field ArrayCase slots 0 32
expect_field ArrayCase tag 32 2
run ArrayCase
[ "$( field slots x )" = "4" ] \
    && ok "ArrayCase.slots: the SLOT_COUNT macro extent resolved to 4" \
    || no "ArrayCase.slots extent = '$( field slots x )' (want 4 — the #define did not resolve)"

# ── 5) the dual-compile macro: two #ifdef arms that AGREE resolve, two that DISAGREE refuse ──────────
expect_size DualCompileUniforms 8 4
run DualCompileUniforms
[ "$( field beat as )" = "half" ] || [ "$( field beat as )" = "__fp16" ] \
    && ok "DualCompileUniforms.beat: the macro type expanded ($( field beat as )) and both arms agreed on 2 B" \
    || no "DualCompileUniforms.beat did not expand its macro type (as='$( field beat as )')"
expect_refused AmbiguousMacroCase macro-type-ambiguous

# ── 6) the two packing controls, treated differently on purpose ───────────────────────────────────────
expect_size PackedAttrCase 6 1
run PackedAttrCase
[ "$( attr 'def ' packed )" = "1" ] \
    && ok "PackedAttrCase: attribute packed modelled (align 1 throughout), and the pragma named in its PROSE did not fool the detector" \
    || no "PackedAttrCase: packed=$( attr 'def ' packed ) (want 1)"
expect_refused PragmaPackedCase pragma-pack

# ── 7) everything the model must REFUSE rather than guess ─────────────────────────────────────────────
expect_refused BitfieldCase    bitfield
expect_refused VirtualCase     virtual
expect_refused DerivedCase     base-class
expect_refused UnknownTypeCase unknown-type

run VirtualCase
printf '%s' "$L" | tr '<' '\n' | grep '^f n=' | grep -q 'off=' \
    && no "VirtualCase still prints offsets — a vtable pointer at offset 0 invalidates them ALL, retroactively" \
    || ok "VirtualCase: no field keeps an offset (the vtable caveat reaches backwards)"

run UnknownTypeCase
{ [ "$( field known off )" = "0" ] && [ "$( field opaque sized )" = "0" ] && [ -z "$( field after off )" ]; } \
    && ok "UnknownTypeCase: the field BEFORE the unsized one keeps its offset, the ones after lose theirs" \
    || no "UnknownTypeCase: known.off='$( field known off )' opaque.sized='$( field opaque sized )' after.off='$( field after off )'"

# ── 7b) §P6.12: count reconciliation — TWO unmodelable fields of the SAME kind must not collapse into one
#        caveat row with no trace of the second (the real bug: Symbol's name/scope, both std::string,
#        both "unknown-type", one <caveat> with no count).
expect_refused DoubleUnknownTypeCase unknown-type
run DoubleUnknownTypeCase
CAVEAT_ROWS="$( printf '%s' "$L" | tr '<' '\n' | grep -c '^caveat k="unknown-type"' )"
[ "$CAVEAT_ROWS" = "1" ] \
    && ok "DoubleUnknownTypeCase: still exactly ONE caveat row per kind (a report, not a log)" \
    || no "DoubleUnknownTypeCase: $CAVEAT_ROWS unknown-type caveat rows (want exactly 1)"
[ "$( attr 'caveat ' count )" = "2" ] \
    && ok "DoubleUnknownTypeCase: the one row's count=\"2\" reconciles against both unmodelable fields" \
    || no "DoubleUnknownTypeCase: caveat count='$( attr 'caveat ' count )' (want 2 — two fields hit unknown-type)"

# ── 7c) §P6.11: an enum (scoped or unscoped) must REFUSE, never silently model as a zero-field struct.
#        A scoped enum's head literally contains the word "class"/"struct", which is exactly what used to
#        fool the aggregate detector into a confident modeled="1" size="1" instead of a refusal.
for enumname in EnumClassCase EnumStructCase PlainEnumCase; do
    "$BIN" "$CORPUS" --layout="$enumname" --no-cache >"$TMP/enum.out" 2>"$TMP/enum.err"
    rc=$?
    [ $rc -eq 1 ] && ok "$enumname: --layout refuses (exit 1)" || no "$enumname: --layout exited $rc (want 1)"
    [ ! -s "$TMP/enum.out" ] && ok "$enumname: no XML on stdout (no silent degrade)" || no "$enumname: printed to stdout: $( cat "$TMP/enum.out" )"
    grep -qi 'is an enum' "$TMP/enum.err" && grep -q -- "$enumname" "$TMP/enum.err" \
        && ok "$enumname: refusal names the type and says 'is an enum'" \
        || no "$enumname: refusal did not say 'is an enum' + name the type: $( cat "$TMP/enum.err" )"
done

# ── 8) the static_assert tripwires ────────────────────────────────────────────────────────────────────
run PadCase
{ [ "$( attr 'assert ' want )" = "24" ] && [ "$( attr 'assert ' got )" = "24" ] && [ "$( attr 'assert ' agree )" = "1" ]; } \
    && ok "PadCase: its sizeof tripwire is found and AGREES with the computed size" \
    || no "PadCase assert: want=$( attr 'assert ' want ) got=$( attr 'assert ' got ) agree=$( attr 'assert ' agree )"

run WrongAssertCase
{ [ "$( attr 'assert ' agree )" = "0" ] && [ "$( attr 'layout ' conflicts )" = "1" ] && [ "$RC" -eq 2 ]; } \
    && ok "WrongAssertCase: a tripwire that contradicts the computed size reports agree=0 and exits 2" \
    || { no "WrongAssertCase: agree=$( attr 'assert ' agree ) conflicts=$( attr 'layout ' conflicts ) rc=$RC (want 0 / 1 / 2)"; }

# ── 9) THE MIRROR CHECK — the reason this verb exists ─────────────────────────────────────────────────
run MirrorUniforms
{ [ "$( attr 'layout ' mirror )" = "mismatch" ] && [ "$( attr 'layout ' defs )" = "2" ] && [ "$RC" -eq 2 ]; } \
    && ok "MirrorUniforms: two definitions with different fields -> mirror=\"mismatch\", exit 2" \
    || { no "MirrorUniforms: mirror=$( attr 'layout ' mirror ) defs=$( attr 'layout ' defs ) rc=$RC (want mismatch / 2 / 2)"; printf '%s\n' "$L" | head -c 900; echo; }

[ "$( attr 'mismatch ' kind )" = "drift" ] \
    && ok "MirrorUniforms: classified as kind=\"drift\" (a real byte-contract break, not a stub or a spelling)" \
    || no "MirrorUniforms mismatch kind=$( attr 'mismatch ' kind ) (want drift)"

{ has 'd n="bias" a="float@4" b="absent"' && has 'd n="flags" a="unsigned int@8" b="unsigned int@4"'; } \
    && ok "MirrorUniforms: the diff NAMES the dropped field and the field it shifted" \
    || { no "MirrorUniforms: the per-field diff is missing or wrong"; printf '%s' "$L" | tr '<' '\n' | grep '^d n='; }

{ [ "$( attr 'mismatch ' size_a )" = "12" ] && [ "$( attr 'mismatch ' size_b )" = "8" ]; } \
    && ok "MirrorUniforms: both sides' sizes are on the mismatch row (12 vs 8)" \
    || no "MirrorUniforms: size_a=$( attr 'mismatch ' size_a ) size_b=$( attr 'mismatch ' size_b ) (want 12 / 8)"

# A same-named TypeScript class (client.ts) has no byte layout and must NOT join the mirror set — its
# `class MirrorUniforms {` head would otherwise parse as a C++ aggregate and report a third, phantom side.
run MirrorUniforms
{ [ "$( attr 'layout ' defs )" = "2" ] && ! has 'p="test/layoutfix/client.ts"'; } \
    && ok "a same-named TypeScript class is excluded (only C-family files carry a byte contract)" \
    || { no "defs=$( attr 'layout ' defs ) — the .ts class leaked into the mirror set"; printf '%s' "$L" | tr '<' '\n' | grep '^def '; }

"$BIN" "$CORPUS" --layout=NotAStructAtAll >/dev/null 2>"$TMP/err"; rc=$?
{ [ $rc -eq 1 ] && grep -q "no indexed struct/class" "$TMP/err"; } \
    && ok "an entirely unknown name gets the spelling-mistake refusal" || no "wrong refusal for an unknown name: $( cat "$TMP/err" )"

# The NEGATIVE control: a name defined twice IDENTICALLY must not cry wolf.
run TwinUniforms
{ [ "$( attr 'layout ' mirror )" = "match" ] && [ "$RC" -eq 0 ] && ! has '^mismatch'; } \
    && ok "TwinUniforms: two IDENTICAL definitions -> mirror=\"match\", exit 0, no mismatch element" \
    || { no "TwinUniforms: mirror=$( attr 'layout ' mirror ) rc=$RC — a matching mirror must be silent"; }

# ── 10) refusals: a bare --layout, and an unknown name ────────────────────────────────────────────────
"$BIN" "$CORPUS" --layout >/dev/null 2>&1
[ $? -eq 1 ] && ok "bare --layout refuses loudly (exit 1)" || no "bare --layout did not exit 1"
"$BIN" "$CORPUS" --layout=NoSuchStructAnywhere >/dev/null 2>&1
[ $? -eq 1 ] && ok "an unknown struct refuses loudly (exit 1, never an empty map)" || no "--layout on an unknown name did not exit 1"

# file:name disambiguation, exactly like --around/--lego.
run "mirror_gpu.h:MirrorUniforms"
{ [ "$( attr 'layout ' defs )" = "1" ] && [ "$( attr 'def ' size )" = "8" ]; } \
    && ok "file:name disambiguates to one definition (mirror_gpu.h -> 8 B)" \
    || no "file:name picked defs=$( attr 'layout ' defs ) size=$( attr 'def ' size ) (want 1 / 8)"

# ── 11) well-formed, minified XML (G4) ────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    for s in PadCase MirrorUniforms UnknownTypeCase PragmaPackedCase; do
        "$BIN" "$CORPUS" --layout="$s" --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
            && ok "XML well-formed ($s)" || no "XML malformed ($s)"
    done
else
    ok "xmllint unavailable — XML well-formedness skipped"
fi
[ "$( grep -c '' "$TMP/a" )" -le 1 ] && ok "output is minified (no stray newlines)" || no "output contains newlines outside CDATA"

[ $fail -eq 0 ] && echo "layoutcheck: ALL PASS" || echo "layoutcheck: FAILURES"
exit $fail
