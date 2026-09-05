#!/usr/bin/env bash
# donelegendcheck.sh — G4: the DONE-CHECKPOINT verbs must not re-inflate their legends, and the compaction
# that shrank them must not have cost a definition.
#
#   test/donelegendcheck.sh                        # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/donelegendcheck.sh
#
# WHY (density round 2026-09-02, lane B). --quality-delta ranks FIRST in this tool's measured call mix,
# ahead of --for, because CLAUDE.md tells every agent to run it before calling work done — so its fixed text
# is paid at every checkpoint. Its legend was ONE unconditional 8,574 B constant (10,512 B
# with the scope half) in front of a 572 B payload on a clean run: 93.7% of every "am I done?" checkpoint was
# fixed text the reader had already met, re-paid on every call. --safe-delete was 4,112 B of legend and
# --test-gate 1,332 B on its empty-diff case.
#
# THE FIX, and therefore what this gate pins: A DEFINITION IS EMITTED WHEN THE THING IT DEFINES IS IN THE
# DOCUMENT. Sections are conditional on the attributes, markers and row kinds the run actually produced, so a
# reader still cannot meet an undefined name — the name and its sentence appear together or not at all. That
# property is what makes the byte ceilings safe to ratchet, so arm (c) asserts the property directly and arm
# (a) only asserts the size.
#
# THE RATCHET IS ABSOLUTE BYTES, not legend<=payload, and the arithmetic is why. On the case these verbs are
# most often called in — a clean tree, nothing regressed — the payload is near-zero BY CONSTRUCTION
# (regressions="0" with no rows is the document's own honest report of "nothing to say"). A relative ceiling
# is therefore unsatisfiable there for any legend that still defines the header it introduces: at 40% of a
# 572 B payload the whole legend would have to fit in 381 B, which is shorter than the list of the ten
# measured kinds. testgatelegendbudgetcheck.sh made the same call for the same reason; graphlegendbudgetcheck.sh
# can use a relative arm only because --callers/--impact/--uses payload is real row content. Arm (b) here
# reports the fraction as INFO so the number stays visible without an unsatisfiable assertion attached to it.
#
# EVERY FIXTURE IS A TEMP GIT REPO, never this checkout. Which sections a quality-delta legend earns depends
# on what the run found, so measuring on the live tree would make the ceiling swing on whether the agent
# running the suite happens to have uncommitted edits — a ratchet that reds because you have unstaged work is
# a ratchet nobody keeps (legendcoveragecheck.sh's own pinning note, same class).
#
# Exits non-zero on a budget, presence or coverage failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }
info(){ printf '  INFO  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  donelegendcheck (git required for the HEAD-baseline fixtures)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "donelegendcheck: BIN=$BIN  (temp git corpora)"

# ── the fixture. ONE committed file with two symbols, then an uncommitted edit that adds a verbatim clone of
# one of them plus a deeply nested, high-arity function. That mix is chosen to light every conditional
# section at once: duplication (members=/tokens=/idiom=), complexity/nesting/params (was=/now=), dead-code,
# api-surface (origin=), and a gating row (gating=). The CLEAN state lights none of them.
FX="$WORK/fx"; mkdir -p "$FX/src"
( cd "$FX" && git init -q && git config user.email t@t && git config user.name t )
cat > "$FX/src/base.cpp" <<'EOF'
#include <string>
int classifyWidth( int w )
{
    if( w < 10 ) { return 0; }
    if( w < 20 ) { return 1; }
    if( w < 40 ) { return 2; }
    if( w < 80 ) { return 3; }
    return 4;
}

int useWidth()
{
    return classifyWidth( 5 );
}

int tangle( int a, int b, int c, int d )
{
    int r = 0;
    for( int i = 0; i < a; ++i )
    {
        if( b > i ) { r += 1; } else if( c > i ) { r += 2; } else { r += 3; }
    }
    return r + d;
}
EOF
( cd "$FX" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )

# a SECOND, pristine copy that is never dirtied — the empty-obligation shape --test-gate is most often
# called in (a clean working tree: changed="0", no <t> and no <u> rows for the row contract to govern).
FXC="$WORK/fxc"; mkdir -p "$FXC/src"
( cd "$FXC" && git init -q && git config user.email t@t && git config user.name t )
cp "$FX/src/base.cpp" "$FXC/src/base.cpp"
( cd "$FXC" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )

DIRT='
int classifyDepth( int w )
{
    if( w < 10 ) { return 0; }
    if( w < 20 ) { return 1; }
    if( w < 40 ) { return 2; }
    if( w < 80 ) { return 3; }
    return 4;
}

int tangleHarder( int a, int b, int c, int d, int e, int f )
{
    int r = 0;
    for( int i = 0; i < a; ++i )
    {
        for( int j = 0; j < b; ++j )
        {
            if( c > i ) { if( d > j ) { if( e > i + j ) { r += 1; } else { r += 2; } } else { r += 3; } }
            else if( f > j ) { r += 4; } else { r += 5; }
        }
    }
    return r;
}
'

# ── measurement helpers. The legend is the sum of the LEADING contiguous <!-- … --> blocks — the same split
# panellegendcheck.sh / graphlegendbudgetcheck.sh / testgatelegendbudgetcheck.sh use, kept independent here
# rather than sourced, so a mistake in one derivation cannot green all four gates at once.
split(){ python3 - "$1" <<'PY'
import re, sys
doc  = open( sys.argv[1], 'rb' ).read().decode( 'utf-8', 'replace' )
m    = re.match( r'\A(?:\s*<!--.*?-->)+', doc, re.S )
lead = m.group( 0 ) if m else ''
print( len( doc.encode() ), len( lead.encode() ), len( doc.encode() ) - len( lead.encode() ) )
PY
}
legendOf(){ python3 - "$1" <<'PY'
import re, sys
doc = open( sys.argv[1], 'rb' ).read().decode( 'utf-8', 'replace' )
m   = re.match( r'\A(?:\s*<!--.*?-->)+', doc, re.S )
sys.stdout.write( m.group( 0 ) if m else '' )
PY
}

echo
echo "=== (a) THE RATCHET — absolute legend bytes per shape ==============================================="
# name | budget | pre-fix bytes at 8e186bb | argv…   (budgets leave ~10% headroom over the post-fix number
# for one honest future addition, and no more; the pre-fix column is what the ratchet is holding back)
run_budget(){
    local name="$1" budget="$2" pre="$3"; shift 3
    "$BIN" "$@" >"$WORK/$name.xml" 2>/dev/null
    [ -s "$WORK/$name.xml" ] || { no "(a) $name produced NO output — the probe is broken, fix it before trusting any row"; return; }
    read -r total legend payload <<EOF
$( split "$WORK/$name.xml" )
EOF
    if [ "$legend" -le "$budget" ]; then
        ok "(a) $name legend $legend B <= $budget B (was $pre B; total=$total payload=$payload)"
    else
        no "(a) $name legend $legend B > $budget B — the essay re-inflated (pre-fix was $pre B)"
    fi
    printf '%s' "$total $legend $payload" >"$WORK/$name.split"
}

run_budget qd_clean       2300  8574  "$FX"  --quality-delta
printf '%s' "$DIRT" >> "$FX/src/base.cpp"
run_budget qd_dirty       3800  8574  "$FX"  --quality-delta
run_budget qd_dirty_scope 5200 10512  "$FX"  --quality-delta "--scope=src/*"
run_budget sd_uses        3800  4112  "$FX"  --safe-delete=classifyWidth
run_budget sd_none        3800  4112  "$FX"  --safe-delete=tangle
# tg_empty 1200 -> 1400 (2026-09-04, capture-audit wave-1 close, lane L4 M15): the zero-row root now carries
# graph_ambiguous=/graph_unresolved= (the resolver gauge every graph-floored root spells, floormarkcheck arm 11),
# and two emitted attributes must be DEFINED in this document (arm (d) below) — the shortest honest sentence is
# 186 B on a legend that was 1111 B, so 1200 cannot hold any wording of it. L4's M2 <u>-paging clause, which had
# landed in the unconditional half too, moved into kTestGateRowLegend (a rule about rows; tg_empty pays nothing).
# Measured post-fix 1297 B; 1400 is the ~8% headroom this table's own rule gives one future honest addition.
# tg_empty 1400 -> 1510 (2026-09-05, capture-audit wave-3, lane L7 P3): that one addition arrived — next= on the
# root (106 B, unconditional: an empty gate still names its follow-up, --situ). Measured 1403 B; 1510 is the same
# ~8% headroom rule applied once more.
run_budget tg_empty       1510  1332  "$FXC" --test-gate
# The ref-pair form — the only shape that lights the ref-pair marker, omits at= and reports churn as
# unavailable. Measured on the FIXTURE, with the same edit committed as a second commit, NOT on this repo's
# own HEAD~1..HEAD: that range means a different diff after every landing, so a budget on it would be a
# ratchet whose value depends on whoever committed last.
( cd "$FX" && git add -A >/dev/null 2>&1 && git commit -qm dirt >/dev/null 2>&1 )
run_budget qd_refpair     4300  8574  "$FX"  --quality-delta=HEAD~1..HEAD

echo
echo "=== (b) the fraction, reported not asserted (see the header for why) ==============================="
for n in qd_clean qd_dirty qd_dirty_scope qd_refpair sd_uses sd_none tg_empty; do
    read -r total legend payload <"$WORK/$n.split"
    info "(b) $n: legend $legend B of $total B = $( python3 -c "print( f'{100.0*$legend/$total:.1f}%' )" ) (payload $payload B)"
done

echo
echo "=== (c) EMIT-ON-PRESENCE — a section is in the document exactly when its subject is ================"
# This is the property the compaction bought, and the one a future edit is most likely to undo by merging
# the sections back into one constant. Each row names a legend anchor and the shape it must / must not be in.
present(){ case "$( legendOf "$WORK/$1.xml" )" in *"$2"*) ok "(c) $1 legend states: $2";; *) no "(c) $1 legend is MISSING: $2";; esac; }
absent(){  case "$( legendOf "$WORK/$1.xml" )" in *"$2"*) no "(c) $1 legend still carries a section it did not earn: $2";; *) ok "(c) $1 legend correctly omits: $2";; esac; }

# the baseline marker in force, and only it. All five fixtures above run the working-tree-vs-HEAD path.
present qd_clean 'baseline="git-HEAD" means no sidecar existed'
for m in 'baseline="sidecar"' 'baseline="ref-pair"' 'baseline="git-HEAD (stale sidecar removed)"' 'baseline="git-HEAD (stale sidecar ignored)"'; do
    absent qd_clean "$m"
done
# the row dictionaries: absent on a clean tree, present the moment there are rows to read.
absent  qd_clean 'ROWS: sym='
absent  qd_clean 'CLONE ROWS name the whole group'
present qd_dirty 'ROWS: sym='
present qd_dirty 'CLONE ROWS name the whole group'
# the scope half follows the scope flag, as it has since P1.
absent  qd_dirty       'SCOPE, present only when the scope flag was given'
present qd_dirty_scope 'SCOPE, present only when the scope flag was given'
# foreign-acks= is "present only when non-zero" — so is its paragraph.
absent  qd_dirty_scope 'foreign-acks= is a SEPARATE axis'
# test-gate's row contract governs rows; the empty-obligation case has none.
absent  tg_empty 'REPEAT VERBATIM'
"$BIN" "$ROOT" --test-gate=src/model.h >"$WORK/tg_rows.xml" 2>/dev/null
present tg_rows 'REPEAT VERBATIM'
# the ref-pair form lights its own marker, omits at=, and omits the four working-tree markers.
present qd_refpair 'baseline="ref-pair" means neither a sidecar nor the working tree'
absent  qd_refpair 'baseline="git-HEAD" means no sidecar existed'
absent  qd_refpair 'at= is the git commit'
present qd_clean   'at= is the git commit'
# safe-delete names the risk= value THIS run reports, not a glossary of all three. Two probes, one per
# branch, so neither sentence can rot behind a fixture that never reaches it.
present sd_uses 'risk= NAMES what was found'
present sd_uses 'untested-radius: callers or uses exist'
absent  sd_uses 'none-found: zero callers AND zero uses'
present sd_none 'none-found: zero callers AND zero uses'
absent  sd_none 'untested-radius: callers or uses exist'

echo
echo "=== (d) COVERAGE — every attribute the root emits is DEFINED in that document's own legend =========="
# The honesty ratchet that makes (a) safe: the definitional predicate legendcoveragecheck.sh arm (B) uses
# (the attribute name immediately followed by '='), applied to the quality-delta shapes only, with NO
# baseline file — quality-delta has zero recorded gaps in test/legendcoverage_baseline.txt and this lane
# closed seven more that legendcoveragecheck's own roster never reached because they only appear on shapes
# it does not run (sa@key, sa@why, r@was, r@now, quality-delta@minor, @stale, @churn). The floor is zero.
covgaps(){ python3 - "$1" <<'PY'
import re, sys
LEAD = re.compile( r'\A(?:\s*<!--.*?-->)+', re.S )
ATTR = re.compile( r'<([a-zA-Z][\w-]*)((?:\s+[\w:.-]+="[^"]*")*)\s*/?>' )
CORE = { "p", "n", "t", "id", "l", "k", "c" }          # the v1 row keys every map legend already defines
doc  = open( sys.argv[1], 'rb' ).read().decode( 'utf-8', 'replace' )
m    = LEAD.match( doc )
leg  = m.group( 0 ) if m else ''
body = doc[ len( leg ): ]
seen = {}
for tag, attrs in ATTR.findall( body ):
    seen.setdefault( tag, re.findall( r'\s([\w:.-]+)="', attrs ) )
gaps = sorted( { f"{tag}@{a}" for tag, names in seen.items() for a in names if a not in CORE and ( a + "=" ) not in leg } )
print( " ".join( gaps ) )
PY
}
for n in qd_clean qd_dirty qd_dirty_scope qd_refpair; do
    g="$( covgaps "$WORK/$n.xml" )"
    if [ -z "$g" ]; then ok "(d) $n: every emitted attribute is defined in its own legend"
    else no "(d) $n: attributes emitted with NO definition on the first screen: $g"; fi
done
# mutation control: the predicate is live, not inert — a document whose legend is stripped must report gaps.
python3 - "$WORK/qd_dirty.xml" "$WORK/qd_stripped.xml" <<'PY'
import re, sys
doc = open( sys.argv[1], 'rb' ).read().decode( 'utf-8', 'replace' )
open( sys.argv[2], 'w' ).write( re.sub( r'\A(?:\s*<!--.*?-->)+', '<!-- x -->', doc, flags=re.S ) )
PY
[ -n "$( covgaps "$WORK/qd_stripped.xml" )" ] \
    && ok "(d) mutation control — a stripped legend DOES report gaps (the coverage arm is live)" \
    || no "(d) mutation control FAILED: a legend replaced by one word reports no gaps, so arm (d) proves nothing"

echo
echo "=== (e) still well-formed and still deterministic after a prose-only edit =========================="
for n in qd_clean qd_dirty qd_dirty_scope qd_refpair sd_uses sd_none tg_empty; do
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$WORK/$n.xml" 2>/dev/null && ok "(e) $n is well-formed XML" || no "(e) $n fails xmllint"
    fi
done
# The ref-pair form is the one re-run that is safe HERE: the fixture's working tree was committed above
# for the qd_refpair probe, so a working-tree shape would legitimately report something else now.
"$BIN" "$FX" --quality-delta=HEAD~1..HEAD >"$WORK/qd_twice.xml" 2>/dev/null
diff -q "$WORK/qd_refpair.xml" "$WORK/qd_twice.xml" >/dev/null \
    && ok "(e) quality-delta deterministic (byte-identical twice on the same fixture state)" \
    || no "(e) quality-delta differs across two runs on an unchanged fixture"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
