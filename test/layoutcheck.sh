#!/usr/bin/env bash
# layoutcheck.sh — the gate for --layout=STRUCT, the CPU/GPU contract verb (src/layout.h).
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
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/layoutfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
if cmp -s "$TMP/a" "$TMP/b"; then ok "determinism (byte-identical)"; else no "--layout is non-deterministic"; fi

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
    if [ $rc -eq 1 ]; then ok "$enumname: --layout refuses (exit 1)"; else no "$enumname: --layout exited $rc (want 1)"; fi
    if [ ! -s "$TMP/enum.out" ]; then ok "$enumname: no XML on stdout (no silent degrade)"; else no "$enumname: printed to stdout: $( cat "$TMP/enum.out" )"; fi
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
if [ $? -eq 1 ]; then ok "bare --layout refuses loudly (exit 1)"; else no "bare --layout did not exit 1"; fi
"$BIN" "$CORPUS" --layout=NoSuchStructAnywhere >/dev/null 2>&1
if [ $? -eq 1 ]; then ok "an unknown struct refuses loudly (exit 1, never an empty map)"; else no "--layout on an unknown name did not exit 1"; fi

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
if [ "$( grep -c '' "$TMP/a" )" -le 1 ]; then ok "output is minified (no stray newlines)"; else no "output contains newlines outside CDATA"; fi

# ── 12) a hostile extent never takes the process down ────────────────────────────────────────────────
# The extent evaluator reads source text. Before the fix: a `#define` extent nested 200,000 `(` deep recursed
# until the stack overflowed (SIGSEGV, exit 139, every platform); `(0-2^40)*2^23/(0-1)` divided INT64_MIN by
# -1 (SIGFPE on x86-64); and `2^40*2^40` was signed overflow (an abort under the G1 sanitizer build — run this
# gate with RIPWIRE_BIN=asan/ripwire to see that one). Each is now an UNKNOWN extent: the field is unsized and
# the struct carries the unknown-extent caveat, exactly like any expression the evaluator cannot read.
HOSTILE="$TMP/hostile"; mkdir -p "$HOSTILE"
python3 - "$HOSTILE/deep.h" <<'PYDEEP'
import sys
n = 200000
open(sys.argv[1], "w").write("#define DEEP_EXTENT " + "(" * n + "1" + ")" * n + "\nstruct DeepExtent\n{\n    int n;\n    char a[DEEP_EXTENT];\n};\n")
PYDEEP
cat > "$HOSTILE/range.h" <<'EOF'
#define QUOTIENT_EXTENT ((0-1099511627776)*8388608/(0-1))
struct QuotientExtent
{
    int  n;
    char a[QUOTIENT_EXTENT];
};
struct ProductExtent
{
    int  n;
    char b[1099511627776*1099511627776];
};
struct PlainExtent
{
    int  n;
    char c[4*2];
};
EOF
for s in DeepExtent QuotientExtent ProductExtent; do
    "$BIN" "$HOSTILE" --layout="$s" --no-cache >"$TMP/h_$s" 2>"$TMP/h_$s.err"; rc=$?
    if [ "$rc" -ne 0 ] || grep -q 'runtime error' "$TMP/h_$s.err"; then
        no "$s: exit $rc $( grep -m1 'runtime error' "$TMP/h_$s.err" | cut -c1-120 ) — a hostile extent crashed the evaluator"
    elif grep -q '<caveat k="unknown-extent"' "$TMP/h_$s"; then
        ok "$s: exit 0, the extent reads as unknown (field unsized, caveat carried)"
    else
        no "$s: exit 0 but no unknown-extent caveat: $( grep -o '<def .*</def>' "$TMP/h_$s" | head -c 200 )"
    fi
done
"$BIN" "$HOSTILE" --layout=PlainExtent --no-cache >"$TMP/h_plain" 2>/dev/null
grep -q '<f n="c" ty="char" x="8" sz="8"' "$TMP/h_plain" && ok "control: an ordinary 4*2 extent still sizes to 8" \
    || no "control: 4*2 no longer sizes: $( grep -o '<def .*</def>' "$TMP/h_plain" | head -c 200 )"
# The paren bound is a DEPTH. A first version counted every `(` in the expression, so a legitimate frame-size macro of
# sixty-six parenthesised sibling terms — nesting one level — came back as an unknown extent where main sized it.
python3 - "$HOSTILE/wide.h" <<'PYWIDE'
import sys
terms = " + ".join("(T%d)" % i for i in range(66))
consts = "".join("#define T%d 4\n" % i for i in range(66))
open(sys.argv[1], "w").write(consts + "#define FRAME_BYTES (" + terms + ")\nstruct WideExtent\n{\n    int  n;\n    char a[FRAME_BYTES];\n};\n")
PYWIDE
"$BIN" "$HOSTILE" --layout=WideExtent --no-cache >"$TMP/h_wide" 2>/dev/null
grep -q '<f n="a" ty="char" x="264" sz="264"' "$TMP/h_wide" && grep -q 'modeled="1"' "$TMP/h_wide" \
    && ok "66 sibling parenthesised terms (one nesting level) still size: a = 264 B, modeled=\"1\"" \
    || no "66 sibling parenthesised terms no longer size — the paren bound counts terms, not depth: $( grep -o '<def .*</def>' "$TMP/h_wide" | head -c 240 )"

# ── 13) a data member whose `(` sits in its extent or its initializer is a FIELD, not a member function ─────────────
# The member-function test took the first `(` anywhere in the statement, so `char a[(4)];`, `int x = (3);` and
# `int x{ (3) };` were skipped as functions: the field vanished while the struct still said modeled="1" and a size
# short by the field's bytes. A wrong answer with no caveat. `operator=( … )` stays a function.
cat > "$HOSTILE/parenfield.h" <<'EOF'
struct ParenExtent   { int n; char a[(4)]; };
struct ParenInit     { int n; int x = (3); };
struct ParenBrace    { int n; int x{ (3) }; };
struct OperatorAssign { int n; OperatorAssign& operator=( const OperatorAssign& ); char c; };
EOF
for pair in ParenExtent:8 ParenInit:8 ParenBrace:8 OperatorAssign:8; do
    s="${pair%%:*}"; want="${pair#*:}"
    "$BIN" "$HOSTILE" --layout="$s" --no-cache >"$TMP/pf_$s" 2>/dev/null
    got="$( grep -o '<def [^>]*' "$TMP/pf_$s" | grep -o 'size="[0-9]*"' | tr -dc 0-9 )"
    fields="$( grep -o '<def [^>]*' "$TMP/pf_$s" | grep -o 'fields="[0-9]*"' | tr -dc 0-9 )"
    [ "$got" = "$want" ] && [ "$fields" = 2 ] \
        && ok "$s: both members placed, size=$want" \
        || no "$s: fields=${fields:-?} size=${got:-?} (want 2 fields, size $want): $( grep -o '<def .*</def>' "$TMP/pf_$s" | head -c 200 )"
done

# ── 14) a `(` from alignas/__attribute__/decltype, or one inside a template's `<…>`, is not a parameter
#        list either — counting it as one silently dropped the field it decorates while the struct still
#        said modeled="1" with a size short by exactly that field's bytes.
expect_refused AlignasFieldCase     unknown-type
expect_refused AttributeFieldCase   unknown-type
expect_refused DecltypeFieldCase    unknown-type
expect_refused StdFunctionFieldCase unknown-type

run AlignasFieldCase
has 'f n="x"' \
    && ok "AlignasFieldCase: the alignas-decorated field is still COUNTED (not silently dropped)" \
    || no "AlignasFieldCase: field 'x' vanished with no trace: $( printf '%s' "$L" | tr '<' '\n' | grep '^f ' )"
{ [ "$( field n sz )" = "4" ] && [ "$( field c sz )" = "1" ]; } \
    && ok "AlignasFieldCase: the plain neighbours (n, c) still size normally" \
    || no "AlignasFieldCase: a neighbour field lost its size: n=$( field n sz ) c=$( field c sz )"

# A3 (found-items 2026-09-17): a postfix `__attribute__((aligned(8)))` used to confuse parseDeclarator's
# last-identifier scan (the attribute's own trailing parens read as unparsed junk after a digit mistaken for
# the field name), so the field never reached appendField at all — refused as "unparsed-member" with NO
# `<f n="x">` row, unlike every other unmodelable-field shape in this fixture. peelAttributeGroups now peels
# the attribute before the name/type split, so `x` is COUNTED (like AlignasFieldCase) and refused the same
# way alignas is: unknown-type, not silently trusted at align=4.
run AttributeFieldCase
has 'f n="x"' \
    && ok "AttributeFieldCase: the __attribute__((aligned(8)))-decorated field is still COUNTED (not silently dropped)" \
    || no "AttributeFieldCase: field 'x' vanished with no trace: $( printf '%s' "$L" | tr '<' '\n' | grep '^f ' )"
{ [ "$( field n sz )" = "4" ] && [ "$( field c sz )" = "1" ]; } \
    && ok "AttributeFieldCase: the plain neighbours (n, c) still size normally" \
    || no "AttributeFieldCase: a neighbour field lost its size: n=$( field n sz ) c=$( field c sz )"

# the other half of A3: a LAYOUT-IRRELEVANT attribute (deprecated, not aligned/packed) must not refuse at all.
expect_size  AttributeHarmlessFieldCase 12 4
expect_field AttributeHarmlessFieldCase x 4 4

# A3 (review round, found-items 2026-09-17): the GNU reserved-namespace double-underscore spelling
# (`__aligned__`/`__packed__`) is the SAME attribute as the bare form and must degrade identically —
# containsWord's word-boundary rule (an underscore counts as an identifier byte) missed it entirely, so
# the field read modeled="1" with a confidently wrong sz/al/off. attrHasKeyword now strips one matching
# leading+trailing "__" pair before comparing.
expect_refused AttributeGnuAlignedFieldCase unknown-type
expect_refused AttributeGnuPackedFieldCase  unknown-type
run AttributeGnuAlignedFieldCase
has 'f n="x"' \
    && ok "AttributeGnuAlignedFieldCase: the __aligned__-decorated field is still COUNTED (not silently dropped)" \
    || no "AttributeGnuAlignedFieldCase: field 'x' vanished with no trace: $( printf '%s' "$L" | tr '<' '\n' | grep '^f ' )"
{ [ "$( field n sz )" = "4" ] && [ "$( field c sz )" = "1" ]; } \
    && ok "AttributeGnuAlignedFieldCase: the plain neighbours (n, c) still size normally" \
    || no "AttributeGnuAlignedFieldCase: a neighbour field lost its size: n=$( field n sz ) c=$( field c sz )"
run AttributeGnuPackedFieldCase
has 'f n="x"' \
    && ok "AttributeGnuPackedFieldCase: the __packed__-decorated field is still COUNTED (not silently dropped)" \
    || no "AttributeGnuPackedFieldCase: field 'x' vanished with no trace: $( printf '%s' "$L" | tr '<' '\n' | grep '^f ' )"

# the layout-NEUTRAL half in the GNU spelling too: normalising __unused__ to "unused" must not make it
# newly match aligned/packed by accident — this must stay fully modelled, same as AttributeHarmlessFieldCase.
expect_size  AttributeGnuHarmlessFieldCase 12 4
expect_field AttributeGnuHarmlessFieldCase x 4 4

# CodeRabbit on #281: a string argument is inert. `deprecated( ")" )` must not unbalance the attribute group and
# `deprecated( "packed" )` must not spell the packed keyword; both stay modelled like AttributeHarmlessFieldCase.
expect_size  AttributeStringParenCase 12 4
expect_field AttributeStringParenCase x 4 4
expect_size  AttributeStringKeywordCase 12 4
expect_field AttributeStringKeywordCase x 4 4

# A3 (review round): the C++11 standard attribute syntax ([[gnu::aligned(8)]] / [[gnu::packed]]) is never
# specially peeled — pinned here so it cannot silently start being modelled as natural. Both already refuse
# as a side effect of how the surrounding text fails to parse as a plain field.
expect_refused AttributeStdAlignedFieldCase unknown-extent
expect_refused AttributeStdPackedFieldCase  unknown-extent
run AttributeStdAlignedFieldCase
has 'f n="x"' \
    && ok "AttributeStdAlignedFieldCase: the [[gnu::aligned(8)]]-decorated field is still COUNTED" \
    || no "AttributeStdAlignedFieldCase: field 'x' vanished with no trace: $( printf '%s' "$L" | tr '<' '\n' | grep '^f ' )"

run DecltypeFieldCase
has 'f n="x"' \
    && ok "DecltypeFieldCase: the decltype field is still COUNTED (not silently dropped)" \
    || no "DecltypeFieldCase: field 'x' vanished with no trace: $( printf '%s' "$L" | tr '<' '\n' | grep '^f ' )"

run StdFunctionFieldCase
has 'f n="cb"' \
    && ok "StdFunctionFieldCase: the std::function field is still COUNTED (not silently dropped)" \
    || no "StdFunctionFieldCase: field 'cb' vanished with no trace: $( printf '%s' "$L" | tr '<' '\n' | grep '^f ' )"

# ── UNREADABLE DEFINITION: a mirror whose second half could not be read is DISCLOSED, in every build flavour ──────
# A definition indexed from a warm cache whose file is unreadable when the verb runs used to be dropped with a
# one-argument DISCLOSE — a debug trace, nothing at all in a Release binary — so a drifting mirror read
# found="1" defs="1" mirror="single" and exited 0: "one definition, nothing to compare". Now the verb's DISCLOSE
# sink counts it into unreadable="N" on <layout>, defined in the legend of the same document.
UR="$TMP/unreadable"; mkdir -p "$UR/tree/a" "$UR/tree/b" "$UR/xdg"
printf 'struct UnreadMirror { int x; int y; };\n'  >"$UR/tree/a/p.h"
printf 'struct UnreadMirror { int x; long y; };\n' >"$UR/tree/b/p.h"
XDG_CACHE_HOME="$UR/xdg" TMPDIR="$UR/xdg" "$BIN" "$UR/tree" --layout=UnreadMirror >"$UR/warm.out" 2>/dev/null; urc=$?
if [ "$urc" -eq 2 ] && grep -q 'mirror="mismatch"' "$UR/warm.out"; then
    ok "unreadable (control): both halves readable → mirror=\"mismatch\", exit 2, and no unreadable= ($( grep -c 'unreadable=' "$UR/warm.out" ) hit)"
    chmod 000 "$UR/tree/b/p.h"
    if cat "$UR/tree/b/p.h" >/dev/null 2>&1; then
        printf '  SKIP  unreadable: chmod 000 does not stop this user reading the file (root?) — the arm cannot plant its fault\n'
    else
        XDG_CACHE_HOME="$UR/xdg" TMPDIR="$UR/xdg" "$BIN" "$UR/tree" --layout=UnreadMirror >"$UR/cold.out" 2>/dev/null; urc3=$?
        # OWNER DECISION 2026-09-19: a definition it could not read is "could not verify" — exit 3 (2 stays drift, 0 verified)
        [ "$urc3" -eq 3 ] \
            && ok "unreadable: exit 3 (could not verify) — not 0 (verified) and not 2 (a drift it saw)" \
            || no "unreadable: a mirror with an unreadable half exited $urc3, expected 3"
        chmod 000 "$UR/tree/a/p.h"
        XDG_CACHE_HOME="$UR/xdg" TMPDIR="$UR/xdg" "$BIN" "$UR/tree" --layout=UnreadMirror >"$UR/none.out" 2>"$UR/none.err"; urcN=$?
        chmod 644 "$UR/tree/a/p.h"
        { [ "$urcN" -eq 3 ] && grep -q 'could not be read' "$UR/none.err"; } \
            && ok "unreadable: every definition unreadable → exit 3 with the reason on stderr, no document" \
            || no "unreadable: every definition unreadable exited $urcN (expected 3): $( head -c 160 "$UR/none.err" )"
        grep -o '<layout [^>]*>' "$UR/cold.out" | grep -q ' defs="1" .*unreadable="1"' \
            && ok "unreadable: the unread definition is named on the root — unreadable=\"1\" beside defs=\"1\" (every build flavour)" \
            || no "unreadable: a definition whose file could not be read vanished silently: $( grep -o '<layout [^>]*>' "$UR/cold.out" )"
        grep -q 'unreadable="N": ' "$UR/cold.out" \
            && ok "unreadable: the attribute is defined in the legend of the same document" \
            || no "unreadable: unreadable= is emitted with no legend definition"
        command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$UR/cold.out" 2>/dev/null \
            && ok "unreadable: the disclosing document is well-formed" || no "unreadable: the disclosing document fails xmllint"; }
    fi
    chmod 644 "$UR/tree/b/p.h"
else
    no "unreadable (control): the readable mirror did not report mismatch/exit 2 (rc=$urc) — the arm is void: $( grep -o '<layout [^>]*>' "$UR/warm.out" )"
fi

# exit-code control for the owner decision: a single readable definition still exits 0, a matching mirror 0, drift 2
for ec in PadCase:0:"a single readable definition" TwinUniforms:0:"a matching mirror" MirrorUniforms:2:"mirror drift"; do
    ecName="${ec%%:*}"; ecRest="${ec#*:}"; ecWant="${ecRest%%:*}"; ecWhat="${ecRest#*:}"
    run "$ecName"
    if [ "$RC" -eq "$ecWant" ]; then
        ok "exit codes: $ecWhat ($ecName) exits $ecWant"
    else
        no "exit codes: $ecName exited $RC, expected $ecWant"
    fi
done

[ $fail -eq 0 ] && echo "layoutcheck: ALL PASS" || echo "layoutcheck: FAILURES"
exit $fail
