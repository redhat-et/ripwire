#!/usr/bin/env bash
# archunqualifiedcheck.sh — a rule whose FROM side holds a file this build never judged reads UNKNOWN, never PASS (lane
# metric-labels, research audit 2026-11-26 item 9).
#
# WHY. --arch judges an edge only when the include/import graph draws it. A file in a language that draws no file edge (Go,
# Java, Swift... LangFacts::fileEdges Unmeasured) or of a code extension this build does not index at all (.scala, .hs, .vue...)
# has imports nothing ever read, so a rule over it was never checked for that file. The base answered such a tree exactly as a
# clean one: `deny ui -> db` over ui/Panel.scala importing db printed violations="0" and exited 0, in --baseline mode with no
# stderr line at all. The identity-hashed baseline is already the right design (arXiv 2610.41276: identity ratchets 480/480
# scenarios, count-only 360/480); what it lacked was OBSERVATION QUALIFICATION. Now <arch> carries unqualified=N (files on a
# rule's FROM side whose imports were unresolved or unindexed), each such rule a <rule text= unqualified= verdict="unknown"> row,
# and stderr says the verdict is UNKNOWN in every mode. The exit codes are UNCHANGED (--help: exit 2 on a violation, 0 in the
# baseline modes); arm (X) pins that, so a future exit-code change is a decision this gate makes visible, not a drift.
#
# ARMS (each built under mktemp; red on base 5f4b50415 unless marked control):
#   (A) plain --arch, one rule-bound .scala file: unqualified="1", the rule row reads unknown, stderr says UNKNOWN
#   (B) --baseline (the brief's red arm: exit 0 and silent on base) and (U) --baseline-update: the same disclosure
#   (G) a Go file (indexed, no file edges) on the FROM side counts the same way
#   (W) `deny * -> db`: a wildcard FROM puts every layered file under the rule
#   (P) a deny path-rule whose FROM regex matches the file counts it on its own row
#   (V) a real C++ violation beside the unqualified file: exit stays 2, the rule still reads unknown (its violations are a floor)
#   (L) legends: compact and full both define unqualified= and the rule row; xmllint-clean
#   (N1..N4) controls (green on base too): the file outside any layer, a non-code .txt under the layer, the file on the TO side
#        only, and a tree with no such file — no unqualified=, no <rule> row, no UNKNOWN line, legend clause absent
#   (X) exit codes: 0 / 0 / 0 for plain, --baseline, --baseline-update with no violation; 2 with one
#
# Usage: bash test/archunqualifiedcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "archunqualifiedcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
HAVE_XMLLINT=0; command -v xmllint >/dev/null 2>&1 && HAVE_XMLLINT=1

# tree DIR RULES — ui/view.cpp (C++, includes nothing of db) and db/store.h; the caller adds the file under test
tree(){
    mkdir -p "$1/ui" "$1/db" "$1/docs"
    printf 'int ui() { return 1; }\n' >"$1/ui/view.cpp"
    printf 'int store();\n' >"$1/db/store.h"
    printf 'layer ui = ui/\nlayer db = db/\n%s\n' "$2" >"$1/rules.txt"
}
SCALA='import db.Store\nobject Panel { def show() = Store.get() }\n'
# run DIR TAG args... — stdout to $TMP/TAG.out, stderr to $TMP/TAG.err, exit code to $TMP/TAG.rc; from inside DIR (the sidecar is CWD-relative)
run(){ local d="$1" t="$2"; shift 2; ( cd "$d" && perl -e 'alarm 60; exec @ARGV' "$BIN" . "$@" --no-cache >"$TMP/$t.out" 2>"$TMP/$t.err" </dev/null ); echo $? >"$TMP/$t.rc"; }
rc(){ cat "$TMP/$1.rc"; }
root(){ grep -o '<arch [^>]*>' "$TMP/$1.out" | head -1; }
payload(){ perl -0pe 's/<!--.*?-->//gs' "$TMP/$1.out"; }
# rulerow TAG TEXT — the <rule> row whose text= is TEXT (escaped either way: the arrow's > may be written &gt;)
rulerow(){ payload "$1" | grep -o '<rule [^>]*/>' | python3 -c '
import html, sys
want = sys.argv[1]
for row in sys.stdin.read().split( "\n" ):
    i = row.find( "text=\"" )
    if i >= 0 and html.unescape( row[i + 6:row.find( "\"", i + 6 )] ) == want:
        print( row )' "$2"; }
# unknownArm LABEL TAG RULETEXT N — root unqualified=N, the rule row reads unknown with unqualified=N, stderr says UNKNOWN
unknownArm(){
    local label="$1" t="$2" text="$3" n="$4" r
    case "$( root "$t" )" in *" unqualified=\"$n\""*) ok "$label: <arch unqualified=\"$n\">" ;; *) no "$label: root lacks unqualified=\"$n\": $( root "$t" )" ;; esac
    r="$( rulerow "$t" "$text" )"
    case "$r" in *'unqualified="'"$n"'"'*'verdict="unknown"'*) ok "$label: rule row $r" ;; *) no "$label: no <rule text=\"$text\" unqualified=\"$n\" verdict=\"unknown\"> row (got '${r:-none}')" ;; esac
    grep -q 'UNKNOWN' "$TMP/$t.err" && ok "$label: stderr says the verdict is UNKNOWN" || no "$label: stderr carries no UNKNOWN line: $( head -c 300 "$TMP/$t.err" )"
}
cleanArm(){
    local label="$1" t="$2"
    [ -n "$( root "$t" )" ] || { no "$label: premise: the run printed no <arch> root (exit $( rc "$t" ))"; return; }   # an absence read off no answer proves nothing
    case "$( root "$t" )" in *" unqualified="*) no "$label: unqualified= rides a tree with nothing unjudged: $( root "$t" )" ;; *) ok "$label: no unqualified= on the root" ;; esac
    payload "$t" | grep -q '<rule ' && no "$label: a <rule> row rides a tree with nothing unjudged" || ok "$label: no <rule> row"
    grep -q 'UNKNOWN' "$TMP/$t.err" && no "$label: stderr says UNKNOWN with nothing unjudged" || ok "$label: no UNKNOWN line on stderr"
    grep -q 'unqualified=' "$TMP/$t.out" && no "$label: the legend defines unqualified= though no answer carries it (present-only)" || ok "$label: the legend clause stays out"
}

echo "=== (A) plain --arch, one rule-bound unindexed-language file ==="
T="$TMP/scala"; tree "$T" 'deny ui -> db'; printf "$SCALA" >"$T/ui/Panel.scala"
run "$T" a --arch=rules.txt
unknownArm "(A)" a "deny ui -> db" 1

echo "=== (B) --baseline / (U) --baseline-update ==="
run "$T" b --arch=rules.txt --baseline
unknownArm "(B) --baseline" b "deny ui -> db" 1
run "$T" u --arch=rules.txt --baseline-update
unknownArm "(U) --baseline-update" u "deny ui -> db" 1
rm -f "$T/.ripwire_arch_baseline"

echo "=== (G) a no-file-edge language (Go) on the FROM side ==="
G="$TMP/go"; tree "$G" 'deny ui -> db'; printf 'package ui\n\nimport "example.com/db"\n\nfunc Show() int { return db.Get() }\n' >"$G/ui/panel.go"
run "$G" g --arch=rules.txt
unknownArm "(G)" g "deny ui -> db" 1

echo "=== (W) a wildcard FROM ==="
W="$TMP/star"; tree "$W" 'deny * -> db'; printf "$SCALA" >"$W/ui/Panel.scala"
run "$W" w --arch=rules.txt
unknownArm "(W)" w "deny * -> db" 1

echo "=== (P) a deny path-rule ==="
P="$TMP/path"; tree "$P" 'deny path ui/.* -> db/.*'; printf "$SCALA" >"$P/ui/Panel.scala"
run "$P" p --arch=rules.txt
unknownArm "(P)" p "deny path ui/.* -> db/.*" 1

echo "=== (V) a real violation beside the unjudged file ==="
V="$TMP/viol"; tree "$V" 'deny ui -> db'; printf "$SCALA" >"$V/ui/Panel.scala"; printf '#include "../db/store.h"\nint ui() { return store(); }\n' >"$V/ui/view.cpp"
run "$V" v --arch=rules.txt
[ "$( rc v )" = 2 ] && ok "(V) exit 2: the C++ violation still gates" || no "(V) exit $( rc v ), expected 2"
unknownArm "(V)" v "deny ui -> db" 1

echo "=== (L) legends and well-formedness ==="
for t in a b u g w p v; do
    if [ "$HAVE_XMLLINT" = 1 ]; then xmllint --noout "$TMP/$t.out" 2>/dev/null || no "(L) $t: not well-formed XML"; fi
done
[ "$HAVE_XMLLINT" = 1 ] && ok "(L) every answer above is well-formed (xmllint)" || echo "  SKIP  (L) xmllint not installed"
grep -q 'unqualified=N:' "$TMP/a.out" && grep -q 'verdict=unknown' "$TMP/a.out" \
    && ok "(L) the compact legend defines unqualified= and the rule row" || no "(L) compact legend: $( grep -o '<!--.*-->' "$TMP/a.out" | head -c 400 )"
run "$T" af --arch=rules.txt --legend=full
grep -q 'unqualified=N:' "$TMP/af.out" && grep -q 'verdict=unknown' "$TMP/af.out" \
    && ok "(L) the full legend defines unqualified= and the rule row" || no "(L) full legend lacks the unqualified= clause"
cmp -s <( payload a | sed "s/ schema=\"[^\"]*\"//" ) <( payload af ) && ok "(L) payload byte-identical under both dialects" || no "(L) payload differs between compact and full"

echo "=== (N) controls: nothing unjudged on a rule's FROM side ==="
N1="$TMP/outside"; tree "$N1" 'deny ui -> db'; printf "$SCALA" >"$N1/docs/Panel.scala"
run "$N1" n1 --arch=rules.txt; cleanArm "(N1) the file outside every layer" n1
N2="$TMP/txt"; tree "$N2" 'deny ui -> db'; printf 'import db notes\n' >"$N2/ui/notes.txt"
run "$N2" n2 --arch=rules.txt; cleanArm "(N2) a non-code .txt under the layer" n2
N3="$TMP/toside"; tree "$N3" 'deny ui -> db'; printf "$SCALA" >"$N3/db/Store.scala"
run "$N3" n3 --arch=rules.txt; cleanArm "(N3) the file on the TO side only" n3
N4="$TMP/plain"; tree "$N4" 'deny ui -> db'
run "$N4" n4 --arch=rules.txt; cleanArm "(N4) a tree with no such file" n4
run "$N4" n4b --arch=rules.txt --baseline; cleanArm "(N4) the same tree under --baseline" n4b

echo "=== (X) exit codes are unchanged ==="
[ "$( rc a )/$( rc b )/$( rc u )/$( rc n4 )" = "0/0/0/0" ] && ok "(X) exits 0/0/0/0 (plain, --baseline, --baseline-update, the clean tree) — the --help contract" \
    || no "(X) exits $( rc a )/$( rc b )/$( rc u )/$( rc n4 ), expected 0/0/0/0 — an exit-code change is an owner decision"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }
