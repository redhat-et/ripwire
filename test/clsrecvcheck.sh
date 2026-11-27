#!/usr/bin/env bash
# clsrecvcheck.sh — Rule 2c, the CLASS-NAME receiver route (docs/EVALS.md "Phase 4b").
#
#   test/clsrecvcheck.sh                    # uses build/ripwire on test/clsrecvfix
#   RIPWIRE_BIN=asan/ripwire test/clsrecvcheck.sh
#
# WHY THIS GATE EXISTS. `Cls.m(...)` — a static/classmethod call THROUGH THE CLASS NAME — reaches the
# resolver as a named-receiver call whose receiver variable has no local binding, so Rule 2 (typed local)
# cannot fire and the S6-C locality tie-break hands the win to the CALLER's own class by the scope segment.
# On astropy that was 5 of the 13 sibling-class disconfirmations left after Phase 4 (`_Interval.validate(…)`
# pinned to `ModelBoundingBox::validate`; `IERS_B.open()` pinned to `IERS_Auto::open`). Rule 2c reads the
# receiver token as the type it names and resolves the callee against that class — walking its direct bases
# level by level when the class itself defines no such method — under Rule 2b's shadow veto.
#
# THE FIXTURE (test/clsrecvfix/boxes.py): one class-name call, four controls (untyped local, a shadowing
# parameter, an inherited method through the base walk, a class that defines no such method).
#
# The three controls where the route does NOT fire used to assert the S6-C locality pin STANDS (mech=locality,
# lpin="1") — that is, that the caller's own Box::validate kept winning by the scope segment. Since 2026-09-16 an
# explicit receiver whose type no receiver rule established earns no scope-segment credit (test/localitycheck.sh
# arms 5-9: that pin was the wrong answer on 14 of 14 sampled rocksdb sites), so a non-firing route leaves the
# honest two-way split instead. The contrast the controls exist for is unchanged: the route fires ⇒ receiver-rule,
# Interval::validate ALONE; it does not ⇒ both candidates survive.
#
# Arms H-N — a MEMBER FIELD named like a class (2026-09-17). Inside a C++ member function an unqualified name finds a
# member of the class or of a base before any namespace-scope class, so `Reader->read()` beside
# `std::unique_ptr<Widget> Reader;` calls Widget::read. A member is not a local, so the shadow veto never saw it and the
# route read the token as the unrelated class `Reader` in another directory: ONE precise edge to Reader::read, no amb=.
# Two llvm-project instances were graded: LVReader.cpp `OutputFile->keep()` (member `std::unique_ptr<ToolOutputFile>
# OutputFile`) landed on VirtualOutputFile.cpp OutputFile::keep, and SampleProfile.cpp `Reader->read()` (a BASE-class
# member `std::unique_ptr<SampleProfileReader> Reader`) on msgpack Reader::read. The fixture is GENERATED below: a
# smart-pointer member (H), a raw-pointer member (I) and a base's member (J), each of which Rule 2b types once the
# class-name route refuses (H needs #282's pointee capture, J the base walk — both integration/train-5), a class template
# base's member (K), a member 16 levels up, past the base walk's 16-name cap (L); two controls keep the contrast: the
# same call from a class with no such member still takes the route (M), and a Python attribute named like the class does
# not veto a Python class-name call — Python reaches an attribute only through `self.` (N).
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/clsrecvfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }

echo "clsrecvcheck: BIN=$BIN  CORPUS=$CORPUS"

"$BIN" "$CORPUS" --pin-census="$TMP/c.tsv" --no-cache >"$TMP/map.xml" 2>"$TMP/err" || { no "the map run exited non-zero"; sed 's/^/          /' "$TMP/err"; }
MAP="$( cat "$TMP/map.xml" )"
# row 6 (2026-09-12): a scoped row prints n= then sc= (the short id); the canonical id composes as <f p=>::sc::n
row(){ _n="${1##*::}"; _r="${1#*::}"; _s="${_r%::*}"; printf '%s' "$MAP" | tr '<' '\n' | grep "n=\"$_n\" sc=\"$_s\"" | head -1; }
# the census C row for a (caller, callee): "<mech> <targets>"
crow(){ awk -F'\t' -v c="$1" -v n="$2" '$1=="C" && index($6, c"#")==1 && $7==n {print $2 "\t" $8; exit}' "$TMP/c.tsv"; }

# ── (A) THE ROUTE — `Interval.validate(v)` resolves to the class the receiver NAMES ───────────────
R="$( crow 'boxes.py::Box::__setitem__' validate )"
printf '%s' "$R" | grep -q '^receiver-rule	' && ok "(A) Box::__setitem__ -> validate is receiver-rule: $R" \
    || no "(A) Box::__setitem__ -> validate is not receiver-rule: '${R:-no row}'"
printf '%s' "$R" | grep -q 'boxes.py::Interval::validate' && ! printf '%s' "$R" | grep -q 'boxes.py::Box::validate' \
    && ok "(A) the target is Interval::validate alone (not the caller's own Box::validate)" \
    || no "(A) targets are not exactly Interval::validate: '$R'"
printf '%s' "$( row 'boxes.py::Box::__setitem__' )" | grep -q 'lpin=' && no "(A) Box::__setitem__ still carries lpin= — the route did not fire" \
    || ok "(A) no lpin= on Box::__setitem__ — the pin is evidence-backed now"

# a control's census row is the honest two-way split: mech split, BOTH validate definitions, nothing else
isBothSplit(){ printf '%s' "$1" | grep -q '^split	' && printf '%s' "$1" | grep -q 'boxes.py::Interval::validate#' && printf '%s' "$1" | grep -q 'boxes.py::Box::validate#' \
    && [ "$( printf '%s' "$1" | cut -f2 | tr '|' '\n' | grep -c . )" = 2 ]; }

# ── (B) control: an UNTYPED local receiver is not a class name — the route does not fire, the split stands ────
R="$( crow 'boxes.py::Box::other' validate )"
isBothSplit "$R" && ok "(B) Box::other -> item.validate is the honest split, not a route: $R" \
    || no "(B) Box::other -> validate is not the two-way split: '${R:-no row}' (the route must key on the CLASS NAME only)"
printf '%s' "$( row 'boxes.py::Box::other' )" | grep -q 'amb="1"' && ! printf '%s' "$( row 'boxes.py::Box::other' )" | grep -q 'lpin=' \
    && ok "(B) Box::other discloses amb=\"1\" and carries no lpin=" \
    || no "(B) Box::other row does not disclose the split: $( row 'boxes.py::Box::other' )"

# ── (C) control: a PARAMETER named like the class SHADOWS it — vetoed ────────────────────────────
R="$( crow 'boxes.py::Box::shadowed' validate )"
isBothSplit "$R" && ok "(C) Box::shadowed -> Interval.validate is VETOED by the parameter Interval (split): $R" \
    || no "(C) Box::shadowed -> validate is not the two-way split: '${R:-no row}' (a local named Interval must veto the route)"

# ── (D) the DIRECT-base walk: Leaf(Interval) defines no validate — Interval::validate through the base ─
R="$( crow 'boxes.py::Box::inherited' validate )"
printf '%s' "$R" | grep -q '^receiver-rule	' && printf '%s' "$R" | grep -q 'boxes.py::Interval::validate' \
    && ok "(D) Box::inherited -> Leaf.validate lands Interval::validate through the base walk: $R" \
    || no "(D) Box::inherited -> validate: '${R:-no row}' (want receiver-rule -> Interval::validate)"

# ── (E) control: a class that defines no such method and has no bases — nothing fires ───────────
R="$( crow 'boxes.py::Box::miss' validate )"
isBothSplit "$R" && ok "(E) Box::miss -> Point.validate: nothing fires, the ladder's split stands: $R" \
    || no "(E) Box::miss -> validate is not the two-way split: '${R:-no row}' (Point defines no validate — nothing may fire)"

# ── (F) the header agrees: the three controls are the three ambiguous calls, and no locality pin is left ────────
HDR="$( printf '%s' "$MAP" | grep -o '<!-- files=[^>]*-->' | head -1 )"
printf '%s' "$HDR" | grep -q ' ambiguous=3 ' && ! printf '%s' "$HDR" | grep -q 'locality_pinned=[1-9]' \
    && ok "(F) header ambiguous=3 (other, shadowed, miss) and no locality_pinned" \
    || no "(F) header is not ambiguous=3 without a locality pin: $HDR"

# ── (G) determinism + well-formedness ─────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --no-cache >"$TMP/map2.xml" 2>/dev/null
if cmp -s "$TMP/map.xml" "$TMP/map2.xml"; then ok "(G) two runs byte-identical"; else no "(G) the map is not deterministic"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/map.xml" 2>/dev/null; then ok "(G) well-formed XML"; else no "(G) xmllint rejects the map"; fi
fi

# ── Arms H-N: a MEMBER FIELD named like a class hides the class (see the header). Generated fixture: the right
#    `read` is app/widget.cpp's Widget::read; every same-named class sits in msgpack/, a different directory. ──────
MFIX="$TMP/memberfix"
mkdir -p "$MFIX/app" "$MFIX/msgpack" "$MFIX/py"
cat >"$MFIX/app/widget.h" <<'EOF'
struct Widget
{
    int read();
};
EOF
cat >"$MFIX/app/widget.cpp" <<'EOF'
#include "widget.h"
int Widget::read() { return 1; }
EOF
{
    printf '#include <memory>\n#include "widget.h"\n'
    printf 'struct Base\n{\n    Widget* Inherited;\n};\n'
    printf 'template <typename T> struct TBase\n{\n    T* Templated;\n};\n'
    printf 'struct Holder : Base\n{\n    std::unique_ptr<Widget> Reader;\n    Widget* Raw;\n    int viaSmart();\n    int viaRaw();\n    int viaBase();\n};\n'
    printf 'struct Deriv : TBase<Widget>\n{\n    int viaTemplateBase();\n};\n'
    printf 'struct Loose\n{\n    int viaNoMember();\n};\n'
    # a 17-name base chain: Chain0 : Chain1 : … : Chain16, the member on the last — past the 16-name walk cap
    i=16; printf 'struct Chain%s\n{\n    Widget* Deep;\n};\n' "$i"
    while [ "$i" -gt 1 ]; do i=$(( i - 1 )); printf 'struct Chain%s : Chain%s\n{\n};\n' "$i" "$(( i + 1 ))"; done
    printf 'struct Chain0 : Chain1\n{\n    int viaDeepBase();\n};\n'
} >"$MFIX/app/holder.h"
cat >"$MFIX/app/holder.cpp" <<'EOF'
#include "holder.h"
int Holder::viaSmart() { return Reader->read(); }
int Holder::viaRaw() { return Raw->read(); }
int Holder::viaBase() { return Inherited->read(); }
int Deriv::viaTemplateBase() { return Templated->read(); }
int Loose::viaNoMember() { return Reader->read(); }
int Chain0::viaDeepBase() { return Deep->read(); }
EOF
{
    printf '#pragma once\n'
    for c in Reader Raw Inherited Templated Deep; do printf 'struct %s\n{\n    static int read();\n};\n' "$c"; done
} >"$MFIX/msgpack/reader.h"
{
    printf '#include "reader.h"\n'
    n=2; for c in Reader Raw Inherited Templated Deep; do printf 'int %s::read() { return %s; }\n' "$c" "$n"; n=$(( n + 1 )); done
} >"$MFIX/msgpack/reader.cpp"
cat >"$MFIX/py/boxes.py" <<'EOF'
class Interval:
    @staticmethod
    def validate(v):
        return v


class Box:
    def __init__(self):
        self.Interval = None

    def check(self, v):
        return Interval.validate(v)
EOF

"$BIN" "$MFIX" --pin-census="$TMP/mc.tsv" --no-cache >"$TMP/mmap.xml" 2>"$TMP/merr" || { no "(H) the member-fixture map run exited non-zero"; sed 's/^/          /' "$TMP/merr"; }
# the census C row for a (caller, callee) in the member fixture: "<mech> <targets>", "" when the call has no row
mcrow(){ awk -F'\t' -v c="$1" -v n="$2" '$1=="C" && index($6, c"#")==1 && $7==n {print $2 "\t" $8; exit}' "$TMP/mc.tsv"; }
WREAD='app/widget.cpp::Widget::read#'

# presence guards: the members are real field-table rows, and the no-member control resolves at all — a fixture the
# ingest cannot see would pass every "not a wrong pin" arm below by answering nothing
for sel in Holder.Reader Holder.Raw Base.Inherited TBase.Templated Chain16.Deep; do
    "$BIN" "$MFIX" --uses="$sel" --no-cache 2>/dev/null | grep -q ' defs="1" ' \
        && ok "(H) presence: the field table holds member $sel" \
        || no "(H) presence: --uses=$sel finds no member definition — the fixture no longer exercises a member"
done

# a member-hidden site whose member Rule 2b CAN type: the row is the member type's method alone, never the class the
# token names. H (a smart-pointer member, #282) and J (a base class's member, lane/field-base-member) join I on
# integration/train-5 — each member now has a declared type Rule 2b reads.
memberTypePin(){ # $1 arm, $2 caller, $3 the class the token names, $4 what the member is
    _R="$( mcrow "$2" read )"
    printf '%s' "$_R" | grep -q "^receiver-rule	${WREAD}[0-9]*$" \
        && ok "($1) $2 -> read is Rule 2b's Widget::read ALONE, the member's type ($4): $_R" \
        || no "($1) $2 -> read is not receiver-rule to Widget::read alone: '${_R:-no row}' (want the member's type, not class $3)"
}

# a member-hidden site whose member Rule 2b CANNOT type (a class template's base, a member past the walk cap): the
# route must not pin the class the token names. No row (the ladder drops a many-way name) is honest; a row must not
notClassPin(){ # $1 arm, $2 caller, $3 the class the token names
    _R="$( mcrow "$2" read )"
    if [ -z "$_R" ]; then ok "($1) $2 -> read: no edge, not the class-name pin"; return; fi
    printf '%s' "$_R" | grep -q '^receiver-rule	' \
        && no "($1) $2 -> read still takes a receiver rule: '$_R' (a member named $3 hides class $3)" \
        || ok "($1) $2 -> read is not a receiver-rule pin: $_R"
    printf '%s' "$_R" | grep -q "$WREAD" \
        && ok "($1) $2 -> read reaches Widget::read, the member's type" \
        || no "($1) $2 -> read names targets without Widget::read: '$_R' (the class-name pin to $3::read, or a lost edge)"
}
# ── (H) std::unique_ptr<Widget> Reader — the field side table sees the member, and since #282 the compose capture
#        records the pointee, so Rule 2b types it ─────────────────────────────────────────────────────────
memberTypePin H 'app/holder.cpp::Holder::viaSmart' Reader 'std::unique_ptr<Widget> Reader'
# ── (I) Widget* Raw — once the class-name route refuses, Rule 2b reads the member's declared type ───────────
memberTypePin I 'app/holder.cpp::Holder::viaRaw' Raw 'Widget* Raw'
# ── (J) a BASE class's member — Rule 2b walks the bases for a member the class itself does not declare ─────
memberTypePin J 'app/holder.cpp::Holder::viaBase' Inherited "the base's Widget* Inherited"
# ── (K) a class TEMPLATE base's member (`: TBase<Widget>` — chaUp keys the template's name) ───────────────
notClassPin K 'app/holder.cpp::Deriv::viaTemplateBase' Templated
# ── (L) a member 16 levels up: past the walk's 16-name cap a narrow that cannot prove the name unshadowed is
#        withheld, never guessed ────────────────────────────────────────────────────────────────────────────
notClassPin L 'app/holder.cpp::Chain0::viaDeepBase' Deep
# ── (M) CONTROL: the identical call from a class with NO member of that name keeps the route — the refusal keys on the
#        member, not on the language or the call shape ─────────────────────────────────────────────────────────
R="$( mcrow 'app/holder.cpp::Loose::viaNoMember' read )"
printf '%s' "$R" | grep -q '^receiver-rule	msgpack/reader.cpp::Reader::read#[0-9]*$' \
    && ok "(M) control: Loose::viaNoMember -> Reader->read keeps the class-name route: $R" \
    || no "(M) control: Loose::viaNoMember -> read is not receiver-rule to Reader::read: '${R:-no row}' (the refusal must key on a member)"
# ── (N) CONTROL: a Python attribute named like the class does not hide it — `Interval.validate(v)` names the class ─
R="$( mcrow 'py/boxes.py::Box::check' validate )"
"$BIN" "$MFIX" --uses=Box.Interval --no-cache 2>/dev/null | grep -q ' defs="1" ' \
    && ok "(N) presence: the field table holds the Python attribute Box.Interval" \
    || no "(N) presence: --uses=Box.Interval finds no attribute — the language control no longer has a member to ignore"
printf '%s' "$R" | grep -q '^receiver-rule	py/boxes.py::Interval::validate#[0-9]*$' \
    && ok "(N) control: Box::check -> Interval.validate keeps the route despite self.Interval: $R" \
    || no "(N) control: Box::check -> validate is not receiver-rule to Interval::validate: '${R:-no row}' (a Python attribute must not veto)"
"$BIN" "$MFIX" --no-cache >"$TMP/mmap2.xml" 2>/dev/null
[ -s "$TMP/mmap.xml" ] || no "zero-evidence premise (clsrecvcheck.sh:233): the file the next arm judges is empty, so its verdict proves nothing"
if cmp -s "$TMP/mmap.xml" "$TMP/mmap2.xml"; then ok "(N) member fixture: two runs byte-identical"; else no "(N) member fixture: the map is not deterministic"; fi

[ "$fail" = 0 ] && { echo "clsrecvcheck: OK"; exit 0; }
echo "clsrecvcheck: FAILURES ABOVE"; exit 1
