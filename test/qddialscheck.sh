#!/usr/bin/env bash
# qddialscheck.sh — the per-kind DIALS of --quality-delta (round 2026-09-10, audit lane Q1's dial table).
#
# Q1 measured the verb on three labelled populations — 12 working-tree replays of landed commits, 40 ref-pair
# replays, and a 15-case synthetic battery — and found the precision problem concentrated in a few kinds while
# the recall headroom sat in others. Each section below is ONE dial, with the case that must stay caught beside
# the case that must stop firing, so a later change cannot quietly restore either half:
#
#   1. short-horizon-churn — churn="self" is informational; GATING needs >= 2 COMMITTED in-window commits on
#      the edited lines (the working edit never counted).
#   2. dead-code — the blanket .h/.hpp/.hh/.hxx exclusion is gone; what is exempt is what the LANGUAGE invokes
#      (constructors, destructors, operators, bare type declarations, main).
#   3. verbosity/complexity — verbosity counts CODE lines (blank and comment lines are not debt); both kinds
#      gate on a bar CROSSING or >= 25% growth, and a sub-bar doubling is a minor row rather than silence.
#   4. api-surface — new-symbol rows are a header COUNT, a surface that SHRANK is not a regression, and a
#      single trailing DEFAULTED parameter is minor.
#   5. duplication / new-clone-of-reused-helper — an overload set and a vendored path are not this change's
#      duplication; a same-file copy IS, which is why the audit's one-file drop was withdrawn.
#   6. error-masking — a block whose only content is a COMMENT is a swallow.
#
# Fixtures are built in temp dirs (git-init where a section needs history); the repo is never touched.
# Usage:  RIPWIRE_BIN=build/ripwire bash test/qddialscheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # BOTH seams: positional AND env (a red-first run hands the pre-change binary in)
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qddialscheck (git not available)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "qddialscheck: BIN=$BIN  (temp corpora)"

# One emitted row, as its own line. The document is newline-free (G4), and a row's own attributes carry
# both '/' (p="path:line") and '"' — so a single-line grep with a character class is the wrong tool and
# silently matched the wrong row when it was tried. Split on '>' first, then match the whole row.
row(){ printf '%s' "$1" | tr '>' '\n' | grep "kind=\"$2\" sym=\"$3\"" ; }
rows(){ printf '%s' "$1" | tr '>' '\n' | grep '<r ' ; }

# ── 1) short-horizon-churn: SELF is informational, TWO committed in-window rewrites gate ─────────────────
# One file, two multi-line functions, and a history built so the two differ ONLY in how many COMMITTED
# in-window commits wrote the lines the working edit touches:
#   c0, backdated 200 days (OUTSIDE the 14-day window)  — both functions written.
#   c1, now — rewrites once() line 1 AND twice() line 1.
#   c2, now — rewrites twice() line 2.
#   working tree — rewrites BOTH lines of BOTH functions.
# once():  edited lines blame to {c1 (in), c0 (out)} → ONE in-window commit → churn="self", informational.
# twice(): edited lines blame to {c1, c2}            → TWO in-window commits → the rewrite thrash that gates.
CH="$WORK/churn"; mkdir -p "$CH/src"
( cd "$CH" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false )
wr(){ printf 'int once(){\n    int a = %s;\n    int b = %s;\n    return a + b;\n}\nint twice(){\n    int c = %s;\n    int d = %s;\n    return c + d;\n}\nint drive(){ return once() + twice(); }\n' "$1" "$2" "$3" "$4" > "$CH/src/f.cpp"; }
cm(){ ( cd "$CH" && git add -A >/dev/null 2>&1 && GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git commit -qm "$2" >/dev/null 2>&1 ); }
OLD="$( date -u -r $(( $( date +%s ) - 200*86400 )) +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '200 days ago' +%Y-%m-%dT%H:%M:%S )"
NOW="$( date -u +%Y-%m-%dT%H:%M:%S )"
wr 1 2 3 4      ; cm "$OLD" c0
wr 11 2 33 4    ; cm "$NOW" c1
wr 11 2 33 44   ; cm "$NOW" c2
wr 111 222 333 444
OCH="$( cd "$CH" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
ECH="$( cd "$CH" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
row "$OCH" short-horizon-churn twice | grep -q 'gating="1"' \
    && ok "churn: twice() GATES (two committed in-window rewrites of the edited lines)" \
    || { no "churn: twice() must still gate — the thrash signal was not preserved"; rows "$OCH"; }
row "$OCH" short-horizon-churn once >/dev/null \
    && ok "churn: once() still REPORTED (the kind stays informational, not deleted)" \
    || { no "churn: once() row disappeared — the dial demotes, it does not drop"; rows "$OCH"; }
row "$OCH" short-horizon-churn once | grep -q 'gating="1"' \
    && { no "churn: once() must NOT gate — ONE in-window commit is a touch, not thrash (this is the dial)"; rows "$OCH"; } \
    || ok "churn: once() does not gate (one in-window commit is informational)"
row "$OCH" short-horizon-churn once | grep -q 'sev="minor"' \
    && ok "churn: once() carries sev=minor" \
    || no "churn: once() should be sev=minor"
if [ "$ECH" = 2 ]; then ok "churn: exit 2 (the gating twice() row fires it)"; else no "churn: expected exit 2, got $ECH"; fi
[ "$OCH" = "$( cd "$CH" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ] \
    && ok "churn: byte-identical run to run (deterministic)" || no "churn: non-deterministic delta"

# ── 2) dead-code: the header exclusion is gone; what is exempt is what the LANGUAGE invokes ──────────────
# The kind used to answer false for ANY symbol in a .h/.hpp/.hh/.hxx file ("header-exported by convention"),
# which on this header-only codebase hid 96.8% of src from it — synthetic S6 (the sole caller of a header
# function deleted) was silently missed. The proxy is replaced by the rule it stood for: a symbol the
# language itself invokes has no named call site for the graph to record, so zero in-edges says nothing.
#
# Two arms, both red on the pre-change binary and for opposite reasons:
#   the header function that LOSES its last caller must now be reported (recall);
#   the constructor / destructor / operator / bare type the working tree ADDS must not be (precision) —
#   before the dial those were only silent because they sat in a header, and in a .cpp they were reported.
DC="$WORK/dead"; mkdir -p "$DC/src"
( cd "$DC" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false )
printf 'inline int usedHelper(){ return 41; }\n' > "$DC/src/lib.hpp"
cat > "$DC/src/m.cpp" <<'CPP'
#include "lib.hpp"
struct Thing {
    Thing() { value = 1; }
    ~Thing() { value = 0; }
    bool operator==( const Thing& o ) const { return value == o.value; }
    int value;
};
int driver(){ return usedHelper(); }
int main(){ Thing t; return driver() + t.value; }
CPP
( cd "$DC" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )
# the working edit: driver() stops calling usedHelper (S6 — the sole caller deleted), and a brand-new type
# arrives whose ctor, dtor and operator have no named caller anywhere.
python3 - "$DC/src/m.cpp" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("int driver(){ return usedHelper(); }","""struct Extra {
    Extra() { n = 2; }
    ~Extra() { n = 0; }
    bool operator<( const Extra& o ) const { return n < o.n; }
    int n;
};
int driver(){ return 41; }""")
open(p,"w").write(s)
PY
ODC="$( cd "$DC" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
row "$ODC" dead-code usedHelper >/dev/null \
    && ok "dead-code: a HEADER function that lost its sole caller is reported (synthetic S6)" \
    || { no "dead-code: usedHelper not reported — the header exclusion still hides the kind"; rows "$ODC"; }
DEADROWS="$( rows "$ODC" | grep -c 'kind="dead-code"' )"
# One match on the whole family: the ctor and dtor BOTH index as Extra::Extra (the parser keeps no leading
# tilde) and the operator arrives XML-escaped as operator&lt;, so naming them one by one greps for spellings
# that never appear. Anything under the new type is a language-invoked symbol and must not be a row.
rows "$ODC" | grep 'kind="dead-code"' | grep -q 'Extra' \
    && { no "dead-code: a language-invoked member of Extra reported (ctor/dtor/operator/type)"; rows "$ODC" | grep 'kind="dead-code"'; } \
    || ok "dead-code: no ctor/dtor/operator/type row for the new Extra type (the language invokes them)"
[ "$DEADROWS" = 1 ] && ok "dead-code: exactly ONE dead-code row on this fixture (only usedHelper)" \
    || { no "dead-code: expected 1 dead-code row, got $DEADROWS"; rows "$ODC" | grep 'kind="dead-code"'; }
[ "$ODC" = "$( cd "$DC" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ] \
    && ok "dead-code: byte-identical run to run (deterministic)" || no "dead-code: non-deterministic delta"


# ── 3) verbosity counts CODE lines; verbosity + complexity gate on a CROSSING or >= 25% growth ───────────
# Q1 measured the median growth of a GATING verbosity row at 6% and of a gating complexity row at 6%, while
# 60 pure BLANK lines added to an 18-LOC body produced `was="18" now="78"`, gating, exit 2. Both halves are
# fixed here: the metric stops counting blank and comment-only lines, and the severity asks how much this
# change ADDED rather than only where the number landed. One fixture, one working edit, six shapes.
VB="$WORK/verb"; mkdir -p "$VB/src"
( cd "$VB" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false )
gen(){ python3 - "$VB/src/v.cpp" "$1" <<'PY'
import sys
p, stage = sys.argv[1], sys.argv[2]
def body(n):                       # n CODE lines inside the braces
    return "".join("    x += %d;\n" % (i % 7 + 1) for i in range(n))
def ifs(n):                        # n sequential ifs at depth 0 => cognitive complexity n
    return "".join("    if( x == %d ) { x += 1; }\n" % i for i in range(n))
after = stage == "after"
out = []
out.append("int blankGrow( int x ){\n" + body(10) + ("\n"*60 if after else "") + "    return x;\n}\n")
out.append("int commentGrow( int x ){\n" + body(10) + ("".join("    // note %d\n" % i for i in range(60)) if after else "") + "    return x;\n}\n")
out.append("int crosser( int x ){\n" + body(70 if after else 50) + "    return x;\n}\n")
out.append("int chronic( int x ){\n" + body(210 if after else 200) + "    return x;\n}\n")
out.append("int doubler( int x ){\n" + body(45 if after else 20) + "    return x;\n}\n")
out.append("int cxDoubler( int x ){\n" + ifs(13 if after else 5) + "    return x;\n}\n")
out.append("int cxChronic( int x ){\n" + ifs(33 if after else 30) + "    return x;\n}\n")
out.append("int cxCrosser( int x ){\n" + ifs(20 if after else 10) + "    return x;\n}\n")
open(p, "w").write("".join(out))
PY
}
gen before
( cd "$VB" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )
gen after
OVB="$( cd "$VB" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
vrow(){ row "$OVB" "$1" "$2"; }
# (a) BLANK and COMMENT lines are not debt — the two synthetics that gated before.
for f in blankGrow commentGrow; do
    vrow verbosity "$f" >/dev/null \
        && { no "verbosity: $f reported — blank/comment lines are still counted as debt"; vrow verbosity "$f"; } \
        || ok "verbosity: $f produces no row (60 blank/comment lines are not code)"
done
# (b) a CROSSING still gates, on both kinds — the shape commit 65d98b76 was written to clear.
vrow verbosity crosser | grep -q 'gating="1"' \
    && ok "verbosity: crosser 50 -> 70 code lines CROSSES the bar and gates" \
    || { no "verbosity: a bar crossing must still gate"; vrow verbosity crosser; }
vrow complexity cxCrosser | grep -q 'gating="1"' \
    && ok "complexity: cxCrosser ccx 10 -> 20 CROSSES the bar and gates" \
    || { no "complexity: a bar crossing must still gate"; vrow complexity cxCrosser; }
# (c) over the bar but grew under 25% — a real row, printed, minor, not gating.
vrow verbosity chronic | grep -q 'sev="minor"' \
    && ok "verbosity: chronic 200 -> 210 (+5%) is sev=minor, not a gate" \
    || { no "verbosity: +5% on an already-huge body must not gate"; vrow verbosity chronic; }
vrow complexity cxChronic | grep -q 'sev="minor"' \
    && ok "complexity: cxChronic 30 -> 33 (+10%) is sev=minor, not a gate" \
    || { no "complexity: +10% on an already-complex body must not gate"; vrow complexity cxChronic; }
# (d) UNDER the bar, a doubling is a minor row instead of silence (synthetics S4b / S8-sub-bar).
vrow verbosity doubler | grep -q 'sev="minor"' \
    && ok "verbosity: doubler 20 -> 45 code lines (under the bar, +125%) is a minor row" \
    || { no "verbosity: a sub-bar doubling should be a minor row (S4b)"; vrow verbosity doubler; }
vrow complexity cxDoubler | grep -q 'sev="minor"' \
    && ok "complexity: cxDoubler ccx 5 -> 13 (under the bar, +160%) is a minor row" \
    || { no "complexity: a sub-bar doubling should be a minor row (S8)"; vrow complexity cxDoubler; }
vrow verbosity doubler | grep -q 'gating="1"' \
    && no "verbosity: a sub-bar row must never gate — nothing is over the bar yet" \
    || ok "verbosity: the sub-bar row does not gate"
# bar= semantics are unchanged: it still names the kind's own threshold.
if vrow verbosity crosser | grep -q 'bar="60"'; then ok "verbosity: bar=60 unchanged"; else no "verbosity: bar= moved"; fi
if vrow complexity cxCrosser | grep -q 'bar="15"'; then ok "complexity: bar=15 unchanged"; else no "complexity: bar= moved"; fi
[ "$OVB" = "$( cd "$VB" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ] \
    && ok "verbosity/complexity: byte-identical run to run (deterministic)" || no "verbosity/complexity: non-deterministic delta"


# ── 4) api-surface: a count for new exports, no row for a SMALLER surface, one row per fact ──────────────
# 103 of 119 api-surface rows over 40 replayed commits carried origin="new-symbol", which the legend itself
# says can never gate — and 193 of the 1,177 rows in this repo's committed ack ledger are that shape, acked
# by hand one at a time. Three more findings from the same replay: three rows reported an arity DROP as a
# regression in a document whose first sentence is "only what a change made WORSE"; 113 of 132 api-surface
# acks say "one trailing DEFAULTED parameter, every existing caller compiles unchanged"; and one parameter
# change emitted TWO rows, under `params` and again under `api-surface`.
AP="$WORK/api"; mkdir -p "$AP/src"
( cd "$AP" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false )
apigen(){ python3 - "$AP/src" "$1" <<'PY'
import sys, os
d, stage = sys.argv[1], sys.argv[2]
after = stage == "after"
h = []
h.append("inline int shrink( int a, int b%s ){ return a + b%s; }\n" % ("" if after else ", int c", "" if after else " + c"))
h.append("inline int defaulted( int a%s ){ return a%s; }\n" % (", int b = 0" if after else "", " + b" if after else ""))
h.append("inline int wide( int a, int b, int c, int d, int e%s ){ return a+b+c+d+e%s; }\n"
         % (", int f, int g" if after else "", "+f+g" if after else ""))
if after:
    h.append("inline int fresh( int a ){ return a + 1; }\n")
open(os.path.join(d, "api.hpp"), "w").write("".join(h))
m = ['#include "api.hpp"\n', "int driver(){\n",
     "    return shrink( 1, 2%s ) + defaulted( 3 ) + wide( 1,2,3,4,5%s )%s;\n" % ("" if after else ", 3", "" if after else "", " + fresh( 9 )" if after else ""),
     "}\n", "int main(){ return driver(); }\n"]
open(os.path.join(d, "m.cpp"), "w").write("".join(m))
PY
}
apigen before
( cd "$AP" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )
apigen after
OAP="$( cd "$AP" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
row "$OAP" api-surface shrink >/dev/null \
    && { no "api-surface: shrink 3 -> 2 params reported — a SMALLER surface is not what a change made worse"; rows "$OAP"; } \
    || ok "api-surface: an arity DROP produces no row"
row "$OAP" api-surface defaulted | grep -q 'sev="minor"' \
    && ok "api-surface: one trailing DEFAULTED parameter is sev=minor (callers still compile)" \
    || { no "api-surface: a trailing defaulted parameter should be minor"; rows "$OAP"; }
APIWIDE="$( rows "$OAP" | grep -c 'sym="wide"' )"
[ "$APIWIDE" = 1 ] && ok "api-surface: wide 5 -> 7 params emits ONE row, not one per kind" \
    || { no "api-surface: expected 1 row for wide, got $APIWIDE (params + api-surface both fired)"; rows "$OAP" | grep 'sym="wide"'; }
rows "$OAP" | grep -q 'kind="params" sym="wide"' \
    && ok "api-surface: the surviving row is the params one (77% precision, the kind that keeps the fact)" \
    || { no "api-surface: the params row must be the one that survives"; rows "$OAP" | grep 'sym="wide"'; }
row "$OAP" api-surface fresh >/dev/null \
    && { no "api-surface: a brand-new export is still a row — it can never gate, so it is a count"; rows "$OAP"; } \
    || ok "api-surface: a brand-new export produces no row"
printf '%s' "$OAP" | grep -q 'api-new-surface="1"' \
    && ok "api-surface: the root carries api-new-surface=\"1\" (nothing is hidden, it is counted)" \
    || { no "api-surface: api-new-surface= missing or wrong on the root"; printf '%s' "$OAP" | head -c 200; }
[ "$OAP" = "$( cd "$AP" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ] \
    && ok "api-surface: byte-identical run to run (deterministic)" || no "api-surface: non-deterministic delta"


# ── 5) duplication: an overload set, one file, and vendored upstream are not this change's copies ────────
# 11 gating duplication rows over 40 replayed commits, 0% precision: overload pairs (emitTo|emitTo,
# sort::stable|sort::stable), sibling implementations inside one body of code (mergeHi|mergeLo,
# gallopLeft|gallopRight), and one commit's 9 rows against vendored upstream. The cross-file copy of a real
# helper — synthetic S1, the shape these kinds exist for — must survive all three drops.
DP="$WORK/dup"; mkdir -p "$DP/src" "$DP/src/infra" "$DP/external"
( cd "$DP" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false )
# FOUR DISTINCT SHAPES, one per case. The clone matcher normalizes identifiers, so four copies of one body
# collapse into a SINGLE six-member group and no per-case assertion can separate them — the first draft of
# this fixture did exactly that and every arm was vacuous. Each shape below differs STRUCTURALLY (different
# statements, different control flow), so each case forms its own two-member group.
clonebody(){ python3 - "$1" "$2" <<'PY'
import sys
name, shape = sys.argv[1], sys.argv[2]
bodies = {
 "1": "    int acc = 0;\n    for( int i = 0; i < n; ++i ) {\n        if( i % 3 == 0 ) { acc += i * 2; }\n        else if( i % 5 == 0 ) { acc -= i; }\n        else { acc += 1; }\n    }\n    if( acc < 0 ) { acc = 0; }\n    return acc;\n",
 "2": "    int total = n;\n    while( total > 1 ) {\n        total = total / 2;\n        total = total + 7;\n        if( total > 900 ) { break; }\n    }\n    for( int k = 0; k < 4; ++k ) { total ^= k; }\n    return total;\n",
 "3": "    int r = 1;\n    switch( n % 4 ) {\n        case 0: r = n + 11; break;\n        case 1: r = n - 11; break;\n        case 2: r = n * 3; break;\n        default: r = n / 2; break;\n    }\n    do { r += 5; } while( r < 0 );\n    return r;\n",
 "4": "    int q = 0;\n    for( int a = 0; a < n; ++a ) {\n        for( int b = 0; b < a; ++b ) { q += a * b; }\n    }\n    q = q > 1000 ? 1000 : q;\n    q = q - ( n % 17 );\n    return q;\n",
}
print( "int %s( int n ){\n%s}" % (name, bodies[shape]) )
PY
}
clonebody alpha 1 > "$DP/src/a.cpp"
clonebody sameA 2 > "$DP/src/same.cpp"
clonebody vendA 3 > "$DP/external/v1.cpp"
clonebody cfgA  4 > "$DP/src/infra/w1.hpp"
printf 'int drive(){ return alpha(1) + sameA(1) + vendA(1) + cfgA(1); }\n' > "$DP/src/drive.cpp"
( cd "$DP" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )
# the working edit: four copies, one per shape.
clonebody beta  1 > "$DP/src/b.cpp"                       # CROSS-FILE — must still be reported
clonebody sameB 2 >> "$DP/src/same.cpp"                  # same file
clonebody vendB 3 > "$DP/external/v2.cpp"                # both members vendored by the built-in convention
clonebody cfgB  4 > "$DP/src/infra/w2.hpp"               # vendored only if .ripwire_config says so
ODP="$( cd "$DP" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
dup(){ rows "$ODP" | grep 'kind="duplication"' | grep "$1"; }
dup 'alpha' >/dev/null && ok "duplication: the CROSS-FILE copy is still reported (synthetic S1's shape)" \
    || { no "duplication: the cross-file copy was dropped — the dial cut a true positive"; rows "$ODP" | grep duplication; }
# THE ONE-FILE DROP WAS WITHDRAWN, and this arm is what it was withdrawn in favour of: a copy-pasted body is
# duplication wherever it lands. test/clonededupcheck.sh and test/qualitycheck.sh §3 both pin exactly this
# shape, deliberately, and a hand rule in the audit's labelling script does not outrank two gates.
dup 'sameA' >/dev/null \
    && ok "duplication: a same-file copy is STILL reported (the one-file drop was withdrawn)" \
    || { no "duplication: the same-file copy was dropped — clonededupcheck and qualitycheck pin this shape"; rows "$ODP" | grep duplication; }
# NON-VACUITY, checked rather than assumed: three of the four built-in prefixes (third_party/, vendor/,
# node_modules/) are already dropped by the CRAWLER, so a fixture placed there would pass this arm on any
# binary ever built — the first draft of it did. external/ is the one the crawler indexes, so it is the one
# that can prove the rule.
( cd "$DP" && "$BIN" . --top-k=100000 --no-cache 2>/dev/null ) | grep -q 'vendA' \
    && ok "duplication: the external/ pair IS indexed (the vendored arm is not vacuous)" \
    || no "duplication: external/ is not indexed — the vendored arm proves nothing"
dup 'vendA' >/dev/null \
    && { no "duplication: a group inside external/ is still reported"; rows "$ODP" | grep duplication; } \
    || ok "duplication: a group under a built-in vendored prefix produces no row"
dup 'cfgA' >/dev/null && ok "duplication: src/infra/ IS reported with no .ripwire_config (the control)" \
    || { no "duplication: the config control is vacuous — src/infra/ was already silent"; rows "$ODP" | grep duplication; }
# now name it vendored, and only that row goes away.
printf 'vendored_paths = src/infra/\n' > "$DP/.ripwire_config"
ODP2="$( cd "$DP" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
rows "$ODP2" | grep 'kind="duplication"' | grep -q 'cfgA' \
    && { no "duplication: vendored_paths= in .ripwire_config did not exempt src/infra/"; rows "$ODP2" | grep duplication; } \
    || ok "duplication: vendored_paths=src/infra/ in .ripwire_config exempts the group"
rows "$ODP2" | grep 'kind="duplication"' | grep -q 'alpha' \
    && ok "duplication: the cross-file copy survives the config key too" \
    || no "duplication: vendored_paths= swallowed an unrelated group"
printf '%s' "$ODP2" | grep -q 'config-warnings=' \
    && { no "duplication: vendored_paths= was reported as an unrecognized .ripwire_config key"; } \
    || ok "duplication: vendored_paths= is a RECOGNIZED key (no config-warnings on the root)"
rm -f "$DP/.ripwire_config"
[ "$ODP" = "$( cd "$DP" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ] \
    && ok "duplication: byte-identical run to run (deterministic)" || no "duplication: non-deterministic delta"


# ── 6) error-masking: a block whose only content is a COMMENT is a swallow ───────────────────────────────
# The kind fired ZERO times across 52 replayed documents and once in 1,177 committed acks, because all seven
# of its rules require a LITERALLY empty block. Synthetic S2 (`catch(...){}`) was caught; S2b
# (`catch( const std::exception& ) { /* ignore */ }`) was missed — and the comment is where a deliberate
# swallow is most likely to be written down. The widening is measured at +0 rows over 40 replayed commits.
EM="$WORK/mask"; mkdir -p "$EM/src"
( cd "$EM" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false )
cat > "$EM/src/m.cpp" <<'CPP'
#include <stdexcept>
#include <cstdio>
int risky( int n );
int guarded( int n ){
    try { return risky( n ); }
    catch( const std::runtime_error& e ) { return -1; }
}
int logged( int n ){
    try { return risky( n ); }
    catch( const std::runtime_error& e ) { std::fprintf( stderr, "bad" ); return -2; }
}
CPP
# The JS half (CodeRabbit #127 / 3985249701). JavaScript is where the review's counterexample lives,
# because ASI means a handler body can carry NO ';' and NO inner '{' — which is everything the flattened
# prefilter can see. All three start life as a real `return -1` handler so the working edit makes each row
# NEW debt, which is the only kind --quality-delta reports.
cat > "$EM/src/m.js" <<'JS'
function riskyJs( n ) { return n }
function recoverJs( n ) { return n + 1 }
function guardedJs( n ) {
    try { return riskyJs( n ) }
    catch ( e ) { return -1 }
}
function recoveredJs( n ) {
    try { return riskyJs( n ) }
    catch ( e ) { return -1 }
}
function lineCommentJs( n ) {
    try { return riskyJs( n ) }
    catch ( e ) { return -1 }
}
JS
( cd "$EM" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )
python3 - "$EM/src/m.cpp" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("catch( const std::runtime_error& e ) { return -1; }",
            "catch( const std::runtime_error& e ) { /* deliberately ignored */ }")
open(p,"w").write(s)
j=p.replace("m.cpp","m.js"); t=open(j).read()
def sub(fn, body):
    global t
    old = "function %s( n ) {\n    try { return riskyJs( n ) }\n    catch ( e ) { return -1 }\n}" % fn
    assert old in t, fn
    t = t.replace(old, "function %s( n ) {\n    try { return riskyJs( n ) }\n    catch ( e ) %s\n}" % (fn, body))
# a REAL swallow — the comment is the whole interior. Must be reported.
sub("guardedJs",     "{ /* deliberately ignored */ }")
# a comment OPENS the block, then code runs. A handler. Must NOT be reported.
sub("recoveredJs",   "{ /* fall back */ recoverJs( n ) }")
# the one flattened text cannot decide: the newline that ends the // comment is scrubbed to a space.
sub("lineCommentJs", "{ // fall back\n        recoverJs( n )\n    }")
open(j,"w").write(t)
PY
OEM="$( cd "$EM" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
row "$OEM" error-masking guarded >/dev/null \
    && ok "error-masking: a comment-only catch block is a swallow (synthetic S2b)" \
    || { no "error-masking: the comment-only catch block was missed"; rows "$OEM"; }
row "$OEM" error-masking logged >/dev/null \
    && { no "error-masking: a catch that LOGS and returns was counted — a statement survives in it"; rows "$OEM"; } \
    || ok "error-masking: a catch carrying a real statement is not a swallow"

# NON-VACUITY FIRST: the JS swallow must be reported, or the two negative arms below prove nothing.
row "$OEM" error-masking guardedJs >/dev/null \
    && ok "error-masking: a comment-only JS catch block is a swallow (the positive control)" \
    || { no "error-masking: the comment-only JS catch was missed — the two arms below are vacuous"; rows "$OEM"; }
# A COMMENT THAT OPENS THE BLOCK DOES NOT CLOSE IT (CodeRabbit #127 / 3985249701). Both bodies open with a
# comment and then run real code; neither holds a ';' or an inner '{', which is everything the flattened
# prefilter can see, so both were reported as swallows even though each HANDLES the error. `lineCommentJs`
# is the one flattened text cannot decide AT ALL: astQuery scrubs the newline that ends a `//` comment, so
# `{ // fall back  recoverJs( n ) }` is byte-identical to a block whose entire interior is a comment. The
# confirm re-reads the file's own bytes, which is the only place that distinction still exists.
row "$OEM" error-masking recoveredJs >/dev/null \
    && { no "error-masking: code AFTER a /* */ comment was counted as a swallow — the block handles the error"; rows "$OEM"; } \
    || ok "error-masking: a /* */ comment followed by code is a HANDLER, not a swallow"
row "$OEM" error-masking lineCommentJs >/dev/null \
    && { no "error-masking: code on the line after a // comment was counted as a swallow"; rows "$OEM"; } \
    || ok "error-masking: a // comment followed by code on the next line is a HANDLER, not a swallow"
[ "$OEM" = "$( cd "$EM" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ] \
    && ok "error-masking: byte-identical run to run (deterministic)" || no "error-masking: non-deterministic delta"


[ "$fail" = 0 ] && echo "qddialscheck: ALL PASS" || echo "qddialscheck: FAILURES"
exit "$fail"
