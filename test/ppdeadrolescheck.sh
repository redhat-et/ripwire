#!/usr/bin/env bash
# ppdeadrolescheck.sh — the gate for: EVERY fact captured from a byte range the preprocessor DECIDES is
# dead is dropped, whatever role it would have carried, and whether it is a reference or a DEFINITION.
#
# WHY THIS GATE EXISTS SEPARATELY FROM blindspotcheck.sh ARM (D). That arm gates ONE role. #62 landed the
# `#if 0` consult inside captureTagsFacts' @reference.call / @reference.import branch only, so the rule
# covered the two roles that branch emits and none of the five it does not: the value-use pass
# (role="read" / role="write"), the type-mention pass (role="type"), the base-clause pass
# (role="extends"), and the include directive's OWN import site (role="import" from captureIncludes,
# a second emitter of the same role the tags branch already filtered). Measured on this gate's own
# fixture against the pre-fix binary: 1 of 7 role arms green, the `--uses=Owner.field` answer reporting
# count="4" where the truth is 2 — on a root that carries counts_floor="1", whose promise is
# true >= reported. A floor that OVER-counts is a wrong answer, not a noisy one.
#
# ROLE COVERAGE IS THE POINT, so the arms are indexed by the role vocabulary --uses publishes
# (call|macro|read|write|import|extends|type) and the gate asserts one LIVE control beside every dead
# row. Both halves, always: "the dead row is absent" also passes on a build that answers nothing at all,
# which is the vacuity shape CONTRIBUTING.md §2 rows 3 and 5 describe.
#
# WHAT IT ASSERTS
#   (1) call     — a call inside `#if 0` is not served; the live call to the same callee is.
#   (2) macro    — the call-shaped invocation of a #define inside `#if 0` is not served; the live one is.
#   (3) read     — a value read inside `#if 0` is not served; the live read of the same member is.
#   (4) write    — an assignment target inside `#if 0` is not served; the live write is.
#   (5) import   — BOTH emitters: a `using ns::x;` inside `#if 0` (the tags branch) and an `#include`
#                  inside `#if 0` (captureIncludes). The live spelling of each is the control.
#   (6) extends  — a base clause inside `#if 0` is not served; the live derivation is.
#   (7) type     — a bare type mention inside `#if 0` is not served; the live mention is.
#   (8) #else ARMS — the same rule through the OTHER two shapes the literal rule decides: the `#else` of
#                  `#if 1` is dead, and the `#else` of `#if 0` is LIVE. A range computed off the `#if`
#                  node instead of its alternative chain passes (1)-(7) and fails here.
#   (9) DEFINITIONS — a definition inside `#if 0` is not indexed, so it cannot split resolution. The
#                  three artefacts it used to mint (overloads= on the survivor, amb= + prov="split" on
#                  the caller, graph_ambiguous= on the <callers> root) are asserted ABSENT/ZERO, and the
#                  live definition and its one caller are asserted PRESENT so the arm cannot pass empty.
#  (10) WARM == COLD — the filtered set is what the per-file cache record stores, so a warm run replays
#                  it. Byte-identity on every answer above, through a private XDG_CACHE_HOME.
#  (11) MUTATION — every row reader and every attribute reader above is shown able to see the thing it
#                  claims to look for, against hand-built input; and both ripwire INVOKERS are shown to
#                  record a non-zero exit rather than discard it.
#  (12) BINDINGS — the ambiguity half rather than the counting one: a `Bar x;` inside `#if 0` above a
#                  live `Foo x;` used to leave `x.m()` unnarrowed, amb="1" and split across both `m`s.
#                  Its control is the SAME file with the dead block physically deleted, so the arm
#                  compares against what the source means rather than against a hand-written literal.
#
# NOT COVERED, and said out loud rather than implied by silence: the A4-R5 FFI aliases (BindingAlias)
# carry no site byte, so an `extern "C"` block inside `#if 0` still contributes its aliases. Giving that
# record a byte is a cache RECORD-SHAPE change; see the note beside bindSiteByte in src/ingest_sidecap.h
# for why the defect does not earn one. The L3 fn-pointer clobber sweep reads its own context state, so
# a clobbering assignment inside a dead range can still suppress a live fn-pointer edge — that direction
# UNDER-reports, which is the floor the tool already publishes, not a floor violation.
#
# Usage:
#   bash test/ppdeadrolescheck.sh                      # build/ripwire
#   bash test/ppdeadrolescheck.sh build/ripwire_base   # the RED run (base binary has roles 3,4,6,7 + half of 5)
#   RIPWIRE_BIN=asan/ripwire bash test/ppdeadrolescheck.sh
#
# Exits non-zero on any failure. Writes only under its own mktemp dir.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "ppdeadrolescheck: python3 required"; exit 2; }
echo "ppdeadrolescheck: BIN=$BIN"

# ── readers ───────────────────────────────────────────────────────────────────────────────────────────
# G4 minifies the whole document to one line, so nothing here is line-oriented: a line filter would
# delete the payload along with the legend and every comparison below would then compare two empty
# strings (CONTRIBUTING.md §2 shape 3). Elements are matched by NAME, non-greedy.

# every `<u …>` row of a --uses answer whose text contains $2, one per line.
rows(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
sys.stdout.write("\n".join(r for r in re.findall(r"<u\b[^>]*>",d) if sys.argv[2] in r))' "$1" "$2"; }

# the first `<NAME …>` element of a document, opening tag only.
rootEl(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
m=re.search(r"<"+sys.argv[2]+r"\b[^>]*>",d)
sys.stdout.write(m.group(0) if m else "")' "$1" "$2"; }

# one attribute's value out of an element string; "" when the attribute is absent.
attr(){ python3 -c '
import re,sys
m=re.search(sys.argv[2]+r"=\"([^\"]*)\"",sys.argv[1])
sys.stdout.write(m.group(1) if m else "")' "$1" "$2"; }

# the `<s …>` symbol row for name $2 out of a map, opening tag only; "" when the symbol is not indexed.
# The name is matched WHOLE (`n="dup"` is not `n="duplicate"`) — arm (11) proves that.
symRow(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
for r in re.findall(r"<s\b[^>]*>",d):
    if re.search(r"\bn=\""+re.escape(sys.argv[2])+r"\"",r):
        sys.stdout.write(r); break' "$1" "$2"; }

# the WHOLE `<s …>…</s>` element for name $2, children included. symRow() returns the opening tag only,
# which is right for the root attributes and WRONG for anything on a `<c>` child — reading prov="split"
# off the opening tag is a check that cannot fail, and arm (11) is what caught it.
symEl(){ python3 -c '
import re,sys
d=open(sys.argv[1]).read()
m=re.search(r"<s\b[^>]*\bn=\""+re.escape(sys.argv[2])+r"\"[^>]*>.*?</s>",d)
sys.stdout.write(m.group(0) if m else "")' "$1" "$2"; }

# Assert a capture is non-empty BEFORE anything is concluded from it.
nonempty(){ [ -n "$2" ] && return 0; no "$1 (empty capture — the arm reading it would have been vacuous)"; return 1; }

# ONE role arm: the live row must be there, the dead row must not. Both halves or the arm is vacuous.
# $1 label · $2 answer file · $3 live marker · $4 dead marker
roleArm(){
    local label="$1" file="$2" live="$3" dead="$4"
    local L D
    L="$( rows "$file" "$live" )"
    D="$( rows "$file" "$dead" )"
    if [ -z "$L" ]; then
        no "($label) control broken — the LIVE row ($live) is missing; the dead-row half would be vacuous"
    elif [ -n "$D" ]; then
        no "($label) a site inside a decided-dead range is served: $D"
    else
        ok "($label) live row present, dead row absent"
    fi
}

# ── corpora ───────────────────────────────────────────────────────────────────────────────────────────
# Built here, not committed: a committed .cpp fixture would also join every OTHER gate's view of test/,
# and this one carries `#if 0` blocks on purpose.
mkdir -p "$TMP/roles" "$TMP/inc" "$TMP/alt" "$TMP/defs"

# (1)-(7): one live/dead pair per role, all in one translation unit so the file-level `#if` text gate,
# the range walk and the per-role capture pass are all exercised by a single parse.
cat > "$TMP/roles/roles.cpp" <<'EOF'
#define STAMP(x) ((x) + 1)

namespace ns
{
void helper();
}

struct Widget
{
    int w;
};

struct Base
{
    int b;
};

struct Owner
{
    int field;
};

using ns::helper;
#if 0
using ns::helper;
#endif

int target(int x)
{
    return x + 1;
}

int liveCall(int x)
{
    return target(x);
}

int deadCall(int x)
{
    return 0;
#if 0
    return target(x);
#endif
}

int liveMacro(int x)
{
    return STAMP(x);
}

int deadMacro(int x)
{
    return 0;
#if 0
    return STAMP(x);
#endif
}

int liveRead(Owner& o)
{
    return o.field;
}

int deadRead(Owner& o)
{
    return 0;
#if 0
    return o.field;
#endif
}

void liveWrite(Owner& o)
{
    o.field = 1;
}

void deadWrite(Owner& o)
{
#if 0
    o.field = 2;
#endif
}

void liveType(Widget w)
{
    (void)w;
}

#if 0
void deadType(Widget w)
{
    (void)w;
}
#endif

struct LiveDerived : Base
{
    int d;
};

#if 0
struct DeadDerived : Base
{
    int d;
};
#endif
EOF

# (5b): the include directive's own role="import" site — a SECOND emitter of the role the tags branch
# already filtered, in its own corpus so the type named by the header is unambiguous.
cat > "$TMP/inc/Widget.h" <<'EOF'
#pragma once
struct Widget
{
    int w;
};
EOF
cat > "$TMP/inc/user.cpp" <<'EOF'
#include "Widget.h"
#if 0
#include "Widget.h"
#endif
int useIt(Widget& w)
{
    return w.w;
}
EOF

# (8): the other two decided shapes. `#if 1`'s ALTERNATIVE is dead; `#if 0`'s alternative is LIVE — so a
# range taken from the `#if` node rather than its alternative chain gets BOTH of these backwards while
# staying green on the plain `#if 0` bodies above.
cat > "$TMP/alt/alt.cpp" <<'EOF'
struct Gauge
{
    int level;
};

int elseOfIfOne(Gauge& g)
{
#if 1
    return g.level;
#else
    return g.level + altOnlyDead();
#endif
}

int elseOfIfZero(Gauge& g)
{
#if 0
    g.level = 41;
    return 0;
#else
    g.level = 42;
    return g.level;
#endif
}
EOF

# (12): the local var→type BINDING half. `x` is declared Bar inside `#if 0` and Foo live, so a build that
# keeps the dead binding cannot narrow `x.m()` and splits it across both `m` methods. The CONTROL is the
# same file with the `#if 0` block physically deleted — the answer the fixed build must reproduce — which
# is what makes this an arm about the dead range rather than about narrowing in general.
mkdir -p "$TMP/bind" "$TMP/bindctl"
cat > "$TMP/bind/b.cpp" <<'EOF'
struct Foo
{
    int m();
};

struct Bar
{
    int m();
};

int Foo::m() { return 1; }
int Bar::m() { return 2; }

int useIt()
{
#if 0
    Bar x;
#endif
    Foo x;
    return x.m();
}
EOF
sed '/^#if 0$/,/^#endif$/d' "$TMP/bind/b.cpp" > "$TMP/bindctl/b.cpp"

# (9): one name DEFINED twice — once inside `#if 0`, once live — and one caller. On a build that indexes
# the dead definition the caller's single call splits across two candidates.
cat > "$TMP/defs/dup.cpp" <<'EOF'
#if 0
int dup(int x)
{
    return x * 2;
}
#endif

int dup(int x)
{
    return x + 1;
}

int caller(int x)
{
    return dup(x);
}
EOF

# ── the answers, cold ─────────────────────────────────────────────────────────────────────────────────
# Every ripwire invocation in this gate goes through run() or warm(), and BOTH record the exit status.
# Discarding it is CONTRIBUTING.md §2 from the other side: each arm below reads a document, so a run that
# fails *after* writing a parseable one satisfies every string check in the file, and the gate certifies a
# filtered answer that an ingestion which did not finish happened to leave behind. Nothing downstream can
# see that — `--uses` output looks the same either way — so the status is the only witness there is.
# The answer file's basename goes in the report, because it is what names the arm about to read it.
# Arm (11) probes both helpers against a refused invocation, so this guard is one observed RED.
run(){
    local out="$1"; shift
    "$BIN" "$@" >"$out" 2>/dev/null
    local rc=$?
    [ "$rc" -eq 0 ] || no "ripwire exited $rc writing ${out##*/}: $*"
    return "$rc"
}
run "$TMP/a_call.xml"    "$TMP/roles" --no-cache --uses=roles.cpp:target
run "$TMP/a_macro.xml"   "$TMP/roles" --no-cache --uses=STAMP
run "$TMP/a_field.xml"   "$TMP/roles" --no-cache --uses=Owner.field
run "$TMP/a_using.xml"   "$TMP/roles" --no-cache --uses=helper
run "$TMP/a_extends.xml" "$TMP/roles" --no-cache --uses=Base
run "$TMP/a_type.xml"    "$TMP/roles" --no-cache --uses=Widget
run "$TMP/a_map.xml"     "$TMP/roles" --no-cache
run "$TMP/a_inc.xml"     "$TMP/inc"   --no-cache --uses=Widget
run "$TMP/a_alt.xml"     "$TMP/alt"   --no-cache --uses=Gauge.level
run "$TMP/a_defs.xml"    "$TMP/defs"  --no-cache
run "$TMP/a_callers.xml" "$TMP/defs"  --no-cache --callers=dup

echo
echo "=== (1)-(7) one live/dead pair per --uses role ==="
nonempty "(1) no <uses> root element for target" "$( rootEl "$TMP/a_call.xml" uses )" \
    && roleArm 1-call    "$TMP/a_call.xml"    'in_id="liveCall"'  'in_id="deadCall"'
nonempty "(2) no <uses> root element for STAMP" "$( rootEl "$TMP/a_macro.xml" uses )" \
    && roleArm 2-macro   "$TMP/a_macro.xml"   'in_id="liveMacro"' 'in_id="deadMacro"'
nonempty "(3)(4) no <uses> root element for Owner.field" "$( rootEl "$TMP/a_field.xml" uses )" && {
    roleArm 3-read       "$TMP/a_field.xml"   'in_id="liveRead"'  'in_id="deadRead"'
    roleArm 4-write      "$TMP/a_field.xml"   'in_id="liveWrite"' 'in_id="deadWrite"'
    # and the COUNT the floor contract is about: exactly the two live sites, never four.
    NF="$( attr "$( rootEl "$TMP/a_field.xml" uses )" count )"
    [ "$NF" = "2" ] && ok "(3)(4) --uses=Owner.field count=\"2\" — the two live sites, floor intact" \
                    || no "(3)(4) --uses=Owner.field count=\"$NF\", expected 2 (counts_floor=\"1\" promises true >= reported)"
}
# (5a) the tags branch's import: two `using ns::helper;`, one of them dead. The live one is at file
# scope and carries no in_id=, so the halves are told apart by LINE.
nonempty "(5a) no <uses> root element for helper" "$( rootEl "$TMP/a_using.xml" uses )" \
    && roleArm 5a-import-using "$TMP/a_using.xml" 'p="roles.cpp:23"' 'p="roles.cpp:25"'
# (5b) captureIncludes' import: the live `#include` is line 1, the dead one line 3.
nonempty "(5b) no <uses> root element for the included Widget" "$( rootEl "$TMP/a_inc.xml" uses )" \
    && roleArm 5b-import-include "$TMP/a_inc.xml" 'role="import" p="user.cpp:1"' 'role="import" p="user.cpp:3"'
nonempty "(6) no <uses> root element for Base" "$( rootEl "$TMP/a_extends.xml" uses )" \
    && roleArm 6-extends "$TMP/a_extends.xml" 'LiveDerived' 'DeadDerived'
nonempty "(7) no <uses> root element for Widget" "$( rootEl "$TMP/a_type.xml" uses )" \
    && roleArm 7-type    "$TMP/a_type.xml"    'in_id="liveType"' 'in_id="deadType"'

echo
echo "=== (8) the #else arms — \`#if 1\`'s alternative is dead, \`#if 0\`'s alternative is LIVE ==="
if nonempty "(8) no <uses> root element for Gauge.level" "$( rootEl "$TMP/a_alt.xml" uses )"; then
    # `#if 1` body (line 9) LIVE · its `#else` (line 11) DEAD
    roleArm 8a-else-of-if-1 "$TMP/a_alt.xml" 'p="alt.cpp:9"'  'p="alt.cpp:11"'
    # `#if 0` body (lines 18,19) DEAD · its `#else` (lines 21,22) LIVE — the direction a range taken
    # from the `#if` node instead of its alternative chain gets backwards.
    roleArm 8b-else-of-if-0 "$TMP/a_alt.xml" 'p="alt.cpp:21"' 'p="alt.cpp:18"'
fi

echo
echo "=== (9) a definition inside \`#if 0\` is not indexed and cannot split resolution ==="
S_DUP="$( symRow "$TMP/a_defs.xml" dup )"
S_CALLER="$( symRow "$TMP/a_defs.xml" caller )"
R_CALLERS="$( rootEl "$TMP/a_callers.xml" callers )"
if nonempty "(9) no <s n=\"dup\"> row" "$S_DUP" && nonempty "(9) no <s n=\"caller\"> row" "$S_CALLER" \
   && nonempty "(9) no <callers> root element" "$R_CALLERS"; then
    # the live definition and its one caller are PRESENT — without this the three absence checks below
    # would all pass on an empty map.
    N_CALL="$( attr "$R_CALLERS" count )"
    [ "$N_CALL" = "1" ] && ok "(9) control: the live dup and its one caller are indexed (count=\"1\")" \
                        || no "(9) control broken — <callers of=\"dup\"> count=\"$N_CALL\", expected 1"
    OV="$( attr "$S_DUP" overloads )"
    [ -z "$OV" ] && ok "(9) no overloads= on dup — the dead definition is not merged into the live row" \
                 || no "(9) dup carries overloads=\"$OV\": a definition inside \`#if 0\` is still indexed"
    AM="$( attr "$S_CALLER" amb )"
    [ -z "$AM" ] && ok "(9) no amb= on caller — the one call is not ambiguous" \
                 || no "(9) caller carries amb=\"$AM\": the resolver is guessing against a definition that cannot compile"
    E_CALLER="$( symEl "$TMP/a_defs.xml" caller )"
    if nonempty "(9) no <s n=\"caller\">…</s> element" "$E_CALLER"; then
        case "$E_CALLER" in
            *'prov="split"'*) no "(9) caller's call carries prov=\"split\" against a dead definition" ;;
            *)                ok "(9) no prov=\"split\" on the call — one candidate, no split" ;;
        esac
        # the call edge itself must still be there, or the absence of prov= means only that the edge is gone.
        case "$E_CALLER" in
            *'<c n="dup"'*) ok "(9) control: the live call edge caller -> dup survives" ;;
            *)              no "(9) control broken — caller has no <c n=\"dup\"> edge at all" ;;
        esac
    fi
    GA="$( attr "$R_CALLERS" graph_ambiguous )"
    DF="$( attr "$R_CALLERS" defs )"
    [ "$GA" = "0" ] && ok "(9) <callers of=\"dup\"> graph_ambiguous=\"0\"" \
                    || no "(9) <callers of=\"dup\"> graph_ambiguous=\"$GA\", expected 0"
    [ "$DF" = "1" ] && ok "(9) <callers of=\"dup\"> defs=\"1\" — one compilable definition of the name" \
                    || no "(9) <callers of=\"dup\"> defs=\"$DF\", expected 1"
fi
# the same rule on the roles corpus: a dead function and a dead struct are absent, their live twins present.
for pair in liveType:deadType LiveDerived:DeadDerived; do
    LIVE="${pair%%:*}"; DEAD="${pair##*:}"
    LR="$( symRow "$TMP/a_map.xml" "$LIVE" )"; DR="$( symRow "$TMP/a_map.xml" "$DEAD" )"
    if [ -z "$LR" ]; then
        no "(9) control broken — $LIVE is missing from the map; the $DEAD absence check would be vacuous"
    elif [ -n "$DR" ]; then
        no "(9) $DEAD is indexed although it is defined inside \`#if 0\`: $DR"
    else
        ok "(9) $LIVE indexed, $DEAD absent"
    fi
done

echo
echo "=== (12) a local var→type binding inside \`#if 0\` does not blur receiver narrowing ==="
run "$TMP/a_bind.xml"    "$TMP/bind"    --no-cache
run "$TMP/a_bindctl.xml" "$TMP/bindctl" --no-cache
E_USE="$( symEl "$TMP/a_bind.xml" useIt )"
E_CTL="$( symEl "$TMP/a_bindctl.xml" useIt )"
if nonempty "(12) no <s n=\"useIt\"> in the fixture" "$E_USE" && nonempty "(12) no <s n=\"useIt\"> in the control" "$E_CTL"; then
    # the control states what the source means: one call edge, no ambiguity. If the control ever stops
    # saying that, the comparison below is measuring something else and must not be believed.
    case "$E_CTL" in
        *'amb='*|*'prov="split"'*) no "(12) control broken — the dead block DELETED still splits: $E_CTL" ;;
        *'<c n="m"'*)              ok "(12) control: with the dead block deleted, x.m() resolves to one edge" ;;
        *)                         no "(12) control broken — the control has no call edge at all: $E_CTL" ;;
    esac
    case "$E_USE" in
        *'amb='*)          no "(12) the dead \`Bar x;\` still blurs narrowing: $E_USE" ;;
        *'prov="split"'*)  no "(12) the dead \`Bar x;\` still splits the call: $E_USE" ;;
        *'<c n="m"'*)      ok "(12) with the dead block PRESENT the answer matches the control" ;;
        *)                 no "(12) the call edge vanished entirely: $E_USE" ;;
    esac
fi

echo
echo "=== (10) WARM == COLD — the cache record replays the filtered set ==="
XDG="$TMP/xdg"; mkdir -p "$XDG/ripwire"
warm(){
    local out="$1"; shift
    env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$@" >"$out" 2>/dev/null
    local rc=$?
    [ "$rc" -eq 0 ] || no "ripwire exited $rc writing ${out##*/}: $*"
    return "$rc"
}
wfail=0
for probe in "roles --uses=Owner.field:w_field" "roles --uses=Widget:w_type" "roles --uses=Base:w_extends" \
             "roles :w_map" "inc --uses=Widget:w_inc" "alt --uses=Gauge.level:w_alt" "defs :w_defs" \
             "bind :w_bind"; do
    spec="${probe%%:*}"; tag="${probe##*:}"
    corpus="${spec%% *}"; verb="${spec#* }"
    [ "$verb" = "$corpus" ] && verb=""
    # warm() reports the exit status itself; the caller ties it to the arm and skips a comparison whose
    # two sides are no longer a cold answer and its replay.
    # shellcheck disable=SC2086
    warm "$TMP/$tag.cold" "$TMP/$corpus" $verb \
        || { no "(10) $tag: the cache-populating run failed — the replay has nothing to replay"; wfail=1; continue; }
    # shellcheck disable=SC2086
    warm "$TMP/$tag.warm" "$TMP/$corpus" $verb \
        || { no "(10) $tag: the replay run failed"; wfail=1; continue; }
    [ -s "$TMP/$tag.cold" ] || { no "(10) $tag: the cold answer is empty — the comparison would be vacuous"; wfail=1; continue; }
    cmp -s "$TMP/$tag.cold" "$TMP/$tag.warm" || { no "(10) $tag: warm output differs from cold"; wfail=1; }
done
# The arm above compares two runs, not necessarily a cold run and a WARM one: with caching disabled for
# any reason both sides are cold parses and the comparison degrades into the determinism gate. So assert
# the cache directory actually holds a record — this is what makes (10) a cache-format arm.
NBLOB="$( find "$XDG/ripwire" -type f -name 'ripwire-*' 2>/dev/null | wc -l | tr -d ' ' )"
[ "${NBLOB:-0}" -gt 0 ] || { no "(10) no cache record was written — the warm side was a second cold parse"; wfail=1; }
[ "$wfail" -eq 0 ] && ok "(10) warm == cold, byte for byte, on every corpus with dead ranges ($NBLOB cache records)"

echo
echo "=== (11) MUTATION — every reader above, and both ripwire invokers, are shown able to fire ==="
printf '<uses of="x" count="2"><u role="write" p="c.cpp:7" in_id="liveWrite"/><u role="write" p="c.cpp:12" in_id="deadWrite"/></uses>' >"$TMP/m_rows.xml"
[ -n "$( rows "$TMP/m_rows.xml" 'in_id="deadWrite"' )" ] \
    && ok "(11) rows(): a served dead row IS detected" \
    || no "(11) rows() cannot see a dead row that is present — every role arm's dead half is inert"
[ -z "$( rows "$TMP/m_rows.xml" 'in_id="deadRead"' )" ] \
    && ok "(11) rows(): returns empty for a marker the document does not carry" \
    || no "(11) rows() matched a marker the document does not carry"
printf '<r><f p="c.cpp"><s t="fn" n="dup" overloads="2" k="0.1"></s><s t="fn" n="caller" amb="1" k="0.1"><c n="dup" prov="split"/></s></f></r>' >"$TMP/m_sym.xml"
MS="$( symRow "$TMP/m_sym.xml" dup )"; MC="$( symRow "$TMP/m_sym.xml" caller )"
[ "$( attr "$MS" overloads )" = "2" ] \
    && ok "(11) symRow()+attr(): an overloads= that IS present is detected" \
    || no "(11) the (9) overloads= reader cannot see an attribute that is present"
[ "$( attr "$MC" amb )" = "1" ] \
    && ok "(11) symRow()+attr(): an amb= that IS present is detected" \
    || no "(11) the (9) amb= reader cannot see an attribute that is present"
ME="$( symEl "$TMP/m_sym.xml" caller )"
case "$ME" in
    *'prov="split"'*) ok '(11) symEl(): a prov="split" that IS present is detected' ;;
    *)                no '(11) the (9) prov="split" reader cannot see a split that is present' ;;
esac
case "$MC" in
    *'prov="split"'*) no '(11) symRow() reaches a child attribute — the (9) split check must read symEl()' ;;
    *)                ok '(11) symRow() is opening-tag only, which is why (9) reads the split off symEl()' ;;
esac
[ -z "$( symRow "$TMP/m_sym.xml" deadType )" ] \
    && ok "(11) symRow(): returns empty for a symbol the map does not carry" \
    || no "(11) symRow() matched a symbol the map does not carry"
# and symRow must not match a name by PREFIX — `dup` and `duplicate` are different symbols.
printf '<r><f p="c.cpp"><s t="fn" n="duplicate" k="0.1"></s></f></r>' >"$TMP/m_pfx.xml"
[ -z "$( symRow "$TMP/m_pfx.xml" dup )" ] \
    && ok "(11) symRow(): n=\"duplicate\" is not read as n=\"dup\"" \
    || no "(11) symRow() matches a symbol name by prefix"
# the vacuity guard itself. Run in a subshell so it cannot set fail.
if ( nonempty "probe" "" >/dev/null 2>&1 ); then
    no "(11) nonempty() accepts an empty capture — every arm's vacuity guard is inert"
else
    ok "(11) vacuity guard: nonempty() rejects an empty capture"
fi
# the EXIT-STATUS guard, on both invokers and in both directions. A ripwire run that fails after writing
# a parseable document satisfies every reader above, so run()/warm() discarding the status is the same
# defect as a reader that cannot see — and a guard that only ever runs against a binary which succeeds has
# never been shown to have a failing state. Each helper is probed through a command substitution, so the
# FAIL line the refused half provokes is captured here instead of reaching this shell's `fail`.
# $1 = the invoker's name, called as a function.
statusGuard(){
    local helper="$1" bad good badrc goodrc
    bad="$( "$helper" "$TMP/m_${helper}_bad.xml" "$TMP/roles" --no-cache --ppdeadroles-not-a-flag )"; badrc=$?
    good="$( "$helper" "$TMP/m_${helper}_ok.xml"  "$TMP/roles" --no-cache --uses=Widget )";           goodrc=$?
    if [ "$badrc" -eq 0 ]; then
        no "(11) $helper() returns 0 for an invocation ripwire refused — every answer it writes is unguarded"
    else
        case "$bad" in
            *'  FAIL  '*) ok "(11) $helper(): a non-zero ripwire exit IS recorded, not discarded" ;;
            *)            no "(11) $helper() returns $badrc for a refused invocation but records no FAIL line" ;;
        esac
    fi
    if [ "$goodrc" -ne 0 ]; then
        no "(11) $helper() returns $goodrc for the same invocation arm (7) reads — the guard has no contrast"
    elif [ -n "$good" ]; then
        no "(11) $helper() reports on an invocation that exited 0: $good"
    else
        ok "(11) $helper(): a succeeding invocation returns 0 and says nothing — the guard has contrast"
    fi
}
statusGuard run
statusGuard warm

echo
[ "$fail" -eq 0 ] && { echo "ppdeadrolescheck: ALL PASS"; exit 0; }
echo "ppdeadrolescheck: FAILURES"; exit 1
