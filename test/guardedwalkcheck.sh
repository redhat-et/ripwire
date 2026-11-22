#!/usr/bin/env bash
# guardedwalkcheck.sh — the C-family guarded base walk is expanded once per root name, not once per call (lane PF2, 2026-11-21).
#
# The incident: a cold flagless map of llvm-project (182,555 files) ran past 10 minutes on one core, every sample in
# buildGraph -> Narrower::methodOnTypeOrBases -> Narrower::expandGuardedLevel. The guarded walk (resolve.h CPP-BASE-BY-NAME)
# re-expanded the receiver type's base levels on EVERY call, and one level's expansion asks meantBase of each base name,
# which pairs every class of the deriving NAME with every class of the base NAME (baseEdgeBound, then the clause-scope and
# include tests). Where class names repeat across files (`Impl`, `Base`, `Visitor` — hundreds of each in llvm), one walk
# costs (classes of the name)^2 and the map paid it once per call: calls x K^2, cubic in a name's fan-out. The walk's
# levels depend only on the root name (and the fixed chaUp / class identity), so they are now memoised per root
# (Narrower::guardedWalkOf); each call replays the memoised levels into the same scratch and probes them as before.
#
# The probe that follows each level asks, per definition a level hits, whether a class the walk means owns it
# (IdentityNarrower::ownedBy). For a member defined out of line in a file with no class of its scope's name, that reads
# every class of the name (plausibleClasses: a visibility test per class) — again on every call. It is memoised per
# (definition, class) (OWNED-MEMO).
#
# Class identity's step (3) (a virtual call on a type whose ancestry declares the callee and defines it nowhere: the
# callee's definitions in the real subclasses) re-read, for every (receiver class, callee), two facts no callee changes:
# whether each subclass's base clause means the receiver class (plausibleClasses per subclass), and the base levels of a
# subclass that inherits its body (queueUnvisitedBases). Both are now kept: per (subclass, class) (SUBCLASS-CLAUSE-MEMO)
# and per subclass, level by level (INHERITED-LEVELS-MEMO).
#
# GW(K, M): K files, each defining `struct RootK`, `struct Base : RootK`, `struct Impl : Base` whose one method repeats
# M times the bare calls `b0()` .. `b(K-1)()` and `r()`, and `struct Peer : Base` calling `bK()` and `r()` once; K more files define `void Base::bK() { }` out of line, and one
# more a namesake `struct Base` no Impl derives from (so the walk's `Base` is narrowed to the K the Impls name, and the
# probe asks ownedBy). Every Impl's bare calls walk Impl's guarded bases; `Base` names K+1 classes and `Impl` K, so one
# walk's meantBase pairs K x (K+1) classes.
#
#   (A) REACHED — the RIPWIRE_STATS lines `[mem] guarded_walk calls=C walks=W cones=X meant=N` and `[mem] owned_by asks=A reads=R`
#       are printed and C > 0, so the arms below cannot pass on a walk the fixture never enters.
#   (B) PER-ROOT — `walks` (roots kept) and `meant` (meantBase evaluations) are the same at M=2 and at M=8 while `calls`
#       grows: the walk's cost is paid per distinct root name, not per call. Likewise `reads` (out-of-line owner answers
#       computed) is the same while `asks` grows. Unmemoised, `meant` and `reads` grow with M and this arm is red.
#   (C) EXACT — at M=8: calls=1272 (12 Impl bodies x 8 x 13 calls, plus 12 Peer bodies x 2), walks=2 (two root names,
#       `Impl` and `Peer`), cones=2 (the two caller classes whose cones the ladder proof and the bare-call test read: kept
#       per class, CONE-MEMO — the one-entry keep it replaced re-expanded a cone at every Impl/Peer switch, 24 times),
#       meant=52 — per root 13 for the walk's two levels (`Base`, then Base's 12 `RootK`) plus 13 for its cone (the same
#       two levels under kConeNameCap); asks=1164 (one per bK() call: the first class it asks about owns it), reads=12 (one
#       per out-of-line definition). Unmemoised the walk alone re-ran 1 or 13 meantBase per call.
# SW(4, M): Shape declares f0..f(M-1) with no body; 4 Circles define them all; 4 Squares define none and inherit them
#   through Painter; use( Shape* s ) calls each once. (A) clause_asks > 0 and grows with M; (B) clause_reads and levels
#   are the same at M=2 and M=8; (C) at M=8 clause_asks=64 (8 callees x 8 subclasses of Shape), clause_reads=8 (one per
#   subclass), levels=4 (each Square's level 1, where Painter answers; never queued again).
#   (D) CONTROL (RIPWIRE_GUARDEDWALK_CONTROL_BIN=<a binary without the memos>) — the default maps of GW(K, 8) and SW(4, 8) are
#       byte-identical between the control and this binary: the memos change cost, never an edge. Without the variable
#       the control arm is reported as not run; (A)-(C) still gate on their own.
#
#   bash test/guardedwalkcheck.sh [path/to/ripwire]

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CONTROL="${RIPWIRE_GUARDEDWALK_CONTROL_BIN:-}"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
TMP="$( cd "$TMP" && pwd -P )"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "guardedwalkcheck: BIN=$BIN"

K=12

# gen DIR K M — the shared-name hierarchy (see header)
gen(){
    local dir="$1" k="$2" m="$3" f i b
    mkdir -p "$dir"
    for f in $( seq 0 $(( k - 1 )) ); do
        {
            printf 'struct Root%d { void r(); };\n' "$f"
            printf 'struct Base : Root%d { void b%d(); };\n' "$f" "$f"
            printf 'struct Impl : Base\n{\n    void run%d()\n    {\n' "$f"
            for i in $( seq 0 $(( m - 1 )) ); do
                for b in $( seq 0 $(( k - 1 )) ); do
                    printf '        b%d();\n' "$b"
                done
                printf '        r();\n'
            done
            printf '    }\n};\n'
            printf 'struct Peer : Base\n{\n    void go%d() { b%d(); r(); }\n};\n' "$f" "$f"   # a second caller class, after each Impl
        } >"$dir/f$f.cpp"
        printf 'void Base::b%d() { }\n' "$f" >"$dir/impl$f.cpp"   # out of line, in a file with no Base: owner unknown
    done
    printf 'struct Base { void z(); };\n' >"$dir/other.cpp"         # a namesake no Impl derives from: the walk's Base is narrowed
}

# gensw DIR K M — step (3) of class identity (see header): Shape declares f0..f(M-1) with no body, K Circles define them,
# K Squares inherit them through Painter, and use() calls each through a Shape*
gensw(){
    local dir="$1" k="$2" m="$3" c i
    mkdir -p "$dir"
    {
        printf 'struct Shape\n{\n'
        for i in $( seq 0 $(( m - 1 )) ); do printf '    virtual void f%d() = 0;\n' "$i"; done
        printf '};\nstruct Painter\n{\n'
        for i in $( seq 0 $(( m - 1 )) ); do printf '    void f%d() { }\n' "$i"; done
        printf '};\n'
    } >"$dir/shape.h"
    for c in $( seq 0 $(( k - 1 )) ); do
        {
            printf '#include "shape.h"\nstruct Circle%d : Shape\n{\n' "$c"
            for i in $( seq 0 $(( m - 1 )) ); do printf '    void f%d() override { }\n' "$i"; done
            printf '};\nstruct Square%d : Shape, Painter { };\n' "$c"
        } >"$dir/c$c.cpp"
    done
    {
        printf '#include "shape.h"\nvoid use( Shape* s )\n{\n'
        for i in $( seq 0 $(( m - 1 )) ); do printf '    s->f%d();\n' "$i"; done
        printf '}\n'
    } >"$dir/use.cpp"
}

# stats NAME DIR — run with RIPWIRE_STATS, set LINE / CALLS / WALKS / MEANT
stats(){
    local name="$1" dir="$2"
    env RIPWIRE_STATS=1 "$BIN" "$dir" --no-cache >"$TMP/$name.xml" 2>"$TMP/$name.err"; RC=$?
    LINE="$( grep -F '[mem] guarded_walk ' "$TMP/$name.err" )"
    CALLS="$( printf '%s' "$LINE" | sed -n 's/.* calls=\([0-9]*\).*/\1/p' )"
    WALKS="$( printf '%s' "$LINE" | sed -n 's/.* walks=\([0-9]*\).*/\1/p' )"
    MEANT="$( printf '%s' "$LINE" | sed -n 's/.* meant=\([0-9]*\).*/\1/p' )"
    OLINE="$( grep -F '[mem] owned_by ' "$TMP/$name.err" )"
    ASKS="$( printf '%s' "$OLINE" | sed -n 's/.* asks=\([0-9]*\).*/\1/p' )"
    READS="$( printf '%s' "$OLINE" | sed -n 's/.* reads=\([0-9]*\).*/\1/p' )"
    BLINE="$( grep -F '[mem] base_edges ' "$TMP/$name.err" )"
    SLINE="$( grep -F '[mem] subclass_walk ' "$TMP/$name.err" )"
    CASKS="$( printf '%s' "$SLINE" | sed -n 's/.* clause_asks=\([0-9]*\).*/\1/p' )"
    CREADS="$( printf '%s' "$SLINE" | sed -n 's/.* clause_reads=\([0-9]*\).*/\1/p' )"
    LEVELS="$( printf '%s' "$SLINE" | sed -n 's/.* levels=\([0-9]*\).*/\1/p' )"
}

GW2="$TMP/gw2"; gen "$GW2" "$K" 2
GW8="$TMP/gw8"; gen "$GW8" "$K" 8

SW2="$TMP/sw2"; gensw "$SW2" 4 2
SW8="$TMP/sw8"; gensw "$SW8" 4 8

stats GW2 "$GW2"; c2="$CALLS" w2="$WALKS" m2="$MEANT" rc2=$RC a2="$ASKS" r2="$READS"
stats GW8 "$GW8"; c8="$CALLS" w8="$WALKS" m8="$MEANT" rc8=$RC line8="$LINE" a8="$ASKS" r8="$READS" oline8="$OLINE" bline8="$BLINE"

stats SW2 "$SW2"; sa2="$CASKS" sr2="$CREADS" sl2="$LEVELS" src2=$RC
stats SW8 "$SW8"; sa8="$CASKS" sr8="$CREADS" sl8="$LEVELS" src8=$RC sline8="$SLINE"

# ── (A) REACHED ────────────────────────────────────────────────────────────────────────────────────────────────
if [ "$rc2$rc8" = "00" ] && [ -n "$c2" ] && [ -n "$c8" ] && [ "$c2" -gt 0 ] && [ "$c8" -gt "$c2" ]; then
    ok "(A) the guarded walk is reached: calls=$c2 at M=2, calls=$c8 at M=8"
else
    no "(A) no guarded walk reached (rc=$rc2/$rc8, M=2 '${c2:-<no line>}', M=8 '${c8:-<no line>}')"
fi
if grep -q "files=$(( 2 * K + 1 )) " "$TMP/GW8.xml" && { ! command -v xmllint >/dev/null || xmllint --noout "$TMP/GW8.xml" 2>/dev/null; }; then
    ok "(A) the GW map is well-formed and indexes all $(( 2 * K + 1 )) fixture files"
else
    no "(A) the GW map is empty or malformed ($( head -c 200 "$TMP/GW8.xml" ))"
fi

if [ "$src2$src8" = "00" ] && [ -n "$sa2" ] && [ -n "$sa8" ] && [ "$sa2" -gt 0 ] && [ "$sa8" -gt "$sa2" ]; then
    ok "(A) step (3)'s subclass walk is reached: clause_asks=$sa2 at M=2, $sa8 at M=8"
else
    no "(A) step (3)'s subclass walk not reached (rc=$src2/$src8, M=2 '${sa2:-<no line>}', M=8 '${sa8:-<no line>}')"
fi

# ── (B) PER-ROOT ───────────────────────────────────────────────────────────────────────────────────────────────
if [ -n "$m2" ] && [ "$w2" = "$w8" ] && [ "$m2" = "$m8" ]; then
    ok "(B) the walk is paid per root, not per call: walks=$w8 meant=$m8 at both M=2 and M=8"
else
    no "(B) the walk's cost grows with the call count: M=2 walks=${w2:-?} meant=${m2:-?}, M=8 walks=${w8:-?} meant=${m8:-?}"
fi

if [ -n "$a2" ] && [ -n "$r2" ] && [ "$a8" -gt "$a2" ] && [ "$r2" -gt 0 ] && [ "$r2" = "$r8" ]; then
    ok "(B) an out-of-line owner is read once per (definition, class): reads=$r8 at both M, asks $a2 -> $a8"
else
    no "(B) out-of-line owner reads grow with the call count, or are never reached: M=2 asks=${a2:-?} reads=${r2:-?}, M=8 asks=${a8:-?} reads=${r8:-?}"
fi

if [ -n "$sr2" ] && [ "$sr2" -gt 0 ] && [ "$sr2" = "$sr8" ] && [ -n "$sl2" ] && [ "$sl2" -gt 0 ] && [ "$sl2" = "$sl8" ]; then
    ok "(B) step (3) reads each subclass clause and queues each inherited level once: clause_reads=$sr8 levels=$sl8 at both M"
else
    no "(B) step (3) re-reads per callee: M=2 clause_reads=${sr2:-?} levels=${sl2:-?}, M=8 clause_reads=${sr8:-?} levels=${sl8:-?}"
fi

# ── (C) EXACT ──────────────────────────────────────────────────────────────────────────────────────────────────
want='[mem] guarded_walk calls=1272 walks=2 cones=2 meant=52'
if [ "$line8" = "$want" ]; then
    ok "(C) GW counter is exact: $line8"
else
    no "(C) GW counter: want '$want', got '${line8:-<no guarded_walk line>}'"
fi
want='[mem] owned_by asks=1164 reads=12'
if [ "$oline8" = "$want" ]; then
    ok "(C) GW counter is exact: $oline8"
else
    no "(C) GW counter: want '$want', got '${oline8:-<no owned_by line>}'"
fi

want='[mem] subclass_walk clause_asks=64 clause_reads=8 levels=4'
if [ "$sline8" = "$want" ]; then
    ok "(C) SW counter is exact: $sline8"
else
    no "(C) SW counter: want '$want', got '${sline8:-<no subclass_walk line>}'"
fi

# ── (D) CONTROL ────────────────────────────────────────────────────────────────────────────────────────────────
if [ -n "$CONTROL" ]; then
    for pair in "GW:$GW8" "SW:$SW8"; do
        name="${pair%%:*}"; dir="${pair#*:}"
        if [ -x "$CONTROL" ] && "$CONTROL" "$dir" --no-cache >"$TMP/ctl$name.xml" 2>/dev/null && "$BIN" "$dir" --no-cache >"$TMP/bin$name.xml" 2>/dev/null \
            && [ -s "$TMP/bin$name.xml" ] && cmp -s "$TMP/ctl$name.xml" "$TMP/bin$name.xml"; then
            ok "(D) $name default map is byte-identical between the control and this binary ($( wc -c <"$TMP/bin$name.xml" | tr -d ' ' ) B)"
        else
            no "(D) $name maps differ, or a run failed (control=$CONTROL)"
        fi
    done
else
    echo "  NOTE  (D) control arm not run: set RIPWIRE_GUARDEDWALK_CONTROL_BIN to a binary without the memo"
fi

[ "$fail" -eq 0 ] && echo "guardedwalkcheck: PASS" || echo "guardedwalkcheck: FAIL"
exit "$fail"
