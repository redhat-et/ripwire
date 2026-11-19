#!/usr/bin/env bash
# langordercheck.sh — task D gate: language-first order for name answers.
#
# The rule (owner's): exact matching language > its edge-family (langCompatible's class) > the
# kind ladder > foreign languages last — levels decide WITHIN a group, never across it. The
# fixtures in test/langorderfix/ + test/langorderjvmfix/ are the collision matrix; their file
# comments carry the tier each line demonstrates. The arms were written red-first against the
# rank-first lane with its path-accident reference language; they ship green with the change.
#
# Arms:
#   (A1) corpus anchor (no context): langorderfix leads with the C++ fn despite rank 2 vs 3/4
#   (A2) @rs suffix pins the foreign trait exact-first          (A3) @c makes the C answer exact
#   (A4) @bogus refuses, naming the known tags                  (A5) foreign fallback SAYS so
#   (A6) JVM corpus: kt wins the count, jv/ never fronts on id  (A7) determinism x2
#   (A8) "?" is display-fallback, never vocabulary               (A9) @lang must not blind the qualified lane
#   (A10) same-rung tie-break: majority fronts AND says so, with the pasteable --defs= next
#   (A11) different rungs: the ladder fronts over the majority language, in silence
#   (A12) single def, active majority anchor: still silent (reflang decided nothing)
#   (A13) a stated @lang must scope the Scope::name tier too — A::f@rs answers RUST, not the id accident
#   (A14) a file lane that names one place is silent          (A15) so is an @FILE:LINE seed
#   (A16) the majority reorders a LOWER rung only: the front did not move, the root is silent
#   (A17) `Box.run@py` reaches the dotted tier tail-free, and the stated tag scopes that tier's answer (@js: disclosed fallback)
#   (A18) literal first on the "::" tiers: an indexed `notes.md::config::user@py` heading answers as itself
#   (A19) the refusal reads the NAME: `data.json:user@corp` and an @FILE:LINE seed whose path holds '@' resolve
#
# Usage:  bash test/langordercheck.sh [path/to/ripwire]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
FIX="$ROOT/test/langorderfix"
JVM="$ROOT/test/langorderjvmfix"
FIX2="$ROOT/test/langorder2fix"
FIX3="$ROOT/test/langorderscopefix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# ── (A1) no stated language: the LADDER fronts — widget.rs's trait is the top rung (Interface 4); the
#    cpp fn (2) cannot ride the census any more (that lifting is what this commit removes). The head
#    rung stands alone, so the majority tie-break is never asked: the root is SILENT.
A1="$( "$BIN" --around=Shape "$FIX" 2>/dev/null )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
A1R="$( printf '%s' "$A1" | grep -m1 -o '<r [^>]*>' )"
first="$( printf '%s' "$A1" | grep -m1 -o '<s [^>]*' )"
case "$first" in
    *'t="iface"'*'n="Shape"'*)
        fp="$( printf '%s' "$A1" | grep -m1 -o '<f p="[^"]*"' | head -1 )"
        case "$fp" in *'p="widget.rs"'*)
            case "$A1R" in
                *reflang*|*next=*) no "(A1) ladder answered on the top rung alone yet the root discloses: $A1R" ;;
                *) ok "(A1) Shape fronts widget.rs's trait on KIND (rung 4), root silent — an unused majority says nothing" ;;
            esac
        ;; *) no "(A1) front file wrong (want widget.rs first): $fp / $first" ;; esac
    ;; *) no "(A1) focus row wrong (a fn on top means the corpus tier still lifts): $first" ;;
esac

# ── (A2/A3) @lang suffix: explicit anchor is exact-tier, byte-pinned per family ─────────────────────
A2="$( "$BIN" --around=Shape@rs "$FIX" 2>/dev/null | grep -m1 -o '<s [^>]*' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
A2F="$( "$BIN" --around=Shape@rs "$FIX" 2>/dev/null | grep -m1 -o '<f p="[^"]*"' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
case "$A2$A2F" in *'t="iface"'*'p="widget.rs"'*) ok "(A2) Shape@rs pins the Rust trait exact-first" ;;
                                                  *) no "(A2) Shape@rs wrong: $A2 | $A2F" ;; esac
A3="$( "$BIN" --around=Shape@c "$FIX" 2>/dev/null | grep -m1 -o '<f p="[^"]*"><s [^>]*' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
case "$A3" in *'p="widget.c"><s t="cls"'*) ok "(A3) Shape@c anchors to C — the struct (class-bucketed by the C grammar, measured) is exact regardless of rank" ;;
                                                  *) no "(A3) Shape@c wrong: $A3" ;; esac

# ── (A4) unknown language tag is refused with the known set (never silently ignored) ────────────────
A4E="$( "$BIN" --around=Shape@bogus "$FIX" 2>&1 >/dev/null )"; A4RC=$?
if [ "$A4RC" = 0 ]; then
    no "(A4) Shape@bogus exit 0 — an unknown anchor must refuse"
elif printf '%s' "$A4E" | grep -q 'cpp' && printf '%s' "$A4E" | grep -qi 'unknown language\|known languages'; then
    ok "(A4) Shape@bogus refused, naming the known tags"
else
    no "(A4) refusal wrong: rc=$A4RC $( printf '%s' "$A4E" | head -c 200 )"
fi

# ── (A5) foreign fallback is DISCLOSED, never a silent cross-language pick ──────────────────────────
A5E="$( "$BIN" --around=Extra@cpp "$JVM" 2>&1 >/dev/null )"; A5RC=$?
A5S="$( "$BIN" --around=Extra@cpp "$JVM" 2>/dev/null | grep -m1 -o '<s [^>]*' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
if [ "$A5RC" = 0 ] && printf '%s' "$A5E" | grep -q 'holds no definition' \
   && case "$A5S" in *'n="Extra"'*) true ;; *) false ;; esac; then
    ok "(A5) cpp-anchored Extra: fallback served AND said ('holds no definition')"
else
    no "(A5) fallback not disclosed or row wrong: rc=$A5RC msg=$( printf '%s' "$A5E" | head -c 160 ) / $A5S"
fi

# ── (A6) JVM pair, measured truth of the grammars: java's interface_declaration indexes Interface (rung 4)
#    while Kotlin's interface shares class_declaration (queries/kotlin/tags.scm) as Class (3) — the ladder
#    therefore fronts JAVA for a bare Marker, and the kt majority is never consulted: silent root. kt
#    users state it — (A6b) is the other path of the same rule.
A6="$( "$BIN" --around=Marker "$JVM" 2>/dev/null )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
A6R="$( printf '%s' "$A6" | grep -m1 -o '<r [^>]*>' )"
A6F="$( printf '%s' "$A6" | grep -m1 -o '<f p="[^"]*"' )"
case "$A6F" in *'p="jv/Marker.java"'*)
    case "$A6R" in
        *reflang*|*next=*) no "(A6) java fronts on the rung gap as it should, but the root discloses anyway: $A6R" ;;
        *) ok "(A6) bare Marker fronts jv/Marker.java on the interface rung; kt majority silent" ;;
    esac ;;
    *) no "(A6) Marker front wrong (want jv by rung, kt only via @kt): $A6F" ;; esac
A6K="$( "$BIN" --around=Marker@kt "$JVM" 2>/dev/null | grep -m1 -o '<f p="[^"]*"' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
case "$A6K" in *'p="kt/Marker.kt"'*) ok "(A6b) Marker@kt states the language and kt fronts — the stated path of the rule" ;;
                                     *) no "(A6b) @kt did not front kt: $A6K" ;; esac

# ── (A7) determinism x2 on the anchor-bearing outputs (house pattern) ──────────────────────────────
"$BIN" --around=Shape "$FIX" > /dev/null 2>&1   # status: a warm-up run; the two runs on the next line are the ones compared
d1="$( "$BIN" --around=Shape "$FIX" 2>/dev/null )"; d2="$( "$BIN" --around=Shape "$FIX" 2>/dev/null )"   # status: -n "$d1" below fails on a run that printed nothing
if [ -n "$d1" ] && [ "$d1" = "$d2" ]; then ok "(A7) --around byte-stable x2"; else no "(A7) anchor output not deterministic"; fi

# ── (A8) "?" is the DISPLAY fallback, not vocabulary: Shape@? refuses like any unknown tail (CR #440) ─
A8E="$( "$BIN" --around=Shape@? "$FIX" 2>&1 >/dev/null )"; A8RC=$?
if [ "$A8RC" != 0 ] && printf '%s' "$A8E" | grep -q 'unknown language after @' \
   && ! printf '%s' "$A8E" | sed -n '/known languages (tags):/,$p' | grep -qE '(^| )\?( |$)'; then
    ok "(A8) Shape@? refused with the tag vocabulary, and the vocabulary carries no ?"
else
    no "(A8) @? accepted or ? advertised: rc=$A8RC $( printf '%s' "$A8E" | head -c 200 )"
fi

# ── (A9) a stated @lang must not blind the qualified lane (CR #440; CONTROL pin — the tier-blindness on
#    scope-bearing canonical ids is real in code but unprovable here: no fixture symbol has a scope,
#    and adding one moves lines that arms (27)/(A1) pin. This guards the file:name@lang agreement. ────
A9="$( "$BIN" --around='widget.rs:Shape@rs' "$FIX" 2>/dev/null | grep -m1 -o '<f p="[^"]*"' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
A9B="$( "$BIN" --around='widget.rs:Shape' "$FIX" 2>/dev/null | grep -m1 -o '<f p="[^"]*"' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
[ "$A9" = '<f p="widget.rs"' ] && [ "$A9" = "$A9B" ] \
    && ok "(A9) widget.rs:Shape@rs resolves where widget.rs:Shape does — the tail is stripped before the tiers" \
    || no "(A9) @lang tail broke the qualified lane: [$A9] vs [$A9B]"

# ── (A10) same-rung cross-language pair: the majority LANGUAGE breaks the TIE (not a tier), and a tie-break
#    that actually ordered rows speaks — reflang= + origin=corpus + the pasteable --defs= next ───────────
A10R="$( "$BIN" --around=same "$FIX2" 2>/dev/null | grep -m1 -o '<r [^>]*>' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
A10F="$( "$BIN" --around=same "$FIX2" 2>/dev/null | grep -m1 -o '<f p="[^"]*"' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
case "$A10F" in
    *'p="z_lib.js"'*)
        case "$A10R" in
            *'reflang="js"'*'reflang-origin="corpus"'*'next="--defs=same"'*)
                ok "(A10) same-rung tie: js fronts by the MAJORITY TIE-BREAK (id baseline would front a_same.py), disclosed with reflang=js origin=corpus and next=--defs=same" ;;
            *) no "(A10) tie-break front right but disclosure wrong: $A10R" ;;
        esac
    ;; *) no "(A10) same front wrong (id accident? no tie-break?): $A10F" ;;
esac

# ── (A11) different rungs decide alone: the js majority must NOT front its rung-2 Function over the
#    py rung-3 Class — and a ladder win needs no language talk: silent root ───────────────────────────
A11R="$( "$BIN" --around=rung "$FIX2" 2>/dev/null | grep -m1 -o '<r [^>]*>' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
A11F="$( "$BIN" --around=rung "$FIX2" 2>/dev/null | grep -m1 -o '<f p="[^"]*"' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
case "$A11F" in
    *'p="y_rung.py"'*) case "$A11R" in
        *reflang*|*next=*) no "(A11) ladder answered alone (Class rung 3 over Function rung 2) yet the root still discloses: $A11R" ;;
        *) ok "(A11) rung fronts y_rung.py on KIND despite the js corpus majority — and the root is silent" ;;
    esac ;;
    *) no "(A11) rung front wrong (corpus tier still lifting?): $A11F" ;;
esac

# ── (A12) one def, majority anchor active elsewhere: NOTHING was decided about this answer → silent ─────
A12R="$( "$BIN" --around=pick "$FIX2" 2>/dev/null | grep -m1 -o '<r [^>]*>' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
A12F="$( "$BIN" --around=pick "$FIX2" 2>/dev/null | grep -m1 -o '<f p="[^"]*"' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
case "$A12F" in
    *'p="b_pick.py"'*) case "$A12R" in
        *reflang*|*next=*) no "(A12) single-def answer carries a majority reflang it decided nothing with: $A12R" ;;
        *) ok "(A12) pick answers its only def (b_pick.py) with no reflang — an unused anchor stays quiet" ;;
    esac ;;
    *) no "(A12) pick front wrong: $A12F" ;;
esac

# ── (A13) the stated @lang must scope the Scope::name tier too (the maintainer's `A::f@rs` shape) ───────
# a_ns.cpp sorts to the LOWER id, so the unscoped tier answer fronts C++ today — the id accident the
# tag exists to prevent. Expected after the fix: only m.rs answers, with the explicit anchor disclosed.
A13="$( "$BIN" --around='A::f@rs' "$FIX3" 2>/dev/null )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
A13R="$( printf '%s' "$A13" | grep -m1 -o '<r [^>]*>' )"
if printf '%s' "$A13" | grep -q '<f p="a_ns.cpp"'; then
    no "(A13) A::f@rs still answers C++ — the Scope::name tier returns before the stated scope applies: $( printf '%s' "$A13" | grep -m1 -o '<f p="[^"]*"' )"
elif case "$A13R" in *'reflang="rs"'*'reflang-origin="explicit"'*) true ;; *) false ;; esac; then
    ok "(A13) A::f@rs is scoped to RUST by the stated tag, and the root discloses it"
else
    no "(A13) rust-only answered but the explicit anchor is undisclosed: $A13R"
fi

# ── (A14)/(A15) a file lane or an @FILE:LINE seed names ONE place: the language decided nothing there ──
# LAND-440 Stage 0 measured `--around=z_lib.js:same` at 1160 -> 2585 bytes: reflang="js" reflang-origin="context"
# plus its legend, on the selector form that already picked the file. The front is the file's own definition
# either way, so the root is silent; a typed @lang (A13) still shows.
for A14Q in 'z_lib.js:same' '@z_lib.js:6'; do
    A14R="$( "$BIN" --around="$A14Q" "$FIX2" 2>/dev/null | grep -m1 -o '<r [^>]*>' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
    A14F="$( "$BIN" --around="$A14Q" "$FIX2" 2>/dev/null | grep -m1 -o '<f p="[^"]*"' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
    [ "$A14Q" = 'z_lib.js:same' ] && A14N='(A14)' || A14N='(A15)'
    case "$A14F" in
        *'p="z_lib.js"'*) case "$A14R" in
            *reflang*|*next=*) no "$A14N --around=$A14Q names one place yet the root discloses a language: $A14R" ;;
            *) ok "$A14N --around=$A14Q answers z_lib.js with no reflang — the selector picked the file, the language decided nothing" ;;
        esac ;;
        *) no "$A14N --around=$A14Q front wrong: $A14F" ;;
    esac
done

# ── (A16) the majority moves a row BELOW the front: c_low.py's Class leads on kind with or without it ──
# d_low.py and z_low.js both hold `low` as a Function; js is the majority, so z_low.js orders ahead of
# d_low.py. That is a lower-rung move: the legend says the corpus origin "appears only when one such tie
# moved the front", and Stage 0 measured +1.65 KB on four large-repo names whose front never moved.
A16="$( "$BIN" --around=low "$FIX2" 2>/dev/null )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
A16R="$( printf '%s' "$A16" | grep -m1 -o '<r [^>]*>' )"
A16C="$( "$BIN" --callers=low "$FIX2" 2>/dev/null | grep -o '<def ix="[0-9][^>]*>' | tr '\n' ' ' )"   # status: a failed run prints no row, and the positive match on it below then fails the arm
case "$A16C" in
    *'ix="1" t="cls"'*'p="c_low.py:'*'ix="2"'*'p="z_low.js:'*'ix="3"'*'p="d_low.py:'*)
        case "$A16R" in
            *reflang*|*next=*) no "(A16) the front (c_low.py's Class) did not move, yet the root discloses the majority: $A16R" ;;
            *) ok "(A16) low: Class fronts on kind, js orders ahead of py one rung down, and the root is silent (the front did not move)" ;;
        esac ;;
    *) no "(A16) low order wrong (want cls c_low.py, then z_low.js ahead of d_low.py): $A16C" ;;
esac

# ── (A17)-(A19): a generated fixture (no committed file joins the repo's own index) ─────────────────────────────────
TAILFIX="$( mktemp -d )"; trap 'rm -rf "$TAILFIX"' EXIT
printf 'class Box:\n    def run(self):\n        return 1\n' > "$TAILFIX/box.py"
printf 'class Box {\n    run() { return 2; }\n}\n' > "$TAILFIX/box.js"   # a JS method carries no Symbol::scope
printf '{\n  "config": {\n    "user@corp": 3\n  }\n}\n' > "$TAILFIX/data.json"
printf '# config\n\n## user\n\ntext\n\n## user@py\n\nmore\n' > "$TAILFIX/notes.md"
printf 'def corp_seed():\n    return 4\n' > "$TAILFIX/user@corp.py"
front(){ "$BIN" --around="$1" "$TAILFIX" 2>/dev/null | grep -m1 -o '<f p="[^"]*"><s [^>]*'; }   # status: a failed run prints no row, and the positive match on it below then fails the arm
# The dotted tier reads Symbol::scope, which Python records and JavaScript does not, so `Box.run` finds box.py's method
# alone: @py answers it with no fallback note, and @js must SAY the stated language holds none (the tag scoped the tier).
A17P="$( front 'Box.run@py' )"; A17PE="$( "$BIN" --around='Box.run@py' "$TAILFIX" 2>&1 >/dev/null )"
A17J="$( front 'Box.run@js' )"; A17JE="$( "$BIN" --around='Box.run@js' "$TAILFIX" 2>&1 >/dev/null )"
case "$A17P|$A17PE|$A17J|$A17JE" in
    '<f p="box.py"><s t="fn" n="run" sc="Box"'*'||<f p="box.py">'*'|'*'the matching language holds no definition'*)
        ok "(A17) Box.run@py answers box.py's method silently; Box.run@js discloses the fallback — the dotted tier saw Box.run and the tag scoped it" ;;
    *) no "(A17) a language tail blinded the dotted tier or did not scope it: py=[$A17P] [$A17PE] js=[$A17J] [$A17JE]" ;;
esac
A18="$( front 'notes.md::config::user@py' )"
case "$A18" in
    '<f p="notes.md"><s t="sec" n="user@py"'*) ok "(A18) notes.md::config::user@py answers the heading user@py — the whole spelling is probed before the tail reads as a language" ;;
    *) no "(A18) the literal id lost to its tail-stripped twin: [$A18]" ;;
esac
A19Q="$( front 'data.json:user@corp' )"; A19S="$( front '@user@corp.py:2' )"
case "$A19Q|$A19S" in
    '<f p="data.json"><s t="sec" n="user@corp"'*'|<f p="user@corp.py"><s t="fn" n="corp_seed"'*) ok "(A19) data.json:user@corp and @user@corp.py:2 resolve — the literal-first check read the name, not the whole selector" ;;
    *) no "(A19) a real name or a line seed was refused as a bad language tail: [$A19Q] [$A19S]" ;;
esac
A19B="$( "$BIN" --around='Shape@bogus' "$FIX" 2>&1 >/dev/null )"; A19BRC=$?
case "$A19BRC|$A19B" in
    1\|*'unknown language after @'*) ok "(A19) control: Shape@bogus still refuses with the known tags" ;;
    *) no "(A19) control: Shape@bogus stopped refusing: rc=$A19BRC [$A19B]" ;;
esac

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
