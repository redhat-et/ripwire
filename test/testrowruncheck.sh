#!/usr/bin/env bash
# testrowruncheck.sh — the FAMILY gate for "a tests_to_run row says how to run it".
#
# capture-audit 2026-09-04, finding M21(b) (lens 0 M0-3, lens 2 L2, lens 8 §(2)).
#
# THE DEFECT. Seven verbs answer "which tests must I run" and they did not agree on whether the answer is a
# COMMAND or a PATH. --test-gate — the verb that EXITS 4 calling its rows "the obligations" — printed
# `<t p="./test/verify_radix.cpp"/>`: the agent is told a test must run and not how. --handoff printed the
# same rows with no run= at all while --situ/--pr-context/--affected beside it carried
# `run="bash test/…check.sh"` for the same file. testmap.h's rule was "absent run= means NOT DERIVABLE", and
# that rule is right — a guessed command is worse than none — but an ABSENCE is not a disclosure: a reader
# cannot tell "no runner exists for this harness" from "this emitter forgot to ask". The honesty contract
# (a zero means none FOUND, every gap stated where it is consumed) wants the not-derivable case SAID.
#
# THE PROPERTY, asserted over the family and not over one verb: every tests_to_run row, in every dialect,
# carries EITHER a real `run=` / `"run":` / `(run: …)` recipe OR the explicit `run_unknown="1"` /
# `"run_unknown":true` / `(run: not derivable)` disclosure — never neither. Plus M21(b)'s second half: the
# untested blast-radius `<u>` rows carry `l=`, the line their sibling --flags --flip rows have always had.
#
# E1 / A4-2 (2026-09-12, owner call): runner-less rows that share their per-row attributes are served as ONE
# `<g … n= p="a,b,c" run_unknown="1"/>` row (JSON `{"p":[…],…,"n":N,"run_unknown":true}`, text
# `[hops=N] (n): a, b, c   (run: not derivable)`), so the disclosure is said once per GROUP. The rule keeps
# its meaning — "a <t> or <g> row carries one or the other, never neither" — and arm 12 proves what the
# grouping must never change: the MULTISET of paths (every path verbatim, each exactly once, across every
# dialect), on a fixture with three hop groups and a runner row in the middle of one of them.
#
# ARM 0 is the DERIVATION arm: it enumerates the row emitters out of src/ and fails when a site appears that
# the arms below do not drive. That is what makes this a family gate rather than seven instance gates — a
# NEW verb that grows a tests_to_run row is a FAILURE here until it is driven and disclosed. Since E1 every
# emitter renders its rows through testmap.h's ONE seam (testRowsRendered), so the census is its call sites.
#
# Usage:  test/testrowruncheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/testrowruncheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

echo "testrowruncheck: BIN=$BIN"

# ── ARM 0 — the emitter census, derived from src/ ──────────────────────────────────────────────────────
# Every site that prints a tests_to_run row. The list is the CONTRACT: a site added to src/ and not added
# here fails, which is the only way a family gate stays a family gate.
EXPECTED_SITES="src/verbs_change.h src/situ.h src/prcontext.h src/packtask.h src/handoff.h src/flipimpact.h src/mcpverbs.h src/mcpedit.h"
FOUND_SITES="$( cd "$ROOT" && grep -lE 'testRows(Rendered|Joined)\(|"<(t|test) p=\\"|\{\\"test\\":|\{\\"p\\":\\"%s\\"%s\}' src/*.h src/*.cpp 2>/dev/null \
                | grep -vE 'src/(serialize|testmap)\.h' | sort | tr '\n' ' ' | sed 's/ $//' )"
WANT_SITES="$( printf '%s\n' $EXPECTED_SITES | sort | tr '\n' ' ' | sed 's/ $//' )"
[ "$FOUND_SITES" = "$WANT_SITES" ] \
    && ok "(0) the tests_to_run row emitters are exactly the census this gate drives" \
    || no "(0) emitter census drifted: src/ has [$FOUND_SITES], gate drives [$WANT_SITES] — drive the new one or explain it here"

# ── the fixture ────────────────────────────────────────────────────────────────────────────────────────
# Two harnesses on purpose, because the property has TWO sides and a fixture that exercises one of them
# proves nothing about the other:
#   test/covered.cpp   — a shell runner shares its STEM (test/covered.sh) ⇒ run= IS derivable
#   test/lonely.cpp    — nothing names it anywhere              ⇒ run= is NOT derivable ⇒ run_unknown
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src" "$WORK/test"
cat > "$WORK/src/app.cpp" <<'EOF'
int compute( int x )
{
    return x + 1;
}

int wrapper( int x )
{
    return compute( x );
}
EOF
cat > "$WORK/test/covered.cpp" <<'EOF'
int compute( int x );
int test_covered( void )
{
    return compute( 1 );
}
EOF
cat > "$WORK/test/lonely.cpp" <<'EOF'
int wrapper( int x );
int test_lonely( void )
{
    return wrapper( 2 );
}
EOF
# a second source file whose CALLER no test reaches — that is what makes the untested blast radius (the
# <u> rows arm 10 asserts) non-empty. --test-gate's untested set is the transitive-caller reach of the
# CHANGED symbols minus the changed symbols themselves, minus anything a test reaches: so the fixture needs
# a changed callee (helper_core, dirtied below) with an unchanged, untested caller (nobody_tests_me).
cat > "$WORK/src/util.cpp" <<'EOF'
int helper_core( int x )
{
    return x + 0;
}
EOF
# the caller lives in its OWN file: the changed-symbol set is FILE-granular, so a caller sharing util.cpp
# would be "changed" too and the untested radius would come back empty (measured: impacted="0").
cat > "$WORK/src/consumer.cpp" <<'EOF'
int helper_core( int x );

int nobody_tests_me( int x )
{
    return helper_core( x );
}
EOF
cat > "$WORK/test/covered.sh" <<'EOF'
#!/usr/bin/env bash
echo covered
EOF
chmod +x "$WORK/test/covered.sh"
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )
# a second commit so the ref-taking verbs (--pr-context, --handoff) have a base to diff against, and a
# dirty working tree so the diff-seeded verbs (--test-gate, --situ) have a change set at all.
printf 'int extra( int x ) { return x - 1; }\n' >> "$WORK/src/app.cpp"
( cd "$WORK" && git add -A && git commit -qm second >/dev/null 2>&1 )
printf 'int extra2( int x ) { return x - 2; }\n' >> "$WORK/src/app.cpp"
# dirty helper_core's BODY only, so nobody_tests_me stays unchanged and lands in the untested blast radius.
sed -i.bak 's/return x + 0;/return x + 7;/' "$WORK/src/util.cpp" && rm -f "$WORK/src/util.cpp.bak"

rw(){ ( cd "$WORK" && "$BIN" . "$@" --no-cache 2>/dev/null ); }

# ── the two assertions every arm shares ────────────────────────────────────────────────────────────────
# $1 = a label, $2 = the document, $3 = the row regex, $4 = the "has a recipe" regex,
# $5 = the "says it has none" regex.
rows_disclosed(){
    local label="$1" doc="$2" rowre="$3" hasre="$4" unkre="$5"
    local rows n bad
    rows="$( printf '%s' "$doc" | grep -oE "$rowre" )"
    n="$( printf '%s' "$rows" | grep -c . )"
    if [ "${n:-0}" -eq 0 ]; then
        no "$label: fixture produced no tests_to_run rows — the arm cannot bite"; printf '%s\n' "$doc" | head -c 800; echo
        return
    fi
    bad="$( printf '%s\n' "$rows" | grep -vE "$hasre" | grep -vE "$unkre" )"
    if [ -n "$bad" ]; then
        no "$label: $( printf '%s\n' "$bad" | grep -c . ) of $n row(s) carry neither a run recipe nor the not-derivable disclosure"
        printf '%s\n' "$bad" | head -5
    else
        ok "$label: all $n tests_to_run row(s) carry a run recipe or run_unknown"
    fi
    # non-vacuity: the fixture must produce BOTH shapes wherever the verb lists both harnesses, so a gate
    # that only ever sees run= cannot pass an emitter that never learned to say run_unknown.
    printf '%s\n' "$rows" | grep -qE "$unkre" \
        || printf '        NOTE  %s listed no not-derivable row (verb reached only the covered harness)\n' "$label"
}

# E1: a <g …> group row is a tests_to_run row too (its p= lists several paths); the JSON twin's "p"/"test"
# is then an ARRAY. Both shapes must carry the disclosure like any single row.
XROW='<(t|test) p="[^"]*"[^>]*/>|<g [^>]*/>'
XHAS=' run="'
XUNK=' run_unknown="1"'
JROW='\{"(p|test)":("[^"]*"|\[[^]]*\])[^}]*\}'
JHAS='"run":"'
JUNK='"run_unknown":true'
# the JSON dialects embed the tests_to_run LIST inside a document that also carries file rows keyed "p";
# slice the list first so the arm asks its question of the row family it is about and no other.
json_tests(){ printf '%s' "$1" | sed 's/\\"/"/g' | grep -oE '"tests_to_run":\[[^]]*\]'; }

# ── ARM 1 — --affected (verbs_change.h) ────────────────────────────────────────────────────────────────
rows_disclosed "(1) --affected"  "$( rw --affected=compute,wrapper )" "$XROW" "$XHAS" "$XUNK"
# ── ARM 2 — --exercises seed rows (verbs_change.h) ─────────────────────────────────────────────────────
rows_disclosed "(2) --exercises" "$( rw --exercises=test/lonely.cpp )" "$XROW" "$XHAS" "$XUNK"
# ── ARM 3 — --test-gate, both dialects (situ.h) ────────────────────────────────────────────────────────
TG="$( rw --test-gate )"
rows_disclosed "(3) --test-gate xml"  "$TG"                     "$XROW" "$XHAS" "$XUNK"
rows_disclosed "(3) --test-gate json" "$( json_tests "$( rw --test-gate --json )" )" "$JROW" "$JHAS" "$JUNK"
# ── ARM 4 — --pr-context (prcontext.h) ─────────────────────────────────────────────────────────────────
rows_disclosed "(4) --pr-context" "$( rw --pr-context )" "$XROW" "$XHAS" "$XUNK"
# ── ARM 5 — --pack-task, both dialects (packtask.h) ────────────────────────────────────────────────────
rows_disclosed "(5) --pack-task xml"  "$( rw --pack-task="change compute and wrapper" )"        "$XROW" "$XHAS" "$XUNK"
rows_disclosed "(5) --pack-task json" "$( json_tests "$( rw --pack-task="change compute and wrapper" --json )" )" "$JROW" "$JHAS" "$JUNK"
# ── ARM 6 — --handoff (handoff.h) — the row family lens 2 L2 found carrying NO run= at all ─────────────
rows_disclosed "(6) --handoff" "$( rw --handoff )" "$XROW" "$XHAS" "$XUNK"
# ── ARM 7 — --flags --flip (flipimpact.h) ──────────────────────────────────────────────────────────────
FLIPNAME="$( rw --flags | grep -oE '<g n="[^"]+"' | head -1 | sed -E 's/^<g n="([^"]*)"$/\1/' )"
FLIPOUT=""
[ -n "$FLIPNAME" ] && FLIPOUT="$( rw --flags --flip="$FLIPNAME" )"
if printf '%s' "$FLIPOUT" | grep -qE '<(t|test) p="'; then
    rows_disclosed "(7) --flags --flip" "$FLIPOUT" "$XROW" "$XHAS" "$XUNK"
else
    # NOT a silent pass: the flip verb's own <t> emitter is in the arm-0 census, so when the fixture cannot
    # reach it the gate says so out loud rather than letting the census claim coverage it did not get.
    printf '  SKIP  (7) --flags --flip emitted no test row on this fixture (gate=%s) — arm 0 pins the emitter, and test/flipcheck.sh coverage arm pins the row shape on a fixture that has a dark gate\n' "${FLIPNAME:-none}"
fi
# ── ARM 8 — --situ's TEXT dialect (situ.h) ─────────────────────────────────────────────────────────────
SITU="$( rw --situ )"
SITU_ROWS="$( printf '%s\n' "$SITU" | sed -n '/tests to run/,/^  \[3\]/p' | grep -E '^        [^ (]' )"
if [ -z "$SITU_ROWS" ]; then
    no "(8) --situ: fixture produced no 'tests to run' rows — the arm cannot bite"; printf '%s\n' "$SITU" | head -30
else
    SITU_BAD="$( printf '%s\n' "$SITU_ROWS" | grep -v '(run: ' )"
    [ -z "$SITU_BAD" ] \
        && ok "(8) --situ text: all $( printf '%s\n' "$SITU_ROWS" | grep -c . ) test line(s) carry a (run: …) recipe or its not-derivable form" \
        || { no "(8) --situ text: a tests-to-run line carries no run recipe and no disclosure"; printf '%s\n' "$SITU_BAD"; }
fi
# ── ARM 9 — MCP situational_awareness (mcpverbs.h) ─────────────────────────────────────────────────────
MCPOUT="$( printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"'"$WORK"'"}}}' \
  | ( cd "$WORK" && "$BIN" --mcp 2>/dev/null ) )"
rows_disclosed "(9) mcp situational_awareness" "$( json_tests "$MCPOUT" )" "$JROW" "$JHAS" "$JUNK"

# ── ARM 10 — M21(b) second half: the untested blast-radius <u> rows carry a LINE ───────────────────────
# `<u sym="dispatchMcpLine" p="./src/mcp.h" ccx="439"/>` names a symbol to test and a file to open, and
# leaves the reader to find it. Its own sibling --flags --flip has printed `<u sym= p= l= ccx=>` since it
# was written; this is that attribute applied where the plan says it was missing. Both dialects.
UROWS="$( printf '%s' "$TG" | grep -oE '<u [^>]*/>' )"
if [ -z "$UROWS" ]; then
    no "(10) --test-gate produced no <u> untested rows — the arm cannot bite"; printf '%s\n' "$TG" | tail -c 600
else
    printf '%s\n' "$UROWS" | grep -vqE ' l="[0-9]+"' \
        && { no "(10) an untested <u> row carries no l= line"; printf '%s\n' "$UROWS" | grep -vE ' l="[0-9]+"' | head -3; } \
        || ok "(10) every --test-gate untested <u> row carries l= ($( printf '%s\n' "$UROWS" | grep -c . ) rows)"
fi
UJSON="$( rw --test-gate --json | grep -oE '\{"sym":"[^"]*"[^}]*\}' )"
if [ -z "$UJSON" ]; then
    no "(10) --test-gate --json produced no untested rows — the arm cannot bite"
else
    printf '%s\n' "$UJSON" | grep -vqE '"l":[0-9]+' \
        && { no "(10) a JSON untested row carries no \"l\""; printf '%s\n' "$UJSON" | head -3; } \
        || ok "(10) every --test-gate --json untested row carries \"l\" (the XML twin's l=)"
fi

# ── ARM 11 — the disclosure is DEFINED where it is emitted ─────────────────────────────────────────────
# legendcoveragecheck.sh owns this rule tool-wide; pinned here too because run_unknown= is the attribute
# this gate exists for, and an undefined attribute is a fact the reader cannot use.
# The legend is everything BEFORE the root element's start tag (the document is one line, so a greedy
# regex over <!--…--> would capture only the last comment — that mistake made this arm read as red while
# the definition was present).
TG_LEGEND="${TG%%<test-gate *}"
if printf '%s' "$TG" | grep -q 'run_unknown'; then
    printf '%s' "$TG_LEGEND" | grep -q 'run_unknown' \
        && ok "(11) run_unknown= is defined in the legend of the document that emits it" \
        || { no "(11) run_unknown= emitted with no legend definition"; }
else
    printf '  SKIP  (11) this document emitted no run_unknown row\n'
fi

# ── ARM 12 — E1: grouping never changes the MULTISET of paths, in any dialect ─────────────────────────
# A fixture with THREE hop groups (tests reaching the changed symbol at depth 1, 2 and 3) and a runner row
# in the MIDDLE of the depth-1 group (t_leaf_b.sh stem-matches t_leaf_b.cpp; path order a < b < c), so the
# arm sees: a runner-less group interrupted by a single run= row, groups at three distinct hops=, and the
# same seven paths in --affected, --test-gate (XML and JSON) and --situ's text. What it proves: every path
# appears exactly once (verbatim — a reader's grep for a file name must still hit), the run= row stays a
# single row, at least three <g> rows exist with distinct hops=, and the root's tests= count is the number
# of FILES, not rows. Red on the pre-E1 binary (no <g> row at all).
command -v python3 >/dev/null 2>&1 || no "(12) python3 missing — the multiset arm cannot run"
W2="$( mktemp -d )"; trap 'rm -rf "$WORK" "$W2"' EXIT
mkdir -p "$W2/src" "$W2/test"
printf 'int leaf( int x )\n{\n    return x + 1;\n}\n' > "$W2/src/leaf.cpp"
printf 'int leaf( int x );\nint mid( int x )\n{\n    return leaf( x );\n}\n' > "$W2/src/mid.cpp"
printf 'int mid( int x );\nint top( int x )\n{\n    return mid( x );\n}\n' > "$W2/src/top.cpp"
for n in leaf_a leaf_b leaf_c; do printf 'int leaf( int x );\nint test_%s( void )\n{\n    return leaf( 1 );\n}\n' "$n" > "$W2/test/t_$n.cpp"; done
for n in mid_a mid_b; do printf 'int mid( int x );\nint test_%s( void )\n{\n    return mid( 1 );\n}\n' "$n" > "$W2/test/t_$n.cpp"; done
for n in top_a top_b; do printf 'int top( int x );\nint test_%s( void )\n{\n    return top( 1 );\n}\n' "$n" > "$W2/test/t_$n.cpp"; done
printf '#!/usr/bin/env bash\necho leaf_b\n' > "$W2/test/t_leaf_b.sh"; chmod +x "$W2/test/t_leaf_b.sh"
( cd "$W2" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
printf 'int leaf2( int x ) { return x + 2; }\n' >> "$W2/src/leaf.cpp"
rw2(){ ( cd "$W2" && "$BIN" . "$@" --no-cache 2>/dev/null ); }
A12="$( rw2 --affected=src/leaf.cpp )"
G12="$( rw2 --test-gate=src/leaf.cpp )"
J12="$( rw2 --test-gate=src/leaf.cpp --json )"
S12="$( rw2 --situ=src/leaf.cpp )"
python3 - "$A12" "$G12" "$J12" "$S12" <<'PY12'
import sys, re, json
aff, tg, tgj, situ = sys.argv[1:5]
EXPECT = sorted( "test/t_%s.cpp" % n for n in ( "leaf_a", "leaf_b", "leaf_c", "mid_a", "mid_b", "top_a", "top_b" ) )
fails = []
def xml_paths( doc ):
    out, groups, singles_run = [], [], []
    for m in re.finditer( r'<(t|test|g)( [^>]*)/>', doc ):
        tag, attrs = m.group( 1 ), m.group( 2 )
        at = dict( re.findall( r' ([a-z_]+)="([^"]*)"', attrs ) )
        if tag == "g":
            ps = [ p.replace( "&#44;", "," ) for p in at["p"].split( "," ) ]
            if int( at.get( "n", "-1" ) ) != len( ps ): fails.append( "n=%s on a <g> row listing %d paths" % ( at.get( "n" ), len( ps ) ) )
            if at.get( "run_unknown" ) != "1": fails.append( "a <g> row without run_unknown=1: %s" % m.group( 0 ) )
            if len( ps ) < 2: fails.append( "a <g> row of one: %s" % m.group( 0 ) )
            groups.append( at.get( "hops" ) ); out += ps
        else:
            if "run" in at: singles_run.append( at["p"] )
            out.append( at["p"] )
    return out, groups, singles_run
a_paths, a_groups, a_run = xml_paths( aff )
g_paths, g_groups, g_run = xml_paths( tg )
if not a_paths: fails.append( "--affected emitted no test row at all (fixture broken)" )
for label, paths in ( ( "--affected", a_paths ), ( "--test-gate", g_paths ) ):
    if sorted( paths ) != EXPECT: fails.append( "%s multiset %r != %r" % ( label, sorted( paths ), EXPECT ) )
for label, groups in ( ( "--affected", a_groups ), ( "--test-gate", g_groups ) ):
    if len( set( groups ) ) < 3 or None in groups: fails.append( "%s: expected >=3 <g> rows at distinct hops=, got hops=%r" % ( label, groups ) )
for label, run in ( ( "--affected", a_run ), ( "--test-gate", g_run ) ):
    if run != [ "test/t_leaf_b.cpp" ]: fails.append( "%s: the run= row must be the single test/t_leaf_b.cpp, got %r" % ( label, run ) )
m = re.search( r'<test-gate [^>]*\btests="(\d+)"', tg )
if not m or int( m.group( 1 ) ) != len( EXPECT ): fails.append( "--test-gate tests= must count FILES (%d), got %s" % ( len( EXPECT ), m and m.group( 1 ) ) )
# JSON twin: "p" is a string on a single row and an ARRAY on a group row
# the list is sliced on bracket DEPTH: a group row's "p":[…] array sits inside it, so a lazy `\[.*?\]` would
# stop at the first inner `]` (the shape that made this arm read red while the document was valid JSON)
def balanced_list( doc, key ):
    i = doc.find( key )
    if i < 0: return None
    i = doc.find( "[", i ); depth = 0; instr = False
    for k in range( i, len( doc ) ):
        c = doc[k]
        if instr:
            if c == "\\": continue
            if c == '"': instr = False
            continue
        if c == '"': instr = True
        elif c == "[": depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0: return doc[i:k+1]
    return None
jl = balanced_list( tgj, '"tests_to_run":' )
try:
    rows = json.loads( jl ) if jl else []
except Exception as e:
    rows = []; fails.append( "--test-gate --json tests_to_run is not JSON: %s" % e )
j_paths = []
for r in rows:
    p = r.get( "p" )
    if isinstance( p, list ):
        j_paths += p
        if r.get( "n" ) != len( p ) or r.get( "run_unknown" ) is not True: fails.append( "JSON group row without n=/run_unknown: %r" % r )
    else:
        j_paths.append( p )
        if "run" not in r and r.get( "run_unknown" ) is not True: fails.append( "JSON single row carries neither: %r" % r )
if sorted( j_paths ) != EXPECT: fails.append( "--test-gate --json multiset %r != %r" % ( sorted( j_paths ), EXPECT ) )
# --situ text: `        path [hops=N]   (run: …)` singles and `        [hops=N] (n): a, b, c   (run: not derivable)` groups
sec = situ.split( "tests to run", 1 )[1].split( "\n  [3]", 1 )[0] if "tests to run" in situ else ""
s_paths, s_groups = [], 0
for line in sec.split( "\n" ):
    if not line.startswith( "        " ) or line.startswith( "        (" ): continue
    body = line[8:]
    gm = re.match( r'(\[[^\]]*\] )?\((\d+)\): (.*?)   \(run: not derivable\)$', body )
    if gm:
        ps = gm.group( 3 ).split( ", " ); s_groups += 1
        if int( gm.group( 2 ) ) != len( ps ): fails.append( "situ group count (%s) != %d paths" % ( gm.group( 2 ), len( ps ) ) )
        s_paths += ps
    else:
        if "   (run: " not in body: fails.append( "situ line carries no run recipe/disclosure: %r" % line )
        s_paths.append( body.split( " ", 1 )[0] )
if sorted( s_paths ) != EXPECT: fails.append( "--situ text multiset %r != %r" % ( sorted( s_paths ), EXPECT ) )
if s_groups < 3: fails.append( "--situ text: expected >=3 group lines, got %d" % s_groups )
if fails:
    print( "\n".join( fails ) ); sys.exit( 1 )
print( "OK %d paths, %d <g> rows on --affected" % ( len( EXPECT ), len( a_groups ) ) )
PY12
r12=$?
[ "$r12" -eq 0 ] \
    && ok "(12) E1: grouping keeps the path multiset in every dialect (7 paths, >=3 hop groups, the run= row single, tests= counts files)" \
    || no "(12) E1: the grouped rows do not carry the same paths as the single rows did (details above)"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
