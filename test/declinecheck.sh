#!/usr/bin/env bash
# declinecheck.sh — the TIER-3 DECLINE is disclosed, and every call reference ends in exactly one disposition.
#
#   test/declinecheck.sh                          # uses build/ripwire on test/declinefix
#   RIPWIRE_BIN=asan/ripwire test/declinecheck.sh
#   test/declinecheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE DEFECT. buildGraph's name-based ladder ends in tier 3, "a UNIQUE global, else DROP". A call whose candidates
# are two or more same-language definitions, none in the caller's file or directory, and which neither a qualifier
# (`canonical`) nor a receiver/include rule (`narrowed`) pinned, left the resolve loop through `continue`: no edge,
# no amb=, and no header gauge moved. `--callers` on either definition then answered count="0" beside ambiguous=0
# unresolved=0 — a zero that read as "none exists" about a call the resolver had SEEN and declined to guess at. On
# the default map that silence covered 22.4% of memgraph's call references, 8.6% of retrofit's and 5.4% of this
# repo's own (measured at 5c808487). CLAUDE.md non-negotiable #3: a zero means "none found".
#
# THE FIX IS DISCLOSURE, NOT RESOLUTION. The precision rule stands (never guess among cross-directory same-named
# definitions) and the edge set is unchanged — arm (C) pins the pre-change binary's own numbers. What changed is
# that the refusal is COUNTED and VISIBLE:
#   header declined=N (JSON "declined")        calls tier 3 declined; absent when 0
#   --callers declined_calls="K"               declined calls that could have meant SYM — K CALLS, never call x def
#   --callees declined_calls="K"               declined calls SYM itself makes
#   --impact  declined_calls="K"               declined calls that could have reached SYM or a symbol in its radius
#   the MCP twins (find_referencing_symbols, find_symbol, impact) carry the same key
#
# THE CONSERVATION LINE, arm (F). --pin-census ends with `# dispositions calls=N bound=… unaccounted=K`: every call
# reference the resolver considers is counted in exactly one bucket when its resolve-loop iteration ENDS, so a
# `continue` that names no disposition lands in `unaccounted`. The dispositions must sum to calls=, unaccounted must
# be 0, and three buckets are re-derived from other surfaces (the header gauges, the census decision rows). A future
# silent `continue` in any language the fixture reaches turns this gate red.
#
# THE FIXTURE (test/declinefix/). Each language puts one same-named method in a/ (alpha/) and one in b/ (beta/) and
# calls it through an untyped receiver from a third directory — the shape no rule can pin.
#   (A) java, cpp, py, rust   the decline: --callees on the caller and --callers on BOTH definitions read
#                             count="0" declined_calls="1"; the bare name (defs="2") still counts ONE call
#   (B) the other 13 code languages (ts js go swift objc bash ruby csharp c php lua elixir dart): the same decline
#   (C) controls, each one census decision row, exactly as the pre-change binary emitted it:
#       same-directory duplicates -> split (Java, C++, Python); a unique global -> unique (Java, C++, Python);
#       a Rule-1 `narrowed` rescue (Widget::run -> step, flags r); a `canonical` rescue (ns::pick, flags q);
#       an external name -> external (C++ find, Python sum); header edges=13 ambiguous=5 unresolved=1 external=2
#   (D) header declined=17, legend-defined, JSON twin; both ABSENT on a one-directory corpus (test/lpinfix)
#   (E) the three answers in XML / --json / --format=columnar and the MCP twins; each legend defines the key it
#       emits, and an answer with nothing declined carries neither the key nor its clause; the callers answer's next=
#       LANDS: --uses=NAME lists each declined site's file:line, and the call sites no caller row encloses number
#       exactly declined_calls (1 on the four arm-A names, 0 on three bound controls); narrowed file:name,
#       line-seed, canonical and scope spellings hand over the bare name, with CLI/MCP parity and an honest legend
#   (F) conservation: the dispositions sum to calls=, unaccounted=0, census declined/external/unresolved == the
#       header's, bound == the non-external decision rows; every exit the fixture is built to reach is reached;
#       a two-root run reaches other_root and conserves too; and test/stdqualfix, where the std:: guard refuses
#       std::move sites through vetoExternal, conserves with each refusal counted external, never unaccounted
#   (G) the predicates can fail (a line that does not sum, unaccounted=1, a bare zero, a header without declined=,
#       a uses answer that drops the declined site, a next= that incorrectly retains the narrowed selector)
#   (H) determinism x2 (map and census), xmllint, no degrade alert on stderr
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
CORPUS="$ROOT/test/declinefix"
CLEAN="$ROOT/test/lpinfix"                           # one directory: no call can reach tier 3
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "declinecheck: BIN=$BIN  CORPUS=$CORPUS"

cd "$CORPUS" || exit 2                               # every file:name selector below is relative to the root `.`
rw(){ "$BIN" . --no-cache "$@" 2>/dev/null; }

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────────
root_tag(){ grep -oE "<$2( [^>]*)?>" "$1" | head -1; }                               # first <TAG …> start tag
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E 's/^[^"]*"([^"]*)"$/\1/'; }
stats(){ grep -oE '<!-- files=[^>]*-->' "$1" | head -1; }                             # the map's STATS comment only
gauge(){ printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | grep -oE '[0-9]+$'; }   # "" when absent
disp_in(){ grep -m1 '^# dispositions ' "$1" | grep -oE " $2=[0-9]+" | head -1 | grep -oE '[0-9]+$'; }
# the census decision row for (caller id, callee): "mech<TAB>flags<TAB>targets"
crow(){ awk -F'\t' -v c="$1" -v n="$2" '$1=="C" && index($6, c"#")==1 && $7==n {print $2 "\t" $5 "\t" $8; exit}' "$TMP/c.tsv"; }
# the leading run of comments — the legend the reader meets first (legendcoveragecheck's own reading)
legend_of(){ python3 - "$1" <<'PY'
import re, sys
t = open( sys.argv[1] ).read()
m = re.match( r"(\s*<!--.*?-->)+", t, re.S )
print( m.group( 0 ) if m else "" )
PY
}
# conservation predicate: calls= equals the sum of every other bucket, and unaccounted= is present and 0
conserves(){ python3 - "$1" <<'PY'
import re, sys
kv = dict( ( k, int( v ) ) for k, v in re.findall( r"(\w+)=(\d+)", sys.argv[1] ) )
calls = kv.pop( "calls", None )
sys.exit( 0 if calls is not None and "unaccounted" in kv and kv[ "unaccounted" ] == 0 and sum( kv.values() ) == calls else 1 )
PY
}
# the role="call" sites (p=file:line) a uses answer lists, one per line; given a callers answer as well, only the sites whose
# enclosing symbol (file + leaf of in_id) is none of its rows — the calls that answer holds no edge for. Nothing on a
# document that does not parse (an empty or failed run lists no site).
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

"$BIN" . --no-cache --pin-census="$TMP/c.tsv" >"$TMP/map.xml" 2>"$TMP/err" || { no "the map run exited non-zero"; sed 's/^/          /' "$TMP/err"; }
HDR="$( stats "$TMP/map.xml" )"

# ── (A) the decline, disclosed where the zero is read ─────────────────────────────────────────────────────────
echo "=== (A) the decline is disclosed where the zero is read — Java, C++, Python, Rust ==="
# lang | caller id (census) | caller name | callee name | definition 1 | definition 2
while IFS='|' read -r lang cid caller name def1 def2; do
    [ -z "$lang" ] && continue
    rw --callees="$caller" >"$TMP/callees.xml"
    R="$( root_tag "$TMP/callees.xml" callees )"
    [ "$( attr "$R" count )" = 0 ] && [ "$( attr "$R" declined_calls )" = 1 ] \
        && ok "(A) $lang: --callees=$caller count=\"0\" declined_calls=\"1\"" \
        || no "(A) $lang: --callees=$caller should read count=\"0\" declined_calls=\"1\": ${R:-no <callees> root}"
    for def in "$def1" "$def2"; do
        rw --callers="$def" >"$TMP/callers.xml"
        R="$( root_tag "$TMP/callers.xml" callers )"
        [ "$( attr "$R" count )" = 0 ] && [ "$( attr "$R" declined_calls )" = 1 ] \
            && ok "(A) $lang: --callers=$def count=\"0\" declined_calls=\"1\" — the zero says a call was declined" \
            || no "(A) $lang: --callers=$def is a bare zero: ${R:-no <callers> root}"
    done
    # the bare name unions both definitions; the ONE declined call is one call, not one per definition
    rw --callers="$name" >"$TMP/callers.xml"
    R="$( root_tag "$TMP/callers.xml" callers )"
    [ "$( attr "$R" defs )" = 2 ] && [ "$( attr "$R" declined_calls )" = 1 ] \
        && ok "(A) $lang: --callers=$name (defs=\"2\") counts the declined call once" \
        || no "(A) $lang: --callers=$name should read defs=\"2\" declined_calls=\"1\": ${R:-no <callers> root}"
    [ -z "$( crow "$cid" "$name" )" ] \
        && ok "(A) $lang: still no decision row for $caller -> $name (no edge was added)" \
        || no "(A) $lang: $caller -> $name now has a decision row — the fix changed which edges exist: $( crow "$cid" "$name" )"
done <<'EOF'
java|java/caller/JavaCaller.java::javaDeclined|javaDeclined|jbody|java/alpha/Alpha.java:jbody|java/beta/Beta.java:jbody
cpp|cpp/caller/caller.cpp::cppDeclined|cppDeclined|crender|cpp/alpha/alpha.cpp:crender|cpp/beta/beta.cpp:crender
py|py/caller/caller.py::py_declined|py_declined|pyfetch|py/alpha/alpha.py:pyfetch|py/beta/beta.py:pyfetch
rust|rust/caller/caller.rs::rust_declined|rust_declined|rfetch|rust/alpha/alpha.rs:rfetch|rust/beta/beta.rs:rfetch
EOF

# ── (B) the ladder is language-agnostic ───────────────────────────────────────────────────────────────────────
echo "=== (B) the same decline in every other code language ==="
for pair in ts:tsDeclined js:jsDeclined go:GoDeclined swift:swiftDeclined objc:objcDeclined bash:bash_declined \
            ruby:ruby_declined csharp:CsDeclined c:c_declined php:phpDeclined lua:lua_declined elixir:ex_declined dart:dartDeclined; do
    lang="${pair%%:*}"; caller="${pair#*:}"
    rw --callees="$caller" >"$TMP/sweep.xml"
    R="$( root_tag "$TMP/sweep.xml" callees )"
    [ "$( attr "$R" count )" = 0 ] && [ "$( attr "$R" declined_calls )" = 1 ] \
        && ok "(B) $lang: --callees=$caller count=\"0\" declined_calls=\"1\"" \
        || no "(B) $lang: --callees=$caller should read count=\"0\" declined_calls=\"1\": ${R:-no <callees> root}"
done

# ── (C) controls: every shape that is NOT a decline resolves exactly as the pre-change binary resolved it ─────
echo "=== (C) controls — resolution unchanged ==="
# label | caller id | callee | mech | flags | target count
while IFS='|' read -r label cid name mech flags want; do
    [ -z "$label" ] && continue
    ROW="$( crow "$cid" "$name" )"
    GOT_M="$( printf '%s' "$ROW" | cut -f1 )"
    GOT_F="$( printf '%s' "$ROW" | cut -f2 )"
    GOT_N="$( printf '%s' "$ROW" | cut -f3 | awk -F'|' '{ print ( $0 == "" ? 0 : NF ) }' )"
    [ -n "$ROW" ] && [ "$GOT_M" = "$mech" ] && [ "$GOT_F" = "$flags" ] && [ "$GOT_N" = "$want" ] \
        && ok "(C) $label: $name -> $mech flags=$flags targets=$want" \
        || no "(C) $label: $name expected $mech/$flags/$want, census row: '${ROW:-none}'"
done <<'EOF'
same-dir split, Java|java/pair/PairUser.java::javaSplit|jtwin|split|-|2
same-dir split, C++|cpp/pair/user.cpp::cppSplit|ctwin|split|-|2
same-dir split, Python|py/pair/user.py::py_split|pytwin|split|-|2
unique global, Java|java/caller/JavaCaller.java::javaUnique|jonly|unique|-|1
unique global, C++|cpp/caller/caller.cpp::cppUnique|conly|unique|-|1
unique global, Python|py/caller/caller.py::py_unique|pyonly|unique|-|1
narrowed rescue, C++ Rule 1|cpp/widget_run/run.cpp::Widget::run|step|split|r|2
canonical rescue, C++ ns::|cpp/ns_user/use.cpp::cppCanonical|pick|split|q|2
external name, C++|cpp/caller/caller.cpp::cppExternal|find|external|-|0
external name, Python|py/caller/caller.py::py_external|sum|external|-|0
EOF
rw --callees=javaSplit >"$TMP/split.xml"
R="$( root_tag "$TMP/split.xml" callees )"
[ "$( attr "$R" count )" = 2 ] && [ -z "$( attr "$R" declined_calls )" ] \
    && ok "(C) a same-directory split is an edge pair, never a decline: --callees=javaSplit count=\"2\", no declined_calls=" \
    || no "(C) --callees=javaSplit: $R"
for pin in "edges 13" "ambiguous 5" "unresolved 1" "external 2"; do
    set -- $pin
    [ "$( gauge "$HDR" "$1" )" = "$2" ] && ok "(C) header $1=$2, the pre-change binary's own number" \
        || no "(C) header $1=$( gauge "$HDR" "$1" ) — the pre-change binary emits $1=$2 on this fixture"
done

# ── (D) the header gauge ──────────────────────────────────────────────────────────────────────────────────────
echo "=== (D) header declined= counts every declined call, is defined, and is silent at zero ==="
[ "$( gauge "$HDR" declined )" = 17 ] && ok "(D) header declined=17 (4 in arm A + 13 in arm B)" \
    || no "(D) header declined= is not 17: $( printf '%s' "$HDR" | grep -oE ' declined=[0-9]+' || echo absent )"
legend_of "$TMP/map.xml" | grep -q 'hdr:declined=' && ok "(D) the map legend defines hdr:declined=" \
    || no "(D) the map legend does not define hdr:declined="
"$BIN" "$CLEAN" --no-cache >"$TMP/clean.xml" 2>/dev/null
[ -n "$( stats "$TMP/clean.xml" )" ] || no "(D) premise: no stats comment from $CLEAN"
stats "$TMP/clean.xml" | grep -q ' declined=' \
    && no "(D) declined= present on a one-directory corpus, where no call can reach tier 3" \
    || ok "(D) declined= absent where nothing was declined (test/lpinfix)"
rw --json >"$TMP/map.json"
grep -q '"declined":17,' "$TMP/map.json" && ok '(D) --json header carries "declined":17' \
    || no "(D) --json declined gauge missing or wrong: $( grep -oE '"declined":[0-9]+' "$TMP/map.json" || echo absent )"
"$BIN" "$CLEAN" --json --no-cache >"$TMP/clean.json" 2>/dev/null
grep -q '"declined"' "$TMP/clean.json" && no '(D) "declined" present in --json on a decline-free corpus' \
    || ok '(D) "declined" absent from --json on a decline-free corpus'

# ── (E) the answers, every dialect ────────────────────────────────────────────────────────────────────────────
echo "=== (E) callers / callees / impact carry declined_calls= in every dialect, defined where emitted; next= lands on the site ==="
DEF=java/alpha/Alpha.java:jbody
for spec in "callers $DEF" "callees javaDeclined" "impact $DEF"; do
    set -- $spec
    verb="$1"; sel="$2"
    rw --"$verb"="$sel" >"$TMP/$verb.xml"
    R="$( root_tag "$TMP/$verb.xml" "$verb" )"
    [ "$( attr "$R" declined_calls )" = 1 ] && ok "(E) --$verb=$sel XML root declined_calls=\"1\"" \
        || no "(E) --$verb=$sel XML root: ${R:-no <$verb> root}"
    legend_of "$TMP/$verb.xml" | grep -q 'declined_calls=' && ok "(E) --$verb legend defines declined_calls=" \
        || no "(E) --$verb legend never defines declined_calls="
    rw --"$verb"="$sel" --json >"$TMP/$verb.json"
    grep -q '"declined_calls":1[,}]' "$TMP/$verb.json" && ok "(E) --$verb --json carries \"declined_calls\":1" \
        || no "(E) --$verb --json: $( head -c 240 "$TMP/$verb.json" )"
    rw --"$verb"="$sel" --format=columnar >"$TMP/$verb.col"
    R="$( root_tag "$TMP/$verb.col" "$verb" )"
    [ "$( attr "$R" declined_calls )" = 1 ] && ok "(E) --$verb --format=columnar root declined_calls=\"1\"" \
        || no "(E) --$verb columnar root: ${R:-no <$verb> root}"
done
# next= must LAND. A declined call has no edge, so no caller row can hold it; the reader is sent to the uses verb, which
# lists call SITES by name. On each name: (a) the callers answer's next= is --uses=NAME; (b) that pointer, run verbatim,
# lists the declined site's own file:line; (c) the role="call" sites no callers row encloses number exactly declined_calls
# — 1 on the arm-A names, 0 (the key absent) on the bound controls, whose one site sits inside the caller they list.
# (c) is an equality on THIS fixture, not an identity: an unbound site can end in another disposition (unresolved, a
# same-named call from another language; self; qualified_external), and a declined site inside a caller that also binds
# the name hides behind that caller's row. Each name below has one call site in the fixture and none of those shapes, so
# a declined site the uses verb drops, or an unbound site that is not counted declined, breaks the equality.
# name | the declined site (- for a bound control) | declined_calls
while IFS='|' read -r name site want; do
    [ -z "$name" ] && continue
    rw --callers="$name" >"$TMP/nxcallers.xml"
    R="$( root_tag "$TMP/nxcallers.xml" callers )"
    NEXT="$( attr "$R" next )"; K="$( attr "$R" declined_calls )"
    [ "$NEXT" = "--uses=$name" ] && ok "(E) --callers=$name next=\"--uses=$name\"" \
        || no "(E) --callers=$name next= should name --uses=$name: ${R:-no <callers> root}"
    : >"$TMP/nxuses.xml"
    case "$NEXT" in --uses=*) rw "$NEXT" >"$TMP/nxuses.xml" ;; esac
    U="$( root_tag "$TMP/nxuses.xml" uses )"
    if [ "$site" != - ]; then
        call_sites "$TMP/nxuses.xml" | grep -qxF "$site" && ok "(E) $NEXT lists the declined site $site" \
            || no "(E) ${NEXT:-the next= pointer} does not list the declined site $site: ${U:-no <uses> root}"
    fi
    GOT="$( call_sites "$TMP/nxuses.xml" "$TMP/nxcallers.xml" | wc -l | tr -d ' ' )"
    [ -n "$U" ] && [ "${K:-0}" = "$want" ] && [ "$GOT" = "$want" ] \
        && ok "(E) $name: $GOT call site(s) outside every caller row == declined_calls=${K:-absent}" \
        || no "(E) $name: $GOT call site(s) outside every caller row, declined_calls=${K:-absent}, expected $want of each"
done <<'EOF'
jbody|java/caller/JavaCaller.java:7|1
crender|cpp/caller/caller.cpp:3|1
pyfetch|py/caller/caller.py:2|1
rfetch|rust/caller/caller.rs:3|1
jtwin|-|0
ctwin|-|0
pytwin|-|0
EOF
# The narrowed callers pointer must land on the actual declined site, not just disclose arithmetic.
# One table drives CLI and MCP; retain the Python/Rust coverage added by the original work.
narrowed_cases(){ cat <<'CASES'
java/alpha/Alpha.java:jbody|jbody|java/caller/JavaCaller.java:7
@java/alpha/Alpha.java:5|jbody|java/caller/JavaCaller.java:7
cpp/alpha/alpha.cpp:crender|crender|cpp/caller/caller.cpp:3
cpp/alpha/alpha.cpp::Alpha::crender|crender|cpp/caller/caller.cpp:3
Alpha::crender|crender|cpp/caller/caller.cpp:3
py/alpha/alpha.py:pyfetch|pyfetch|py/caller/caller.py:2
rust/alpha/alpha.rs:rfetch|rfetch|rust/caller/caller.rs:3
CASES
}
is_bare_next(){ [ "$( attr "$1" next )" = "--uses=$2" ]; }
while IFS='|' read -r wanted_selector want site; do
    rw --callers="$wanted_selector" >"$TMP/nxcallers.xml"
    R="$( root_tag "$TMP/nxcallers.xml" callers )"
    NEXT="$( attr "$R" next )"; K="$( attr "$R" declined_calls )"
    [ "$K" = 1 ] && is_bare_next "$R" "$want" \
        && ok "(E) --callers=$wanted_selector next=\"$NEXT\" is the bare name with one declined call" \
        || no "(E) --callers=$wanted_selector expected --uses=$want and declined_calls=1: ${R:-no root}"
    : >"$TMP/nxuses.xml"
    case "$NEXT" in --uses=*) rw "$NEXT" >"$TMP/nxuses.xml" ;; esac
    call_sites "$TMP/nxuses.xml" | grep -qxF "$site" \
        && ok "(E) --callers=$wanted_selector next= actually lists $site" \
        || no "(E) --callers=$wanted_selector next= does not list $site"
    rw --callers="$wanted_selector" --format=columnar >"$TMP/nxcolumnar.xml"
    C="$( root_tag "$TMP/nxcolumnar.xml" callers )"
    [ -n "$NEXT" ] && [ "$( attr "$C" next )" = "$NEXT" ] \
        && ok "(E) --callers=$wanted_selector XML and columnar next= agree" \
        || no "(E) --callers=$wanted_selector columnar next= differs"
    L="$( legend_of "$TMP/nxcallers.xml" )"
    printf '%s' "$L" | grep -qF 'follow-up (the uses verb on the called name' \
        && ! printf '%s' "$L" | grep -qF 'the uses verb on this selector' \
        && ok "(E) --callers=$wanted_selector legend defines the emitted bare-name pointer" \
        || no "(E) --callers=$wanted_selector legend still describes the wrong selector"
done < <( narrowed_cases )
# Both unchanged populations retain the original selector legend and pointer.
for sel in java/solo/Solo.java:jonly jbody; do
    rw --callers="$sel" >"$TMP/control.xml"
    R="$( root_tag "$TMP/control.xml" callers )"
    [ "$( attr "$R" next )" = "--uses=$sel" ] \
        && legend_of "$TMP/control.xml" | grep -qF 'the uses verb on this selector: the call sites' \
        && ok "(E) --callers=$sel keeps its original pointer and legend" \
        || no "(E) --callers=$sel changed its pointer or legend"
done
# omit-at-zero: an answer with nothing declined carries neither the key nor the clause
for spec in "callers java/solo/Solo.java:jonly" "callees javaUnique" "impact java/solo/Solo.java:jonly"; do
    set -- $spec
    verb="$1"; sel="$2"
    rw --"$verb"="$sel" >"$TMP/zero.xml"
    R="$( root_tag "$TMP/zero.xml" "$verb" )"
    [ -n "$R" ] && [ -z "$( attr "$R" declined_calls )" ] && ok "(E) --$verb=$sel: nothing declined, no declined_calls=" \
        || no "(E) --$verb=$sel carries declined_calls= with nothing declined (or no root): ${R:-none}"
    legend_of "$TMP/zero.xml" | grep -q 'declined_calls=' \
        && no "(E) --$verb=$sel legend defines declined_calls= on an answer that does not carry it" \
        || ok "(E) --$verb=$sel legend carries no declined_calls= clause either"
done
# the MCP twins — JSON-RPC over stdio, exactly what a client speaks
mcp_text(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load( sys.stdin )
print( "__ERROR__:" + r[ "error" ].get( "message", "" ) if "error" in r else r[ "result" ][ "content" ][ 0 ][ "text" ] )
'
}
call(){ printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }
# The very same selector table and JSON-RPC helpers verify the MCP twin.
while IFS='|' read -r wanted_selector want site; do
    M="$( mcp_text "$( call find_referencing_symbols '{"path":"'"$CORPUS"'","symbol":"'"$wanted_selector"'"}' )" )"
    printf '%s' "$M" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("next")==sys.argv[1] and d.get("declined_calls")==1 else 1)' "--uses=$want" \
        && ok "(E) MCP find_referencing_symbols $wanted_selector next= matches CLI" \
        || no "(E) MCP find_referencing_symbols $wanted_selector next= differs"
done < <( narrowed_cases )
M="$( mcp_text "$( call find_referencing_symbols '{"path":"'"$CORPUS"'","symbol":"jbody"}' )" )"
printf '%s' "$M" | grep -q '"declined_calls":1[,}]' && ok "(E) MCP find_referencing_symbols carries \"declined_calls\":1" \
    || no "(E) MCP find_referencing_symbols: $( printf '%s' "$M" | head -c 240 )"
M="$( mcp_text "$( call find_symbol '{"path":"'"$CORPUS"'","symbol":"javaDeclined"}' )" )"
printf '%s' "$M" | grep -q '"declined_calls":1[,}]' && ok "(E) MCP find_symbol (the callees direction) carries \"declined_calls\":1" \
    || no "(E) MCP find_symbol: $( printf '%s' "$M" | head -c 240 )"
M="$( mcp_text "$( call impact '{"path":"'"$CORPUS"'","symbol":"jbody","legend":"full"}' )" )"
printf '%s' "$M" | grep -oE '<impact [^>]*>' | grep -q ' declined_calls="1"' && ok "(E) MCP impact root declined_calls=\"1\"" \
    || no "(E) MCP impact: $( printf '%s' "$M" | grep -oE '<impact [^>]*>' | head -1 || echo no root )"

# ── (F) conservation ──────────────────────────────────────────────────────────────────────────────────────────
echo "=== (F) conservation — every call reference ends in exactly one disposition ==="
DL="$( grep -m1 '^# dispositions ' "$TMP/c.tsv" )"
if [ -z "$DL" ]; then
    no "(F) the census carries no '# dispositions' line — the resolver's reference total is not exposed"
else
    ok "(F) census: $DL"
    if conserves "$DL"; then ok "(F) the dispositions sum to calls= and unaccounted=0"; else no "(F) conservation broken: $DL"; fi
    for pair in "declined declined" "external external" "unresolved unresolved"; do
        set -- $pair
        [ "$( disp_in "$TMP/c.tsv" "$1" )" = "$( gauge "$HDR" "$2" )" ] \
            && ok "(F) census $1=$( disp_in "$TMP/c.tsv" "$1" ) == header $2=" \
            || no "(F) census $1=$( disp_in "$TMP/c.tsv" "$1" ) but header $2=$( gauge "$HDR" "$2" ) — two derivations disagree"
    done
    NONEXT="$( awk -F'\t' '$1=="C" && $2!="external"' "$TMP/c.tsv" | wc -l | tr -d ' ' )"
    [ "$( disp_in "$TMP/c.tsv" bound )" = "$NONEXT" ] \
        && ok "(F) bound=$NONEXT == the non-external decision rows (recorded at the emission point, not the loop's end)" \
        || no "(F) bound=$( disp_in "$TMP/c.tsv" bound ) but the census has $NONEXT non-external decision rows"
    for d in bound self external unresolved undefined qualified_external declined file_scope; do
        v="$( disp_in "$TMP/c.tsv" "$d" )"
        [ -n "$v" ] && [ "$v" -ge 1 ] && ok "(F) presence: the fixture reaches $d ($v)" \
            || no "(F) presence: $d=${v:-absent} — the fixture no longer exercises that exit, so its arm proves nothing"
    done
fi
# two roots: the caller's only same-named definition lives in the OTHER root, with no include evidence
"$BIN" java/caller java/alpha --no-cache --pin-census="$TMP/mr.tsv" >"$TMP/mr.xml" 2>/dev/null
MR="$( grep -m1 '^# dispositions ' "$TMP/mr.tsv" 2>/dev/null )"
v="$( disp_in "$TMP/mr.tsv" other_root 2>/dev/null )"
[ -n "$MR" ] && conserves "$MR" && [ -n "$v" ] && [ "$v" -ge 1 ] \
    && ok "(F) two-root run reaches other_root ($v) and conserves: $MR" \
    || no "(F) two-root run: ${MR:-no dispositions line}"
# the std:: guard (graph.h keepStdQualifiedCandidates) refuses a std::-qualified C++ call with no candidate inside namespace
# std through vetoExternal — the Phase-5 veto's own refusal, so the site is external= and must be counted External. Its
# fixture, test/stdqualfix, gives std::move and std::swap LONE in-repo decoys, so those sites reach the guard with
# candidates. A guard exit that drops vetoExternal's disposition lands in unaccounted, raises the alert, and leaves the
# census's external below the header's — three reds below.
SQFIX="$ROOT/test/stdqualfix"
"$BIN" "$SQFIX" --no-cache --pin-census="$TMP/sq.tsv" >"$TMP/sq.xml" 2>"$TMP/sq.err"
SQ="$( grep -m1 '^# dispositions ' "$TMP/sq.tsv" 2>/dev/null )"
SQHDR="$( stats "$TMP/sq.xml" )"
# premise: a qualified call cannot reach the Phase-5 veto (it requires an empty qualifier), so takeTwice's two std::move
# external rows are the guard's own refusals — without them the arms below would pass on a corpus the guard never touched
SQG="$( awk -F'\t' '$1=="C" && $2=="external" && index($6, "takeTwice#") > 0' "$TMP/sq.tsv" 2>/dev/null | wc -l | tr -d ' ' )"
[ "$SQG" = 2 ] && ok "(F) std:: guard premise: takeTwice's two std::move sites are refused (2 external census rows)" \
    || no "(F) std:: guard premise: takeTwice has ${SQG:-0} external census rows, expected 2 — the arms below would prove nothing"
[ -n "$SQ" ] && conserves "$SQ" && ok "(F) the std:: guard corpus conserves: $SQ" \
    || no "(F) the std:: guard corpus does not conserve: ${SQ:-no dispositions line}"
v="$( disp_in "$TMP/sq.tsv" external 2>/dev/null )"
[ -n "$v" ] && [ "$v" = "$( gauge "$SQHDR" external )" ] \
    && ok "(F) std:: guard corpus: census external=$v == header external=" \
    || no "(F) std:: guard corpus: census external=${v:-absent} but header external=$( gauge "$SQHDR" external ) — a vetoExternal exit named no disposition"
grep -q 'disposition' "$TMP/sq.err" \
    && no "(F) the std:: guard corpus raised the unaccounted-disposition alert: $( grep 'disposition' "$TMP/sq.err" | head -1 )" \
    || ok "(F) no unaccounted-disposition alert on the std:: guard corpus"

# ── (G) the predicates can fail ───────────────────────────────────────────────────────────────────────────────
echo "=== (G) mutation — every predicate above rejects its failure shape ==="
conserves '# dispositions calls=5 bound=2 self=0 external=1 unresolved=0 undefined=0 other_root=0 qualified_external=0 declined=1 file_scope=0 unaccounted=0' \
    && no "(G) the conservation predicate accepts a line that sums to 4 of 5" || ok "(G) a line that does not sum IS rejected"
conserves '# dispositions calls=5 bound=2 self=0 external=1 unresolved=0 undefined=0 other_root=0 qualified_external=0 declined=1 file_scope=0 unaccounted=1' \
    && no "(G) the conservation predicate accepts unaccounted=1" || ok "(G) unaccounted=1 IS rejected"
conserves '# dispositions calls=4 bound=2 external=1 declined=1' \
    && no "(G) the conservation predicate accepts a line with no unaccounted bucket" || ok "(G) a line without unaccounted= IS rejected"
R='<callers of="x" defs="1" count="0" root="." counts_floor="1">'
[ "$( attr "$R" count )" = 0 ] && [ "$( attr "$R" declined_calls )" = 1 ] \
    && no "(G) the answer predicate cannot see a bare zero" || ok "(G) a bare count=\"0\" without declined_calls= IS detected"
H='<!-- files=1 symbols=2 edges=0 shown=2 est_tokens=9 ambiguous=0 unresolved=0 order=important-first -->'
[ "$( gauge "$H" declined )" = 17 ] && no "(G) the header predicate cannot see a missing gauge" || ok "(G) a header without declined= IS detected"
printf '%s' '<uses of="jbody" defs="2" external="0" count="0" root="." counts_floor="1"></uses>' >"$TMP/g_uses.xml"
call_sites "$TMP/g_uses.xml" | grep -qxF java/caller/JavaCaller.java:7 \
    && no "(G) the site predicate finds a declined site the uses answer does not list" || ok "(G) a uses answer that drops the declined site IS detected"

# Exercise the identical live predicate against the original broken pointer shape.
R='<callers of="java/alpha/Alpha.java:jbody" defs="1" count="0" declined_calls="1" next="--uses=java/alpha/Alpha.java:jbody">'
is_bare_next "$R" jbody \
    && no "(G) the bare-name pointer predicate accepts a narrowed selector" \
    || ok "(G) a next= that still names the narrowed selector IS rejected"

# ── (H) determinism, well-formedness, no degrade alert ────────────────────────────────────────────────────────
echo "=== (H) determinism + well-formedness ==="
"$BIN" . --no-cache --pin-census="$TMP/c2.tsv" >"$TMP/map2.xml" 2>/dev/null
cmp -s "$TMP/map.xml" "$TMP/map2.xml" && cmp -s "$TMP/c.tsv" "$TMP/c2.tsv" && ok "(H) map + census byte-identical across two runs" \
    || no "(H) map or census differs between two runs"
if command -v xmllint >/dev/null 2>&1; then
    for f in map.xml callers.xml impact.xml callees.xml; do
        if xmllint --noout "$TMP/$f" 2>/dev/null; then ok "(H) xmllint clean: $f"; else no "(H) xmllint rejected $f"; fi
    done
fi
grep -q 'disposition' "$TMP/err" && no "(H) the map run raised the unaccounted-disposition alert: $( grep 'disposition' "$TMP/err" | head -1 )" \
    || ok "(H) no unaccounted-disposition alert on stderr"

[ "$fail" = 0 ] && echo "declinecheck: PASS" || echo "declinecheck: FAIL"
exit "$fail"
