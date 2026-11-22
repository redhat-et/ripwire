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
# every class of the name (plausibleClasses: a visibility test per class) — again on every call, for every class the walk
# means. The answer depends on the file and the name only, so it is kept per (file, name) (OWNED-MEMO).
#
# Class identity's step (3) (a virtual call on a type whose ancestry declares the callee and defines it nowhere: the
# callee's definitions in the real subclasses) re-read, for every (receiver class, callee), two facts no callee changes:
# whether each subclass's base clause means the receiver class (plausibleClasses per subclass), and the base levels of a
# subclass that inherits its body (queueUnvisitedBases). Both are now kept: per (subclass, class) (SUBCLASS-CLAUSE-MEMO)
# and per subclass, level by level (INHERITED-LEVELS-MEMO).
#
# GW(K, M): K files, each defining `struct RootK`, `struct Base : RootK`, `struct Impl : Base` whose one method repeats
# M times the bare calls `b0()` .. `b(K-1)()` and `r()`, and `struct Peer : Base` calling `bK()` and `r()` once; one more file defines every `void Base::bK() { }` out of line, and one
# more a namesake `struct Base` no Impl derives from (so the walk's `Base` is narrowed to the K the Impls name, and the
# probe asks ownedBy). Every Impl's bare calls walk Impl's guarded bases; `Base` names K+1 classes and `Impl` K, so one
# walk's meantBase pairs K x (K+1) classes.
#
#   (A) REACHED — the RIPWIRE_STATS lines `[mem] guarded_walk calls=C walks=W cones=X meant_asks=Q meant=N` and `[mem] plausible owned_asks=A reads=R`
#       are printed and C > 0, so the arms below cannot pass on a walk the fixture never enters.
#   (B) PER-ROOT — `walks` (roots kept) and `meant` (meantBase evaluations) are the same at M=2 and at M=8 while `calls`
#       grows: the walk's cost is paid per distinct root name, not per call. Likewise `reads` (out-of-line owner answers
#       computed) is the same while `asks` grows. Unmemoised, `meant` and `reads` grow with M and this arm is red.
#   (C) EXACT — at M=8: calls=1272 (12 Impl bodies x 8 x 13 calls, plus 12 Peer bodies x 2), walks=2 (two root names,
#       `Impl` and `Peer`), cones=2 (the two caller classes whose cones the ladder proof and the bare-call test read: kept
#       per class, CONE-MEMO — the one-entry keep it replaced re-expanded a cone at every Impl/Peer switch, 24 times),
#       meant_asks=52 — per root 13 for the walk's two levels (`Base`, then Base's 12 `RootK`) plus 13 for its cone (the
#       same two levels under kConeNameCap) — of which meant=14 are computed: MEANT-MEMO keeps meantBase per (parent name,
#       parent's reading, base), and the four expansions meet Impl->Base, Peer->Base and Base->RootK x 12 only; asks=24 (one per Impl-root bK() callee and Peer-root bK, the answers kept — GUARDED-ANSWER-MEMO; per call it was 1164: the first class it asks about owns it), reads=1 (the
#       one file all 12 out-of-line definitions sit in, against the one name `Base`: OWNED-MEMO keeps plausibleClasses per
#       (file, name); kept per (definition, class) it was 12). Unmemoised the walk alone re-ran 1 or 13 meantBase per call.
# meantBase's pairing (drawnAndStandingBases) asked, for every class of the deriving name, whether the map drew an edge
# from EVERY class of the base's name to it — |deriving| x |base| binary searches. `Impl` is a name hundreds of llvm classes
# share, and chaUp merges all their bases under it, so a base one Impl names (`Visitor`, itself defined many times) is
# paired with every Impl. Now the shorter side is walked: a class's own base edges (BASE-EDGES-BY-DERIVED: the implementors
# map read backwards) or the classes of the name. `[mem] base_edges pairs=` counts the edges examined.
# BE(8): 8 files `struct BaseK` + `struct Impl : BaseK`, 8 files `struct Visitor`, one `struct Impl : Visitor`. GW(12, 8)'s
#   pairs=456 (Impl->Base and Peer->Base: 12 classes each drawn to all 13 `Base`s, so the two sides are equal there, 2 x
#   156; Base->RootK x 12: 12 x 12) and BE(8)'s pairs=16 are pinned (MEANT-MEMO computes each pairing once); walking every
#   class of the name, and per expansion, examined 1,200 in GW and 144 in BE(8).
#
# The argument-type overload pick (argtypepick.h) reads each candidate's namespace chain with the brace lexer, and
# EditCheckBraceLexer::chainAt lexes the WHOLE file per call: signatures x file size, the hottest frame of
# llvm-project/clang's resolve loop once the walks were kept. SCOPE-INDEX lexes a file once and answers every offset.
# AT(N): one file, class S with N overload pairs fK( T ) / fK( U ) and run( T x ) calling each: asks = 2N + 1 signatures
# (run's own and both overloads of each fK), passes=1 (re-lexed per ask: passes = asks).
#
# The ladder's by-name cone test (ReceiverEvidence::inCone: is a candidate's owner the caller's class or a base?) walked the
# caller class's bases once per CANDIDATE of every call, deduplicating every push by a linear scan of the whole frontier.
# RECV-CONE-MEMO keeps each type's first kWalkCap classes and stops pushing past them (nothing there is ever read).
# RC(16, M): 16 files with RootK / Base : RootK / Impl : Base, Impl's method calling r() M times — every call has 16
# candidates, each asking about Impl's cone: asks = 16 x M x 16 (512, 2048), builds=1 at both (re-walked per ask: builds = asks).
#
# SW(4, M): Shape (deriving from Root) declares f0..f(M-1) with no body; 4 Circles define them all; 4 Squares define none and inherit them
#   through Painter; use( Shape* s ) and use2( Shape* s ) call each once. (A) clause_asks > 0 and grows with M; (B) clause_reads and levels
#   are the same at M=2 and M=8; (C) at M=8 clause_asks=64 (8 callees x 8 subclasses of Shape), clause_reads=8 (one per
#   subclass), levels=4 (each Square's level 1, where Painter answers; never queued again). Two callers (use, use2) ask
#   every (Shape, fK): step (2)'s ancestor walk (inheritedDefinitions) runs once per pair — `[mem] inherited asks=16
#   walks=8` (INHERITED-MEMO; walked per ask: walks=16). Its `[mem] plausible reads=`
#   (plausibleOfName answers computed: Shape's ancestor level, each subclass's clause, each Square's bases) is the same
#   at M=2 and M=8 (PLAUSIBLE-MEMO; recomputed per ask it is 18 and 24).
# The receiver-evidence method lookup (ReceiverEvidence::methodOf: `x = Impl(); x.m()` — Impl's own m, else the shallowest base
# level defining it) walked the type's base levels on EVERY call, de-duplicating each push by a linear scan, and looked every
# class of every level up by "Class::m". METHOD-MEMO (lane PF3) keeps the answer per ( type, name, superOnly, cls ).
# RM(K, M): K Python files with RootK / Base(RootK) / Impl(Base), Base defining b and RootK defining r; use() binds x = Impl()
#   and calls x.r() and x.b() M times each. `[mem] recv_method asks=2M walks=2` (one walk per (Impl, name) question; walked
#   per ask: walks = asks).
# A call to a name some function-local definitions share (reachableByName: a local out of the call's reach yields to the
# name's other definitions) stamped every local of the name and then filtered the name's whole list — per call, though a
# call no local holds always gets the same answer: the list minus all its locals. REACH-OUTSIDE-MEMO (lane PF3) keeps that
# list per name and answers such a call with it, after one search of the name's locals by (file, start).
# RN(K, M): K Python files each nesting `def helper()` in outerK() (which calls it), h.py defining a top-level helper, and use()
#   calling helper() M times; and a.js, where wrap() and wrap2() nest `function helper()`, wrap() and deep() (in wrap2) call
#   it — a local HOLDS those three calls, so they still walk — and use() calls the top-level helper() twice.
#   `[mem] reach_by_name asks=M+5 kept=M+2`: 7/4 at M=2, 13/10 at M=8 (the per-call walk keeps none: kept=0).
# Each call still replayed its root's kept levels and probed them (ownedBy per definition per meant class) though the answer
# reads only the kept levels, the callee and two flags. GUARDED-ANSWER-MEMO (lane PF3) keeps it per (root, callee, flags) with
# the scratch the walk left (fieldWalk / walkMeant to the level it stopped at, walkUnion), restored on a replay.
# `[mem] guarded_answer asks=C kept=K`: GW(12, M) has 26 (root, callee) pairs (Impl and Peer x b0..b11, r), so asks - kept = 26
# at M=2 (336/310) and M=8 (1272/1246), and the probe's owned_asks fall to 24 at both M (1164 at M=8 per call).
# Step (3) and the inherited-body walk ask canonByName for "Class::callee" (and "Scope::Class::callee") at every class they
# visit — every real subclass, for every (class, callee) — building the key text and hashing it into the whole definitions
# table each time. CANON-SPLIT (lane PF3) splits the table's keys once at their last "::" into (scope, name) ids, keeps a
# scope id per class symbol and the last callee's id, and probes by the pair. `[mem] canon_split asks=A keyed=K`: K of the A
# class visits answered by ids (a callee with a ':' keeps the text lookup; with the ids compiled out keyed=0). SW(4, 8)
# pins asks=keyed=128 (every callee is a plain name); NS(4) — the same shape inside namespace ns, so every class visit also asks
# the "ns::Class::callee" key — pins asks=keyed=32 and joins the (D) arm.
# The external-veto tables resolve an absolute Python import Step-A cannot place by a suffix match over EVERY indexed path
# (resolvePythonModuleSuffix). FE-A's own asks were memoized per module spelling (PythonSuffixMemo), but the module-form file
# of `import X [as y]` (pythonModuleFormFile) scanned per import. PY-SUFFIX-MEMO (lane PF3) routes it through the same memo.
# PS(K): K Python files, each `import os` (outside the tree) and `import util` (pkg/util.py, a suffix hit): `[mem] py_suffix
# asks=4K scans=2` (one scan per module spelling; 2 + 2K with the form-file asks unmemoized).
#   (D) CONTROL (RIPWIRE_GUARDEDWALK_CONTROL_BIN=<a binary without the memos>) — the default maps of GW(K, 8), SW(4, 8), BE(8), AT(8), RC(16, 8), RM(4, 8), RN(4, 8), NS(4) and PS(16) are
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
        printf 'void Base::b%d() { }\n' "$f" >>"$dir/impl.cpp"   # out of line, all in one file with no Base: owner unknown
    done
    printf 'struct Base { void z(); };\n' >"$dir/other.cpp"         # a namesake no Impl derives from: the walk's Base is narrowed
}

# gensw DIR K M — step (3) of class identity (see header): Shape declares f0..f(M-1) with no body, K Circles define them,
# K Squares inherit them through Painter, and use() calls each through a Shape*
gensw(){
    local dir="$1" k="$2" m="$3" c i
    mkdir -p "$dir"
    {
        printf 'struct Root { };\nstruct Shape : Root\n{\n'
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
    for c in use use2; do   # two callers make every (Shape, fK) question twice
        {
            printf '#include "shape.h"\nvoid %s( Shape* s )\n{\n' "$c"
            for i in $( seq 0 $(( m - 1 )) ); do printf '    s->f%d();\n' "$i"; done
            printf '}\n'
        } >"$dir/$c.cpp"
    done
}

# genbe DIR N — base-edge fan-in (see header): N files with `struct BaseK` and `struct Impl : BaseK`, N files with a
# `struct Visitor`, and one more `struct Impl : Visitor`
genbe(){
    local dir="$1" n="$2" k
    mkdir -p "$dir"
    for k in $( seq 0 $(( n - 1 )) ); do
        printf 'struct Base%d { void b%d(); };\nstruct Impl : Base%d\n{\n    void run%d() { b%d(); v(); }\n};\n' "$k" "$k" "$k" "$k" "$k" >"$dir/f$k.cpp"
        printf 'struct Visitor { void v(); };\n' >"$dir/v$k.cpp"
    done
    printf 'struct Impl : Visitor\n{\n    void walk() { v(); }\n};\n' >"$dir/w.cpp"
}

# genat DIR N — the argument-type overload pick (see header): one file, a class S with N overload pairs fK( T ) / fK( U ) and a
# method run( T x ) calling each once
genat(){
    local dir="$1" n="$2" k
    mkdir -p "$dir"
    {
        printf 'namespace ns\n{\nstruct T { };\nstruct U { };\nstruct S\n{\n'
        for k in $( seq 0 $(( n - 1 )) ); do printf '    void f%d( T a ) { }\n    void f%d( U a ) { }\n' "$k" "$k"; done
        printf '    void run( T x )\n    {\n'
        for k in $( seq 0 $(( n - 1 )) ); do printf '        f%d( x );\n' "$k"; done
        printf '    }\n};\n}\n'
    } >"$dir/s.cpp"
}

# genrc DIR K M — the ladder's by-name cone (see header): K files, each `struct RootK { void r(); }`, `struct Base : RootK` and
# `struct Impl : Base` whose method calls r() M times (K candidates per call, each asked "is RootK in Impl's cone?")
genrc(){
    local dir="$1" k="$2" m="$3" f i
    mkdir -p "$dir"
    for f in $( seq 0 $(( k - 1 )) ); do
        {
            printf 'struct Root%d { void r(); };\nstruct Base : Root%d { };\nstruct Impl : Base\n{\n    void run%d()\n    {\n' "$f" "$f" "$f"
            for i in $( seq 1 "$m" ); do printf '        r();\n'; done
            printf '    }\n};\n'
        } >"$dir/f$f.cpp"
    done
}

# genrm DIR K M — the receiver-evidence method lookup (see header): K Python files RootK / Base(RootK) / Impl(Base), and use()
# calling x.r() and x.b() M times each on x = Impl()
genrm(){
    local dir="$1" k="$2" m="$3" f i
    mkdir -p "$dir"
    for f in $( seq 0 $(( k - 1 )) ); do
        printf 'class Root%d:\n    def r(self):\n        pass\n\nclass Base(Root%d):\n    def b(self):\n        pass\n\nclass Impl(Base):\n    pass\n' "$f" "$f" >"$dir/m$f.py"
    done
    {
        printf 'from m0 import Impl\n\ndef use():\n    x = Impl()\n'
        for i in $( seq 1 "$m" ); do printf '    x.r()\n    x.b()\n'; done
    } >"$dir/use.py"
}

# genrn DIR K M — the by-name reach of function-local definitions (see header)
genrn(){
    local dir="$1" k="$2" m="$3" f i
    mkdir -p "$dir"
    for f in $( seq 0 $(( k - 1 )) ); do
        printf 'def outer%d():\n    def helper():\n        return %d\n    return helper()\n' "$f" "$f" >"$dir/f$f.py"
    done
    printf 'def helper():\n    return 9\n' >"$dir/h.py"
    # and JS, whose calls inside a local's span DO reach the walk (a local holds them): wrap's and deep's helper()
    printf 'function wrap() {\n  function helper() { return 1; }\n  return helper();\n}\nfunction helper() { return 2; }\nfunction use() { helper(); helper(); }\nfunction wrap2() {\n  function helper() { return 3; }\n  function deep() { return helper(); }\n  return deep();\n}\n' >"$dir/a.js"
    {
        printf 'from h import helper\n\ndef use():\n'
        for i in $( seq 1 "$m" ); do printf '    helper()\n'; done
    } >"$dir/use.py"
}

# genns DIR N — CANON-SPLIT's nested key (see header): in namespace ns, Shape (deriving from Root) declares f0, f1 bodiless; N
# Circles define them in class (scope "ns": the "ns::CircleK::fJ" key too); N Squares inherit Painter's; ns::use( Shape* s ) calls both
genns(){
    local dir="$1" n="$2" c
    mkdir -p "$dir"
    printf 'namespace ns\n{\nstruct Root { };\nstruct Shape : Root\n{\n    virtual void f0() = 0;\n    virtual void f1() = 0;\n};\nstruct Painter\n{\n    void f0() { }\n    void f1() { }\n};\n}\n' >"$dir/shape.h"
    for c in $( seq 0 $(( n - 1 )) ); do
        printf '#include "shape.h"\nnamespace ns\n{\nstruct Circle%d : Shape\n{\n    void f0() override { }\n    void f1() override { }\n};\nstruct Square%d : Shape, Painter { };\n}\n' "$c" "$c" >"$dir/c$c.cpp"
    done
    printf '#include "shape.h"\nnamespace ns\n{\nvoid use( Shape* s )\n{\n    s->f0();\n    s->f1();\n}\n}\n' >"$dir/use.cpp"
}

# genps DIR K — the Python suffix scan (see header)
genps(){
    local dir="$1" k="$2" f
    mkdir -p "$dir/pkg"
    : >"$dir/pkg/__init__.py"
    printf 'def helper():\n    return 1\n' >"$dir/pkg/util.py"
    for f in $( seq 0 $(( k - 1 )) ); do
        printf 'import os\nimport util\n\ndef f%d():\n    return util.helper() + len(os.sep)\n' "$f" >"$dir/m$f.py"
    done
}

# stats NAME DIR — run with RIPWIRE_STATS, set LINE / CALLS / WALKS / MEANT
stats(){
    local name="$1" dir="$2"
    env RIPWIRE_STATS=1 "$BIN" "$dir" --no-cache >"$TMP/$name.xml" 2>"$TMP/$name.err"; RC=$?
    LINE="$( grep -F '[mem] guarded_walk ' "$TMP/$name.err" )"
    CALLS="$( printf '%s' "$LINE" | sed -n 's/.* calls=\([0-9]*\).*/\1/p' )"
    WALKS="$( printf '%s' "$LINE" | sed -n 's/.* walks=\([0-9]*\).*/\1/p' )"
    MEANT="$( printf '%s' "$LINE" | sed -n 's/.* meant=\([0-9]*\).*/\1/p' )"
    OLINE="$( grep -F '[mem] plausible ' "$TMP/$name.err" )"
    ASKS="$( printf '%s' "$OLINE" | sed -n 's/.* owned_asks=\([0-9]*\).*/\1/p' )"
    READS="$( printf '%s' "$OLINE" | sed -n 's/.* reads=\([0-9]*\).*/\1/p' )"
    BLINE="$( grep -F '[mem] base_edges ' "$TMP/$name.err" )"
    ALINE="$( grep -F '[mem] arg_type_chain ' "$TMP/$name.err" )"
    RLINE="$( grep -F '[mem] recv_cone ' "$TMP/$name.err" )"
    SLINE="$( grep -F '[mem] subclass_walk ' "$TMP/$name.err" )"
    ILINE="$( grep -F '[mem] inherited ' "$TMP/$name.err" )"
    MLINE="$( grep -F '[mem] recv_method ' "$TMP/$name.err" )"
    GALINE="$( grep -F '[mem] guarded_answer ' "$TMP/$name.err" )"
    NLINE="$( grep -F '[mem] reach_by_name ' "$TMP/$name.err" )"
    CSLINE="$( grep -F '[mem] canon_split ' "$TMP/$name.err" )"
    PSLINE="$( grep -F '[mem] py_suffix ' "$TMP/$name.err" )"
    CASKS="$( printf '%s' "$SLINE" | sed -n 's/.* clause_asks=\([0-9]*\).*/\1/p' )"
    CREADS="$( printf '%s' "$SLINE" | sed -n 's/.* clause_reads=\([0-9]*\).*/\1/p' )"
    LEVELS="$( printf '%s' "$SLINE" | sed -n 's/.* levels=\([0-9]*\).*/\1/p' )"
}

GW2="$TMP/gw2"; gen "$GW2" "$K" 2
GW8="$TMP/gw8"; gen "$GW8" "$K" 8

BE8="$TMP/be8"; genbe "$BE8" 8
RC2="$TMP/rc2"; genrc "$RC2" 16 2
RC8="$TMP/rc8"; genrc "$RC8" 16 8
AT2="$TMP/at2"; genat "$AT2" 2
AT8="$TMP/at8"; genat "$AT8" 8
RM2="$TMP/rm2"; genrm "$RM2" 4 2
RM8="$TMP/rm8"; genrm "$RM8" 4 8
RN2="$TMP/rn2"; genrn "$RN2" 4 2
RN8="$TMP/rn8"; genrn "$RN8" 4 8
NS4="$TMP/ns4"; genns "$NS4" 4
PS4="$TMP/ps4"; genps "$PS4" 4
PS16="$TMP/ps16"; genps "$PS16" 16
SW2="$TMP/sw2"; gensw "$SW2" 4 2
SW8="$TMP/sw8"; gensw "$SW8" 4 8

stats GW2 "$GW2"; c2="$CALLS" w2="$WALKS" m2="$MEANT" rc2=$RC a2="$ASKS" r2="$READS" galine2="$GALINE"
stats GW8 "$GW8"; c8="$CALLS" w8="$WALKS" m8="$MEANT" rc8=$RC line8="$LINE" a8="$ASKS" r8="$READS" oline8="$OLINE" bline8="$BLINE" galine8="$GALINE"

stats BE8 "$BE8"; beline8="$BLINE" berc=$RC
stats RC2 "$RC2"; rcline2="$RLINE"
stats RC8 "$RC8"; rcline8="$RLINE" rcrc=$RC
stats AT2 "$AT2"; atline2="$ALINE"
stats AT8 "$AT8"; atline8="$ALINE" atrc=$RC
stats RM2 "$RM2"; rmline2="$MLINE"
stats RM8 "$RM8"; rmline8="$MLINE" rmrc=$RC
stats RN2 "$RN2"; rnline2="$NLINE"
stats RN8 "$RN8"; rnline8="$NLINE" rnrc=$RC
stats NS4 "$NS4"; nsline="$CSLINE" nsrc=$RC
stats PS4 "$PS4"; psline4="$PSLINE"
stats PS16 "$PS16"; psline16="$PSLINE" psrc=$RC
stats SW2 "$SW2"; sa2="$CASKS" sr2="$CREADS" sl2="$LEVELS" src2=$RC sp2="$READS"
stats SW8 "$SW8"; sa8="$CASKS" sr8="$CREADS" sl8="$LEVELS" src8=$RC sline8="$SLINE" sp8="$READS" spline8="$OLINE" iline8="$ILINE" swcs8="$CSLINE"

# ── (A) REACHED ────────────────────────────────────────────────────────────────────────────────────────────────
if [ "$rc2$rc8" = "00" ] && [ -n "$c2" ] && [ -n "$c8" ] && [ "$c2" -gt 0 ] && [ "$c8" -gt "$c2" ]; then
    ok "(A) the guarded walk is reached: calls=$c2 at M=2, calls=$c8 at M=8"
else
    no "(A) no guarded walk reached (rc=$rc2/$rc8, M=2 '${c2:-<no line>}', M=8 '${c8:-<no line>}')"
fi
if grep -q "files=$(( K + 2 )) " "$TMP/GW8.xml" && { ! command -v xmllint >/dev/null || xmllint --noout "$TMP/GW8.xml" 2>/dev/null; }; then
    ok "(A) the GW map is well-formed and indexes all $(( K + 2 )) fixture files"
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

# GUARDED-ANSWER-MEMO (lane PF3) keeps each (root, callee) answer, so the probe — and its ownedBy asks — runs once per pair:
# asks no longer grow with M (they did, 1164 at M=8, before it; the arm then read "asks grow, reads stay")
if [ -n "$a2" ] && [ -n "$r2" ] && [ "$a2" -gt 0 ] && [ "$a2" = "$a8" ] && [ "$r2" -gt 0 ] && [ "$r2" = "$r8" ]; then
    ok "(B) an out-of-line owner is read once per (file, name), and asked once per (root, callee): reads=$r8 asks=$a8 at both M"
else
    no "(B) out-of-line owner asks or reads grow with the call count, or are never reached: M=2 asks=${a2:-?} reads=${r2:-?}, M=8 asks=${a8:-?} reads=${r8:-?}"
fi
if [ "$galine2" = '[mem] guarded_answer asks=336 kept=310' ] && [ "$galine8" = '[mem] guarded_answer asks=1272 kept=1246' ]; then
    ok "(B)(C) GW: the guarded walk answers each (root, callee) once, every later call replays it (26 walked at both M): $galine2 / $galine8"
else
    no "(B)(C) GW guarded_answer: want 'asks=336 kept=310' at M=2 and 'asks=1272 kept=1246' at M=8, got '${galine2:-<none>}' / '${galine8:-<none>}'"
fi

if [ -n "$sr2" ] && [ "$sr2" -gt 0 ] && [ "$sr2" = "$sr8" ] && [ -n "$sl2" ] && [ "$sl2" -gt 0 ] && [ "$sl2" = "$sl8" ]; then
    ok "(B) step (3) reads each subclass clause and queues each inherited level once: clause_reads=$sr8 levels=$sl8 at both M"
else
    no "(B) step (3) re-reads per callee: M=2 clause_reads=${sr2:-?} levels=${sl2:-?}, M=8 clause_reads=${sr8:-?} levels=${sl8:-?}"
fi

if [ -n "$sp2" ] && [ "$sp2" -gt 0 ] && [ "$sp2" = "$sp8" ]; then
    ok "(B) step (3)'s walks read each (file, name) plausible set once: reads=$sp8 at both M"
else
    no "(B) step (3)'s plausible reads grow with the callee count, or are never reached: M=2 reads=${sp2:-?}, M=8 reads=${sp8:-?}"
fi

# ── (C) EXACT ──────────────────────────────────────────────────────────────────────────────────────────────────
want='[mem] guarded_walk calls=1272 walks=2 cones=2 meant_asks=52 meant=14'
if [ "$line8" = "$want" ]; then
    ok "(C) GW counter is exact: $line8"
else
    no "(C) GW counter: want '$want', got '${line8:-<no guarded_walk line>}'"
fi
want='[mem] plausible owned_asks=24 reads=1'
if [ "$oline8" = "$want" ]; then
    ok "(C) GW counter is exact: $oline8"
else
    no "(C) GW counter: want '$want', got '${oline8:-<no owned_by line>}'"
fi

want='[mem] base_edges pairs=456'
if [ "$bline8" = "$want" ]; then
    ok "(C) GW counter is exact: $bline8"
else
    no "(C) GW counter: want '$want', got '${bline8:-<no base_edges line>}'"
fi
want='[mem] base_edges pairs=16'
if [ "$berc" = 0 ] && [ "$beline8" = "$want" ]; then
    ok "(C) BE counter is exact: $beline8"
else
    no "(C) BE counter: want '$want', got '${beline8:-<no base_edges line>}' (rc=$berc)"
fi
want='[mem] arg_type_chain asks=17 passes=1'
if [ "$atrc" = 0 ] && [ "$atline8" = "$want" ] && [ "$atline2" = '[mem] arg_type_chain asks=5 passes=1' ]; then
    ok "(B)(C) AT: one lexer pass per file however many signatures ask: $atline2 at N=2, $atline8 at N=8"
else
    no "(B)(C) AT counter: want 'asks=5 passes=1' at N=2 and '$want' at N=8, got '${atline2:-<none>}' / '${atline8:-<none>}' (rc=$atrc)"
fi
want='[mem] recv_cone asks=2048 builds=1'
if [ "$rcrc" = 0 ] && [ "$rcline8" = "$want" ] && [ "$rcline2" = '[mem] recv_cone asks=512 builds=1' ]; then
    ok "(B)(C) RC: one cone walk per type however many candidates ask: $rcline2 at M=2, $rcline8 at M=8"
else
    no "(B)(C) RC counter: want 'asks=512 builds=1' at M=2 and '$want' at M=8, got '${rcline2:-<none>}' / '${rcline8:-<none>}' (rc=$rcrc)"
fi
want='[mem] recv_method asks=16 walks=2 kept=2'
if [ "$rmrc" = 0 ] && [ "$rmline8" = "$want" ] && [ "$rmline2" = '[mem] recv_method asks=4 walks=2 kept=2' ]; then
    ok "(B)(C) RM: one base-level walk per (type, name) however many calls ask: $rmline2 at M=2, $rmline8 at M=8"
else
    no "(B)(C) RM counter: want 'asks=4 walks=2 kept=2' at M=2 and '$want' at M=8, got '${rmline2:-<none>}' / '${rmline8:-<none>}' (rc=$rmrc)"
fi
want='[mem] reach_by_name asks=13 kept=10'
if [ "$rnrc" = 0 ] && [ "$rnline8" = "$want" ] && [ "$rnline2" = '[mem] reach_by_name asks=7 kept=4' ]; then
    ok "(C) RN: every call no local holds is answered from the name's kept list, the three a local holds walk: $rnline2 at M=2, $rnline8 at M=8"
else
    no "(C) RN counter: want 'asks=7 kept=4' at M=2 and '$want' at M=8, got '${rnline2:-<none>}' / '${rnline8:-<none>}' (rc=$rnrc)"
fi
want='[mem] canon_split asks=128 keyed=128'
if [ "$swcs8" = "$want" ]; then
    ok "(C) SW: every class visit of step (3) is answered by CANON-SPLIT's ids: $swcs8"
else
    no "(C) SW canon_split counter: want '$want', got '${swcs8:-<no canon_split line>}'"
fi
want='[mem] canon_split asks=32 keyed=32'
if [ "$nsrc" = 0 ] && [ "$nsline" = "$want" ]; then
    ok "(C) NS: the nested \"Scope::Class::callee\" key is answered by ids too: $nsline"
else
    no "(C) NS canon_split counter: want '$want', got '${nsline:-<no canon_split line>}' (rc=$nsrc)"
fi
want='[mem] py_suffix asks=64 scans=2'
if [ "$psrc" = 0 ] && [ "$psline16" = "$want" ] && [ "$psline4" = '[mem] py_suffix asks=16 scans=2' ]; then
    ok "(B)(C) PS: one suffix scan per module spelling however many imports ask: $psline4 at K=4, $psline16 at K=16"
else
    no "(B)(C) PS counter: want 'asks=16 scans=2' at K=4 and '$want' at K=16, got '${psline4:-<none>}' / '${psline16:-<none>}' (rc=$psrc)"
fi
want='[mem] inherited asks=16 walks=8'
if [ "$iline8" = "$want" ]; then
    ok "(C) SW: step (2)'s ancestor walk runs once per (class, callee) though two callers ask: $iline8"
else
    no "(C) SW inherited counter: want '$want', got '${iline8:-<no inherited line>}'"
fi
want='[mem] subclass_walk clause_asks=64 clause_reads=8 levels=4'
if [ "$sline8" = "$want" ]; then
    ok "(C) SW counter is exact: $sline8"
else
    no "(C) SW counter: want '$want', got '${sline8:-<no subclass_walk line>}'"
fi

# ── (D) CONTROL ────────────────────────────────────────────────────────────────────────────────────────────────
if [ -n "$CONTROL" ]; then
    for pair in "GW:$GW8" "SW:$SW8" "BE:$BE8" "AT:$AT8" "RC:$RC8" "RM:$RM8" "RN:$RN8" "NS:$NS4" "PS:$PS16"; do
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
