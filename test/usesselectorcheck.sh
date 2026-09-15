#!/usr/bin/env bash
# usesselectorcheck.sh — §P10.2 gate: --uses accepts the "file:name" selector its eight siblings
# (--callers/--callees/--impact/--around/--edit-check/--lego/--expand/--outline) already do.
#
# THE BUG (pre-fix): --uses=src/graph.h:buildGraph refused with a FALSE message ("no definition AND no
# reference site in the indexed tree" — both exist) and a constant nonsense suggestion (`srcmut_sigchange`,
# the did-you-mean fuzzy-matching the literal "src" prefix of every "src/...:name" selector).
#
# THE FIX: defs= now resolves through the SAME shared resolver (resolveAllByNameQualified) --callers/
# --expand/--path use, so a file: qualifier narrows WHICH definitions are counted. Use-site matching stays
# reference-NAME-based (r.calleeName carries no file/scope info), so it can NOT be split per-def — sites
# stays the name-wide union, and a new defs_of_name= attribute (present only with a file: qualifier)
# discloses that un-narrowed count so the gap is visible instead of silently implied. The refusal message
# for a genuinely-unresolved selector now states only what is true (no INDEXED DEFINITION matched — never
# "no reference site", which the sites scan never actually checked per-file) and the did-you-mean now
# suggests against the NAME half only.
#
# Run against this repo's own source tree (self-hosting) — the concrete symbols below (buildGraph,
# NoteIndex::empty / ScipOverlay::empty as the overloaded-name pair) are real ripwire symbols, not a fixture.
#
#   test/usesselectorcheck.sh                      # uses build/ripwire on the repo root
#   RIPWIRE_BIN=build_base/ripwire test/usesselectorcheck.sh   # must FAIL — the pre-fix binary (RED proof)
#
# (f), added 2026-09-11, was the KNOWN GAP section for the help-wanted prompt prompts/help-wanted/uses-qualified-selector.md
# (issue #164): a "::" selector (the canonical id path::scope::name, or Scope::name) resolves defs= and then answers count="0",
# because the site scan matches the WHOLE spelling against reference names, which are always bare. Its arms, and arm (d)'s
# canonical-id arm, pinned that wrong answer and PASSED; issue #164's fix flipped each to its FIXED line, which is that
# prompt's acceptance test. It runs on two fixtures other gates own and pin:
# test/declinefix (C++, Python — declinecheck.sh) and test/rustqualfix (Rust — rustqualcheck.sh).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "usesselectorcheck: BIN=$BIN  ROOT=$ROOT"

uses_elem(){ "$BIN" "$ROOT" --uses="$1" --no-cache 2>/dev/null | grep -o '<uses[^>]*>'; }
attr(){ printf '%s' "$1" | grep -o "$2=\"[0-9]*\"" | grep -o '[0-9]*'; }
# the role="call" sites (p=file:line) a uses answer lists that NO caller row of a callers answer holds —
# test/declinecheck.sh's call_sites helper (line 107), copied verbatim: the enclosing symbol is (file, in_id
# leaf), the caller rows are (p, n leaf). Empty output means the two verbs agree.
# Defined up here (not with the other helpers below) because arm (d) calls it at line ~170.
call_sites(){ python3 - "$@" <<'PY'
import sys, xml.etree.ElementTree as ET
leaf = lambda s: s.rsplit( "::", 1 )[ -1 ]
where = lambda p, n: ( p.rsplit( ":", 1 )[ 0 ], leaf( n ) )
try:
    uses = ET.parse( sys.argv[ 1 ] ).getroot()
    rows = ET.parse( sys.argv[ 2 ] ).getroot().iter( "s" ) if len( sys.argv ) > 2 else []
except ( ET.ParseError, OSError ):
    sys.exit( 1 )
bound = { where( s.get( "p", "" ), s.get( "n", "" ) ) for s in rows }
for u in uses.iter( "u" ):
    if u.get( "role" ) == "call" and where( u.get( "p", "" ), u.get( "in_id", "" ) ) not in bound:
        print( u.get( "p" ) )
PY
}

# ── (a) --uses=src/graph.h:buildGraph must resolve (not refuse), narrow defs= AND the call-role sites ───
#
# §A6b UPDATE (2026-07-28): this arm used to assert count= EQUALS the bare-name count ("sites stay
# name-wide"). That was the bug, not the contract: the qualifier narrowed the LABEL and not the answer, so
# two different files' selectors returned byte-identical site sets. A call site's resolved target is
# recorded in the call graph, so the call role narrows exactly as --callers does; the roles that carry no
# resolution (read/write/import/extends) still stay name-matched, and call_sites_of_name= discloses the
# un-narrowed call total. So the assertion inverts: qualified count= must be <= the bare count.
Q_QUAL="$( uses_elem 'src/graph.h:buildGraph' )"
Q_QUAL_RC=$?
Q_BARE="$( uses_elem 'buildGraph' )"
[ -n "$Q_QUAL" ] && ok "--uses=src/graph.h:buildGraph resolves (was a false refusal pre-fix): $Q_QUAL" \
    || no "--uses=src/graph.h:buildGraph still refuses (bug not fixed)"
if [ -n "$Q_QUAL" ] && [ -n "$Q_BARE" ]; then
    CQ="$( attr "$Q_QUAL" count )"; CB="$( attr "$Q_BARE" count )"
    { [ -n "$CQ" ] && [ -n "$CB" ] && [ "$CQ" -le "$CB" ]; } \
        && ok "count= is the narrowed site set, never larger than the bare-name union: $CQ <= $CB" \
        || no "count= grew under a file: qualifier: qualified=$CQ bare=$CB"
    printf '%s' "$Q_QUAL" | grep -q 'narrowed_roles="call"' \
        && ok 'narrowed_roles="call" discloses which roles the qualifier narrowed' \
        || no "narrowed_roles= missing from a file:name selector: $Q_QUAL"
    CSN="$( attr "$Q_QUAL" call_sites_of_name )"
    [ -n "$CSN" ] && ok "call_sites_of_name= discloses the un-narrowed call total: $CSN" \
        || no "call_sites_of_name= missing from a file:name selector: $Q_QUAL"
    DQ="$( attr "$Q_QUAL" defs )"; DB="$( attr "$Q_BARE" defs )"
    [ -n "$DQ" ] && [ -n "$DB" ] && [ "$DQ" -le "$DB" ] && ok "defs= narrowed by the file qualifier: $DQ (unqualified: $DB)" \
        || no "defs= not narrowed: qualified=$DQ bare=$DB"
fi

# ── (b) an OVERLOADED name (NoteIndex::empty vs ScipOverlay::empty) — defs narrows to 1, sites stay ─────
#    the name-wide union, and the defs_of_name= disclosure attribute is present.
E_QUAL="$( uses_elem 'src/notes.h:empty' )"
E_BARE="$( uses_elem 'empty' )"
if [ -n "$E_QUAL" ] && [ -n "$E_BARE" ]; then
    EDQ="$( attr "$E_QUAL" defs )"
    [ "$EDQ" = "1" ] && ok "src/notes.h:empty narrows defs= to exactly 1 (the overload in that file)" \
        || no "src/notes.h:empty defs=$EDQ (expected exactly 1)"
    ECQ="$( attr "$E_QUAL" count )"; ECB="$( attr "$E_BARE" count )"
    { [ -n "$ECQ" ] && [ "$ECQ" -lt "$ECB" ]; } \
        && ok "src/notes.h:empty count= is a NARROWED site set, smaller than the name-wide union ($ECQ < $ECB)" \
        || no "src/notes.h:empty count=$ECQ vs unqualified empty count=$ECB — the qualifier must narrow the call sites (§A6b)"
    EDN="$( attr "$E_QUAL" defs_of_name )"
    [ -n "$EDN" ] && [ "$EDN" -gt "$EDQ" ] && ok "defs_of_name= disclosure present and larger than the narrowed defs= ($EDN > $EDQ)" \
        || no "defs_of_name= missing or not > defs= (got '${EDN:-<absent>}' vs defs=$EDQ) — overloaded-name disclosure broken"
else
    no "could not read --uses=src/notes.h:empty or --uses=empty output"
fi
# the unqualified form must NOT carry defs_of_name= (only a file: qualifier discloses it)
printf '%s' "$E_BARE" | grep -q 'defs_of_name=' && no "unqualified --uses=empty wrongly carries defs_of_name=" \
    || ok "unqualified --uses=empty carries no defs_of_name= (disclosure is qualifier-only)"

# ── (c) a genuinely-unknown file:name selector refuses honestly — no false 'no reference site' claim, ───
#    and the suggestion is a real name, not the constant srcmut_sigchange bug.
OUT="$( "$BIN" "$ROOT" --uses='src/graph.h:nosuchfn' --no-cache 2>"$TMP/err" )"; RC=$?
if [ "$RC" -eq 1 ]; then ok "--uses=src/graph.h:nosuchfn refuses (exit 1)"; else no "--uses=src/graph.h:nosuchfn exit $RC (expected 1)"; fi
grep -qi 'no reference site' "$TMP/err" && no "refusal still falsely claims 'no reference site': $( cat "$TMP/err" )" \
    || ok "refusal does not claim 'no reference site' (states only what defs.empty() proves)"
grep -q 'srcmut_sigchange' "$TMP/err" && no "the constant nonsense suggestion (srcmut_sigchange) is back: $( cat "$TMP/err" )" \
    || ok "suggestion is not the constant srcmut_sigchange bug"
# §P12.1: didYouMean() now does true bounded edit distance and honestly omits a suggestion when nothing in
# the corpus is within a few edits, instead of the old shared-prefix*4-lenDelta score that always forced
# SOME guess (pre-fix this fixture got "did you mean 'norm_rel'?" — an unrelated name, exactly the
# fabricated-confidence class the plan's §P0.5/§P5 findings call out). "nosuchfn" is not a plausible
# near-miss of anything in this corpus, so a suggestion is no longer guaranteed here — the load-bearing
# assertion is the line above (never the constant srcmut_sigchange bug). A positive "does suggest a real
# near-miss" case for the file:name selector lives in didyoumeancheck.sh's §P12.1 section
# (src/graph.h:buildGrap -> buildGraph).

# ── (d) plain name and canonical-id forms stay byte-identical to pre-fix (only file:name changed) ───────
#    NoteIndex::empty's canonical id ("path::scope::name") — a scoped method, so it actually carries "::"
#    (a scope-less free function's canonical id degrades to its bare name and can't test this branch).
#    The id is looked up live via --outline, not --expand (it embeds the corpus path exactly as invoked —
#    "." vs an absolute ROOT produce different id= strings — so it must never be hardcoded). V1 fix
#    (verifier finding 1, 2026-08-15): --expand's own exact-name default now correctly picks whichever of
#    lean-bundle/whole-file is genuinely cheaper (the bug this fix closed made whole-file win here for the
#    WRONG reason — a phantom map size — which is what let a bare --expand double as an id= lookup before).
#    Bundle mode's <b> body tag carries no id= at all, so --expand is no longer a mode-independent way to
#    fetch a canonical id; --outline always rides the classic 200-row map (no V1 lean default applies to
#    it) and its <s> rows carry id= unconditionally, so it is the stable lookup path here.
# row 6 (2026-09-12): the row prints the short id sc=; the canonical id composes as <f p=>::sc::n
CANON_ID="$( "$BIN" "$ROOT" --outline='src/notes.h:empty' --no-cache 2>/dev/null | python3 -c '
import re, sys
doc, name, scope = sys.stdin.read(), sys.argv[1], ( sys.argv[2] if len( sys.argv ) > 2 else None )
for f in re.finditer( r"<f p=\"([^\"]*)\"[^>]*>(.*?)</f>", doc, re.S ):
    for row in re.finditer( r"<[sd]\b([^>]*)>", f.group( 2 ) ):
        a = dict( re.findall( r"\s([\w:.-]+)=\"([^\"]*)\"", row.group( 1 ) ) )
        if a.get( "n" ) == name and "sc" in a and ( scope is None or a[ "sc" ] == scope ):
            print( f.group( 1 ) + "::" + a[ "sc" ] + "::" + a[ "n" ] ); sys.exit( 0 )
for row in re.finditer( r"<d\b([^>]*)>", doc ):
    a = dict( re.findall( r"\s([\w:.-]+)=\"([^\"]*)\"", row.group( 1 ) ) )
    if a.get( "n" ) == name and "sc" in a and "p" in a and ( scope is None or a[ "sc" ] == scope ):
        print( a[ "p" ] + "::" + a[ "sc" ] + "::" + a[ "n" ] ); sys.exit( 0 )
' empty NoteIndex )"
[ -n "$CANON_ID" ] || { no "could not look up NoteIndex::empty's canonical id via --outline"; CANON_ID="./src/notes.h::NoteIndex::empty"; }
BARE_A="$( uses_elem 'buildGraph' )"
BARE_B="$( uses_elem 'buildGraph' )"
if [ "$BARE_A" = "$BARE_B" ]; then ok "bare-name form is stable/reproducible: $BARE_A"; else no "bare-name form not reproducible"; fi
CANON_A="$( uses_elem "$CANON_ID" )"
if [ -n "$CANON_A" ]; then ok "canonical-id form still resolves: $CANON_A"; else no "canonical-id form stopped resolving: $CANON_ID"; fi
# FIXED (issue #164; was the KNOWN GAP for prompts/help-wanted/uses-qualified-selector.md). This arm used to call
# the zero below "documented, unchanged behaviour": the canonical id resolved defs="1", then the site scan compared
# the WHOLE spelling with reference names, which are always bare, so count="0" while --callers on the same id counts
# hundreds of callers on this repo.
# FIXED (issue #164): 1 <= count= <= the bare --uses=empty count — the narrowing arm (b) already asserts for src/notes.h:empty.
if [ -n "$CANON_A" ]; then
    CC="$( attr "$CANON_A" count )"; CBE="$( attr "$E_BARE" count )"
    if [ -n "$CC" ] && [ -n "$CBE" ] && [ "$CC" -ge 1 ] && [ "$CC" -le "$CBE" ] \
        && printf '%s' "$CANON_A" | grep -q 'narrowed_roles="call"' && [ -n "$( attr "$CANON_A" call_sites_of_name )" ]; then
        ok "(d) FIXED: the canonical id $CANON_ID answers count=\"$CC\" (bare --uses=empty: $CBE) with the narrowing disclosure"
    else
        no "(d) FIXED (issue #164): the canonical id $CANON_ID should answer 1 <= count <= ${CBE:-?} with narrowed_roles=: ${CANON_A:-no <uses> root}"
    fi
    # FIXED, same definition same rows: the canonical id against the file:name spelling arm (b) proves.
    QR="$( "$BIN" "$ROOT" --uses="$CANON_ID" --no-cache 2>/dev/null | grep -o '<u [^>]*>' | sort )"
    FR="$( "$BIN" "$ROOT" --uses='src/notes.h:empty' --no-cache 2>/dev/null | grep -o '<u [^>]*>' | sort )"
    if [ -n "$QR" ] && [ "$QR" = "$FR" ]; then
        ok "(d) FIXED: the canonical id and src/notes.h:empty list identical rows"
    else
        no "(d) FIXED (issue #164): canonical-id rows and file:name rows for one definition differ"
    fi
    # FIXED, the two verbs agree: every role="call" row sits inside a caller the --callers answer lists
    # (the relation test/declinecheck.sh's call_sites helper reads).
    "$BIN" "$ROOT" --uses="$CANON_ID" --no-cache >"$TMP/d_uses.xml" 2>/dev/null
    "$BIN" "$ROOT" --callers="$CANON_ID" --no-cache >"$TMP/d_callers.xml" 2>/dev/null
    DU="$( call_sites "$TMP/d_uses.xml" "$TMP/d_callers.xml" )"
    if [ -z "$DU" ]; then
        ok "(d) FIXED: every role=\"call\" row of the canonical-id answer sits inside a --callers-listed caller"
    else
        no "(d) FIXED (issue #164): call rows with no --callers edge: $( printf '%s' "$DU" | tr '\n' ' ' )"
    fi
fi

# ── (e) determinism — the new file:name path is deterministic run-to-run ─────────────────────────────────
"$BIN" "$ROOT" --uses='src/graph.h:buildGraph' --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$ROOT" --uses='src/graph.h:buildGraph' --no-cache >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "determinism (file:name selector, byte-identical run-to-run)" \
    || no "file:name selector is non-deterministic"

# ── xml well-formed ────────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    "$BIN" "$ROOT" --uses='src/graph.h:buildGraph' --no-cache 2>/dev/null | xmllint --noout - \
        && ok "--uses=file:name xml well-formed" || no "--uses=file:name xml malformed"
fi

# ── (f) FIXED (issue #164; was the KNOWN GAP for prompts/help-wanted/uses-qualified-selector.md) — a "::" selector's use-sites ─
# THE GAP (pre-fix). Every SYM-taking verb resolves a "::" spelling through graph.h resolveAllByNameQualified: the canonical-id
# tier (path::scope::name, the id= the map prints), then the scope tier (Scope::name, the sym= --edit-check prints).
# --callers/--callees/--impact/--expand read the call graph by NodeId after that, so the spelling no longer matters.
# --uses did not: verbs_navigate.h resolveUsesSelector set fileQualified only for a ':' with no "::" and otherwise
# kept the WHOLE spelling as siteMatchName, and collectUseSites compared that with r.calleeName, which is always a bare
# name. defs= resolved, count="0" followed, and nothing — no refusal, no call_sites_of_name= — said the zero was a
# spelling artifact rather than "no use exists". --safe-delete's uses= and --verify's uses()/unused() rode the same
# scan; the MCP uses twin (mcpverbs.h usesText) carried its own copy of the whole-spelling match.
#
# The gap arms below were KNOWN GAP arms pinning the wrong answer; each one's FIXED comment said what it asserts
# once the gap is closed, and a FAIL on one meant the gap moved. (2026-09-14: issue #164's fix flipped every gap
# arm below to its FIXED line. The premises, controls, precision and
# negative arms are byte-identical to the pre-fix file — a change that turns one red is wrong.)
#
# Every site below is a literal read off the fixture source, never derived the way the code derives it:
#   test/declinefix   cpp/pair/{one,two}.cpp share ctwin in one directory (called once, cpp/pair/user.cpp:3);
#                     Solo::conly is a unique global (cpp/caller/caller.cpp:8); ns::pick has two overloads inside
#                     namespace ns (cpp/ns_user/use.cpp:3); py/pair One::pytwin (py/pair/user.py:2); Alpha::find is
#                     shadowed by an EXTERNAL find( 3 ) (cpp/caller/caller.cpp:13); Widget::run is never called
#   test/rustqualfix  util::tool (src/lib.rs:79) and Widget::new (src/lib.rs:77, src/gadget/mod.rs:47), each call
#                     isolated in one function; Vec::<u32>::new() (src/lib.rs:91) binds nothing; Gadget::spin is never called
UQ_PROMPT="prompts/help-wanted/uses-qualified-selector.md"
fx(){ local d="$ROOT/test/$1"; shift; ( cd "$d" && "$BIN" . --no-cache "$@" 2>/dev/null </dev/null ); }   # every selector is fixture-relative
tag_of(){ printf '%s' "$1" | grep -oE "<$2( [^>]*)?>" | head -1; }
val_of(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E 's/^[^"]*"([^"]*)"$/\1/'; }
lists_site(){ printf '%s' "$1" | grep -qF "<u role=\"call\" p=\"$2\""; }   # rows QUOTE role=; the MCP legend spells <u role=call|… bare

echo "=== (f) the \"::\" selector's use-sites (issue #164, fixed) ==="
command -v python3 >/dev/null 2>&1 || no "(f) python3 is required by the MCP arms below — they would read nothing"

# fixture | "::" selector | bare name | the call site a FIXED --uses lists | --callers= count (premise) | shape
# FIXED (every row): rc=0, lists the site (role="call"), 1 <= count= <= the bare-name count, and the answer discloses
# what narrowed the way a file:name selector does (narrowed_roles= / call_sites_of_name=). Narrowing is per enclosing
# symbol (usesChosenCallers), so Widget::new's fixed answer also carries src/gadget/mod.rs:48 — a Gadget::new() call
# inside a caller that ALSO calls Widget::new. That is the file:name rule's own granularity, not this gap.
while IFS='|' read -r fix sel bare site ncall shape; do
    [ -z "$fix" ] && continue
    fx "$fix" --callers="$sel" >"$TMP/callers.xml" 2>/dev/null
    CR="$( tag_of "$( cat "$TMP/callers.xml" )" callers )"
    [ "$( val_of "$CR" count )" = "$ncall" ] \
        && ok "(f) premise, $shape: --callers=$sel resolves and counts $ncall caller(s)" \
        || no "(f) premise, $shape: --callers=$sel should count $ncall — the fixture moved, so the arm below proves nothing: ${CR:-no <callers> root}"
    BARE="$( fx "$fix" --uses="$bare" )"
    lists_site "$BARE" "$site" \
        && ok "(f) control, $shape: the bare --uses=$bare lists $site" \
        || no "(f) control, $shape: the bare --uses=$bare no longer lists $site: $( tag_of "$BARE" uses )"
    BARE_COUNT="$( val_of "$( tag_of "$BARE" uses )" count )"
    OUT="$( fx "$fix" --uses="$sel" )"; RC=$?
    printf '%s' "$OUT" >"$TMP/uses.xml"
    U="$( tag_of "$OUT" uses )"
    C="$( val_of "$U" count )"
    # FIXED (issue #164): the narrowed answer — rc=0, the site listed, 1 <= count <= the bare-name union,
    # and the qualifier disclosure a file:name selector carries.
    if [ "$RC" = 0 ] && [ -n "$U" ] && lists_site "$OUT" "$site" && [ -n "$C" ] && [ -n "$BARE_COUNT" ] \
        && [ "$C" -ge 1 ] && [ "$C" -le "$BARE_COUNT" ] \
        && printf '%s' "$U" | grep -q 'narrowed_roles="call"' && [ -n "$( val_of "$U" call_sites_of_name )" ] \
        && [ -n "$( val_of "$U" defs_of_name )" ]; then
        ok "(f) FIXED, $shape: --uses=$sel lists $site at count=$C (bare: $BARE_COUNT) with the narrowing disclosure"
    else
        no "(f) FIXED ($UQ_PROMPT), $shape: --uses=$sel should list $site with 1 <= count <= ${BARE_COUNT:-?} plus narrowed_roles=/call_sites_of_name=: rc=$RC ${U:-no <uses> root}"
    fi
    # FIXED, the two verbs agree: every role="call" row sits inside a caller the --callers answer lists.
    UNACC="$( call_sites "$TMP/uses.xml" "$TMP/callers.xml" )"
    if [ -z "$UNACC" ]; then
        ok "(f) FIXED, $shape: every role=\"call\" row sits inside a --callers-listed caller"
    else
        no "(f) FIXED ($UQ_PROMPT), $shape: call rows with no --callers edge: $( printf '%s' "$UNACC" | tr '\n' ' ' )"
    fi
done <<'EOF'
declinefix|cpp/pair/one.cpp::One::ctwin|ctwin|cpp/pair/user.cpp:3|1|C++ canonical id
declinefix|One::ctwin|ctwin|cpp/pair/user.cpp:3|1|C++ Class::method without a file
declinefix|Solo::conly|conly|cpp/caller/caller.cpp:8|1|C++ Class::method on a unique global
declinefix|ns::pick|pick|cpp/ns_user/use.cpp:3|1|C++ namespace-qualified function
declinefix|One::pytwin|pytwin|py/pair/user.py:2|1|Python Class::method
rustqualfix|util::tool|tool|src/lib.rs:79|1|Rust mod::fn
rustqualfix|Widget::new|new|src/gadget/mod.rs:47|2|Rust Type::assoc
EOF

# the pointer --callers hands the reader. On a bound call next= is --uses on the SAME selector (the next-uses-bare-name
# prompt changes next= only on answers with declined_calls, and this ctwin call is bound), so run verbatim it lands on
# the fixed answer. FIXED: that pointer, run verbatim, lists cpp/pair/user.cpp:3 at count="1" with the disclosure.
CR="$( tag_of "$( fx declinefix --callers=cpp/pair/one.cpp::One::ctwin )" callers )"
NEXT="$( val_of "$CR" next )"
[ "$NEXT" = "--uses=cpp/pair/one.cpp::One::ctwin" ] && [ "$( val_of "$CR" count )" = 1 ] \
    && ok "(f) premise: --callers=cpp/pair/one.cpp::One::ctwin counts 1 caller and carries next=\"$NEXT\"" \
    || no "(f) premise: --callers=cpp/pair/one.cpp::One::ctwin should count 1 with next=\"--uses=\" on the same selector: ${CR:-no <callers> root}"
: >"$TMP/next.xml"
case "$NEXT" in --uses=*) fx declinefix "$NEXT" >"$TMP/next.xml" ;; esac
NOUT="$( cat "$TMP/next.xml" )"
NU="$( tag_of "$NOUT" uses )"
if lists_site "$NOUT" cpp/pair/user.cpp:3 && [ "$( val_of "$NU" count )" = 1 ] && [ -n "$( val_of "$NU" call_sites_of_name )" ]; then
    ok "(f) FIXED: the callers answer's own next=, run verbatim, lists cpp/pair/user.cpp:3 with the narrowing disclosure"
else
    no "(f) FIXED ($UQ_PROMPT): next=\"${NEXT:-absent}\" run verbatim should list cpp/pair/user.cpp:3 at count=\"1\": ${NU:-no <uses> root}"
fi
# control: the file:name spelling of the SAME definition already lands — the contrast that makes the "::" zero a bug
OUT="$( fx declinefix --uses=cpp/pair/one.cpp:ctwin )"
lists_site "$OUT" cpp/pair/user.cpp:3 && [ "$( val_of "$( tag_of "$OUT" uses )" call_sites_of_name )" = 1 ] \
    && ok "(f) control: --uses=cpp/pair/one.cpp:ctwin (file:name, the same definition) lists cpp/pair/user.cpp:3 with call_sites_of_name=\"1\"" \
    || no "(f) control: --uses=cpp/pair/one.cpp:ctwin stopped listing cpp/pair/user.cpp:3: $( tag_of "$OUT" uses )"
# FIXED, same definition same rows: the canonical id against the file:name spelling above.
QROWS="$( printf '%s' "$( fx declinefix --uses=cpp/pair/one.cpp::One::ctwin )" | grep -o '<u [^>]*>' | sort )"
FROWS="$( printf '%s' "$OUT" | grep -o '<u [^>]*>' | sort )"
if [ -n "$QROWS" ] && [ "$QROWS" = "$FROWS" ]; then
    ok "(f) FIXED: the canonical id and the file:name spelling of one definition list identical rows"
else
    no "(f) FIXED ($UQ_PROMPT): canonical-id rows and file:name rows for one definition differ"
fi

# --safe-delete's uses= rides the same scan. FIXED: --safe-delete=Solo::conly reads uses="1", the bare spelling's number.
SDB="$( tag_of "$( fx declinefix --safe-delete=conly )" safe-delete )"
SDQ="$( tag_of "$( fx declinefix --safe-delete=Solo::conly )" safe-delete )"
[ "$( val_of "$SDB" uses )" = 1 ] && ok "(f) control: --safe-delete=conly reads uses=\"1\"" \
    || no "(f) control: --safe-delete=conly should read uses=\"1\": ${SDB:-no <safe-delete> root}"
if [ "$( val_of "$SDQ" uses )" = 1 ] && [ "$( val_of "$SDQ" callers )" = 1 ]; then
    ok "(f) FIXED: --safe-delete=Solo::conly reads uses=\"1\" beside callers=\"1\""
else
    no "(f) FIXED ($UQ_PROMPT): --safe-delete=Solo::conly should read uses=\"1\" callers=\"1\": ${SDQ:-no <safe-delete> root}"
fi

# --verify's uses()/unused() claims read the same scan. FIXED: uses(Solo::conly) is verdict="confirmed" count="1".
VB="$( tag_of "$( fx declinefix --verify='uses(conly)' )" verify )"
VQ="$( tag_of "$( fx declinefix --verify='uses(Solo::conly)' )" verify )"
[ "$( val_of "$VB" verdict )" = confirmed ] && ok "(f) control: --verify=\"uses(conly)\" is confirmed" \
    || no "(f) control: --verify=\"uses(conly)\" should be confirmed: ${VB:-no <verify> root}"
if [ "$( val_of "$VQ" verdict )" = confirmed ] && [ "$( val_of "$VQ" count )" = 1 ]; then
    ok "(f) FIXED: --verify=\"uses(Solo::conly)\" is confirmed on count=\"1\""
else
    no "(f) FIXED ($UQ_PROMPT): --verify=\"uses(Solo::conly)\" should be confirmed count=\"1\": ${VQ:-no <verify> root}"
fi

# the MCP uses twin kept its OWN copy of the whole-spelling match (mcpverbs.h usesText) — JSON-RPC over stdio, as a
# client speaks it. FIXED (issue #164, the plan's option b): a resolving "::" spelling refuses as CLI-only, naming
# the bare-name retry and the CLI form — never a silent count="0".
mcp_uses(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"uses\",\"arguments\":{\"path\":\"$ROOT/test/declinefix\",\"symbol\":\"$1\"}}}" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load( sys.stdin )
print( "__ERROR__:" + r[ "error" ].get( "message", "" ) if "error" in r else r[ "result" ][ "content" ][ 0 ][ "text" ] )
' 2>/dev/null
}
MB="$( mcp_uses ctwin )"
lists_site "$MB" cpp/pair/user.cpp:3 && ok "(f) control: MCP uses symbol=\"ctwin\" lists cpp/pair/user.cpp:3" \
    || no "(f) control: MCP uses symbol=\"ctwin\" should list cpp/pair/user.cpp:3: $( printf '%s' "$MB" | head -c 240 )"
MQ="$( mcp_uses One::ctwin )"
if printf '%s' "$MQ" | grep -q '^__ERROR__:' && printf '%s' "$MQ" | grep -q 'CLI-only' \
    && printf '%s' "$MQ" | grep -q "bare name 'ctwin'" && printf '%s' "$MQ" | grep -q -- '--uses=One::ctwin'; then
    ok "(f) FIXED: MCP uses symbol=\"One::ctwin\" refuses as CLI-only, naming the bare-name retry and the CLI form"
else
    no "(f) FIXED ($UQ_PROMPT): MCP uses symbol=\"One::ctwin\" should refuse as CLI-only with the retry: $( printf '%s' "$MQ" | head -c 240 )"
fi

# precision controls — the naive fix (strip the scope, then name-match the bare half) turns these red. Today they pass
# only because the gap answers nothing; after the fix they must still pass, because a call site is kept only where its
# enclosing symbol has a resolved edge to the chosen definition (usesChosenCallers, the file:name rule):
#   Alpha::find   the only find call, cpp/caller/caller.cpp:13, is EXTERNAL (no edge to Alpha::find) — the file:name
#                 spelling cpp/alpha/alpha.cpp:find already answers count="0" call_sites_of_name="1"
#   Widget::new   external_caller's Vec::<u32>::new() at src/lib.rs:91 binds nothing, so it is never a Widget::new row
while IFS='|' read -r fix sel bare site; do
    [ -z "$fix" ] && continue
    lists_site "$( fx "$fix" --uses="$bare" )" "$site" \
        && ok "(f) precision premise: the bare --uses=$bare on test/$fix lists $site" \
        || no "(f) precision premise: the bare --uses=$bare on test/$fix no longer lists $site — the control below proves nothing"
    lists_site "$( fx "$fix" --uses="$sel" )" "$site" \
        && no "(f) precision control: --uses=$sel lists $site, a call that never resolves to $sel — the scope was stripped, not narrowed" \
        || ok "(f) precision control: --uses=$sel does not list $site (same name, resolves elsewhere)"
done <<'EOF'
declinefix|Alpha::find|find|cpp/caller/caller.cpp:13
rustqualfix|Widget::new|new|src/lib.rs:91
EOF
U="$( tag_of "$( fx declinefix --uses=cpp/alpha/alpha.cpp:find )" uses )"
[ "$( val_of "$U" count )" = 0 ] && [ "$( val_of "$U" call_sites_of_name )" = 1 ] \
    && ok "(f) control: --uses=cpp/alpha/alpha.cpp:find answers count=\"0\" call_sites_of_name=\"1\" — the shape a fixed Alpha::find agrees with" \
    || no "(f) control: --uses=cpp/alpha/alpha.cpp:find should answer count=\"0\" call_sites_of_name=\"1\": ${U:-no <uses> root}"

# negative controls — nothing anywhere calls these names, so the answer is rc=0 count="0" before AND after the fix. A
# fix that lists a row here invented a use; a fix that refuses here confused "unused" with "unknown".
for spec in "declinefix Widget::run" "rustqualfix Gadget::spin"; do
    set -- $spec
    OUT="$( fx "$1" --uses="$2" )"; RC=$?
    U="$( tag_of "$OUT" uses )"
    [ "$RC" = 0 ] && [ "$( val_of "$U" count )" = 0 ] && ! printf '%s' "$OUT" | grep -qE '<u role="[a-z]+" p="' \
        && ok "(f) negative control: --uses=$2 on test/$1, a definition nothing calls, answers count=\"0\"" \
        || no "(f) negative control: --uses=$2 on test/$1 should answer rc=0 count=\"0\": rc=$RC ${U:-no <uses> root}"
done

# control: a WRONG scope still refuses — the scope tier never falls back to the bare-name union, and neither may the fix
OUT="$( fx declinefix --uses=Nope::ctwin )"; RC=$?
[ "$RC" = 1 ] && [ -z "$OUT" ] && ok "(f) control: --uses=Nope::ctwin refuses (exit 1, nothing on stdout)" \
    || no "(f) control: --uses=Nope::ctwin exit $RC — a wrong scope must refuse, never answer the bare-name union"

# determinism and well-formedness on a "::" selector
fx declinefix --uses=cpp/pair/one.cpp::One::ctwin >"$TMP/q1"
fx declinefix --uses=cpp/pair/one.cpp::One::ctwin >"$TMP/q2"
[ -s "$TMP/q1" ] && cmp -s "$TMP/q1" "$TMP/q2" && ok "(f) determinism: --uses on a canonical id is byte-identical run to run" \
    || no "(f) determinism: --uses=cpp/pair/one.cpp::One::ctwin differs between two runs, or printed nothing"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/q1" 2>/dev/null && ok "(f) --uses on a canonical id is well-formed XML" \
        || no "(f) --uses=cpp/pair/one.cpp::One::ctwin is malformed XML"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
