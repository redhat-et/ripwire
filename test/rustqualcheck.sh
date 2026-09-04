#!/usr/bin/env bash
# rustqualcheck.sh — gate for the RUST half of §H4 (W3 lane):
# `::`-path calls extract at all, the canonical tier resolves them PRECISELY (including across
# DIRECTORIES), an EXTERNAL qualified call does not false-edge onto a same-named local def, `Self::`
# reaches its own impl, and the one genuinely ambiguous spelling is DISCLOSED rather than guessed.
#
# WHAT WAS BROKEN. queries/rust/tags.scm carried NO scoped_identifier call pattern, so 100% of Rust's
# DOMINANT call form — `Widget::new()`, `util::tool()`, `Self::helper()`, `Widget::bump(&w)` — produced
# no reference at all. The drop happened at EXTRACTION, before resolution, so `ambiguous=`/`unresolved=`
# (the tool's published call-graph completeness gauges) could not move: a reader had no signal whatsoever,
# in a language the tool GATE-CLAIMS (rustimportprecisecheck.sh ships).
#
# WHY THE PATTERN ALONE WAS NOT ENOUGH (W1-MEASURE, recorded in the plan's §Execution). Rust defs carried
# scope="" and Rust refs carried qualifier="", so every widened edge fell to the bare-name spray, and:
#   (1) two types defining `new` in DIFFERENT directories hit §2a's tier-3 unique-or-DROP rule and BOTH
#       edges died SILENTLY — no amb=, no unresolved= movement, the flagship reflex still broken exactly
#       on idiomatic Rust;
#   (2) an external `Vec::<u32>::new()` false-edged onto a local `new`.
# So the lane ships pattern + per-ref qualifier + per-def scope + a qualified-scope guard. §4 and §5 below
# are the arms that would go green on the pattern alone and are therefore the ones that matter.
#
# EVERY expected count below is a LITERAL, read by hand off test/rustqualfix/src/*.rs (plan §7 trap 1: a
# gate that derives its expected number the way the code does cannot catch the derivation).
#
# RED-FIRST (measured 2026-07-31, plain build, pre-lane binary kept as build/ripwire_base):
#   fixture header       edges=2  ambiguous=0                (now 14 / 1)
#   --uses    0 for new, helper, tool, deepfn, generic, area, gadget_free, run   (now 4/2/1/1/1/1/1/1)
#   --callers 0 for new, helper, tool, deepfn, generic, area, gadget_free, run   (now 2/2/1/1/1/1/1/1)
#   --callees caller=2, crossdir_caller=0, amb_caller=0, bump=0, spin=0          (now 8/2/2/1/1)
#   --expand=bump returned the WHOLE `impl Widget { … }` block                   (now just bump's body)
#   34 of the gate's then-49 checks FAILED against build/ripwire_base; the counts above predate the V3
#   fixture additions (a top-level `new`, src/plainmod.rs, crossdir_amb, the detached pair), so read them
#   as the shape of the original red, not as literals to re-derive. The gate is now 56 checks.
#   The 15 that pass on BOTH are, by construction, controls and regression guards rather than evidence of
#   this round: the bare/method-call controls, the never-called `spin`, the "no edge to the STRUCT Widget"
#   and "no local ::new edge" negative arms (vacuous when nothing is extracted — see the three-state note
#   below), the §8 inherit arms, and the §9 hygiene arms.
#   The §5 no-false-edge arm is the one exception and needs a THREE-state reading, because base is
#   vacuously green (it extracts nothing at all): base --callees=external_caller = 0 (nothing extracted),
#   mid-lane at commit f2b3d40 (patterns + canonical tier, no guard) = 1, WRONGLY naming Widget::new,
#   final = 0. The middle state is the one this arm defends and it was measured live before the guard.
#
# RED-FIRST for the V3 verifier round (measured 2026-07-31 against the MERGED pre-fix binary, i.e. main with
# the lane's first four commits but without the M-2/M-3 fixes). 7 of the 56 checks FAIL there, and they are
# exactly the two findings:
#   M-3 (§3b)  --callees=crossdir_amb = 0 (silent drop) · no amb="1" row · only 2 of the 4 `<c n="run"/>`
#              rows · header ambiguous=1 not 2 · "unexpected amb= rows" naming only amb_caller
#   M-2 (§5)   --callees=external_caller = 1, binding the top-level `new` · --callers=new = 3 not 2
# The M-6 (§4) arm passes on BOTH binaries, because it defends the arm's DISCRIMINATION rather than a fix:
# its evidence is that rewriting `Self::detached()` bare moves --callees=bump 2 -> 3 and adds amb="1"
# (measured; recorded at the arm and in the fixture).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/rustqualcheck.sh   |   bash test/rustqualcheck.sh asan/ripwire
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"      # BOTH seams: positional arg and RIPWIRE_BIN=
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolute BEFORE we cd away
# RELATIVE corpus paths (we cd to $ROOT below): every `p="…"` the gate matches is echoed back as the
# caller spelled the root, so an absolute root would make every path assertion below unwritable.
# RE-PINNED 2026-08-19 (R-E CORRECTION): p= is now relative to the CRAWL ROOT, which is $FIX itself, so the
# rows spell "src/lib.rs" and the fixture prefix is stated once as root="test/rustqualfix". The p= literals
# below dropped that prefix; nothing about the resolver's answers moved.
FIX="test/rustqualfix"
LEGO="test/legofix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$ROOT/$FIX" ] || { echo "no test/rustqualfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "rustqualcheck: BIN=$BIN  CORPUS=test/rustqualfix"

run(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$@" 2>/dev/null; }
cnt(){ printf '%s' "$1" | grep -oE 'count="[0-9]+"' | head -1 | tr -dc 0-9; }

expect(){   # $1 verb  $2 sym  $3 want  $4 prose
    local out; out="$( run "$FIX" "--$1=$2" --no-cache )"
    local got; got="$( cnt "$out" )"
    [ "${got:-REFUSED}" = "$3" ] && ok "--$1=$2 count=$3 — $4" \
        || no "--$1=$2 expected count=$3, got '${got:-REFUSED}' — $4"
}

MAP="$( run "$FIX" --no-cache )"

# ── §1 per-SPELLING extraction (src/lib.rs `caller` has 8 calls, 8 DISTINCT targets) ───────────────────
expect uses free        1 "bare call — unaffected control, bound before and after"
expect uses bump        1 "method call (w.bump()) — unaffected control"
expect uses tool        1 "mod::fn, 2 segments (util::tool()) — bound NOTHING before the widening"
expect uses deepfn      1 "mod::mod::fn, 3 segments (util::deep::deepfn()) — LEFT nesting, one pattern, any depth"
expect uses generic     1 "turbofish on a BARE fn (generic::<u32>(1)) — the generic_function node kind"
expect uses area        1 "TRAIT-qualified call (Shape::area(&w))"
expect uses gadget_free 1 "crate-anchored call into a DIRECTORY-form file module (src/gadget/mod.rs)"
expect uses plainfn     1 "crate-anchored call into a FILE-form file module (src/plainmod.rs) — the other spelling"
expect uses helper      2 "Self::helper() — once per directory (lib.rs and gadget/mod.rs)"
expect uses spin        0 "Gadget::spin is DEFINED and never called — the widening invents no call site"

expect callers tool        1 "2-segment scoped call names its caller"
expect callers deepfn      1 "3-segment scoped call names its caller"
expect callers generic     1 "turbofish call names its caller"
expect callers area        1 "trait-qualified call names its caller"
expect callers gadget_free 1 "file-module call names its caller"

expect callers plainfn  1 "file-form file-module call names its caller"
expect callees caller   9 "all 9 spellings in caller() resolve, each to its own target"

# ── §2 CANONICAL PRECISION — the right target, not merely a target ─────────────────────────────────────
CAL="$( run "$FIX" --callees=caller --no-cache )"
for want in 'n="free"' 'n="new"' 'n="bump"' 'n="tool"' 'n="deepfn"' 'n="generic"' 'n="area"' 'n="gadget_free"' 'n="plainfn"'; do
    printf '%s' "$CAL" | grep -q "$want" \
        && ok "caller binds $want" || no "caller is MISSING $want: $CAL"
done
# the qualified constructor spelling must land on the METHOD `new`, never on the STRUCT `Widget`.
printf '%s' "$CAL" | grep -q 'n="Widget"' \
    && no "WRONG GRAPH: caller has an edge to the STRUCT Widget — Widget::new() resolved to the type" \
    || ok "no edge to the struct Widget (Widget::new() names the assoc fn, not the type)"

# ── §3 CROSS-DIRECTORY PRECISION — the case W1-MEASURE proved dies silently without the canonical tier ─
# src/gadget/mod.rs::crossdir_caller writes `crate::Widget::new()` and `Gadget::new()`. Two `new` defs,
# DIFFERENT directories → neither same-file nor same-dir → tier-3 unique-or-DROP kills BOTH under a bare
# spray. Each must instead land on ITS OWN impl.
XD="$( run "$FIX" --callees=crossdir_caller --no-cache )"
[ "$( cnt "$XD" )" = 2 ] \
    && ok "--callees=crossdir_caller count=2 (both cross-directory Type::new() calls survive)" \
    || no "--callees=crossdir_caller expected 2, got '$( cnt "$XD" )': $XD"
printf '%s' "$XD" | grep -q 'n="new" p="src/lib.rs' \
    && ok "crossdir_caller → Widget::new in src/lib.rs (ACROSS a directory boundary, precise)" \
    || no "crossdir_caller did not bind lib.rs's Widget::new: $XD"
printf '%s' "$XD" | grep -q 'n="new" p="src/gadget/mod.rs' \
    && ok "crossdir_caller → Gadget::new in src/gadget/mod.rs (its own impl, precise)" \
    || no "crossdir_caller did not bind gadget/mod.rs's Gadget::new: $XD"
# and neither call is ambiguous — canonical keying, not a lucky tier win. (V3 L-8: match the attribute
# ANYWHERE in the tag, not adjacent to n=" — an adjacency match goes permanently green the moment the symbol
# gains an id=/overloads= attribute between the two, which is a silent, undetectable pass.)
printf '%s' "$MAP" | grep -qE 'n="crossdir_caller"[^>]*amb=' \
    && no "crossdir_caller carries amb= — canonical keying did NOT hold across directories" \
    || ok "PRECISE: crossdir_caller carries no amb= (canonical keying held across directories)"

# ── §3b CROSS-DIRECTORY *AMBIGUOUS* — V3 M-3, the round's headline failure class inside its own fix ────
# §3 covers cross-dir with a UNIQUE canonical key; §6 covers ambiguity SAME-FILE. Their INTERSECTION was
# untested and broken: `crossdir_amb` (in src/gadget/) calls `Thing::run(t)` whose canonical key matches TWO
# defs over in src/lib.rs. The canonical tier found both, then tier-3's `cand.size() == 1 || narrowed` gate —
# which did not know about `canonical` — dropped the whole thing. No edge, no amb=, no unresolved= movement,
# map byte-identical: precisely the silent death this plan exists to kill.
XA="$( run "$FIX" --callees=crossdir_amb --no-cache )"
[ "$( cnt "$XA" )" = 2 ] \
    && ok "--callees=crossdir_amb count=2 — a cross-dir AMBIGUOUS canonical key splits instead of vanishing" \
    || no "SILENT DROP: --callees=crossdir_amb expected 2, got '$( cnt "$XA" )': $XA"
printf '%s' "$MAP" | grep -qE 'n="crossdir_amb"[^>]*amb="1"' \
    && ok "crossdir_amb carries amb=\"1\" — the cross-dir split is DISCLOSED, not silently resolved" \
    || no "crossdir_amb is missing amb=\"1\" — the split was not routed into ambiguity accounting"

# ── §4 Self:: — resolved to the ENCLOSING impl's type at extraction, per directory ─────────────────────
# `Self::helper()` appears once in EACH file, and `Self::detached()` once in lib.rs.
#
# V3 M-6: the helper arms alone do NOT discriminate — rewriting the call bare leaves them green, because with
# Rust def scopes populated, CHA-lite narrows a bare in-method call by the SAME enclosing-scope fact (see the
# note in the fixture). The DISCRIMINATING arm is `Self::detached()`, whose target lives in a second
# `impl Widget` block in the OTHER DIRECTORY next to a same-named `Detacher::detached` decoy. Measured:
#   bare `detached()`  → count=3 and bump carries amb="1"   (Rule 3 narrows to the FILE, i.e. to both defs)
#   `Self::detached()` → count=2 and bump carries NO amb=   (canonical `Widget::detached`)
BUMP="$( run "$FIX" --callees=bump --no-cache )"
printf '%s' "$BUMP" | grep -q 'n="helper" p="src/lib.rs' \
    && ok "Self::helper() inside Widget::bump → lib.rs's Widget::helper (Self resolved to Widget)" \
    || no "Widget::bump did not bind lib.rs's helper: $BUMP"
printf '%s' "$BUMP" | grep -q 'n="detached" p="src/gadget/mod.rs' \
    && ok "Self::detached() reaches the CROSS-DIRECTORY impl Widget block" \
    || no "Widget::bump did not bind gadget/mod.rs's Widget::detached: $BUMP"
[ "$( cnt "$BUMP" )" = 2 ] \
    && ok "--callees=bump count=2 (Self:: picked ONE helper and ONE detached, not the decoys)" \
    || no "--callees=bump expected 2, got '$( cnt "$BUMP" )': $BUMP"
printf '%s' "$MAP" | grep -qE 'n="bump"[^>]*amb=' \
    && no "bump carries amb= — Self:: did NOT pin the target (a bare call scores amb=\"1\" here)" \
    || ok "PRECISE: bump carries no amb= — the discriminating Self:: arm (bare would be amb=\"1\")"
SPIN="$( run "$FIX" --callees=spin --no-cache )"
printf '%s' "$SPIN" | grep -q 'n="helper" p="src/gadget/mod.rs' \
    && ok "Self::helper() inside Gadget::spin → gadget/mod.rs's Gadget::helper (per-directory Self)" \
    || no "Gadget::spin did not bind gadget/mod.rs's helper: $SPIN"
[ "$( cnt "$SPIN" )" = 1 ] \
    && ok "--callees=spin count=1" || no "--callees=spin expected 1, got '$( cnt "$SPIN" )': $SPIN"

# ── §5 EXTERNAL qualified call must NOT false-edge (the W1-MEASURE case, and the turbofish decision) ───
# `external_caller` contains exactly one call: `Vec::<u32>::new()`. `Vec` is not defined in this tree, and
# `Widget::new`/`Gadget::new` are. The TURBOFISH DECISION is what makes the qualifier readable at all:
# Rust spells type args in expression position as `Vec::<u32>`, so the `::` survives stripping `<u32>` —
# ingest strips the group FIRST, then the leftover separator, then takes the last top-level segment, giving
# qualifier `Vec`. A qualified call can only mean a member of the scope it names, so no edge may be minted.
#
# V3 M-2 — THE DECISIVE PART. src/lib.rs holds a TOP-LEVEL `pub fn new() {}`, because in Rust EVERY
# top-level fn carries scope="", not just file-module members. The guard's first version kept every
# scope-less candidate and so bound THAT `new`: count 0 -> 1, no amb=, `ambiguous=` unmoved. This arm is the
# reason the guard now tests FILE-MODULE MEMBERSHIP (graph.h::rustFileModuleOf) rather than "scope is empty".
# The §2 `caller` arms are the other half of the same decision: they prove the precise rule did not pay for
# this by killing the legitimate file-module shapes (both the `x/mod.rs` and the `x.rs` spellings).
EXT="$( run "$FIX" --callees=external_caller --no-cache )"
[ "$( cnt "$EXT" )" = 0 ] \
    && ok "--callees=external_caller count=0 — Vec::<u32>::new() minted NO edge (turbofish qualifier = Vec)" \
    || no "FALSE EDGE: external_caller has $( cnt "$EXT" ) callee(s) — Vec::<u32>::new() bound a local new: $EXT"
# (V3 L-7: the old 'no n="new" row' arm here was implied by count=0 above and added no evidence. Replaced
# with the assertion count=0 CANNOT make — that the top-level `new` decoy is really in the corpus, so the
# arm above is testing the hard case rather than passing because the decoy silently disappeared.)
printf '%s' "$MAP" | grep -qE '<s t="fn" n="new"' \
    && ok 'the top-level scope-less "new" decoy IS in the map (so count=0 above is the HARD case)' \
    || no 'the top-level "new" decoy vanished from the corpus — the M-2 arm above is now vacuous'
# --uses is a call-SITE count and is name-based by contract, so the site itself IS still listed under `new`
# (4 sites: caller's Widget::new, external_caller's Vec::<u32>::new, and crossdir_caller's two). The
# distinction is deliberate: --uses answers "where is this name written", the call graph answers "what
# resolves to this def". Asserted so a future change cannot quietly conflate them.
expect uses    new 4 "4 call SITES spell ::new (name-based use-sites, one of them the external Vec)"
expect callers new 2 "but only 2 CALLERS — external_caller is not one of them"

# ── §6 AMBIGUITY IS DISCLOSED, never silently resolved (plan §6) ───────────────────────────────────────
# Canonical keying makes the honest cases precise, so the amb= path is exercised ON PURPOSE: two modules
# in ONE file each hold `impl Thing`, so `Thing::run` legitimately keys TWO defs.
expect callees amb_caller 2 "Thing::run() splits onto BOTH dup_a and dup_b impls"
printf '%s' "$MAP" | grep -qE '<s t="fn" n="amb_caller"[^>]*amb="1"' \
    && ok "amb_caller carries amb=\"1\" — the deliberate collision, disclosed per-row" \
    || no "amb_caller is missing its amb=\"1\" row attribute"
# 4 rows = TWO ambiguous callers (amb_caller in §6, crossdir_amb in §3b) x TWO run defs each. Neither ever
# picks one — and crossdir_amb contributes 2 of these only because the M-3 fix routes a cross-directory
# canonical multi-match into the split instead of dropping it.
[ "$( printf '%s' "$MAP" | grep -oE '<c n="run"/>' | wc -l | tr -d ' ' )" = 4 ] \
    && ok "both ambiguous calls split onto BOTH run defs (4 rows total), never picking one" \
    || no "the ambiguous calls did not split onto both run defs"
printf '%s' "$MAP" | grep -qE 'files=3 symbols=39 edges=18 shown=39 est_tokens=[0-9]+ ambiguous=2 unresolved=0' \
    && ok "fixture header: edges=18 ambiguous=2 unresolved=0 (was edges=2 ambiguous=0 pre-lane)" \
    || no "fixture header wrong: $( printf '%s' "$MAP" | grep -oE 'files=3 [^-]*' | head -1 )"
# exactly TWO ambiguous callers in the whole fixture — amb_caller (same-file, §6) and crossdir_amb
# (cross-directory, §3b). Everything else stayed canonical-precise.
[ "$( printf '%s' "$MAP" | grep -oE ' amb="[0-9]+"' | wc -l | tr -d ' ' )" = 2 ] \
    && ok "exactly two amb= rows in the fixture (canonical keying held everywhere else)" \
    || no "unexpected amb= rows: $( printf '%s' "$MAP" | grep -oE 'n="[a-z_]+"[^>]*amb="[0-9]+"' | tr '\n' ' ' )"

# ── §7 the METHOD-SPAN fix (found by this lane; see queries/rust/tags.scm) ─────────────────────────────
# @definition.method used to be captured on the `declaration_list` WRAPPER, which has no body: field, so
# ingest's span walk climbed to the impl_item and every method got the WHOLE BLOCK as its span — wrong
# --expand bodies, wrong loc/cx, and every call in the block attributed to one arbitrary method.
EXP="$( run "$FIX" --expand=bump --no-cache )"
printf '%s' "$EXP" | grep -q 'self.n += 1' \
    && ok "--expand=bump returns bump's body" || no "--expand=bump lost the body: $EXP"
printf '%s' "$EXP" | grep -q 'impl Widget {' \
    && no "--expand=bump returned the WHOLE impl block — the method-span regression is back" \
    || ok "--expand=bump does NOT contain 'impl Widget {' (span is the METHOD, not the block)"
printf '%s' "$EXP" | grep -q 'pub fn new()' \
    && no "--expand=bump leaked a SIBLING method — span still covers the block" \
    || ok "--expand=bump leaks no sibling method"

# ── §8 the INHERIT path is UNCHANGED (RawRef::qualifier is shared with Rust trait-impl refs) ───────────
# ingest stashes an `impl Trait for T` implementor in RawRef::qualifier, and graph.h reads it behind
# `if( !ir.isInherit ) continue;`. A CALL ref now also carries a qualifier, so prove the two cannot leak
# into one another: the inherit-derived --lego output must be byte-identical to the pre-lane binary's.
# RE-PINNED 2026-09-04 (capture-audit L5, H6/F2): the TARGETED --lego now carries defs= — how many
# definitions the SELECTOR's name has — because resolveFocus picks the lowest-id one and `--lego=size`
# used to report implementors="0" about a definition nobody chose. Shape has exactly one definition in this
# fixture, so the golden gains defs="1" and NOTHING else; the inherit edge this arm is about (implementors=1,
# the single Widget impl row) is unmoved, which is the whole claim.
LEGO_NEW="$( run "$FIX" --lego=Shape --no-cache | grep -o '<lego.*</lego>' )"
[ "$LEGO_NEW" = '<lego><iface n="Shape" p="src/lib.rs" methods="0" caveat="not-extracted-for-lang" defs="1" implementors="1"><impl n="Widget" p="src/lib.rs"/></iface></lego>' ] \
    && ok "impl Shape for Widget still yields exactly its inherit edge (call qualifiers did not leak in)" \
    || no "inherit edges CHANGED: $LEGO_NEW"
if [ -d "$ROOT/$LEGO" ]; then
    LEGO_V="$( run "$LEGO" --lego=Vehicle --no-cache | grep -o '<lego.*</lego>' )"
    # literal read off test/legofix/vehicle.rs: `impl Vehicle for Car` and `impl Vehicle for Bike`.
    printf '%s' "$LEGO_V" | grep -q 'implementors="2"' \
        && printf '%s' "$LEGO_V" | grep -q '<impl n="Car"' && printf '%s' "$LEGO_V" | grep -q '<impl n="Bike"' \
        && ok "legofix: Vehicle still has exactly its 2 Rust implementors (Car, Bike)" \
        || no "legofix Vehicle implementors changed: $LEGO_V"
fi

# ── §9 hygiene: determinism, warm==cold, well-formed XML ───────────────────────────────────────────────
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
run "$FIX" --no-cache >"$TMP/d1"; run "$FIX" --no-cache >"$TMP/d2"
cmp -s "$TMP/d1" "$TMP/d2" && ok "deterministic (two --no-cache runs identical)" || no "non-deterministic"
run "$FIX" --cache="$TMP/c.bin" >"$TMP/cold"; run "$FIX" --cache="$TMP/c.bin" >"$TMP/warm"
cmp -s "$TMP/cold" "$TMP/warm" && ok "warm == cold (qualifier + scope survive the cache round-trip)" || no "warm != cold"
# V3 H-3: this used to print "PASS xml well-formed (xmllint absent — skipped)" when the tool was missing —
# a PASS for a check that never ran, which is exactly the false-green class this round exists to remove. G4
# is a hard guardrail (CLAUDE.md), so a missing xmllint is a BROKEN ENVIRONMENT, not a satisfied assertion.
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    no "cannot verify G4: xmllint is NOT INSTALLED — this check did not run (install libxml2)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
