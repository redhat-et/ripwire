#!/usr/bin/env bash
# scroundtripcheck.sh — a symbol row's short id (sc=) composes to EXACTLY the id= it replaced, and that id
# still resolves.
#
# THE DEFECT. On every scoped map row the canonical id repeated the enclosing <f p=> path verbatim
# (id="qual.cpp::Widget::ping" under <f p="qual.cpp">): 942 of 942 scoped rows on this tree, 11.2% of a
# flagless map (PLAN_OUTPUT_ROUTING_LOOP 2026-09-12, row 6). The row now prints sc="Widget" — the enclosing
# scope alone — and the legend states the composition: id = p::sc::n, p= taken from the row's own p= (a
# lens <d> row) or from its enclosing <f p=> (a map <s> row). The selectors (--expand, --callers, --impact,
# --uses, the MCP twins) keep ACCEPTING the composed path::scope::name spelling unchanged.
#
# WHAT IS PINNED, and why each arm is a real contrast:
#   (A) the map prints sc= rows at all (RED on the pre-change binary: zero rows — the presence guard).
#   (B) the multiset of p::sc::n composed from the rows EQUALS the multiset of id= values the pre-change
#       binary printed on the same fixture (embedded below, captured 2026-09-12 from main @ 1cf3086e).
#       This is the lossless-ness proof: nothing a reader could address before is unaddressable now.
#   (C) every composed id round-trips through --expand: every body served carries the composed path as
#       p= and the composed name as n= (the resolver's own answer, an independent derivation), and a
#       mutated scope serves nothing — so the scope segment is read, not skipped to a bare-name union.
#   (D) the old id= spelling stays ACCEPTED on input (--expand and --callers), naming the same symbol.
#   (E) the old shape is gone from the rows (no id= on <s>/<d> rows) and the legend defines sc= (the
#       legend-coverage contract: every attribute a reader meets has a name= definition).
#   (F) the lens rows (--for's <d>) compose the same way with the row's OWN p=.
#   (G) the JSON twin carries "sc" and no "id" on the same rows (attribute-name parity, mcpattrparity).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
cd "$ROOT"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }
TMP="$( mktemp -d "${TMPDIR:-/tmp}/scroundtrip.XXXXXX" )"; trap 'rm -rf "$TMP"' EXIT
echo "scroundtripcheck: BIN=$BIN"

# The id= values the PRE-CHANGE binary printed on each fixture's flagless map (sorted, one per line, duplicates
# kept: a class row and its constructor row share one canonical id by construction). Captured from
# `ripwire test/<fixture>` at main @ 1cf3086e, 2026-09-12 — the population arm (B) compares against.
expected_cppqualfix='qual.cpp::Base::Base
qual.cpp::Box::Box
qual.cpp::Box::get
qual.cpp::Derived::Derived
qual.cpp::Tag::Tag
qual.cpp::Widget::Widget
qual.cpp::Widget::Widget
qual.cpp::Widget::make
qual.cpp::Widget::ping
qual.cpp::a::scopedTmpl
qual.cpp::a::twoSeg
qual.cpp::b::mutexFn
qual.cpp::b::pick
qual.cpp::b::targetFn'
expected_nestedqualfix='defs.hpp::Outer::Inner
defs.hpp::Outer::Inner::Inner
defs.hpp::SOuter::SInner
defs.hpp::SOuter::SInner::SInner
outer.hpp::Base::Base
outer.hpp::Decoy::Decoy
outer.hpp::Inner::Inner
outer.hpp::Outer::Outer
outer.hpp::Outer::Outer
outer.hpp::SOuter::SOuter
outer.hpp::SOuter::SOuter'

# compose p::sc::n from a map: every <f p=> wrapper, then each <s ... sc=...> row under it. Attribute ORDER on
# the row is not assumed (n= and sc= are found by name); a row without sc= composes nothing.
cat > "$TMP/compose.py" <<'PY'
import re, sys
doc = open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read()
tag = sys.argv[2] if len( sys.argv ) > 2 else "s"
out = []
if tag == "s":
    for f in re.finditer( r'<f p="([^"]*)"[^>]*>(.*?)</f>', doc, re.S ):
        p = f.group( 1 )
        for row in re.finditer( r'<s\b([^>]*)>', f.group( 2 ) ):
            a = dict( re.findall( r'\s([\w:.-]+)="([^"]*)"', row.group( 1 ) ) )
            if "sc" in a: out.append( p + "::" + a[ "sc" ] + "::" + a[ "n" ] )
else:
    for row in re.finditer( r'<d\b([^>]*)>', doc ):
        a = dict( re.findall( r'\s([\w:.-]+)="([^"]*)"', row.group( 1 ) ) )
        if "sc" in a and "p" in a: out.append( a[ "p" ] + "::" + a[ "sc" ] + "::" + a[ "n" ] )
sys.stdout.write( "\n".join( sorted( out ) ) + ( "\n" if out else "" ) )
PY

for fx in cppqualfix nestedqualfix; do
    "$BIN" "test/$fx" --no-cache >"$TMP/$fx.map" 2>/dev/null </dev/null || { no "($fx) the flagless map did not run"; continue; }
    python3 "$TMP/compose.py" "$TMP/$fx.map" s >"$TMP/$fx.composed"
    nsc="$( grep -c . "$TMP/$fx.composed" )"
    # (A) presence: sc= rows exist at all
    if [ "$nsc" -gt 0 ]; then ok "(A) $fx: $nsc scoped rows carry sc="; else no "(A) $fx: no <s ... sc=> row on the map (the short id is not emitted)"; fi
    # (B) the composed multiset equals the pre-change id= multiset
    eval "printf '%s\n' \"\$expected_$fx\"" | sort >"$TMP/$fx.expected"
    if [ "$nsc" -gt 0 ] && cmp -s "$TMP/$fx.composed" "$TMP/$fx.expected"; then
        ok "(B) $fx: p::sc::n composed from the rows == the id= multiset the pre-change binary printed ($nsc ids)"
    else
        no "(B) $fx: composed ids differ from the pre-change id= set"; diff "$TMP/$fx.expected" "$TMP/$fx.composed" | head -6 | sed 's/^/        /'
    fi
    # (C) round trip: --expand=<composed> resolves to the body of THAT symbol — every <b> served carries the
    #     composed path as p= and the composed name as n= — and a scope that names nothing refuses (the contrast
    #     that proves the scope segment is read, not skipped past to a bare-name union).
    bad=0; n=0
    while IFS= read -r cid; do
        [ -n "$cid" ] || continue
        n=$(( n + 1 ))
        cpath="${cid%%::*}"; cname="${cid##*::}"
        out="$( "$BIN" "test/$fx" --no-cache --top-k=0 "--expand=$cid" 2>&1 </dev/null )"; rc=$?
        nb="$( printf '%s' "$out" | grep -o '<b [^>]*>' | wc -l | tr -d ' ' )"
        nbmatch="$( printf '%s' "$out" | grep -o '<b [^>]*>' | grep -c " p=\"$cpath\"" )"
        nbname="$( printf '%s' "$out" | grep -o '<b [^>]*>' | grep -c " n=\"$cname\"" )"
        if [ $rc -ne 0 ] || printf '%s' "$out" | grep -q 'symbol not found\|matched no symbol' \
           || [ "$nb" -lt 1 ] || [ "$nbmatch" != "$nb" ] || [ "$nbname" != "$nb" ]; then
            bad=$(( bad + 1 )); [ $bad -le 2 ] && printf '        --expand=%s: rc=%s bodies=%s path-matched=%s name-matched=%s\n' "$cid" "$rc" "$nb" "$nbmatch" "$nbname"
        fi
    done < <( sort -u "$TMP/$fx.composed" )
    if [ "$n" -gt 0 ] && [ "$bad" -eq 0 ]; then ok "(C) $fx: all $n composed ids round-trip through --expand to bodies of that path and name"
    else no "(C) $fx: $bad of $n composed ids did not round-trip"; fi
    first="$( sort -u "$TMP/$fx.composed" | head -1 )"
    if [ -n "$first" ]; then
        wrong="${first%%::*}::ZZnoScope::${first##*::}"
        out="$( "$BIN" "test/$fx" --no-cache --top-k=0 "--expand=$wrong" 2>&1 </dev/null )"
        if printf '%s' "$out" | grep -q '<b '; then no "(C) $fx: a WRONG scope ($wrong) still served a body — the scope segment is not read"; else ok "(C) $fx: a wrong scope ($wrong) serves no body (the scope segment is read)"; fi
    fi
    # (E) the old shape is gone and the legend defines the new one
    if grep -q '<s [^>]* id="' "$TMP/$fx.map"; then no "(E) $fx: an <s> row still prints id= (the short id did not replace it)"; else ok "(E) $fx: no <s> row prints id="; fi
    if grep -o '<!--.*-->' "$TMP/$fx.map" | grep -q 'sc='; then ok "(E) $fx: the legend defines sc="; else no "(E) $fx: the legend never spells sc="; fi
done

# (D) the old id= spelling stays accepted on input — the same symbol's body / callers
OLDID='qual.cpp::Widget::ping'
out="$( "$BIN" test/cppqualfix --no-cache --top-k=0 "--expand=$OLDID" 2>&1 </dev/null )"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -o '<b [^>]*>' | grep -q ' p="qual.cpp"[^>]* n="ping"'; then ok "(D) --expand still accepts the path::scope::name spelling ($OLDID)"; else no "(D) --expand refused the old id= spelling (rc=$rc)"; fi
out="$( "$BIN" test/cppqualfix --no-cache "--callers=$OLDID" 2>&1 </dev/null )"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q '<callers of='; then ok "(D) --callers still accepts the path::scope::name spelling"; else no "(D) --callers refused the old id= spelling (rc=$rc)"; fi

# (F) the lens rows: <d p= n= sc=> compose with the row's OWN p= to an id that --expand resolves
"$BIN" test/cppqualfix --no-cache --for=scopedTmpl >"$TMP/for.xml" 2>/dev/null </dev/null
python3 "$TMP/compose.py" "$TMP/for.xml" d >"$TMP/for.composed"
if grep -qxF 'qual.cpp::a::scopedTmpl' "$TMP/for.composed"; then ok "(F) --for's <d> row composes p::sc::n = qual.cpp::a::scopedTmpl"; else no "(F) --for's <d> row did not compose qual.cpp::a::scopedTmpl (got: $( tr '\n' ' ' <"$TMP/for.composed" | head -c 200 ))"; fi
if grep -q '<d [^>]* id="' "$TMP/for.xml"; then no "(F) a <d> row still prints id="; else ok "(F) no <d> row prints id="; fi

# (G) the JSON twin: "sc" present, "id" absent on the symbol rows
"$BIN" test/cppqualfix --no-cache --json >"$TMP/map.json" 2>/dev/null </dev/null
if grep -q '"sc":"Widget"' "$TMP/map.json" && ! grep -q '"id":"qual.cpp::' "$TMP/map.json"; then ok "(G) --json rows carry \"sc\" and no \"id\""; else no "(G) --json rows do not mirror sc= (id present or sc absent)"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "ALL FAIL"; exit 1; }
