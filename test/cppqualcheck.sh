#!/usr/bin/env bash
# cppqualcheck.sh — gate for §H4: C++ qualified calls extract at ANY
# `::` depth, explicit-template-argument calls extract at all, cast keywords extract NEVER, and the widened
# edges stay canonically PRECISE — with the one genuinely ambiguous spelling DISCLOSED rather than guessed.
#
# Before this fix a plainly written, single-target, statically resolvable call produced NO REFERENCE AT ALL
# when it was spelled with two or more `::` segments, or with explicit template arguments. The drop happened
# at EXTRACTION, before resolution, so `ambiguous=`/`unresolved=` — the tool's own published call-graph
# completeness gauges — could not move: the reader had no signal whatsoever. --uses/--callers/--edit-check
# silently under-reported on ripwire's own CLI<->MCP seam.
#
# §11 (added 2026-08-15) carries the DEFINITION half of the same grammar recursion: an out-of-line
# definition written with two or more qualifier segments was dropped by the mirror-image defect in the
# definition pattern, just as silently. Read its own section header for that round's evidence.
#
# THREE CORPORA. test/cppqualfix/ proves each CALL SPELLING extracts and resolves; every name in it has
# exactly one definition, so those arms cannot prove the re-split chose the RIGHT def. test/cppqualdecoyfix/
# (§8) gives each name a same-final-name DECOY in another scope, so a wrong qualifier binds provably wrong.
# test/cppqualdeffix/ (§11) is the definition-side corpus, with its own same-final-name decoy.
#
# EVERY expected count below is a LITERAL, read by hand off the fixtures (plan §7 trap 1: a gate that derives
# its expected number the way the code does cannot catch the derivation). Each fixture's header comment maps
# each spelling to the mechanism it proves.
#
# RED-FIRST (recorded 2026-07-31; three reference binaries, each pinned to what it proves):
#   vs build/ripwire_base (pre-§H4): 28 of the 49 checks fail —
#     fixture header edges=3 ambiguous=0   (now 11 / 1)
#     --uses: targetFn 0, make 0, get 0, pick 0, freeTmpl 0, scopedTmpl 0, Widget 0   (now 1/1/2/1/1/1/1)
#     repo root: --uses=selectBaseline 1, --callers=writeTally 0, --uses=writeTally 0, --uses=readWholeFile 1
#     --edit-check arity change on a 3-segment cross-file caller: callers="1"  (now "2", both incompatible)
#   vs build/ripwire_prefixup (§H4 as first shipped): the three §8 `>`-family arms fail — qualified
#     operator> / operator>> / operator>= bound the OUTER decoys at :65/:66/:67 instead of :76/:77/:78.
#   vs asan/ripwire_prefixup: §9's --from-trace arm exits 134 (sanitizer abort). The PLAIN build is silent
#     on that wrap, so §9 only carries evidence when RIPWIRE_BIN points at a G1 binary.
#   All 49 PASS against the fixed binary, plain AND asan (65 with §11's definition arm, added later).
#   (The four cast arms and the two most-vexing-parse arms pass on every binary by construction — they are
#   regression guards for a future round, not evidence of this one.)
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/cppqualcheck.sh   |   bash test/cppqualcheck.sh asan/ripwire
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"      # BOTH seams: positional arg and RIPWIRE_BIN=
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolute BEFORE we cd away
PROBE="$( dirname "$BIN" )/ripwire_probe"
FIX="$ROOT/test/cppqualfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/cppqualfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "cppqualcheck: BIN=$BIN  CORPUS=test/cppqualfix + repo root"

run(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$@" 2>/dev/null; }
cnt(){ printf '%s' "$1" | grep -oE 'count="[0-9]+"' | head -1 | tr -dc 0-9; }

# expect the `count="N"` of a fixture verb to equal a literal
expect(){   # $1 verb  $2 sym  $3 want  $4 prose
    local out; out="$( run "$FIX" "--$1=$2" --no-cache )"
    local got; got="$( cnt "$out" )"
    [ "${got:-REFUSED}" = "$3" ] && ok "--$1=$2 count=$3 — $4" \
        || no "--$1=$2 expected count=$3, got '${got:-REFUSED}' — $4"
}

MAP="$( run "$FIX" --no-cache )"

# ── §1 per-SPELLING extraction + resolution (one call site per spelling; see the fixture header) ────────
expect uses    twoSeg     1 "2-segment control (a::twoSeg) — the shape the REPLACED pattern bound, still bound once"
expect uses    targetFn   1 "3 segments (a::b::targetFn) — bound NOTHING before the widening"
expect uses    make       1 "4 segments (a::b::Widget::make)"
expect uses    globalFn   1 "leading :: with no scope field (::globalFn)"
expect uses    get        2 "templated scope (a::b::Box<int>::get AND a::b::Box<a::b::Tag>::get)"
expect uses    freeTmpl   1 "explicit template arguments (freeTmpl<int>)"
expect uses    scopedTmpl 1 "template_function UNDER a qualified_identifier (a::scopedTmpl<int>)"
expect uses    Widget     1 "qualified constructor (a::b::Widget()) — a call ref named for the CLASS"
expect uses    ping       1 "member call on the ctor temporary — unaffected control"
expect callers targetFn   1 "3-segment call names its caller"
expect callers make       1 "4-segment call names its caller"
expect callers get        1 "both templated-scope sites collapse to ONE caller (edges are distinct pairs)"
expect callers freeTmpl   1 "explicit-template-arg call names its caller"

# ── §2 PRECISION: the trap spelling must land on Box::get, never on the CLASS Box ───────────────────────
# `finalSegment()` truncates at the FIRST '<', so running it on the widened capture would name
# `b::Box<int>::get` as `Box` and spray an edge onto the Box CLASS DEF — a plausible, wrong graph. The
# re-split (last TOP-LEVEL `::`, template args stripped from the scope half) is what prevents it.
CALLEES="$( run "$FIX" --callees=callerQualified --no-cache )"
printf '%s' "$CALLEES" | grep -q 'n="get"' \
    && ok "templated-scope call resolves to the METHOD get" \
    || no "templated-scope call did not resolve to get: $CALLEES"
printf '%s' "$CALLEES" | grep -q 'n="Box"' \
    && no "WRONG GRAPH: callerQualified has an edge to the CLASS Box — finalSegment ran before the re-split" \
    || ok "no edge to the class Box (the first-'<' truncation trap is closed)"
[ "$( cnt "$CALLEES" )" = 7 ] \
    && ok "--callees=callerQualified count=7 (globalFn twoSeg targetFn pick pick make get)" \
    || no "--callees=callerQualified expected 7, got '$( cnt "$CALLEES" )': $CALLEES"

# ── §3 AMBIGUITY IS DISCLOSED, never silently resolved ─────────────────────────────────────────────────
# `a::b::pick( 1 )` has TWO defs of equal arity in the SAME immediate scope, so the arity prune cannot split
# them. New edges must land in `ambiguous=` and carry per-row `amb=` exactly like every other name-based
# edge — if a widened edge bypassed the accounting, the fix would have swapped a silent UNDER-count for a
# silent OVER-count, which is worse. This arm uses a SAME-immediate-scope pair because a different-scope
# pair is separated by the canonical qualifier and so would never reach the ambiguity path at all.
# That is NOT the claim "different-scope pairs resolve precisely" — §8's decoy fixture exists because for
# the `>`-family operator names they did NOT, and the mis-binding was silent (ambiguous=0, no amb=).
printf '%s' "$MAP" | grep -qE 'files=1 symbols=23 edges=11 shown=23 est_tokens=[0-9]+ ambiguous=1 unresolved=0' \
    && ok "fixture header: edges=11 ambiguous=1 unresolved=0 (was edges=3 ambiguous=0)" \
    || no "fixture header wrong: $( printf '%s' "$MAP" | grep -oE 'files=1 [^-]*' | head -1 )"
printf '%s' "$MAP" | grep -q '<s t="fn" n="callerQualified" amb="1"' \
    && ok "callerQualified carries amb=\"1\" — the pick pair, disclosed per-row" \
    || no "callerQualified is missing its amb=\"1\" row attribute"
[ "$( printf '%s' "$MAP" | grep -oE '<c n="pick"/>' | wc -l | tr -d ' ' )" = 2 ] \
    && ok "the ambiguous call splits onto BOTH pick defs (2 rows), never picks one" \
    || no "the ambiguous call did not split onto both pick defs"
# and the canonical sites did NOT become ambiguous: exactly ONE ambiguous call in the whole fixture.
printf '%s' "$MAP" | grep -qE '<s t="fn" n="callerTemplated"( |>)' \
    && ! printf '%s' "$MAP" | grep -q 'n="callerTemplated" amb=' \
    && ok "PRECISE: callerTemplated carries no amb= (canonical keying held for the template forms)" \
    || no "callerTemplated unexpectedly ambiguous — canonical keying broke"
printf '%s' "$MAP" | grep -q 'n="callerCtor" amb=' \
    && no "callerCtor unexpectedly ambiguous" \
    || ok "PRECISE: callerCtor carries no amb="

# ── §4 CAST KEYWORDS MINT ZERO REFERENCES ──────────────────────────────────────────────────────────────
# tree-sitter-cpp parses `static_cast<T>( x )` as call_expression function: (template_function name:
# (identifier)) — the SAME node shape as a real explicit-template-argument call. Query predicates cannot
# exclude them (passesPredicates is wired into --match/--lint only, never the tags pass — measured), so the
# exclusion lives at capture time in ingest.cpp. Asserted PRE-resolution via the probe, because a cast ref
# resolves to nothing and would otherwise vanish silently while still inflating every extraction count.
if [ -x "$PROBE" ]; then
    CASTREFS="$( perl -e 'alarm 30; exec @ARGV' "$PROBE" "$FIX" 2>/dev/null | grep -A1 'callerCasts' | grep 'calls:' )"
    # VACUITY GUARD (L-6). "does not contain a cast keyword" is satisfied by the EMPTY STRING, so if the
    # probe's output format ever shifts under this grep the arm would pass while testing nothing. Assert the
    # POSITIVE first: callerCasts' four cast operands and its parameters are real refs that must be present.
    if printf '%s' "$CASTREFS" | grep -q 'opaque' && printf '%s' "$CASTREFS" | grep -q 'base' \
       && printf '%s' "$CASTREFS" | grep -q 'c1'; then
        ok "probe output for callerCasts is non-vacuous (control refs opaque/base/c1 present)"
        printf '%s' "$CASTREFS" | grep -qE 'static_cast|reinterpret_cast|const_cast|dynamic_cast' \
            && no "cast keywords minted references: $CASTREFS" \
            || ok "callerCasts extracts ZERO cast references (probe, pre-resolution): $CASTREFS"
    else
        no "probe output for callerCasts is EMPTY or unrecognised — the cast arm would pass vacuously. Got: '$CASTREFS'"
    fi
else
    echo "  SKIP  ripwire_probe not built at $PROBE — cast arm is --uses-only"
fi
for kw in static_cast reinterpret_cast const_cast dynamic_cast; do
    RC="$( perl -e 'alarm 30; exec @ARGV' "$BIN" "$FIX" --uses="$kw" --no-cache >/dev/null 2>&1; echo $? )"
    [ "$RC" = 1 ] && ok "--uses=$kw refuses (no def, no use-sites) — the cast flood stayed out" \
        || no "--uses=$kw expected refusal (exit 1), got exit $RC"
done

# ── §5 MOST-VEXING-PARSE: a permanent, pinned ZERO ──────────────────────────────────────────────────────
# `std::lock_guard<std::mutex> g( a::b::mutexFn() );` contains NO call_expression at all — the whole line
# parses as a declaration with a function_declarator. No query widening can recover it (this is why the
# repo's own --callers=headSnapshotIngestMutex is still 0). The literal 0 is pinned so a later round cannot
# "fix" it by inventing an edge from a shape the grammar never produced.
expect uses    mutexFn 0 "most-vexing-parse: unfixable by any query widening, pinned at literal 0"
expect callers mutexFn 0 "most-vexing-parse: no caller, by construction"

# ── §6 REPO-ROOT RECOVERY — the seams the defect was found on ───────────────────────────────────────────
# Literals from the W1-MEASURE census. These are the
# flagship "did I break a caller?" sites: selectBaseline's second caller is a hard compile error under an
# arity change and was never named; writeTally had a def and two call sites and reported ZERO callers.
US="$( run . --uses=selectBaseline --no-cache )"
{ [ "$( cnt "$US" )" = 2 ] && printf '%s' "$US" | grep -q 'mcpverbs.h'; } \
    && ok "repo: --uses=selectBaseline count=2 and names the mcpverbs.h qualified caller (was 1)" \
    || no "repo: --uses=selectBaseline expected 2 incl. mcpverbs.h, got '$( cnt "$US" )': $US"
# 4 -> 5 when src/readability.h adopted docparse::detail::readWholeFile as the canonical whole-file read
# (the feat/readability-lens round); 5 -> 6 when src/renamemine.h adopted the same one (feat/naming-calibration);
# 6 -> 7 when src/commentcoherence.h adopted the same one (feat/comment-coherence).
# The literal counts REAL call sites, so it moves when a real call site is
# added; what it pins is that the qualified `docparse::detail::` spelling still RESOLVES, which is the defect
# this arm was written for. Bumping it is correct; changing it to a >= would retire the arm.
# 7 -> 9 2026-08-08: docTextViaBridgeCache (ingest.cpp) reads the doc bytes for its content-hash key and
# reads the cached blob back through the same canonical helper — both sites re-read before this re-pin.
[ "$( cnt "$( run . --uses=readWholeFile --no-cache )" )" = 9 ] \
    && ok "repo: --uses=readWholeFile count=9 (docparse::detail:: — a seam the audit's rw::-anchored grep missed)" \
    || no "repo: --uses=readWholeFile expected 9"
[ "$( cnt "$( run . --callers=writeTally --no-cache )" )" = 1 ] \
    && ok "repo: --callers=writeTally count=1 (was 0 — both template call sites are in writeDocDriftPage)" \
    || no "repo: --callers=writeTally expected 1"
[ "$( cnt "$( run . --uses=writeTally --no-cache )" )" = 2 ] \
    && ok "repo: --uses=writeTally count=2 (the two explicit-template-argument call sites)" \
    || no "repo: --uses=writeTally expected 2"
[ "$( cnt "$( run . --callers=headSnapshotIngestMutex --no-cache )" )" = 0 ] \
    && ok "repo: --callers=headSnapshotIngestMutex stays 0 — its 4 sites are most-vexing-parse declarations" \
    || no "repo: --callers=headSnapshotIngestMutex expected 0 (widening must NOT invent these edges)"

# ── §7 --edit-check names a CROSS-FILE QUALIFIED caller on a contract change (plan §6) ──────────────────
# The measured defect: `--edit-check=selectBaseline` on an arity change reported callers="1" and never named
# the `rw::quality::selectBaseline( … )` caller in mcpverbs.h — a hard compile error under that change.
# Same scenario, hermetically, in a private temp git repo (editcheckcheck.sh's mechanism).
if command -v git >/dev/null 2>&1; then
    WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
    mkdir -p "$WORK/src"
    cat > "$WORK/src/a.cpp" <<'EOF'
namespace app
{
namespace core
{

int inner( int x ) { return x + 1; }

int nearUse( int a ) { return inner( a ); }

}
}
EOF
    cat > "$WORK/src/far.cpp" <<'EOF'
int farUse( int a )
{
    return app::core::inner( a );   // 3-segment cross-file caller — invisible before §H4
}
EOF
    ( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init >/dev/null 2>&1 )

    EC0="$( cd "$WORK" && perl -e 'alarm 30; exec @ARGV' "$BIN" . --edit-check=inner --no-cache 2>/dev/null )"
    printf '%s' "$EC0" | grep -q 'status="unchanged"' && printf '%s' "$EC0" | grep -q 'callers="2"' \
        && ok "--edit-check clean tree: callers=\"2\" — the qualified cross-file caller is counted (was 1)" \
        || no "--edit-check clean tree: expected unchanged + callers=\"2\", got: $EC0"

    # arity change: BOTH callers are now provably incompatible and BOTH must be named.
    cat > "$WORK/src/a.cpp" <<'EOF'
namespace app
{
namespace core
{

int inner( int x, int y ) { return x + y; }

int nearUse( int a ) { return inner( a ); }

}
}
EOF
    EC1="$( cd "$WORK" && perl -e 'alarm 30; exec @ARGV' "$BIN" . --edit-check=inner --no-cache 2>/dev/null )"
    ROWS="$( printf '%s' "$EC1" | grep -oE '<c [^>]*/>' )"
    printf '%s' "$EC1" | grep -q 'status="contract-change"' && printf '%s' "$EC1" | grep -q 'params_was="1" params_now="2"' \
        && ok "--edit-check arity change: contract-change, params 1 -> 2" \
        || no "--edit-check arity change: expected contract-change 1->2, got: $EC1"
    printf '%s' "$ROWS" | grep -q 'n="farUse".*incompatible="1"' \
        && ok "--edit-check names the QUALIFIED cross-file caller farUse() as incompatible — the §H4 headline" \
        || no "--edit-check did NOT name the qualified caller farUse: $ROWS"
    printf '%s' "$ROWS" | grep -q 'n="nearUse".*incompatible="1"' \
        && ok "--edit-check still names the unqualified caller nearUse() (no regression)" \
        || no "--edit-check lost the unqualified caller nearUse: $ROWS"
else
    echo "  SKIP  git not available — the --edit-check arm needs a temp repo"
fi

# ── §8 THE DECOY CORPUS: prove the re-split picked the RIGHT def, not merely A def ─────────────────────
# Every name in cppqualfix has ONE definition, so a garbage qualifier still lands on it by bare-name
# fallback — those arms prove extraction, never binding. test/cppqualdecoyfix/decoy.cpp gives each name a
# same-final-name DECOY in a different scope, so a wrong qualifier binds provably wrong. Line numbers are
# read off the fixture: outer decoys 65-70, inner targets 76-81, Box::get 41, Other::get 46.
DEC="$ROOT/test/cppqualdecoyfix"
if [ -d "$DEC" ]; then
    DMAP="$( run "$DEC" --no-cache )"
    DOPS="$( run "$DEC" --callees=callerOperators --no-cache )"
    DSTR="$( run "$DEC" --callees=callerStrip --no-cache )"

    # M-2: the `>`-family. A trailing `>` opened a template group the reverse scan never closed, so the
    # re-split was SKIPPED and the qualifier fell back to the OUTERMOST scope — binding the outer decoy.
    # Measured before the fix: operator> -> :65, operator>> -> :66, operator>= -> :67 (all decoys).
    for pair in 'operator&gt;:76' 'operator&gt;&gt;:77' 'operator&gt;=:78'; do
        opname="${pair%:*}"; wantline="${pair##*:}"
        printf '%s' "$DOPS" | grep -qE "<s [^>]*n=\"$opname\" p=\"[^\"]*decoy\.cpp:$wantline\"" \
            && ok "qualified $opname binds the INNER target (decoy.cpp:$wantline), not the outer decoy" \
            || no "qualified $opname bound the WRONG def — expected decoy.cpp:$wantline, got: $DOPS"
    done
    # controls: the `<`-family never broke, and a plain identifier that merely STARTS with "operator"
    # must NOT take the operator path.
    printf '%s' "$DOPS" | grep -qE '<s [^>]*n="operator&lt;&lt;" p="[^"]*decoy\.cpp:79"' \
        && ok "control: operator<< still binds the inner target (decoy.cpp:79)" \
        || no "control: operator<< regressed — got: $DOPS"
    printf '%s' "$DOPS" | grep -qE '<s [^>]*n="operatorId" p="[^"]*decoy\.cpp:80"' \
        && ok "control: operatorId is a PLAIN identifier (decoy.cpp:80) — the operator path did not swallow it" \
        || no "control: operatorId took the operator path — got: $DOPS"
    printf '%s' "$DOPS" | grep -qE '<s [^>]*n="gt" p="[^"]*decoy\.cpp:81"' \
        && ok "control: the plain-name 3-segment call binds the inner gt (decoy.cpp:81)" \
        || no "control: plain-name 3-segment call bound the outer decoy — got: $DOPS"

    # M-3: the template-argument strip. `a::b::Box<int>::get` re-splits to the qualifier `Box<int>` — not a
    # canonical key — unless the scope half is stripped first, and then the call sprays across BOTH get defs.
    # NOTE: --callees alone does NOT discriminate here (a sprayed call still touches both defs, so the same
    # two rows appear). `ambiguous=` is the discriminator — verified by a scratch build with the strip
    # removed, which moved this corpus to ambiguous=1 while --callees stayed byte-identical.
    printf '%s' "$DMAP" | grep -q 'ambiguous=0 unresolved=0' \
        && ok "decoy corpus: ambiguous=0 — the template-arg strip kept every call canonically bound" \
        || no "decoy corpus: expected ambiguous=0 (a lost stripTemplateArgs sprays Box::get across Other::get): $( printf '%s' "$DMAP" | grep -oE 'ambiguous=[0-9]+ unresolved=[0-9]+' )"
    printf '%s' "$DSTR" | grep -qE '<s [^>]*n="get" p="[^"]*decoy\.cpp:41"' \
        && printf '%s' "$DSTR" | grep -qE '<s [^>]*n="get" p="[^"]*decoy\.cpp:46"' \
        && ok "decoy: Box<int>::get -> :41 and Other::get -> :46, each on its own def" \
        || no "decoy: callerStrip did not reach both gets by line: $DSTR"

    # L-2 REGRESSION FENCE (explicitly NOT red-first — see hostile.cpp's header). operatorNameStart used a
    # bare rfind and so returned non-npos for a NON-trailing operator segment, splitting `op::operator>::go`
    # into name `operator>::go` / qualifier `op` — a contract violation, but one the graph never showed:
    # both the pre-fix and post-fix binaries name this reference `go`. The helper now requires the operator's
    # punctuation run to reach end-of-text; this pins the observable behaviour so a future scan change cannot
    # start mis-splitting the spelling unnoticed.
    DHOS="$( run "$DEC" --callees=hostileCaller --no-cache )"
    printf '%s' "$DHOS" | grep -qE '<s [^>]*n="go" p="[^"]*hostile\.cpp:25"' \
        && ok "L-2 fence: op::operator>::go resolves to go (hostile.cpp:25) — no wrong split from the non-trailing operator segment" \
        || no "L-2 fence: op::operator>::go did not resolve to go at hostile.cpp:25 — got: $DHOS"
else
    echo "  SKIP  test/cppqualdecoyfix missing — the discriminating arms cannot run"
fi

# ── §9 G1: an operator frame through --from-trace must not ABORT the sanitizer build ───────────────────
# stripTrailingGroup's reverse scan used the classic `for( i = n; i-- > 0; )`, whose final test wraps i to
# SIZE_MAX. That is a defined unsigned overflow, but `-fsanitize=integer -fno-sanitize-recover=all` ABORTS
# on it, and the wrap only happens when the scan runs off the front — i.e. on an UNBALANCED trailing group,
# which every `>`-family operator name supplies. Measured before the fix: rc=134.
#
# TWO THINGS MAKE THIS ARM MEAN SOMETHING, and it had neither when it was first written (V3-H-2):
#
#   (a) A POSITIVE CONTROL. `rc == 0` is satisfied by a run that never enters stripTrailingGroup at all — a
#       trace naming a symbol that is not in the corpus exits 0 just as happily. So the arm FIRST proves the
#       hostile frame was actually parsed and RESOLVED BY NAME. `resolved_by="name"` is the exact signal:
#       name resolution is what runs the frame's spelling through nameCandidates -> stripTemplateArgs, so
#       that attribute is the receipt that the scan was executed on `nsx::ops::operator>`. If --from-trace
#       ever stops parsing operator frames — or falls back to line-enclosure — this arm reds instead of
#       silently going vacuous.
#
#   (b) A FLAVOUR PROBE, so the arm cannot be mistaken for evidence it did not gather. The integer-overflow
#       class is ONLY observable under the G1 stack; a plain binary executes the same wrap in silence. The
#       probe reports which flavour ran. It deliberately does NOT fail on a plain binary — unlike
#       estchargecheck #14a, where the alert SHOULD be visible in the plain build and its absence means
#       NDEBUG — because here the plain build legitimately cannot see the class, and the whole suite runs
#       plain. What a plain rc=0 still buys: the frame parses, the scan terminates, and the document is
#       produced — everything except the sanitizer class. The abort evidence comes from CI, which runs this
#       gate under asan (.github/workflows/ci.yml, the G1 heavy-verb list).
TRDIR="$( mktemp -d )"; TRTXT="$( mktemp )"; trap 'rm -rf "$TRDIR" "$TRTXT" ${WORK:+"$WORK"}' EXIT
cat > "$TRDIR/edge.cpp" <<'EOF'
namespace nsx
{
namespace ops
{

struct S { int v = 0; };

bool operator>( const S& a, const S& b ) { return a.v > b.v; }

}
}
EOF
printf '#0 0x1 in nsx::ops::operator>(S const&, S const&) edge.cpp:8\n' > "$TRTXT"
TROUT="$( perl -e 'alarm 60; exec @ARGV' "$BIN" "$TRDIR" --from-trace="$TRTXT" --no-cache 2>/dev/null )"
TRC="$( perl -e 'alarm 60; exec @ARGV' "$BIN" "$TRDIR" --from-trace="$TRTXT" --no-cache >/dev/null 2>&1; echo $? )"

# (a) POSITIVE CONTROL first — without it, rc=0 proves nothing about the scan.
#
# TWO traps live in this one assertion, and both were stepped in while writing it:
#   * Match the <frame/> ELEMENT, never the whole document. --from-trace's legend comment prose-describes
#     `resolved_by="name"`, so a document-wide grep matches the LEGEND and passes on a frame that resolved
#     by line. (editcheckcheck.sh documents the identical trap for incompatible="1"; its `rows()` helper is
#     the pattern followed here.)
#   * `resolved_by` is the whole assertion. A frame naming a symbol that does not exist ANYWHERE still comes
#     back with n="operator&gt;" p="edge.cpp:8" — because line-enclosure binds it to whatever squats on line
#     8. Measured: an absent-symbol frame yields resolved_by="line" with byte-identical n=/p=. Asserting the
#     obvious n=/p= pair alone would therefore have been satisfied by a frame the name ladder never touched.
#     Only resolved_by="name" proves nameCandidates -> stripTemplateArgs actually ran the hostile spelling.
TRFRAME="$( printf '%s' "$TROUT" | grep -oE '<frame [^>]*/>' )"
if printf '%s' "$TRFRAME" | grep -q 'n="operator&gt;"' \
   && printf '%s' "$TRFRAME" | grep -q 'p="edge.cpp:8"' \
   && printf '%s' "$TRFRAME" | grep -q 'resolved_by="name"'; then
    ok "positive control: the operator> frame IS parsed and resolved BY NAME (edge.cpp:8) — the hostile spelling really ran through the scan"
else
    no "positive control FAILED: the <frame/> did not resolve by NAME, so the rc check below would be vacuous. Got: ${TRFRAME:-<no frame element>}"
fi

# (b) FLAVOUR PROBE — disclose whether this binary can observe the class the arm is about. Detected from the
#     binary's UNDEFINED symbols: a -fsanitize=integer build imports __ubsan_handle_* from the runtime, a
#     plain one imports none. `strings` is the fallback for a toolchain without nm; if neither tool is
#     present the flavour is reported UNKNOWN rather than guessed.
TRFLAV="unknown"
if command -v nm >/dev/null 2>&1; then
    nm -u "$BIN" 2>/dev/null | grep -qE '__ubsan_handle|__asan_report' && TRFLAV="sanitizer" || TRFLAV="plain"
elif command -v strings >/dev/null 2>&1; then
    strings -a "$BIN" 2>/dev/null | grep -q '__asan_annotation' && TRFLAV="sanitizer" || TRFLAV="plain"
fi
case "$TRFLAV" in
    sanitizer) echo "  NOTE  §9 flavour: SANITIZER binary — this run CAN observe the integer-overflow class (rc=134 before the fix)" ;;
    plain)     echo "  NOTE  §9 flavour: PLAIN binary — the wrap would execute SILENTLY here, so rc=0 below is NOT abort evidence."
               echo "        It still proves the frame parses, the scan terminates and the document is produced."
               echo "        The abort evidence is CI's asan run of this gate (.github/workflows/ci.yml, G1 job)." ;;
    *)         echo "  NOTE  §9 flavour: UNKNOWN (no nm/strings) — treat rc=0 below as parse evidence only." ;;
esac

[ "$TRC" = 0 ] \
    && ok "--from-trace on an operator> frame exits 0 (rc=134 before the fix, under the G1 sanitizer stack)" \
    || no "--from-trace on an operator> frame exited $TRC — the reverse-scan wrap is back (134 = sanitizer abort)"

# ── §11 the DEFINITION half of the same recursion (C1 — memgraph F1) ────────────────────────────────────
# Everything above is about qualified CALLS. A C++ out-of-line DEFINITION written with TWO OR MORE
# qualifier segments — `void nsD::OuterD::InnerD::deep3(){}`, the house style of whole codebases — was
# dropped by the mirror-image defect in the DEFINITION pattern, and dropped SILENTLY: no --skipped row, no
# floor, no `unresolved=`. The symbol did not exist, so every caller of it read as a leaf.
#
# THIRD CORPUS: test/cppqualdeffix/. §3 pins a hand-read `files=1 symbols=23` header for cppqualfix/, so a
# second .cpp there would invalidate that literal for reasons unrelated to what it proves. See the
# fixture's own header for the shape->sink table every literal below is read off.
#
# Each definition body calls its OWN uniquely named sink, so `--callers=<sink>` is one literal that proves
# BOTH halves of the claim at once: the definition is indexed, AND it carries its body's call edges (a def
# indexed without a body would report the same count="0" as a def that was never indexed at all).
#
# RED-FIRST (recorded 2026-08-15 against build/ripwire_c1base, the pre-fix binary built at 4b9386c):
# 12 of the 14 checks below FAIL. The fixture header reads `symbols=24 edges=1` (now 30 / 7); six of the
# seven sink arms report count=0 — sinkOneSeg, the 1-qualifier control, is the only definition that was
# ever indexed; and neither deep3 row carries overloads="2", because both rows are the in-class
# DECLARATIONS alone. The two that pass pre-fix are the control and the negative `nsD::deep3` arm (a
# spelling neither binary produces — it is the guard against the outermost-scope key, not evidence of this
# round). All 14 pass against the fixed binary.
DEFFIX="$ROOT/test/cppqualdeffix"
[ -d "$DEFFIX" ] || { echo "no test/cppqualdeffix dir — the definition fixture is missing"; exit 2; }
DEFMAP="$( run "$DEFFIX" --no-cache )"

# (a) POSITIVE CONTROL first (L-6 vacuity guard): the 1-qualifier definition was ALWAYS indexed, so an arm
#     that reports 0 for it means the corpus/run is broken, not that the fix regressed.
[ "$( cnt "$( run "$DEFFIX" --callers=sinkOneSeg --no-cache )" )" = 1 ] \
    && ok "def §11 control: --callers=sinkOneSeg count=1 (OuterB::oneSeg — 1 qualifier, indexed before the fix too)" \
    || no "def §11 control: --callers=sinkOneSeg expected 1 — the fixture or the run is broken, every arm below is vacuous"

# (b) one literal per newly indexed SHAPE.
defcallers(){   # $1 sink  $2 prose
    local got; got="$( cnt "$( run "$DEFFIX" --callers="$1" --no-cache )" )"
    [ "${got:-REFUSED}" = 1 ] && ok "def §11: --callers=$1 count=1 — $2" \
        || no "def §11: --callers=$1 expected 1, got '${got:-REFUSED}' — $2"
}
defcallers sinkTwo     "OuterB::InnerB::deep2 — 2 qualifiers, class in class"
defcallers sinkNsCls   "nsC::ClsC::nsQualMeth — 2 qualifiers, namespace + class"
defcallers sinkThree   "nsD::OuterD::InnerD::deep3 — 3 qualifiers"
defcallers sinkTmplDef "OuterT<T>::InnerT::tdeep — 2 qualifiers, TEMPLATED outer scope"
defcallers sinkOpDef   "VecV::InnerV::operator== — 2 qualifiers, OPERATOR name"
defcallers sinkDecoy   "nsD::OuterD::deep3 — the decoy definition is itself 2 qualifiers"

# (c) --callees on such a definition is non-empty and names the right sink (the downstream symptom the
#     finding was reported on: `--callees=<a Storage::Accessor:: method>` returned count=0 because the only
#     def it could see was the bodyless header declaration).
DEFCALLEES="$( run "$DEFFIX" --callees=deep2 --no-cache )"
{ [ "$( cnt "$DEFCALLEES" )" = 1 ] && printf '%s' "$DEFCALLEES" | grep -q 'n="sinkTwo"'; } \
    && ok "def §11: --callees=deep2 count=1 and names sinkTwo — the def has a BODY to read callees from" \
    || no "def §11: --callees=deep2 expected count=1 naming sinkTwo, got: $DEFCALLEES"

# (d) PRECISION: the scope is the IMMEDIATE one, not the outermost. The captured node is an INNER
#     qualified_identifier, so the naive read — qualifierOf() on the capture's own parent — yields the
#     OUTERMOST scope (`nsD` for a 3-segment name). `nsD::OuterD` declares its own `deep3()` precisely so
#     that a mis-key is observable: an outermost-scope def would merge into that decoy row and hand
#     sinkThree to the wrong method, silently and plausibly.
#
#     WHY NOT ASSERT THE id= ROWS ALONE: both `InnerD::deep3` and `OuterD::deep3` rows exist even on the
#     PRE-FIX binary, minted by the in-class DECLARATIONS — so an id-presence arm passes while the two
#     definitions are missing entirely. The discriminating fact is which row the def MERGED INTO, read off
#     `overloads=` (decl+def collapsed = 2) and off the caller line each sink names.
printf '%s' "$DEFMAP" | grep -qE '<s t="method" n="deep3" id="[^"]*nesteddef\.cpp::InnerD::deep3" overloads="2"' \
    && ok "def §11 precision: the 3-segment def merged into the InnerD::deep3 row (overloads=2) — IMMEDIATE scope" \
    || no "def §11 precision: InnerD::deep3 is not overloads=2 — the def took the wrong scope or is absent"
printf '%s' "$DEFMAP" | grep -qE '<s t="method" n="deep3" id="[^"]*nesteddef\.cpp::OuterD::deep3" overloads="2"' \
    && ok "def §11 precision: the decoy OuterD::deep3 kept exactly its own def (overloads=2, not 3)" \
    || no "def §11 precision: OuterD::deep3 is not overloads=2 — the two deep3 definitions merged"
printf '%s' "$DEFMAP" | grep -qE 'id="[^"]*nesteddef\.cpp::nsD::deep3"' \
    && no "def §11 precision: a nsD::deep3 row exists — the def keyed on the OUTERMOST namespace" \
    || ok "def §11 precision: no nsD::deep3 row (the outermost-scope mis-key is closed)"
# and the two sinks name DIFFERENT definition lines — the same fact from the edge side, where a merge
# would be invisible to any row attribute. Literals read by hand off the fixture.
printf '%s' "$( run "$DEFFIX" --callers=sinkThree --no-cache )" | grep -qE 'p="[^"]*nesteddef\.cpp:107"' \
    && ok "def §11 precision: sinkThree's caller is the def at nesteddef.cpp:107 (nsD::OuterD::InnerD::deep3)" \
    || no "def §11 precision: sinkThree's caller is not the :107 definition"
printf '%s' "$( run "$DEFFIX" --callers=sinkDecoy --no-cache )" | grep -qE 'p="[^"]*nesteddef\.cpp:102"' \
    && ok "def §11 precision: sinkDecoy's caller is the def at nesteddef.cpp:102 (nsD::OuterD::deep3)" \
    || no "def §11 precision: sinkDecoy's caller is not the :102 definition"

# (e) the fixture header, hand-read: 7 definitions x 1 sink call each = 7 edges, all canonical.
printf '%s' "$DEFMAP" | grep -qE 'files=1 symbols=30 edges=7 shown=30 est_tokens=[0-9]+ ambiguous=0 unresolved=0' \
    && ok "def §11 header: symbols=30 edges=7 ambiguous=0 unresolved=0 (was symbols=24 edges=1)" \
    || no "def §11 header wrong: $( printf '%s' "$DEFMAP" | grep -oE 'files=1 [^-]*' | head -1 )"

# ── §10 determinism + well-formed XML ───────────────────────────────────────────────────────────────────
[ "$( run "$FIX" --no-cache )" = "$( run "$FIX" --no-cache )" ] \
    && ok "determinism: the fixture map is byte-identical run-to-run" \
    || no "determinism: the fixture map is not byte-identical"
# V4 MED-1: a missing xmllint is a FAILURE, not a silent skip — G4 is a hard guardrail and a PASS
# count that silently shrinks hides the hole (same law floormarkcheck/rustqualcheck already follow).
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$MAP" | xmllint --noout - 2>/dev/null && printf '%s' "$CALLEES" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (fixture map + --callees)" || no "xml malformed"
else
    no "xmllint not on PATH — the G4 arm cannot run; install libxml2/xmllint (a gate that cannot run must say so)"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
