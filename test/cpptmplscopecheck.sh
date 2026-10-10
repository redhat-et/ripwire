#!/usr/bin/env bash
# cpptmplscopecheck.sh — gate: a C++ out-of-line member of a class template's PRIMARY definition keys the same identity
# as its in-class declaration (no template-argument list in its scope); a SPECIALIZATION keeps its own identity; a call
# through a template-id that names no specialization lands on the template's family, never on an unrelated decoy.
#
# THE DEFECT (observed 2026-09-16 while fixing the --pin-census field escape). An out-of-line member definition of
# a class template kept the scope's template-argument list: `template <class T> void Box<T>::grow() {}` minted
# `<s t="method" n="grow" sc="Box&lt;T&gt;">` beside the in-class declaration's `sc="Box"`. One member became two
# identities, so `--callers=Box::grow` resolved the selector to the DECLARATION and answered `count="0"` while
# `use( Box<int>& b ) { b.grow(); }` sat in plain sight. The same raw text reached every consumer of the id: the census
# printed `SmallVec<T, Alloc, SizeType,<LF> GrowingPolicy, N>::grow` with the line break in the id, and a scope whose
# arguments hold `::` was cut INSIDE the list (`template<> void Slot<std::string>::clear()` scoped as `string>`).
# The reference side had the twin at two segments: `Factory<int>::make()` carried the qualifier `Factory<int>`, which
# keys nothing, so the call SPLIT onto an unrelated `Decoy::make` — a caller published for a function nobody called.
#
# THE DECISION (owner, 2026-09-16, after an independent review of the first version of this fix). That first version
# stripped the argument list from EVERY template scope, so a specialization's member joined the primary's. Measured by
# the review on llvm ADT + Support (590 files): 58 precise edges became splits, and one true edge disappeared outright
# (`DenseMapInfo<APSInt>::getHashValue` -> `DenseMapInfo<APInt>::getHashValue`, APSInt.h:371, `--callers` 5 -> 4) —
# a delegation from one specialization into another is a call to a different body. And `Traits<int>::encode( 1 )`
# already resolved precisely on main, because the call's spelling matched the specialization's scope byte for byte.
# So the two halves are split apart:
#   * a PRIMARY template's out-of-line member — the declarator's template-id names exactly the parameters its own
#     `template <…>` introduces (`template <class T, int N> void Box<T, N>::grow()`) — keys the bare template name;
#   * an explicit or partial SPECIALIZATION (`template<> … Traits<int>::encode`, `template <class T> … Slot<T*>`, the
#     members of `template<> struct Slot<bool> { … }`) keeps its template-id, spelled canonically (whitespace dropped
#     except between two identifier characters, `, ` after a comma, so `Traits< int >` and a list broken over lines
#     key the same identity as `Traits<int>`);
#   * a reference keeps the template-id it writes. When no definition is keyed by it, the resolver answers from the
#     template's FAMILY, and only when that answer cannot be missing a body the call may reach (re-review of aa69e66f,
#     llvm Casting.h:548 — the family had omitted what the primary INHERITS and pinned `isa` to one rare
#     specialization): the family is the primary's own OR INHERITED member plus every specialization's own or
#     inherited member (a specialization header's base clause is now read), each member reached through a base
#     widened to that base template's specializations; an existing specialization that does not define the name
#     answers with what it inherits; with nothing visible from the primary, only a split of two or more
#     specializations answers. Anything else is left to the bare-name ladder exactly as before.
#
# SIX CORPORA, generated below into a scratch dir (never committed under test/, where the live-tree gates would
# index them: the repo already has a `grow` with callers, and a fixture def beside it would move the live graph):
#   plain/  the CONTROL — the non-template twin, the join the codebase already makes (decl + out-of-line def = one
#           row, overloads="2"; --callers=Box::grow defs="2" count="1" use).
#   templ/  the SAME file with the template added — line-aligned (the `template <class T>` prefix shares the line),
#           so the ONE difference is templateness; every answer must be byte-identical to plain/'s. `plain` and
#           `templ` are the same length on purpose: root="…" rides in the bytes.
#   shape/  every other PRIMARY spelling, each with its own names so arms cannot lean on each other: a multi-line
#           argument list, a nested-namespace chain, a C++17 nested namespace, a template inside a template, a member
#           function template, an out-of-line nested class of a template, and the two-segment decoy call.
#   spec/   the specializations: the three forms (one with `::` inside its arguments, one broken over lines), the
#           review's own `Traits` probe verbatim, an APSInt-shaped delegation between two explicit specializations
#           across a header and its .cpp, a partial specialization calling its own member (llvm's
#           `SmallVectorTemplateBase<T, true>` shape), and the inherited-member shapes: a primary that inherits the
#           member (Casting.h's CastInfo), a specialization that only inherits it, a primary with nothing visible
#           (CommandLine.h's list_storage), and a primary that defines nothing (MappingTraits).
#   tiepl/ tietm/  the NESTED-CLASS LOCALITY TIE, non-template and template twins (equal-length names): a bare
#           `start()` in `Outer::operator=` beside `Outer::Inner::start`. Both ids share the `Outer::` segment, so the
#           segment-counting tie-break could not choose; on main the non-template twin split and the template twin
#           pinned the NESTED class's `start` (the argument text had hidden the shared segment from one candidate).
#
# EVERY expected value below is a LITERAL read by hand off the fixture text, never derived the way the code does.
#
# RED-FIRST (2026-09-16, plain builds, every arm below; 64 checks):
#   main 31e788ce                      42 FAIL. It passes the §1 control, the presence guards, determinism,
#                                      --callers=Leaf::shed (a suffix match), and the arms that keep main's own correct
#                                      edges (Traits<int|bool|long>::encode, the Dmi delegation, Svb's own-class call,
#                                      the distinct encode rows, Storage<D, bool>::reset, the MapInfo default-argument
#                                      split, the ladder's refusal to pin Storage<D, S>).
#   d42f3639 (first version)           every specialization arm plus both tie twins (17 of the 55 it then had).
#   aa69e66f (second version)          6 FAIL — the inherited-member arms: Caster<int>::isPossible pinned to the one
#                                      defining specialization, Hasher<char>/<long> pinned to the primary's charHash,
#                                      Storage<D, S>::reset pinned to the lone specialization, and --uses=CharBase
#                                      missing the specialization header's extends site.
#   the build before the lone-specialization rule   1 FAIL — Mapping<T>::mapFields fell to the ladder instead of
#                                      splitting over the primary-less template's two specializations.
#   ALL PASS on the fix.
# Usage:  RIPWIRE_BIN=build/ripwire bash test/cpptmplscopecheck.sh   |   bash test/cpptmplscopecheck.sh asan/ripwire
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"      # BOTH seams: positional arg and RIPWIRE_BIN=
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

echo "cpptmplscopecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plain" "$TMP/templ" "$TMP/shape" "$TMP/spec" "$TMP/tiepl" "$TMP/tietm" || { echo "could not create the scratch corpora under $TMP"; exit 2; }
cd "$TMP"

run(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$@" 2>/dev/null; }
cnt(){ printf '%s' "$1" | grep -oE ' count="[0-9]+"' | head -1 | tr -dc 0-9; }
defs(){ printf '%s' "$1" | grep -oE ' defs="[0-9]+"' | head -1 | tr -dc 0-9; }
el(){ printf '%s' "$1" | grep -oE '<(callers|callees|uses|impact) .*' | head -1; }   # the answer, without the legend
noroot(){ sed -e 's/ root="[^"]*"//g'; }

# ── the corpora ─────────────────────────────────────────────────────────────────────────────────────────────────
cat > plain/box.hpp <<'EOF'
struct Box
{
    void grow();
};
void Box::grow()
{
}
void use( Box& b )
{
    b.grow();
}
EOF
cat > templ/box.hpp <<'EOF'
template <class T> struct Box
{
    void grow();
};
template <class T> void Box<T>::grow()
{
}
void use( Box<int>& b )
{
    b.grow();
}
EOF

# multi-line argument list — the census report's own shape
cat > shape/smallvec.hpp <<'EOF'
template <class T, class Alloc, class SizeType, class GrowingPolicy, int N>
struct SmallVec
{
    void reserveMore();
};
template <class T, class Alloc, class SizeType,
          class GrowingPolicy, int N>
void SmallVec<T, Alloc, SizeType,
              GrowingPolicy, N>::reserveMore()
{
}
void useVec( SmallVec<int, int, int, int, 4>& v )
{
    v.reserveMore();
}
EOF

# namespaces, a template inside a template, a member function template, and an out-of-line nested class of a template
cat > shape/nested.hpp <<'EOF'
namespace outer
{
namespace inner
{
template <class T>
struct Cell
{
    void fill();
};
}
}
template <class T>
void outer::inner::Cell<T>::fill()
{
}
namespace outer::inner
{
template <class T>
struct Tray
{
    void stack();
};
template <class T>
void Tray<T>::stack()
{
}
}
template <class T>
struct Tree
{
    template <class U>
    struct Node
    {
        void link();
    };
    struct Leaf;
    template <class W>
    void graft( W w );
};
template <class T>
template <class W>
void Tree<T>::graft( W w )
{
}
template <class T>
template <class U>
void Tree<T>::Node<U>::link()
{
}
template <class T>
struct Tree<T>::Leaf
{
    void shed();
};
void useNested( outer::inner::Cell<int>& c, outer::inner::Tray<int>& t, Tree<int>::Node<long>& n, Tree<int>::Leaf& l, Tree<int>& tr )
{
    c.fill();
    t.stack();
    n.link();
    l.shed();
    tr.graft( 1 );
}
EOF

# the specialization forms — explicit member (with `::` INSIDE its argument list, and one broken over lines), partial
# class, explicit class; the primary's own out-of-line member beside them
cat > spec/slot.hpp <<'EOF'
template <class T>
struct Slot
{
    void clear();
};
template <class T>
void Slot<T>::clear()
{
}
template <>
void Slot<std::string>::clear()
{
}
template <>
void Slot<std::pair<int,
                    long>>::clear()
{
}
template <class T>
struct Slot<T*>
{
    void clear();
};
template <class T>
void Slot<T*>::clear()
{
}
template <>
struct Slot<bool>
{
    void clear();
};
void Slot<bool>::clear()
{
}
void useSlot( Slot<int>& a, Slot<int*>& b )
{
    a.clear();
    b.clear();
}
EOF

# the independent review's probe, verbatim: explicit specializations called through their own template-id, the same
# call spelled with spaces, a template-id no specialization matches, a same-name decoy, and a 3-segment spelling
cat > spec/traits.hpp <<'EOF'
template <class T> struct Traits { static int encode( T v ) { return 0; } };
template <> struct Traits<int> { static int encode( int v ) { return 1; } };
template <> struct Traits<bool> { static int encode( bool v ) { return 2; } };
template <> int Traits<long>::encode( long v ) { return 4; }
struct Decoy { static int encode( int v ) { return 3; } };
int useInt() { return Traits<int>::encode( 1 ); }
int useBool() { return Traits<bool>::encode( true ); }
int useLong() { return Traits<long>::encode( 1L ); }
int useGeneric() { return Traits<double>::encode( 1.0 ); }
int useSpaced() { return Traits< int >::encode( 1 ); }
namespace ns { template <class K> struct Info { static unsigned hash( K k ); }; }
namespace ns { template <> struct Info<char> { static unsigned hash( char k ) { return 7; } }; }
namespace ns { template <class K> unsigned Info<K>::hash( K k ) { return 8; } }
unsigned useInfo() { return ns::Info<char>::hash( 'a' ); }
unsigned useInfo2() { return ns::Info<short>::hash( 1 ); }
EOF

# APSInt.h:371's shape: one explicit specialization delegating to ANOTHER, whose member is defined in a .cpp
cat > spec/dmi.h <<'EOF'
struct Wide
{
};
struct SWide
{
};
template <class T, class E = void>
struct Dmi
{
    static unsigned hashValue( const T& key );
};
template <>
struct Dmi<Wide, void>
{
    static unsigned hashValue( const Wide& key );
};
template <>
struct Dmi<SWide, void>
{
    static unsigned hashValue( const SWide& key )
    {
        return Dmi<Wide, void>::hashValue( key );
    }
};
EOF
cat > spec/dmi.cpp <<'EOF'
#include "dmi.h"
unsigned Dmi<Wide, void>::hashValue( const Wide& key )
{
    return 1;
}
EOF

# llvm SmallVectorTemplateBase<T, true>'s shape: a partial specialization's member calls its OWN class's member
cat > spec/svb.hpp <<'EOF'
template <class T, bool B>
struct Svb
{
    void grow();
    void assignGrow()
    {
        grow();
    }
};
template <class T>
struct Svb<T, true>
{
    void grow();
    void assignGrow()
    {
        grow();
    }
};
template <class T, bool B>
void Svb<T, B>::grow()
{
}
template <class T>
void Svb<T, true>::grow()
{
}
EOF

# the family fallback must see INHERITED members (re-review of aa69e66f, llvm Casting.h:548): the primary `Caster`
# defines no isPossible but inherits PossibleBase's; one partial specialization defines its own; another only inherits
# PtrBase's; Unrelated is a same-name decoy outside the template
cat > spec/caster.hpp <<'EOF'
struct PossibleBase { static bool isPossible( int v ) { return v > 0; } };
struct PtrBase { static bool isPossible( int v ) { return v != 0; } };
template <class T, class Enable = void> struct Caster : PossibleBase { static int tag() { return 0; } };
template <class T> struct Caster<T, typename T::simplified> { static bool isPossible( int v ) { return v < 0; } };
template <class T> struct Caster<T*> : PtrBase {};
struct Unrelated { static bool isPossible( int v ) { return false; } };
bool useInherited() { return Caster<int>::isPossible( 1 ); }
template <class K, class E = void> struct MapInfo { static unsigned keyHash( const K& ) { return 0; } };
struct Key {};
template <> struct MapInfo<Key, void> { static unsigned keyHash( const Key& ) { return 1; } };
unsigned useDefaultArg() { return MapInfo<Key>::keyHash( Key{} ); }
EOF

# a specialization that only INHERITS the member the primary defines itself
cat > spec/hasher.hpp <<'EOF'
struct CharBase { static unsigned charHash( char c ) { return 1; } };
template <class T, class E = void> struct Hasher { static unsigned charHash( T t ) { return 0; } };
template <> struct Hasher<char> : CharBase {};
unsigned useSpecInherited() { return Hasher<char>::charHash( 'a' ); }
unsigned usePrimaryHasher() { return Hasher<long>::charHash( 1L ); }
EOF

# llvm CommandLine.h list_storage's shape: the primary supplies nothing visible (here: declared only), so a call
# through `Storage<D, S>` must not become a lone pin to the one specialization; the exact `<D, bool>` call is precise
cat > spec/store.hpp <<'EOF'
template <class D, class S> class Storage;
template <class D> class Storage<D, bool>
{
public:
    void reset();
};
template <class D> void Storage<D, bool>::reset()
{
}
struct OtherStore
{
    void reset();
};
void OtherStore::reset()
{
}
template <class D, class S> struct ListOpt : Storage<D, S>
{
    void clearAll()
    {
        Storage<D, S>::reset();
    }
    void clearDefault()
    {
        Storage<D, bool>::reset();
    }
};
EOF

# a traits template whose PRIMARY defines nothing (llvm's MappingTraits / DenseMapInfo shape): only its specializations
# can be reached, so a call through a dependent template-id is their split — never a stray same-name function
cat > spec/mapping.hpp <<'EOF'
template <class T, class E = void> struct Mapping
{
};
struct Alpha
{
};
struct Beta
{
};
template <> struct Mapping<Alpha> { static void mapFields( Alpha& ) {} };
template <> struct Mapping<Beta> { static void mapFields( Beta& ) {} };
struct Stray { static void mapFields( int ) {} };
template <class T> void doMapping( T& v ) { Mapping<T>::mapFields( v ); }
EOF

# the nested-class locality tie, non-template and template twins
cat > tiepl/m.hpp <<'EOF'
struct Outer
{
    void start();
    struct Inner;
    Outer& operator=( const Outer& o );
};
struct Outer::Inner
{
    void start();
};
Outer& Outer::operator=( const Outer& o )
{
    start();
    return *this;
}
EOF
cat > tietm/m.hpp <<'EOF'
template <class T> struct Outer
{
    void start();
    struct Inner;
    Outer& operator=( const Outer& o );
};
template <class T> struct Outer<T>::Inner
{
    void start();
};
template <class T> Outer<T>& Outer<T>::operator=( const Outer& o )
{
    start();
    return *this;
}
EOF

# the two-segment static call, with a same-final-name decoy in another class
cat > shape/statics.hpp <<'EOF'
template <class T>
struct Factory
{
    static Factory make();
};
template <class T>
Factory<T> Factory<T>::make()
{
    return {};
}
struct Decoy
{
    static Decoy make();
};
Decoy Decoy::make()
{
    return {};
}
void build()
{
    Factory<int>::make();
}
EOF

# ── §1 THE CONTROL: how the codebase already joins a NON-template out-of-line member ────────────────────────────
PMAP="$( run plain --no-cache --legend=compact )"
PCALL="$( run plain --callers=Box::grow --no-cache --legend=compact )"
[ "$( printf '%s' "$PMAP" | grep -oE '<s t="method" n="grow"[^>]*>' | sed 's/ k="[^"]*"//' )" = '<s t="method" n="grow" sc="Box" overloads="2">' ] \
    && ok "control: declaration + out-of-line definition are ONE map row, sc=\"Box\" overloads=\"2\"" \
    || no "control map row moved — the join this gate mirrors is not what it was: $( printf '%s' "$PMAP" | grep -oE '<s t="method" n="grow"[^>]*>' | tr '\n' ' ' )"
{ [ "$( defs "$PCALL" )" = 2 ] && [ "$( cnt "$PCALL" )" = 1 ] && printf '%s' "$PCALL" | grep -q '<s t="fn" n="use" p="box.hpp:8" sites_at="box.hpp:10"/>'; } \
    && ok "control: --callers=Box::grow defs=\"2\" count=\"1\" -> use (box.hpp:8)" \
    || no "control: --callers=Box::grow expected defs=2 count=1 use, got: $( el "$PCALL" )"

# ── §2 THE CONTRAST: the template twin answers byte-identically ─────────────────────────────────────────────────
TMAP="$( run templ --no-cache --legend=compact )"
TCALL="$( run templ --callers=Box::grow --no-cache --legend=compact )"
{ [ "$( defs "$TCALL" )" = 2 ] && [ "$( cnt "$TCALL" )" = 1 ] && printf '%s' "$TCALL" | grep -q '<s t="fn" n="use" p="box.hpp:8" sites_at="box.hpp:10"/>'; } \
    && ok "templ: --callers=Box::grow defs=\"2\" count=\"1\" -> use — the definition and the declaration are one member" \
    || no "templ: --callers=Box::grow expected defs=2 count=1 use (the control's answer), got: $( el "$TCALL" )"
[ "$( printf '%s' "$TMAP" | grep -oE '<s t="method" n="grow"[^>]*>' | sed 's/ k="[^"]*"//' )" = '<s t="method" n="grow" sc="Box" overloads="2">' ] \
    && ok "templ: ONE map row sc=\"Box\" overloads=\"2\", as the control" \
    || no "templ: the member is still split across rows: $( printf '%s' "$TMAP" | grep -oE '<s t="method" n="grow"[^>]*>' | tr '\n' ' ' )"
[ "$( printf '%s' "$TMAP" | noroot )" = "$( printf '%s' "$PMAP" | noroot )" ] \
    && ok "templ: the whole map is byte-identical to the control's (root= aside)" \
    || no "templ: map differs from the control's: $( diff <( printf '%s' "$PMAP" | noroot | sed 's/<s /\n<s /g' ) <( printf '%s' "$TMAP" | noroot | sed 's/<s /\n<s /g' ) | grep '^[<>]' | tr '\n' ' ' )"
# Each verb's presence guard reads the attribute that verb actually answers with: --callers count=, --impact
# reaches=, --uses defs=. --uses reads defs= and not count= because a `::` selector's count= on --uses is 0 on the
# CONTROL too — a separate selector defect with its own lane (fix/uses-qualified-selector) — so a count= guard
# would declare the arm vacuous for a reason this gate is not about, while defs= is exactly the join (1 vs 2).
for pair in callers:count impact:reaches uses:defs; do
    verb="${pair%%:*}"; attr="${pair#*:}"
    P="$( run plain "--$verb=Box::grow" --no-cache --legend=compact | noroot )"
    T="$( run templ "--$verb=Box::grow" --no-cache --legend=compact | noroot )"
    got="$( printf '%s' "$P" | grep -oE " $attr=\"[0-9]+\"" | head -1 | tr -dc 0-9 )"
    # presence guard: two empty answers agree about nothing (CONTRIBUTING §2 shape 3)
    if [ -z "$got" ] || [ "$got" = 0 ]; then
        no "control --$verb=Box::grow answered $attr='$got' — the contrast below would be vacuous"
        continue
    fi
    [ "$T" = "$P" ] \
        && ok "templ: --$verb=Box::grow byte-identical to the control ($attr=\"$got\")" \
        || no "templ: --$verb=Box::grow differs from the control — control: $( el "$P" ) — templ: $( el "$T" )"
done
run plain --pin-census="$TMP/plain.tsv" --no-cache >/dev/null
run templ --pin-census="$TMP/templ.tsv" --no-cache >/dev/null
PC="$( grep -E $'^(C|S)\t' "$TMP/plain.tsv" 2>/dev/null )"
TC="$( grep -E $'^(C|S)\t' "$TMP/templ.tsv" 2>/dev/null )"
printf '%s\n' "$PC" | grep -qE $'^C\t[a-z-]+\t.*\tbox\\.hpp::use#[0-9]+\tgrow\tbox\\.hpp::Box::grow#[0-9]+\t10$' \
    && ok "control census: use -> box.hpp::Box::grow at line 10" \
    || no "control census row for use -> grow missing: $( printf '%s' "$PC" | tr '\n\t' '| ' )"
# The IDENTITIES must be identical — every S row, and every C row's caller, callee, targets and line. The deciding
# MECHANISM (column 2) and its flags (column 5) are masked: since #248 (typed-parameter receivers) the control's
# `Box& b` narrows by receiver-rule, while `Box<int>& b`'s written type keeps its argument list, matches no scope, and
# the same single target is labelled `unique` — a label difference, not an edge difference (disclosed follow-up).
censusIds(){ printf '%s\n' "$1" | awk -F '\t' 'BEGIN { OFS = "\t" } $1 == "C" { $2 = "-"; $5 = "-" } { print }'; }
[ -n "$PC" ] && [ "$( censusIds "$TC" )" = "$( censusIds "$PC" )" ] \
    && ok "templ census: every S row and every C row's caller, callee, targets and line identical to the control's (the S6-C id space is the same)" \
    || no "templ census identities differ — control: $( censusIds "$PC" | tr '\n\t' '| ' ) — templ: $( censusIds "$TC" | tr '\n\t' '| ' )"

# ── §3 NO TEMPLATE ARGUMENTS IN A PRIMARY TEMPLATE'S SCOPE, over every other spelling ───────────────────────────
SMAP="$( run shape --no-cache --legend=compact )"
run shape --pin-census="$TMP/shape.tsv" --no-cache >/dev/null
SC_ALL="$( printf '%s' "$SMAP" | grep -oE ' sc="[^"]*"' )"
# 16 by hand once joined: smallvec 2 (SmallVec, reserveMore) + nested 10 (Cell fill Tray stack Tree Node link Leaf shed
# graft) + statics 4 (Factory, Factory::make, Decoy, Decoy::make). The split pre-fix map has more rows.
[ "$( printf '%s\n' "$SC_ALL" | grep -c . )" -ge 16 ] \
    && ok "presence: the shape map carries $( printf '%s\n' "$SC_ALL" | grep -c . ) sc= attributes (>= 16) — the sweep below has a population" \
    || no "presence: the shape map carries only $( printf '%s\n' "$SC_ALL" | grep -c . ) sc= attributes — the no-arguments sweep would be vacuous"
BAD="$( printf '%s\n' "$SC_ALL" | grep -E '&lt;|&gt;|&#10;|&#13;' )"
[ -z "$BAD" ] \
    && ok "no sc= value holds a template-argument list or a line break" \
    || no "$( printf '%s\n' "$BAD" | grep -c . ) sc= values still carry template text: $( printf '%s' "$BAD" | tr '\n' ' ' )"
[ -s "$TMP/shape.tsv" ] \
    && ok "presence: the shape census wrote rows" \
    || no "the shape census wrote nothing — the two census arms below would be vacuous"
[ "$( grep -v '^#' "$TMP/shape.tsv" | grep -c '<' )" = 0 ] \
    && ok "no census id holds a template-argument list" \
    || no "census ids still carry template text: $( grep -v '^#' "$TMP/shape.tsv" | grep '<' | tr '\n\t' '| ' )"
[ "$( grep -v '^#' "$TMP/shape.tsv" | grep -cvE $'^(C|S|O)\t' )" = 0 ] \
    && ok "every census data line is a whole C/S row — no id broke across lines" \
    || no "census lines that are not whole rows (an id split by a line break): $( grep -v '^#' "$TMP/shape.tsv" | grep -vE $'^(C|S|O)\t' | tr '\n\t' '| ' )"

row(){ printf '%s' "$SMAP" | grep -oE "<s t=\"$1\" n=\"$2\"[^>]*>" | sed 's/ k="[^"]*"//'; }
expect_row(){   # $1 kind  $2 name  $3 exact tag (k= stripped)  $4 prose
    [ "$( row "$1" "$2" )" = "$3" ] \
        && ok "$4: $3" \
        || no "$4 — expected $3, got: $( row "$1" "$2" | tr '\n' ' ' )"
}
expect_callers(){   # $1 selector  $2 defs  $3 caller name  $4 prose
    local out; out="$( run shape "--callers=$1" --no-cache --legend=compact )"
    { [ "$( defs "$out" )" = "$2" ] && [ "$( cnt "$out" )" = 1 ] && printf '%s' "$out" | grep -q "<s t=\"fn\" n=\"$3\""; } \
        && ok "--callers=$1 defs=\"$2\" count=\"1\" -> $3 — $4" \
        || no "--callers=$1 expected defs=$2 count=1 $3 — $4 — got: $( el "$out" )"
}

expect_row     method reserveMore '<s t="method" n="reserveMore" sc="SmallVec" overloads="2">' "multi-line argument list joins its declaration"
expect_callers SmallVec::reserveMore 2 useVec "the list broken over two lines, both in the declarator and in the header"
expect_row     method fill  '<s t="method" n="fill" sc="Cell" overloads="2">'  "outer::inner::Cell<T>::fill (2+ segment declarator) joins"
expect_callers Cell::fill   2 useNested "nested-namespace chain"
expect_row     method stack '<s t="method" n="stack" sc="Tray" overloads="2">' "Tray<T>::stack inside a C++17 nested namespace joins"
expect_callers Tray::stack  2 useNested "C++17 nested namespace"
expect_row     method link  '<s t="method" n="link" sc="Node" overloads="2">'  "Tree<T>::Node<U>::link keys its IMMEDIATE scope, arguments stripped"
expect_callers Node::link   2 useNested "a template member of a template"
expect_row     cls    Leaf  '<s t="cls" n="Leaf" sc="Tree">'                  "the out-of-line nested class Tree<T>::Leaf scopes to its container"
expect_row     method shed  '<s t="method" n="shed" sc="Tree::Leaf">'         "its member scopes to Tree::Leaf, the non-template Outer::Inner reading"
expect_callers Leaf::shed   1 useNested "member of an out-of-line nested class of a template"
# (the in-class `template <class W> void graft( W w );` declaration is extracted as t="fn" and the out-of-line body as
# t="method" — a separate kind-classification gap for member templates — so the map shows two rows; the IDENTITY is
# the join this pair proves, through the scope pairing rule: two `template <…>` lists, one template-id)
expect_row     method graft '<s t="method" n="graft" sc="Tree">' "a member FUNCTION template's out-of-line body scopes to Tree (two template <…>, one template-id)"
expect_callers Tree::graft  2 useNested "a member function template's declaration and body are one member"

# ── §4 A SPECIALIZATION KEEPS ITS OWN IDENTITY, spelled canonically (the decision in the header) ───────────────
XMAP="$( run spec --no-cache --legend=compact )"
run spec --pin-census="$TMP/spec.tsv" --no-cache >/dev/null
[ -s "$TMP/spec.tsv" ] \
    && ok "presence: the spec census wrote rows" \
    || no "the spec census wrote nothing — every census arm in §4 would be vacuous"
xrows(){ printf '%s' "$XMAP" | grep -oE "<s t=\"method\" n=\"$1\"[^>]*>" | sed 's/ k="[^"]*"//' | LC_ALL=C sort | tr '\n' '|'; }
expect_rows(){   # $1 name  $2 the exact sorted row set, '|'-joined  $3 prose
    [ "$( xrows "$1" )" = "$2" ] \
        && ok "$3" \
        || no "$3 — expected $2 — got $( xrows "$1" )"
}
# the census answer for one caller's sites: "<mech>\t<target|target…>" per site, ids without #NODEID, targets sorted
xsite(){ awk -F'\t' -v c="$1" '$1=="C" { id=$6; sub( /#[0-9]+$/, "", id ); if( id == c ) { t=$8; gsub( /#[0-9]+/, "", t ); print $2 "\t" t } }' "$TMP/spec.tsv"; }
xtargets(){ xsite "$1" | cut -f2 | tr '|' '\n' | LC_ALL=C sort | tr '\n' '|'; }
expect_site(){   # $1 caller id  $2 exact "<mech>\t<target>"  $3 prose
    [ "$( xsite "$1" )" = "$2" ] \
        && ok "census: $3" \
        || no "census: $3 — expected '$( printf '%s' "$2" | tr '\t' ' ' )' — got '$( xsite "$1" | tr '\t\n' ' ;' )'"
}

expect_rows clear '<s t="method" n="clear" sc="Slot" overloads="2">|<s t="method" n="clear" sc="Slot&lt;T*&gt;" overloads="2">|<s t="method" n="clear" sc="Slot&lt;bool&gt;" overloads="2">|<s t="method" n="clear" sc="Slot&lt;std::pair&lt;int, long&gt;&gt;">|<s t="method" n="clear" sc="Slot&lt;std::string&gt;">|' \
    "slot.hpp: the primary joins its declaration; the partial and explicit class specializations each join theirs; the two explicit members stand alone — the \`::\` list uncut, the broken list on one line"
expect_rows encode '<s t="method" n="encode" sc="Decoy">|<s t="method" n="encode" sc="Traits">|<s t="method" n="encode" sc="Traits&lt;bool&gt;">|<s t="method" n="encode" sc="Traits&lt;int&gt;">|<s t="method" n="encode" sc="Traits&lt;long&gt;">|' \
    "traits.hpp: an explicit specialization's member does NOT join the primary's (five identities, not one)"
expect_rows hash '<s t="method" n="hash" sc="Info" overloads="2">|<s t="method" n="hash" sc="Info&lt;char&gt;">|' \
    "traits.hpp: Info<K>::hash (primary, out of line, inside ns) joins its declaration; Info<char> stays apart"

expect_site 'traits.hpp::useInt'    $'qualified\ttraits.hpp::Traits<int>::encode'  "Traits<int>::encode( 1 ) is ONE precise edge to the int specialization (main's edge, kept)"
expect_site 'traits.hpp::useBool'   $'qualified\ttraits.hpp::Traits<bool>::encode' "Traits<bool>::encode( true ) is precise"
expect_site 'traits.hpp::useLong'   $'qualified\ttraits.hpp::Traits<long>::encode' "Traits<long>::encode( 1L ) reaches the out-of-line explicit MEMBER specialization"
expect_site 'traits.hpp::useSpaced' $'qualified\ttraits.hpp::Traits<int>::encode'  "Traits< int >::encode( 1 ) keys the same canonical identity (main split it five ways)"
expect_site 'traits.hpp::useInfo'   $'qualified\ttraits.hpp::Info<char>::hash'     "ns::Info<char>::hash( 'a' ), a 3-segment spelling, keeps its template-id and is precise"
[ "$( xtargets 'traits.hpp::useGeneric' )" = 'traits.hpp::Traits::encode|traits.hpp::Traits<bool>::encode|traits.hpp::Traits<int>::encode|traits.hpp::Traits<long>::encode|' ] \
    && ok "census: Traits<double>::encode names no specialization, so it lands on the Traits FAMILY (primary + 3 specializations) — never Decoy::encode" \
    || no "census: Traits<double>::encode expected the four-member Traits family, got '$( xtargets 'traits.hpp::useGeneric' )'"
[ "$( xtargets 'traits.hpp::useInfo2' )" = 'traits.hpp::Info::hash|traits.hpp::Info<char>::hash|' ] \
    && ok "census: ns::Info<short>::hash lands on the Info family (primary + Info<char>)" \
    || no "census: ns::Info<short>::hash expected the Info family, got '$( xtargets 'traits.hpp::useInfo2' )'"
TENC="$( run spec --callers=Traits::encode --no-cache --legend=compact )"
{ printf '%s' "$TENC" | grep -q 'n="useGeneric"' && ! printf '%s' "$TENC" | grep -qE 'n="use(Int|Bool|Long|Spaced)"'; } \
    && ok "--callers=Traits::encode lists useGeneric (the family split) and none of the four calls a specialization owns" \
    || no "--callers=Traits::encode should list useGeneric only among the Traits callers, got: $( el "$TENC" )"

expect_site 'dmi.h::Dmi<SWide, void>::hashValue' $'qualified\tdmi.cpp::Dmi<Wide, void>::hashValue' \
    "Dmi<SWide>::hashValue delegating to Dmi<Wide, void>::hashValue is an edge to the OTHER specialization's body in dmi.cpp"
DMI="$( run spec --callers=dmi.cpp:hashValue --no-cache --legend=compact )"
{ [ "$( cnt "$DMI" )" = 1 ] && printf '%s' "$DMI" | grep -q 'n="hashValue" p="dmi.h:20"'; } \
    && ok "--callers=dmi.cpp:hashValue count=\"1\" -> dmi.h:20 (APSInt.h:371's shape; the first version of this fix answered 0)" \
    || no "--callers=dmi.cpp:hashValue expected count=1 from dmi.h:20, got: $( el "$DMI" )"
expect_site 'svb.hpp::Svb<T, true>::assignGrow' "$( xsite 'svb.hpp::Svb<T, true>::assignGrow' | cut -f1 )"$'\tsvb.hpp::Svb<T, true>::grow' \
    "a partial specialization's own-class call grow() binds ITS grow, one target"
[ "$( xtargets 'svb.hpp::Svb::assignGrow' )" = 'svb.hpp::Svb::grow|' ] \
    && ok "census: the primary's own-class call grow() binds the primary's grow, one target" \
    || no "census: Svb::assignGrow expected the primary's grow alone, got '$( xtargets 'svb.hpp::Svb::assignGrow' )'"
# ── inherited members in the family (the re-review's R1): a family answer that omits what the primary or a
# specialization INHERITS is a confident wrong edge; one that includes it is an honest split
[ "$( xtargets 'caster.hpp::useInherited' )" = 'caster.hpp::Caster<T, typename T::simplified>::isPossible|caster.hpp::PossibleBase::isPossible|caster.hpp::PtrBase::isPossible|' ] \
    && ok "census: Caster<int>::isPossible splits over the primary's INHERITED PossibleBase::isPossible, the defining specialization and the inheriting Caster<T*>'s PtrBase::isPossible — no lone pin, no Unrelated" \
    || no "census: Caster<int>::isPossible expected the three-member family with inherited members, got '$( xtargets 'caster.hpp::useInherited' )'"
[ "$( xsite 'caster.hpp::useInherited' | cut -f1 )" = split ] \
    && ok "census: that family answer is a disclosed split (mech=split), never mech=qualified to one body" \
    || no "census: Caster<int>::isPossible expected mech=split, got '$( xsite 'caster.hpp::useInherited' | tr '\t\n' ' ;' )'"
[ "$( xtargets 'caster.hpp::useDefaultArg' )" = 'caster.hpp::MapInfo::keyHash|caster.hpp::MapInfo<Key, void>::keyHash|' ] \
    && ok "census: MapInfo<Key>::keyHash (a default-argument spelling of MapInfo<Key, void>) is the two-member family split" \
    || no "census: MapInfo<Key>::keyHash expected the MapInfo family, got '$( xtargets 'caster.hpp::useDefaultArg' )'"
[ "$( xtargets 'mapping.hpp::doMapping' )" = 'mapping.hpp::Mapping<Alpha>::mapFields|mapping.hpp::Mapping<Beta>::mapFields|' ] \
    && ok "census: Mapping<T>::mapFields — a primary that defines nothing — is the split of its two specializations, no Stray" \
    || no "census: Mapping<T>::mapFields expected the two-specialization split, got '$( xtargets 'mapping.hpp::doMapping' )'"
expect_site 'hasher.hpp::useSpecInherited' $'qualified\thasher.hpp::CharBase::charHash' \
    "Hasher<char>::charHash reaches what the char specialization INHERITS (CharBase), never the primary's own charHash"
[ "$( xtargets 'hasher.hpp::usePrimaryHasher' )" = 'hasher.hpp::CharBase::charHash|hasher.hpp::Hasher::charHash|' ] \
    && ok "census: Hasher<long>::charHash splits over the primary's member and the inheriting specialization's — no lone pin" \
    || no "census: Hasher<long>::charHash expected the primary + CharBase split, got '$( xtargets 'hasher.hpp::usePrimaryHasher' )'"
[ "$( xsite 'store.hpp::ListOpt::clearAll' | cut -f2 | tr '|' '\n' | grep -c . )" -ge 2 ] \
    && ok "census: Storage<D, S>::reset() with a primary that supplies nothing visible is NOT a lone pin to Storage<D, bool>::reset (the ladder decides: $( xsite 'store.hpp::ListOpt::clearAll' | cut -f1 ))" \
    || no "census: Storage<D, S>::reset() became a lone pin: '$( xsite 'store.hpp::ListOpt::clearAll' | tr '\t\n' ' ;' )'"
expect_site 'store.hpp::ListOpt::clearDefault' $'qualified\tstore.hpp::Storage<D, bool>::reset' \
    "Storage<D, bool>::reset() — the exact template-id — is precise"
XUSES="$( run spec --uses=CharBase --no-cache --legend=compact )"
printf '%s' "$XUSES" | grep -q '<u role="extends" p="hasher.hpp:3"' \
    && ok "--uses=CharBase lists the specialization header's base clause (hasher.hpp:3), which was never read before" \
    || no "--uses=CharBase is missing the specialization's extends site: $( el "$XUSES" )"
BADX="$( printf '%s' "$XMAP" | grep -oE ' sc="[^"]*"' | grep -E '&#10;|&#13;|sc="string' )"
[ -z "$BADX" ] \
    && ok "no specialization sc= holds a line break or a list cut at an inner ::" \
    || no "specialization scopes still carry raw text: $( printf '%s' "$BADX" | tr '\n' ' ' )"
[ "$( grep -v '^#' "$TMP/spec.tsv" | grep -cvE $'^(C|S|O)\t' )" = 0 ] \
    && ok "every spec census data line is a whole C/S row — no id broke across lines" \
    || no "spec census lines that are not whole rows: $( grep -v '^#' "$TMP/spec.tsv" | grep -vE $'^(C|S|O)\t' | tr '\n\t' '| ' )"

# ── §5 THE REFERENCE SIDE: a two-segment call through a template-id is QUALIFIED, not sprayed onto a decoy ─────
expect_callers Factory::make 2 build "Factory<int>::make() keys Factory::make"
DECOY="$( run shape --callers=Decoy::make --no-cache --legend=compact )"
{ [ "$( defs "$DECOY" )" = 2 ] && [ "$( cnt "$DECOY" )" = 0 ]; } \
    && ok "--callers=Decoy::make defs=\"2\" count=\"0\" — no false caller (was count=\"1\" build)" \
    || no "--callers=Decoy::make expected defs=2 count=0, got: $( el "$DECOY" )"
[ "$( run shape --uses=make --no-cache --legend=compact | grep -oE '<u role="call" p="statics\.hpp:21" in_id="build"/>' | grep -c . )" = 1 ] \
    && ok "presence: build's make() site is still a use-site — the zero above is resolution, not a lost reference" \
    || no "build's make() site vanished from --uses=make — the Decoy arm is vacuous"
printf '%s' "$SMAP" | grep -qE '<s t="fn" n="build"[^>]* amb=' \
    && no "build still carries amb= — the call was split, not qualified" \
    || ok "build carries no amb= (was amb=\"1\")"
[ "$( awk -F'\t' '$1=="C" && $6 ~ /^statics\.hpp::build#/ { sub( /#[0-9]+$/, "", $8 ); print $2 "\t" $8 }' "$TMP/shape.tsv" )" = "$( printf 'qualified\tstatics.hpp::Factory::make' )" ] \
    && ok "census: build's site is decided by mech=qualified -> statics.hpp::Factory::make" \
    || no "census: build's site expected qualified -> Factory::make, got: $( awk -F'\t' '$1=="C" && $6 ~ /^statics\.hpp::build#/' "$TMP/shape.tsv" | tr '\n\t' '| ' )"

# ── §6 THE NESTED-CLASS LOCALITY TIE: a bare call in Outer's member binds Outer::start, not Outer::Inner::start ───
# Both candidates share the caller's whole `m.hpp::Outer::` prefix, so counting shared segments ties them. A bare or
# `this->` call inside a scope names that scope's member: a nested class's non-static member needs an object. The
# tie-break now prefers the candidate declared in the caller's own scope over one nested inside it (resolve.h
# localityRank) — and only for a bare or `this->` call, where the enclosing scope is the evidence.
for tie in tiepl tietm; do
    run "$tie" --pin-census="$TMP/$tie.tsv" --no-cache >/dev/null
    got="$( awk -F'\t' '$1=="C" { id=$6; sub( /#[0-9]+$/, "", id ); t=$8; gsub( /#[0-9]+/, "", t ); print $2 "\t" id "\t" t }' "$TMP/$tie.tsv" )"
    [ "$got" = "$( printf 'locality\tm.hpp::Outer::operator=\tm.hpp::Outer::start' )" ] \
        && ok "$tie: start() in Outer::operator= binds m.hpp::Outer::start alone (mech=locality)" \
        || no "$tie: expected locality -> m.hpp::Outer::start, got '$( printf '%s' "$got" | tr '\t\n' ' ;' )'"
done

# ── §7 determinism ──────────────────────────────────────────────────────────────────────────────────────────────
for corpus in shape spec; do
    run "$corpus" --pin-census="$TMP/$corpus.again.tsv" --no-cache >"$TMP/$corpus.again.xml"
    run "$corpus" --pin-census="$TMP/$corpus.once.tsv" --no-cache >"$TMP/$corpus.once.xml"
    { cmp -s "$TMP/$corpus.again.xml" "$TMP/$corpus.once.xml" && cmp -s "$TMP/$corpus.again.tsv" "$TMP/$corpus.once.tsv"; } \
        && ok "deterministic: $corpus map and census byte-identical across two --no-cache runs" \
        || no "$corpus map or census differs between two identical runs"
done

if [ "$fail" = 0 ]; then echo "cpptmplscopecheck: ALL PASS"; else echo "cpptmplscopecheck: FAIL"; fi
exit "$fail"
