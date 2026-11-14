#!/usr/bin/env bash
# warmsnapcheck.sh — the warm snapshot (src/warmsnap.h): a run that LOADS the tree, the model and the resolved graph
# from `<cache>.snap` must print the bytes a run that walks, decodes and resolves prints. No modulo, no normalisation.
#
# The corpus is every test/*fix directory copied into one tree (C, C++, C#, Dart, Elixir, Go, Java, JS, Kotlin, PHP,
# Python, Ruby, Rust, TS, ...), so one run crosses every language's resolve rules.
#
# The observable is one stderr line under RIPWIRE_SNAPSHOT_STATS=1:
#   ripwire: snapshot-stats tree=walked|replayed model=built|loaded graph=built|loaded why=<first refusal> model_why= graph_why= saved=0|1
#
# ARMS
#   V   vacuity guard: the second run on an unchanged tree must say graph=loaded AND tree=replayed. A build without
#       the snapshot prints no such line, so "nothing was loaded, the two outputs are trivially equal" is a FAIL here,
#       never a pass. Every identity arm below re-asserts the load on the very run whose bytes it compares.
#   I   identity: per verb, stdout of the loading run == stdout of a --no-cache run (which builds everything).
#   S   a stale snapshot is REFUSED and the answer is the full build's: (S6) the parse cache blob is gone; (S7) other
#       options; (S1) one file's content changed; (S2) the
#       snapshot's version field differs; (S3) a flipped byte in the body; (S4) a truncated file; (S5) a file the
#       resolver read outside the crawl (go.mod) changed.
#   L   the crawl replay is REFUSED, and the answer is the full crawl's, when the tree moved: (a) a file added, with no
#       pause after the recording run; (b) a file deleted; (c) a file modified in place at the SAME size — once
#       plainly and once with its mtime put back; (d) a file added inside a new subdirectory; (e) a .gitignore changed;
#       (f) a file added under a directory git reported ignored as a whole.
#
#   RIPWIRE_BIN=./build/ripwire bash test/warmsnapcheck.sh
#
# Exits non-zero on any failure. Prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "warmsnapcheck: BIN=$BIN  TMP=$TMP"
export XDG_CACHE_HOME="$TMP/xdg"; mkdir -p "$XDG_CACHE_HOME"   # the ignore-probe sidecar stays inside TMP

# run CACHE ROOT OUT [verb args...] — one cached run; stdout to OUT, the stats line to OUT.stats
run()
{
    local cache="$1" root="$2" out="$3"; shift 3
    RIPWIRE_CACHE_STATS=1 RIPWIRE_SNAPSHOT_STATS=1 "$BIN" "$root" --cache="$cache" "$@" >"$out" 2>"$out.err"
    grep '^ripwire: snapshot-stats ' "$out.err" >"$out.stats" || : >"$out.stats"
}
# full ROOT OUT [verb args...] — the reference: no cache, so the tree is walked, parsed and resolved
full()
{
    local root="$1" out="$2"; shift 2
    "$BIN" "$root" --no-cache "$@" >"$out" 2>/dev/null
}
has(){ grep -q -- "$2" "$1.stats"; }   # has OUT 'graph=loaded'
# same LABEL A B — byte identity, and the reference must not be empty (an empty pair is no evidence)
same()
{
    if [ ! -s "$3" ]; then no "$1 — the reference run printed nothing"; return; fi
    if cmp -s "$2" "$3"; then ok "$1"; else no "$1 — stdout differs from the full build ($( cmp "$2" "$3" 2>&1 | head -1 ))"; fi
}
# refused LABEL OUT FIELD — the fast path named by FIELD (tree=replayed / graph=loaded / model=loaded) was NOT taken,
# and the run still printed a stats line (so "no line at all" cannot read as a refusal)
refused()
{
    if [ ! -s "$2.stats" ]; then no "$1 — no snapshot-stats line (the snapshot is not in this binary)"; return; fi
    if has "$2" "$3"; then no "$1 — $3 on a tree that moved: $( cat "$2.stats" )"; else ok "$1 ($( sed 's/^ripwire: snapshot-stats //' "$2.stats" ))"; fi
}

# ── the corpus ────────────────────────────────────────────────────────────────────────────────────
mkcorpus()
{
    local dst="$1"; mkdir -p "$dst"
    for d in "$ROOT"/test/*fix; do cp -R "$d" "$dst/" 2>/dev/null; done
    mkdir -p "$dst/gomod"
    printf 'module example.com/snap\n\ngo 1.21\n' >"$dst/gomod/go.mod"
    printf 'package main\n\nimport "example.com/snap/lib"\n\nfunc main() {\n\tlib.Hello()\n}\n' >"$dst/gomod/main.go"
    mkdir -p "$dst/gomod/lib"
    printf 'package lib\n\nfunc Hello() int {\n\treturn 1\n}\n' >"$dst/gomod/lib/lib.go"
}
W="$TMP/w"; mkcorpus "$W"
C="$TMP/c.bin"

# ── V: the vacuity guard ──────────────────────────────────────────────────────────────────────────
run "$C" "$W" "$TMP/v.cold"
sleep 2                                   # leave the recording run's racy window (directory mtimes, as the stat gate's)
run "$C" "$W" "$TMP/v.warm1"              # may re-record entries that were racy at the cold run
sleep 2
run "$C" "$W" "$TMP/v.warm"
if has "$TMP/v.warm" 'graph=loaded'; then ok "V  the unchanged tree's second run LOADED the graph section"
else no "V  VACUOUS: no run loaded a graph section ($( cat "$TMP/v.warm.stats" 2>/dev/null || echo 'no snapshot-stats line' )) — every identity below would compare a build with a build"; fi
if has "$TMP/v.warm" 'tree=replayed'; then ok "V  the unchanged tree's second run REPLAYED the crawl"
else no "V  VACUOUS: no run replayed the crawl ($( cat "$TMP/v.warm.stats" 2>/dev/null || echo 'no snapshot-stats line' ))"; fi
if has "$TMP/v.warm" 'model=loaded'; then ok "V  the unchanged tree's second run LOADED the model section"
else no "V  VACUOUS: no run loaded a model section ($( cat "$TMP/v.warm.stats" 2>/dev/null || echo 'no snapshot-stats line' ))"; fi
if [ -s "$C.snap" ]; then ok "V  $( basename "$C" ).snap exists ($( wc -c <"$C.snap" | tr -d ' ' ) B)"; else no "V  no snapshot file was written beside the cache"; fi

# V2: the options key is of the SET of environment variables, not of the order the parent shell exports them in (zsh and
#     bash differ, measured: every run launched from the other shell refused the snapshot as why=options)
envrun(){ env -i "$@" RIPWIRE_SNAPSHOT_STATS=1 "$BIN" "$W" --cache="$TMP/v2.bin" 2>&1 >/dev/null | grep '^ripwire: snapshot-stats ' >"$TMP/v2.stats"; }
envrun HOME="$HOME" PATH="$PATH" XDG_CACHE_HOME="$XDG_CACHE_HOME" GIT_EDITOR=true; sleep 2
envrun HOME="$HOME" PATH="$PATH" XDG_CACHE_HOME="$XDG_CACHE_HOME" GIT_EDITOR=true
envrun HOME="$HOME" PATH="$PATH" XDG_CACHE_HOME="$XDG_CACHE_HOME" GIT_EDITOR=true
if grep -q 'graph=loaded' "$TMP/v2.stats"; then ok "V2 the snapshot is served under the environment it was recorded in"; else no "V2 VACUOUS: not served under its own environment: $( cat "$TMP/v2.stats" )"; fi
envrun GIT_EDITOR=true XDG_CACHE_HOME="$XDG_CACHE_HOME" PATH="$PATH" HOME="$HOME"
if grep -q 'graph=loaded' "$TMP/v2.stats"; then ok "V2 ...and under the same variables exported in another order"; else no "V2 the same variables in another order refused the snapshot: $( cat "$TMP/v2.stats" )"; fi
envrun HOME="$HOME" PATH="$PATH" XDG_CACHE_HOME="$XDG_CACHE_HOME" GIT_EDITOR=true GIT_CEILING_DIRECTORIES=/nowhere
if grep -q 'why=options' "$TMP/v2.stats"; then ok "V2 ...and refused when a GIT_* variable appears (why=options)"; else no "V2 a new GIT_* variable did not refuse the snapshot: $( cat "$TMP/v2.stats" )"; fi

# ── I: identity, per verb ─────────────────────────────────────────────────────────────────────────
ident()
{
    local tag="$1"; shift
    local cache="$TMP/i.$tag.bin"
    run "$cache" "$W" "$TMP/i.$tag.cold" "$@"
    sleep 2
    run "$cache" "$W" "$TMP/i.$tag.w1" "$@"
    run "$cache" "$W" "$TMP/i.$tag.warm" "$@"
    full "$W" "$TMP/i.$tag.full" "$@"
    if has "$TMP/i.$tag.warm" "${MARK:-graph=loaded}" && has "$TMP/i.$tag.warm" 'model=loaded'; then
        same "I  [$tag] loaded == built ($( sed 's/^ripwire: snapshot-stats //' "$TMP/i.$tag.warm.stats" ))" "$TMP/i.$tag.warm" "$TMP/i.$tag.full"
    else
        no "I  [$tag] VACUOUS: the run under comparison is not ${MARK:-graph=loaded} with model=loaded ($( cat "$TMP/i.$tag.warm.stats" ))"
    fi
    same "I  [$tag] the recording (cold) run == built" "$TMP/i.$tag.cold" "$TMP/i.$tag.full"
}
ident map
ident map-nostable   --no-stable
ident json           --json
ident metrics        --metrics
ident callers        --callers=Hello
ident callees        --callees=main
ident impact         --impact=Hello
ident uses           --uses=Hello
ident around         --around=main
ident for            --for="hello main lib"
ident clones         --clones
MARK='tree=replayed' ident deps --deps      # --deps never reads the graph (graphUnreadByWinner): the crawl replay is what it loads
ident defs           --defs=Hello
ident expand         --expand=Hello
ident tree           --tree
ident seams          --seams
ident lint           --lint
ident packtask       --pack-task="hello main lib"
ident rankchurn      --rank-by=pagerank
ident deadcode       --dead-code
ident lego           --lego=Shape
ident skipped        --skipped
ident grep           --grep=Hello
ident topk           --top-k=40

# ── S: a stale or damaged snapshot is refused ─────────────────────────────────────────────────────
snapof(){ cp -R "$W" "$1"; run "$2" "$1" "$TMP/s.prime"; sleep 2; run "$2" "$1" "$TMP/s.prime2"; run "$2" "$1" "$TMP/s.prime3"; }

S1="$TMP/s1"; snapof "$S1" "$TMP/s1.bin"
has "$TMP/s.prime3" 'graph=loaded' || no "S1 VACUOUS: the tree was never served from the snapshot before the edit"
printf 'package lib\n\nfunc Hello() int {\n\treturn Other()\n}\n\nfunc Other() int {\n\treturn 2\n}\n' >"$S1/gomod/lib/lib.go"
run "$TMP/s1.bin" "$S1" "$TMP/s1.out"; full "$S1" "$TMP/s1.full"
refused "S1 one changed file refuses the graph section" "$TMP/s1.out" 'graph=loaded'
refused "S1 one changed file refuses the model section" "$TMP/s1.out" 'model=loaded'
if has "$TMP/s1.out" 'graph_why=stale'; then ok "S1 the refusal is the tree key's (graph_why=stale)"; else no "S1 the graph was not refused by its tree key: $( cat "$TMP/s1.out.stats" )"; fi
same    "S1 the answer after the edit == built" "$TMP/s1.out" "$TMP/s1.full"
run "$TMP/s1.bin" "$S1" "$TMP/s1.defs" --defs=Other
if grep -q 'lib.go' "$TMP/s1.defs"; then ok "S1 the new symbol is in the answer"; else no "S1 the new symbol is missing from the answer"; fi

# patch OFFSET BYTE FILE — overwrite one byte in place
patch(){ printf "$( printf '\\%03o' "$2" )" | dd of="$3" bs=1 seek="$1" conv=notrunc 2>/dev/null; }

S2="$TMP/s2"; snapof "$S2" "$TMP/s2.bin"
has "$TMP/s.prime3" 'graph=loaded' || no "S2 VACUOUS: the tree was never served from the snapshot before the patch"
patch 8 255 "$TMP/s2.bin.snap"            # byte 8: the low byte of the snapshot's format version
run "$TMP/s2.bin" "$S2" "$TMP/s2.out"; full "$S2" "$TMP/s2.full"
refused "S2 a version-mismatched snapshot refuses the graph" "$TMP/s2.out" 'graph=loaded'
refused "S2 a version-mismatched snapshot refuses the crawl replay" "$TMP/s2.out" 'tree=replayed'
if has "$TMP/s2.out" 'why=version'; then ok "S2 the refusal names the version"; else no "S2 the refusal does not say why=version: $( cat "$TMP/s2.out.stats" )"; fi
same    "S2 the answer == built" "$TMP/s2.out" "$TMP/s2.full"
run "$TMP/s2.bin" "$S2" "$TMP/s2.again"; run "$TMP/s2.bin" "$S2" "$TMP/s2.again"
if has "$TMP/s2.again" 'graph=loaded'; then ok "S2 the refused snapshot was rebuilt: the next run loads"; else no "S2 the snapshot did not heal: $( cat "$TMP/s2.again.stats" )"; fi

S3="$TMP/s3"; snapof "$S3" "$TMP/s3.bin"
sz=$( wc -c <"$TMP/s3.bin.snap" | tr -d ' ' )
for frac in 3 5 7 9; do
    cp "$TMP/s3.bin.snap" "$TMP/s3.keep"
    off=$(( sz * frac / 10 ))
    was=$( dd if="$TMP/s3.bin.snap" bs=1 skip="$off" count=1 2>/dev/null | od -An -tu1 | tr -d ' ' )
    patch "$off" $(( ( was + 1 ) % 256 )) "$TMP/s3.bin.snap"
    run "$TMP/s3.bin" "$S3" "$TMP/s3.out"; full "$S3" "$TMP/s3.full"
    same "S3 a flipped byte at ${frac}0% of the snapshot: the answer == built ($( sed 's/^ripwire: snapshot-stats //' "$TMP/s3.out.stats" ))" "$TMP/s3.out" "$TMP/s3.full"
    if has "$TMP/s3.out" 'why=checksum'; then ok "S3 ...and the refusal says why=checksum"; else no "S3 a flipped byte at ${frac}0% was not refused as a checksum failure: $( cat "$TMP/s3.out.stats" )"; fi
    cp "$TMP/s3.keep" "$TMP/s3.bin.snap"
done

S4="$TMP/s4"; snapof "$S4" "$TMP/s4.bin"
sz=$( wc -c <"$TMP/s4.bin.snap" | tr -d ' ' )
dd if="$TMP/s4.bin.snap" of="$TMP/s4.cut" bs=1 count=$(( sz / 2 )) 2>/dev/null && mv "$TMP/s4.cut" "$TMP/s4.bin.snap"
run "$TMP/s4.bin" "$S4" "$TMP/s4.out"; full "$S4" "$TMP/s4.full"
refused "S4 a truncated snapshot refuses the graph" "$TMP/s4.out" 'graph=loaded'
same    "S4 the answer == built" "$TMP/s4.out" "$TMP/s4.full"

S5="$TMP/s5"; snapof "$S5" "$TMP/s5.bin"
has "$TMP/s.prime3" 'graph=loaded' || no "S5 VACUOUS: the tree was never served from the snapshot before the edit"
printf 'module example.com/renamed\n\ngo 1.21\n' >"$S5/gomod/go.mod"
run "$TMP/s5.bin" "$S5" "$TMP/s5.out"; full "$S5" "$TMP/s5.full"
refused "S5 a changed go.mod (read by the resolver, outside the parse cache) refuses the graph" "$TMP/s5.out" 'graph=loaded'
same    "S5 the answer == built" "$TMP/s5.out" "$TMP/s5.full"
if has "$TMP/s5.out" 'graph_why=dep'; then ok "S5 the refusal is the dependency log's (graph_why=dep): the tree key alone did not move"; else no "S5 the graph was not refused by its dependency log: $( cat "$TMP/s5.out.stats" )"; fi

# S6: the parse cache blob is gone (or another configuration rewrote it): the model built from it is not served
S6="$TMP/s6"; snapof "$S6" "$TMP/s6.bin"
has "$TMP/s.prime3" 'model=loaded' || no "S6 VACUOUS: the model was never served before the blob was removed"
rm -f "$TMP/s6.bin"
run "$TMP/s6.bin" "$S6" "$TMP/s6.out"; full "$S6" "$TMP/s6.full"
refused "S6 a removed parse cache blob refuses the model" "$TMP/s6.out" 'model=loaded'
same    "S6 the answer == built" "$TMP/s6.out" "$TMP/s6.full"
if grep -q 'cache-stats reparsed=[1-9]' "$TMP/s6.out.err"; then ok "S6 ...and the run re-parsed, as a run with no blob always did"; else no "S6 the run did not re-parse: $( grep cache-stats "$TMP/s6.out.err" )"; fi

# S7: a rich-class verb (--for) and a lean one share nothing: each cache file has its own snapshot, keyed on its class
run "$TMP/s7.bin" "$W" "$TMP/s7.a"; sleep 2; run "$TMP/s7.bin" "$W" "$TMP/s7.a"; run "$TMP/s7.bin" "$W" "$TMP/s7.a"
run "$TMP/s7.bin" "$W" "$TMP/s7.b" --exclude=gomod; full "$W" "$TMP/s7.bfull" --exclude=gomod
refused "S7 another --exclude set refuses the whole snapshot" "$TMP/s7.b" 'graph=loaded'
if has "$TMP/s7.b" 'why=options'; then ok "S7 ...as recorded under other options (why=options)"; else no "S7 the refusal is not why=options: $( cat "$TMP/s7.b.stats" )"; fi
same    "S7 the answer == built" "$TMP/s7.b" "$TMP/s7.bfull"

# ── L: the crawl replay is refused when the tree moved ────────────────────────────────────────────
# prime DIR CACHE — record, leave the racy window, and prove the replay engaged (else the arm is vacuous)
prime()
{
    run "$2" "$1" "$TMP/l.p1"; sleep 2; run "$2" "$1" "$TMP/l.p2"; run "$2" "$1" "$TMP/l.p3"
    has "$TMP/l.p3" 'tree=replayed' || no "L  VACUOUS for $( basename "$1" ): the crawl was never replayed before the change ($( cat "$TMP/l.p3.stats" 2>/dev/null ))"
}
# moved LABEL DIR CACHE NEEDLE — the run after the change walked, matches the full crawl, and carries NEEDLE
moved()
{
    run "$3" "$2" "$TMP/l.out"; full "$2" "$TMP/l.full"
    refused "L$1: the crawl replay is refused" "$TMP/l.out" 'tree=replayed'
    refused "L$1: the model section is refused" "$TMP/l.out" 'model=loaded'
    same    "L$1: the answer == the full crawl's" "$TMP/l.out" "$TMP/l.full"
    run "$3" "$2" "$TMP/l.again"; full "$2" "$TMP/l.full2"
    same    "L$1: the next run == the full crawl's too" "$TMP/l.again" "$TMP/l.full2"
    if [ -n "${4:-}" ]; then      # the changed symbol, asked for by name: the default map may rank it below its cut
        run "$3" "$2" "$TMP/l.defs" --defs="$4"; full "$2" "$TMP/l.defs.full" --defs="$4"
        same "L$1: --defs=$4 == the full crawl's" "$TMP/l.defs" "$TMP/l.defs.full"
        if grep -q -- "$5" "$TMP/l.defs"; then ok "L$1: the answer shows the change ($5)"; else no "L$1: the answer does not show the change ($5): $( head -c 300 "$TMP/l.defs" )"; fi
    fi
}

LA="$TMP/la"; cp -R "$W" "$LA"; prime "$LA" "$TMP/la.bin"
printf 'package lib\n\nfunc AddedLater() int {\n\treturn 7\n}\n' >"$LA/gomod/lib/added.go"
moved "(a) a file added" "$LA" "$TMP/la.bin" AddedLater added.go

# (a') added with NO pause after the recording run: the directory's mtime may equal the recorded one's granule
LA2="$TMP/la2"; cp -R "$W" "$LA2"
run "$TMP/la2.bin" "$LA2" "$TMP/l.p1"
printf 'package lib\n\nfunc AddedAtOnce() int {\n\treturn 8\n}\n' >"$LA2/gomod/lib/atonce.go"
moved "(a') a file added straight after the recording run" "$LA2" "$TMP/la2.bin" AddedAtOnce atonce.go

LB="$TMP/lb"; cp -R "$W" "$LB"; prime "$LB" "$TMP/lb.bin"
rm "$LB/gomod/lib/lib.go"
moved "(b) a file deleted" "$LB" "$TMP/lb.bin" ""
run "$TMP/lb.bin" "$LB" "$TMP/lb.defs" --defs=Hello
grep -q 'gomod/lib/lib.go' "$TMP/lb.defs" && no "L(b): the deleted file is still in the answer" || ok "L(b): the deleted file left the answer"

LC="$TMP/lc"; cp -R "$W" "$LC"; prime "$LC" "$TMP/lc.bin"
printf 'package lib\n\nfunc Jello() int {\n\treturn 1\n}\n' >"$LC/gomod/lib/lib.go"          # same byte length as Hello
moved "(c) a same-size in-place edit" "$LC" "$TMP/lc.bin" Jello lib.go

LC2="$TMP/lc2"; cp -R "$W" "$LC2"; prime "$LC2" "$TMP/lc2.bin"
cp -p "$LC2/gomod/lib/lib.go" "$TMP/lc2.ref"
printf 'package lib\n\nfunc Cello() int {\n\treturn 1\n}\n' >"$LC2/gomod/lib/lib.go"
touch -r "$TMP/lc2.ref" "$LC2/gomod/lib/lib.go"                                               # mtime put back: only ctime moved
moved "(c') a same-size in-place edit with its mtime restored" "$LC2" "$TMP/lc2.bin" Cello lib.go

LD="$TMP/ld"; cp -R "$W" "$LD"; prime "$LD" "$TMP/ld.bin"
mkdir -p "$LD/gomod/lib/deep/er"
printf 'package er\n\nfunc InNewDir() int {\n\treturn 9\n}\n' >"$LD/gomod/lib/deep/er/new.go"
moved "(d) a file added inside a newly created subdirectory" "$LD" "$TMP/ld.bin" InNewDir deep/er/new.go

if command -v git >/dev/null 2>&1; then
    LE="$TMP/le"; mkdir -p "$LE/src" "$LE/gen/deep"
    printf 'int kept( void )\n{\n    return 1;\n}\n' >"$LE/src/kept.c"
    printf 'int generated( void )\n{\n    return 2;\n}\n' >"$LE/gen/deep/generated.c"
    printf 'gen/\n' >"$LE/.gitignore"
    ( cd "$LE" && git init -q . && git add .gitignore src && git -c user.name=t -c user.email=t@t commit -q -m init ) >/dev/null 2>&1
    prime "$LE" "$TMP/le.bin"
    grep -q 'generated' "$TMP/l.p3" && no "L(e): the ignored file was indexed before the change (the fixture is wrong)"
    printf '# nothing ignored now\n' >"$LE/.gitignore"
    moved "(e) a .gitignore changed" "$LE" "$TMP/le.bin" generated generated.c

    # (f) git reports `stuff/` ignored as a WHOLE when every file under it is ignored by a FILE rule; a new
    #     un-ignored file deep inside changes git's answer while no walked directory's mtime moves
    LF="$TMP/lf"; mkdir -p "$LF/src" "$LF/stuff/deep"
    printf 'int kept( void )\n{\n    return 1;\n}\n' >"$LF/src/kept.c"
    printf 'log line\n' >"$LF/stuff/deep/a.log"
    printf '*.log\n' >"$LF/.gitignore"
    ( cd "$LF" && git init -q . && git add .gitignore src && git -c user.name=t -c user.email=t@t commit -q -m init ) >/dev/null 2>&1
    prime "$LF" "$TMP/lf.bin"
    printf 'int surfaced( void )\n{\n    return 3;\n}\n' >"$LF/stuff/deep/surfaced.c"
    moved "(f) a file added under a directory git reported ignored as a whole" "$LF" "$TMP/lf.bin" surfaced surfaced.c
else
    no "L(e)/(f): git is not on PATH — the ignore arms cannot run"
fi

echo
if [ "$fail" -eq 0 ]; then echo "warmsnapcheck: ALL PASS"; exit 0; fi
echo "warmsnapcheck: FAILED"; exit 1
