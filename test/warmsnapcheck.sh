#!/usr/bin/env bash
# warmsnapcheck.sh — the warm snapshot (src/warmsnap.h): a run that LOADS the tree, the model and the resolved graph
# from it must print the bytes a run that walks, decodes and resolves prints. No modulo, no normalisation.
#
# WHERE THE SNAPSHOT LIVES, because every arm below has to find it — and because WHERE is the whole design.
# It is one file in ripwire's own cache directory (quality::cacheDirLadder, the dir= `--doctor` reports):
#
#     <cacheDir>/<shard>/ripwire-warmsnap-<optionsKey>-<blobIdentity>.bin
#
# `blobIdentity` is the parse cache blob's OWN trailer digest (ingest_cache.h cacheBlobIdentity: the tableSum over
# its header and its whole offset table). That is not decoration — it is the binding between a stored model and the
# records it was assembled from, which earlier shapes of this lane had to ASSERT with a stored stat signature and
# this one gets from the name: rewrite the blob and the run resolves a different name, delete it and the run
# resolves none. So `snapfile` below finds the snapshot by recomputing the blob's digest itself, and an arm that
# cannot find it that way is an arm whose binding is broken.
#
# `optionsKey` is first because it is the eviction group (quality::evictOldCacheFamily, keep 1): one configuration
# keeps one snapshot, and two configurations — two checkouts of one committed blob, a lean verb and a rich one —
# never meet at one path. That is what S7 and S10 pin, and it is why the snapshot is NOT in the blob and NOT beside
# it: `<cache>.snap` breaks test/cacheidentitycheck.sh arm (D3), and a section inside the blob mutates an artifact
# another checkout owns (test/portablecachecheck.sh arm (a)) and reintroduces #334's refuse-and-rewrite thrash.
#
# The corpus is every test/*fix directory copied into one tree (C, C++, C#, Dart, Elixir, Go, Java, JS, Kotlin, PHP,
# Python, Ruby, Rust, TS, ...), so one run crosses every language's resolve rules.
#
# The observable is one stderr line under RIPWIRE_SNAPSHOT_STATS=1:
#   ripwire: snapshot-stats tree=walked|replayed model=built|loaded graph=built|loaded why=<first refusal> model_why= graph_why= saved=0|1
#            unsaved_why=<why a stage this run built was not stored: ok|racy|reparsed>
#
# ARMS
#   V   vacuity guard: the second run on an unchanged tree must say graph=loaded AND tree=replayed. A build without
#       the snapshot prints no such line, so "nothing was loaded, the two outputs are trivially equal" is a FAIL here,
#       never a pass. V also pins the two placement contracts: nothing is written beside the blob the user named, and
#       a run that serves the snapshot leaves that blob byte-identical.
#   N   the earliest serving call: from a fresh cache on a tree older than the racy slack, call 1 (cold) records the
#       crawl, the model and the graph, and call 2 is served; calls 1-4 all print the --no-cache bytes.
#   I   identity: per verb, stdout of the loading run == stdout of a --no-cache run (which builds everything).
#   S   a stale snapshot is REFUSED and the answer is the full build's: (S1) one file's content changed; (S2) the
#       snapshot's version field differs; (S3) a flipped byte in its body; (S4) a snapshot truncated inside a field;
#       (S5) a file the resolver read outside the crawl (go.mod) changed; (S6) the parse cache blob is gone, so the
#       snapshot on disk is not even reached — the binding is the NAME; (S7) other options resolve another name, and
#       the two snapshots coexist; (S8) the STRUCTURAL invalidation the design rests on — a run that re-parses leaves
#       a blob with a new identity, so what it stores is a new snapshot and the old one is evicted, never served;
#       (S9) a serving run writes nothing at all; (S10) two checkouts sharing ONE committed blob, which is the case
#       that killed the in-blob design: neither mutates it and neither refuses the other\'s snapshot.
#   L   the crawl replay is REFUSED, and the answer is the full crawl's, when the tree moved: (a) a file added, with no
#       pause after the recording run; (b) a file deleted; (c) a file modified in place at the SAME size — once
#       plainly and once with its mtime put back; (d) a file added inside a new subdirectory; (e) a .gitignore changed;
#       (f) a file added under a directory git reported ignored as a whole.
#
#   K   the key keeps apart what the count guards cannot: (KA0) premise — a test file that adds bindings only, so
#       --ignore-tests leaves files/symbols/references equal; (KA1) a graph recorded without --ignore-tests is not
#       served with it, (KA5) nor the reverse, each answer the full build's; (KA2-KA4) each view serves its own and
#       both snapshots coexist; (KB) with RIPWIRE_BIN_OTHER set to the other build type of this tree, neither build
#       serves the other's snapshot (why=producer). Without it KB prints SKIP.
#
#   RIPWIRE_BIN=./build/ripwire bash test/warmsnapcheck.sh
#   RIPWIRE_BIN=./build/ripwire RIPWIRE_BIN_OTHER=./build-rel/ripwire bash test/warmsnapcheck.sh   # with arm KB
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
echo "warmsnapcheck: BIN=$BIN ($( "$BIN" --version 2>/dev/null | head -1 ))  TMP=$TMP"
export XDG_CACHE_HOME="$TMP/xdg"; mkdir -p "$XDG_CACHE_HOME"   # the ignore-probe sidecar stays inside TMP
# TMPDIR OUTRANKS XDG_CACHE_HOME in the cache-dir ladder (quality::cacheDirLadder), and this gate writes one
# snapshot of the whole test corpus per configuration — about thirty of them across the arms below. Point TMPDIR at
# TMP too, or they land in the machine's real cache directory, where they outlive the run and race other sessions'.
export TMPDIR="$TMP/tmpdir"; mkdir -p "$TMPDIR"

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

# ── finding the snapshot, and two ways to damage it ───────────────────────────────────────────────
# The snapshot derived from a blob is named after that blob's OWN trailer digest, so the gate recomputes the digest
# and looks the file up by it. Nothing here reads the snapshot's format; the arms damage it from the outside.
#   blobid   BLOB         -> BLOB's identity: the u64 tableSum in its last 8 bytes, 16 lowercase hex
#   snapfile BLOB         -> the path of the snapshot derived from BLOB, or empty when none exists
#   fpatch   FILE FRAC    -> flip one byte FRAC/10 of the way into FILE, in place
#   fcut     FILE FRAC    -> truncate FILE to FRAC/10 of its length: a snapshot that ends inside a field
command -v python3 >/dev/null 2>&1 || { echo "python3 required (the blob's trailer digest)"; exit 2; }
blobid()
{
    python3 - "$1" <<'PYID'
import struct, sys
try:
    b = open( sys.argv[ 1 ], 'rb' ).read()
except OSError:
    print( '0' * 16 ); raise SystemExit( 0 )
print( '%016x' % ( struct.unpack_from( '<Q', b, len( b ) - 8 )[ 0 ] if len( b ) >= 24 else 0 ) )
PYID
}
# The cache directory the TOOL says it uses, not one this gate assumes: a ladder change must move the arms with it.
SNAPDIR="$( "$BIN" "$ROOT/test/fixture" --doctor 2>/dev/null | sed -n 's/.*<c n="cache-dir"[^>]*dir="\([^"]*\)".*/\1/p' | head -1 )"
[ -n "$SNAPDIR" ] && [ -d "$SNAPDIR" ] || { echo "warmsnapcheck: --doctor reports no cache-dir (dir=) to look in: '$SNAPDIR'"; exit 2; }
echo "warmsnapcheck: SNAPDIR=$SNAPDIR"
snapfile(){ find "$SNAPDIR" -name "ripwire-warmsnap-*-$( blobid "$1" ).bin" 2>/dev/null | head -1; }
hasSnap(){ [ -n "$( snapfile "$1" )" ]; }
# snapcount BLOB — how many snapshots in the cache dir are derived from BLOB (one per configuration that recorded one)
snapcount(){ find "$SNAPDIR" -name "ripwire-warmsnap-*-$( blobid "$1" ).bin" 2>/dev/null | wc -l | tr -d ' '; }
fpatch()
{
    python3 - "$1" "$2" <<'PYPATCH'
import sys
path, frac = sys.argv[ 1 ], int( sys.argv[ 2 ] )
b  = bytearray( open( path, 'rb' ).read() )
at = min( len( b ) * frac // 10, len( b ) - 1 )
b[ at ] = ( b[ at ] + 1 ) % 256
open( path, 'wb' ).write( b )
PYPATCH
}
fcut()
{
    python3 - "$1" "$2" <<'PYCUT'
import sys
path, frac = sys.argv[ 1 ], int( sys.argv[ 2 ] )
b = open( path, 'rb' ).read()
open( path, 'wb' ).write( b[ : max( 1, len( b ) * frac // 10 ) ] )
PYCUT
}
# alone BLOB — nothing whose name starts with the blob's was written beside it (test/cacheidentitycheck.sh arm (D3))
alone(){ [ -z "$( find "$( dirname "$1" )" -maxdepth 1 -name "$( basename "$1" )?*" 2>/dev/null )" ]; }
# steady OUT — this run served from the blob's records and grew none of them, so saveCache had nothing to publish and
# the blob must be untouched. Record growth is a pre-existing cache behaviour (warm_growths=, ingest_parsepool.h) and
# does legitimately rewrite the blob, so the no-mutation arms assert on a run that reports none.
steady(){ grep -q 'warm_growths=0' "$1.err"; }

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
if hasSnap "$C"; then ok "V  the snapshot is in the cache dir, named after the blob's own identity ($( blobid "$C" ): $( wc -c <"$( snapfile "$C" )" | tr -d ' ' ) B, beside a $( wc -c <"$C" | tr -d ' ' ) B blob)"
else no "V  no snapshot in $SNAPDIR is named after this blob's identity ($( blobid "$C" )) — the binding by name is broken"; fi
if alone "$C"; then ok "V  and nothing was written beside the blob: --cache=PATH wrote exactly the file the user named (arm (D3)'s contract)"
else no "V  a file was written beside the blob: $( find "$( dirname "$C" )" -maxdepth 1 -name "$( basename "$C" )?*" | tr '\n' ' ' )"; fi
# V3: and the run that SERVED it left the blob alone. The contract the placement exists for: a committed blob is
#     read-shared by many checkouts, so a consuming run must not mutate the artifact another checkout owns
#     (test/portablecachecheck.sh arm (a)). Asserted on a run that grew no record, because growth legitimately
#     republishes the blob and has nothing to do with the snapshot.
cp "$C" "$TMP/v.blobwas"
run "$C" "$W" "$TMP/v.serve"
if ! has "$TMP/v.serve" 'graph=loaded'; then no "V3 the run under comparison did not serve the snapshot ($( cat "$TMP/v.serve.stats" ))"
elif ! steady "$TMP/v.serve"; then no "V3 could not be evaluated: the serving run grew a record ($( grep -o 'warm_growths=[0-9]*' "$TMP/v.serve.err" )) and republished the blob for its own reasons"
elif cmp -s "$C" "$TMP/v.blobwas"; then ok "V3 a serving run left the blob BYTE-IDENTICAL: nothing is written into the artifact the user named"
else no "V3 a serving run modified the blob the user named ($( cmp "$C" "$TMP/v.blobwas" 2>&1 | head -1 ))"; fi

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
# The options key is in the NAME, so another environment resolves another file and finds nothing there: why=absent,
# where the sidecar and the in-blob section both read one artifact and refused it as why=options. The stored key is
# still compared inside (warmsnap.h openSnapshot) and still the only thing that could catch a name collision.
if grep -q 'why=absent' "$TMP/v2.stats"; then ok "V2 ...and a new GIT_* variable resolves another snapshot entirely (why=absent)"; else no "V2 a new GIT_* variable did not refuse the snapshot: $( cat "$TMP/v2.stats" )"; fi

# ── N: the EARLIEST serving call, from a fresh cache ─────────────────────────────────────────────
# MEASURE-M5 (11-26, llvm-project): from an empty cache dir, calls 1, 2 AND 3 built the model and the graph, and only
# call 4 was served — two 24-32 s calls an agent paid before its first served one. Call 1 parses every file because
# there is no blob to hit, and "a run that parsed stores nothing" (the edit-loop rule S8b pins) kept it from recording
# the model and the graph; on llvm, call 2 then re-parsed 5 files for reasons of the parse pool's own, so it recorded
# nothing either. A run whose blob did not exist when it opened is not the run after an edit: it records.
# So call 2 must serve, and every call must print the bytes a --no-cache build prints.
# The tree is aged past the racy slack BEFORE call 1: that is the honest premise. A tree written within the slack is
# refused by the racy rule, which is a different arm (S8).
nsrv()
{
    local tag="$1" k; shift
    local nd="$TMP/n.$tag" nc="$TMP/n.$tag.bin"
    mkcorpus "$nd"; sleep 3                 # every signature older than the racy slack before call 1 starts
    for k in 1 2 3 4; do run "$nc" "$nd" "$TMP/n.$tag.$k" "$@"; done
    full "$nd" "$TMP/n.$tag.full" "$@"
    if grep -q 'cache-stats reparsed=[1-9]' "$TMP/n.$tag.1.err" && has "$TMP/n.$tag.1" 'why=absent'; then
        ok "N  [$tag] premise: call 1 is cold — no blob, every file parsed ($( grep -o 'cache-stats reparsed=[0-9]*' "$TMP/n.$tag.1.err" ))"
    else no "N  [$tag] premise: call 1 is not a cold run: $( grep -o 'cache-stats reparsed=[0-9]*' "$TMP/n.$tag.1.err" ) $( cat "$TMP/n.$tag.1.stats" )"; fi
    if has "$TMP/n.$tag.1" 'saved=1' && has "$TMP/n.$tag.1" 'unsaved_why=ok'; then ok "N  [$tag] call 1 recorded a snapshot and held nothing back (unsaved_why=ok)"
    else no "N  [$tag] call 1 did not record all it built: $( cat "$TMP/n.$tag.1.stats" )"; fi
    if has "$TMP/n.$tag.2" 'tree=replayed' && has "$TMP/n.$tag.2" 'model=loaded' && has "$TMP/n.$tag.2" 'graph=loaded'; then
        ok "N  [$tag] call 2 is SERVED ($( sed 's/^ripwire: snapshot-stats //' "$TMP/n.$tag.2.stats" ))"
    else no "N  [$tag] call 2 is not served — the first served call is later than the design allows: $( cat "$TMP/n.$tag.2.stats" )"; fi
    if has "$TMP/n.$tag.2" 'saved=0'; then ok "N  [$tag] ...and writes nothing"; else no "N  [$tag] the serving call 2 rewrote the snapshot: $( cat "$TMP/n.$tag.2.stats" )"; fi
    for k in 3 4; do
        if has "$TMP/n.$tag.$k" 'model=loaded' && has "$TMP/n.$tag.$k" 'graph=loaded'; then ok "N  [$tag] call $k is served"
        else no "N  [$tag] call $k is not served: $( cat "$TMP/n.$tag.$k.stats" )"; fi
    done
    for k in 1 2 3 4; do same "N  [$tag] call $k == built" "$TMP/n.$tag.$k" "$TMP/n.$tag.full"; done
}
nsrv map
nsrv for --for="hello lib module"

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
SNAP2="$( snapfile "$TMP/s2.bin" )"
[ -n "$SNAP2" ] || no "S2 VACUOUS: no snapshot to patch"
# byte 8 of the snapshot: the low byte of its format version, right after the u64 magic.
patch 8 255 "$SNAP2"
run "$TMP/s2.bin" "$S2" "$TMP/s2.out"; full "$S2" "$TMP/s2.full"
refused "S2 a version-mismatched section refuses the graph" "$TMP/s2.out" 'graph=loaded'
refused "S2 a version-mismatched section refuses the crawl replay" "$TMP/s2.out" 'tree=replayed'
if grep -q 'reparsed=0' "$TMP/s2.out.err"; then ok "S2 ...and the blob's RECORDS were still served: the damage is confined to the snapshot"
else no "S2 the patch cost the run its parse cache too: $( grep -o 'cache-stats.*' "$TMP/s2.out.err" )"; fi
if has "$TMP/s2.out" 'why=version'; then ok "S2 the refusal names the version"; else no "S2 the refusal does not say why=version: $( cat "$TMP/s2.out.stats" )"; fi
same    "S2 the answer == built" "$TMP/s2.out" "$TMP/s2.full"
run "$TMP/s2.bin" "$S2" "$TMP/s2.again"; run "$TMP/s2.bin" "$S2" "$TMP/s2.again"
if has "$TMP/s2.again" 'graph=loaded'; then ok "S2 the refused snapshot was rewritten: the next run loads"; else no "S2 the snapshot did not heal: $( cat "$TMP/s2.again.stats" )"; fi

S3="$TMP/s3"; snapof "$S3" "$TMP/s3.bin"
SNAP3="$( snapfile "$TMP/s3.bin" )"
if [ -z "$SNAP3" ]; then no "S3 VACUOUS: no snapshot to flip a byte in"; else
cp "$SNAP3" "$TMP/s3.snapwas"; cp "$TMP/s3.bin" "$TMP/s3.blobwas"
for frac in 3 5 7 9; do
    cp "$TMP/s3.blobwas" "$TMP/s3.bin"; cp "$TMP/s3.snapwas" "$SNAP3"   # the blob's bytes decide the name: restore both
    fpatch "$SNAP3" "$frac"
    run "$TMP/s3.bin" "$S3" "$TMP/s3.out"; full "$S3" "$TMP/s3.full"
    same "S3 a flipped byte at ${frac}0% of the snapshot: the answer == built ($( sed 's/^ripwire: snapshot-stats //' "$TMP/s3.out.stats" ))" "$TMP/s3.out" "$TMP/s3.full"
    if has "$TMP/s3.out" 'why=checksum'; then ok "S3 ...and the refusal says why=checksum"; else no "S3 a flipped byte at ${frac}0% was not refused as a checksum failure: $( cat "$TMP/s3.out.stats" )"; fi
done
fi

S4="$TMP/s4"; snapof "$S4" "$TMP/s4.bin"
SNAP4="$( snapfile "$TMP/s4.bin" )"
if [ -z "$SNAP4" ]; then no "S4 VACUOUS: no snapshot to cut"; else
fcut "$SNAP4" 5                                   # half a snapshot: it ends inside a field, and its checksum covers bytes that are gone
run "$TMP/s4.bin" "$S4" "$TMP/s4.out"; full "$S4" "$TMP/s4.full"
refused "S4 a snapshot cut in half refuses the graph" "$TMP/s4.out" 'graph=loaded'
refused "S4 ...and the crawl replay" "$TMP/s4.out" 'tree=replayed'
same    "S4 the answer == built" "$TMP/s4.out" "$TMP/s4.full"
if grep -q 'reparsed=0' "$TMP/s4.out.err"; then ok "S4 ...and the blob's RECORDS were still served: the cut cost the run nothing but the snapshot"
else no "S4 the cut cost the run its parse cache too: $( grep -o 'cache-stats.*' "$TMP/s4.out.err" )"; fi
fi

S5="$TMP/s5"; snapof "$S5" "$TMP/s5.bin"
has "$TMP/s.prime3" 'graph=loaded' || no "S5 VACUOUS: the tree was never served from the snapshot before the edit"
printf 'module example.com/renamed\n\ngo 1.21\n' >"$S5/gomod/go.mod"
run "$TMP/s5.bin" "$S5" "$TMP/s5.out"; full "$S5" "$TMP/s5.full"
refused "S5 a changed go.mod (read by the resolver, outside the parse cache) refuses the graph" "$TMP/s5.out" 'graph=loaded'
same    "S5 the answer == built" "$TMP/s5.out" "$TMP/s5.full"
if has "$TMP/s5.out" 'graph_why=dep'; then ok "S5 the refusal is the dependency log's (graph_why=dep): the tree key alone did not move"; else no "S5 the graph was not refused by its dependency log: $( cat "$TMP/s5.out.stats" )"; fi

# S6: the parse cache blob is gone. The snapshot is STILL THERE, and is not even reached — the blob that names it
#     is what resolves its name, so there is nothing to compare and nothing to get wrong. This arm is why
#     warmsnap_model.h no longer stores a stat signature of the blob (warmsnap::kVersion 2).
S6="$TMP/s6"; snapof "$S6" "$TMP/s6.bin"
has "$TMP/s.prime3" 'model=loaded' || no "S6 VACUOUS: the model was never served before the blob was removed"
SNAP6="$( snapfile "$TMP/s6.bin" )"
S6WAS=0
if [ -n "$SNAP6" ] && [ -s "$SNAP6" ]; then S6WAS="$( wc -c <"$SNAP6" | tr -d ' ' )"; else no "S6 VACUOUS: there was no snapshot on disk to leave behind"; fi
rm -f "$TMP/s6.bin"
run "$TMP/s6.bin" "$S6" "$TMP/s6.out"; full "$S6" "$TMP/s6.full"
refused "S6 a removed parse cache blob refuses the model" "$TMP/s6.out" 'model=loaded'
refused "S6 ...and the graph, and the crawl replay" "$TMP/s6.out" 'graph=loaded'
if has "$TMP/s6.out" 'why=absent'; then ok "S6 the refusal is why=absent — with a $S6WAS B snapshot of the removed blob sitting on disk the whole time: the binding is the NAME, which no blob now resolves, not a stored field that could be wrong"
else no "S6 the refusal is not why=absent: $( cat "$TMP/s6.out.stats" )"; fi
same    "S6 the answer == built" "$TMP/s6.out" "$TMP/s6.full"
if grep -q 'cache-stats reparsed=[1-9]' "$TMP/s6.out.err"; then ok "S6 ...and the run re-parsed, as a run with no blob always did"; else no "S6 the run did not re-parse: $( grep cache-stats "$TMP/s6.out.err" )"; fi

# S7: another configuration resolves another NAME, and the two snapshots COEXIST. This is the anti-thrash property
#     the placement was chosen for: the options key is the first field of the name and the eviction group, so one
#     configuration can never refuse-and-rewrite another's — the #334 shape an in-blob section brought back.
run "$TMP/s7.bin" "$W" "$TMP/s7.a"; sleep 2; run "$TMP/s7.bin" "$W" "$TMP/s7.a"; run "$TMP/s7.bin" "$W" "$TMP/s7.a"
has "$TMP/s7.a" 'graph=loaded' || no "S7 VACUOUS: the first configuration was never served"
S7COUNT1="$( snapcount "$TMP/s7.bin" )"
run "$TMP/s7.bin" "$W" "$TMP/s7.b" --exclude=gomod; full "$W" "$TMP/s7.bfull" --exclude=gomod
refused "S7 another --exclude set refuses the whole snapshot" "$TMP/s7.b" 'graph=loaded'
if has "$TMP/s7.b" 'why=absent'; then ok "S7 ...by resolving a name of its own and finding nothing there (why=absent)"; else no "S7 the refusal is not why=absent: $( cat "$TMP/s7.b.stats" )"; fi
same    "S7 the answer == built" "$TMP/s7.b" "$TMP/s7.bfull"
run "$TMP/s7.bin" "$W" "$TMP/s7.b2" --exclude=gomod; run "$TMP/s7.bin" "$W" "$TMP/s7.b3" --exclude=gomod
S7COUNT2="$( snapcount "$TMP/s7.bin" )"
if [ "$S7COUNT2" -gt "$S7COUNT1" ]; then ok "S7 the second configuration recorded its OWN snapshot of the same blob ($S7COUNT1 -> $S7COUNT2), evicting nothing of the first's"
else no "S7 the second configuration did not add a snapshot ($S7COUNT1 -> $S7COUNT2) — either it recorded nothing or it took the first's place"; fi
run "$TMP/s7.bin" "$W" "$TMP/s7.a2"
if has "$TMP/s7.a2" 'graph=loaded'; then ok "S7 ...and the FIRST configuration is still served after it: no thrash between the two"
else no "S7 the first configuration lost its snapshot to the second: $( cat "$TMP/s7.a2.stats" )"; fi

# S8: THE STRUCTURAL INVALIDATION the whole design rests on. A run that re-parses anything republishes the blob, and
#     the blob's identity is its trailer digest — so the stored outcome of the OLD tree is not reachable from the new
#     blob at all: the run resolves a different name. Nothing has to notice that a stored outcome went stale. Asserted
#     on the artifacts themselves, not on behaviour, so a guard that happened to refuse for another reason cannot
#     stand in for it.
S8="$TMP/s8"; snapof "$S8" "$TMP/s8.bin"
S8OLDID="$( blobid "$TMP/s8.bin" )"; S8OLDSNAP="$( snapfile "$TMP/s8.bin" )"
[ -n "$S8OLDSNAP" ] || no "S8 VACUOUS: there was no snapshot before the edit"
alone "$TMP/s8.bin" || no "S8 a file was written beside the blob before the edit"
printf 'package lib\n\nfunc Zello() int {\n\treturn 3\n}\n' >"$S8/gomod/lib/lib.go"
run "$TMP/s8.bin" "$S8" "$TMP/s8.out"
if grep -q 'cache-stats reparsed=[1-9]' "$TMP/s8.out.err"; then ok "S8 the run after the edit re-parsed ($( grep -o 'cache-stats reparsed=[0-9]*' "$TMP/s8.out.err" ))"
else no "S8 the run after the edit did not re-parse: $( grep -o 'cache-stats.*' "$TMP/s8.out.err" )"; fi
S8NEWID="$( blobid "$TMP/s8.bin" )"
if [ "$S8NEWID" != "$S8OLDID" ]; then ok "S8 the republished blob has a NEW identity ($S8OLDID -> $S8NEWID), so the old tree's snapshot is not reachable from it"
else no "S8 the blob kept its identity through a re-parse ($S8NEWID): a stale snapshot would still be named by it"; fi
# RECORD-FIRST (warm snapshot v12): the run that parsed records the MODEL and the GRAPH, keyed on content (the tree key),
# under the NEW blob's name; the crawl's signatures are inside the racy window, so the TREE is held back (asserted on the
# next run, which walks and is still served the graph).
if hasSnap "$TMP/s8.bin" && has "$TMP/s8.out" 'saved=1'; then ok "S8 ...and that run recorded under the NEW blob's name (record-first): $( sed 's/^ripwire: snapshot-stats //' "$TMP/s8.out.stats" )"
else no "S8 the run that parsed recorded nothing reachable from its blob: $( cat "$TMP/s8.out.stats" ) snapshot=$( snapfile "$TMP/s8.bin" )"; fi
alone "$TMP/s8.bin" || no "S8 a file was written beside the blob by the run after the edit"
sleep 2
run "$TMP/s8.bin" "$S8" "$TMP/s8.next"
if has "$TMP/s8.next" 'tree=walked' && has "$TMP/s8.next" 'graph=loaded'; then ok "S8 the next run walks (the racy run held its TREE back) and is served the graph the racy run recorded"
else no "S8 the run after the racy one: expected tree=walked graph=loaded, got $( cat "$TMP/s8.next.stats" )"; fi
if hasSnap "$TMP/s8.bin" && has "$TMP/s8.next" 'saved=1'; then ok "S8 the first run outside that window records the crawl, under the NEW blob's name"
else no "S8 nothing was recorded on the clean run after the edit: $( cat "$TMP/s8.next.stats" ) snapshot=$( snapfile "$TMP/s8.bin" )"; fi
if [ ! -e "$S8OLDSNAP" ]; then ok "S8 ...and the snapshot named after the OLD blob is gone with it: one per configuration, the rest evicted"
else no "S8 the snapshot named after the old blob survived ($S8OLDSNAP) — an edit loop would leave one orphan per edit"; fi
sleep 2
run "$TMP/s8.bin" "$S8" "$TMP/s8.third"; full "$S8" "$TMP/s8.full"
if has "$TMP/s8.third" 'graph=loaded'; then ok "S8 ...and the run after THAT loads it"; else no "S8 the re-recorded snapshot is not served: $( cat "$TMP/s8.third.stats" )"; fi
same "S8 the answer after the whole edit-and-re-record cycle == built" "$TMP/s8.third" "$TMP/s8.full"
if has "$TMP/s8.third" 'saved=0'; then ok "S8 ...and a steady warm run writes no snapshot: the file already says it all"
else no "S8 a steady warm run rewrote the snapshot: $( cat "$TMP/s8.third.stats" )"; fi

# S8b: a run that re-parses and is OUTSIDE the racy window records EVERYTHING — the crawl, the model and the graph,
#      under the name of the blob it has just republished — so the very next run is served (RECORD-FIRST, warm snapshot
#      v12; until then warmsnap_graph.h buildGraphRecorded and ingest.cpp recordWarmModel stopped on
#      ing.reparsedFiles != 0, and the second run after an edit rebuilt the model and the graph).
printf 'package lib\n\nfunc Yello() int {\n\treturn 4\n}\n' >"$S8/gomod/lib/lib.go"
sleep 2
run "$TMP/s8.bin" "$S8" "$TMP/s8b.out"
if grep -q 'cache-stats reparsed=[1-9]' "$TMP/s8b.out.err" && has "$TMP/s8b.out" 'saved=1' && hasSnap "$TMP/s8.bin"; then
    ok "S8b a re-parsing run records: $( grep -o 'cache-stats reparsed=[0-9]*' "$TMP/s8b.out.err" ), saved=1, and the snapshot is named after the blob it left behind"
else no "S8b the re-parsing run stored nothing reachable from its own blob: $( cat "$TMP/s8b.out.stats" ), $( grep -o 'cache-stats reparsed=[0-9]*' "$TMP/s8b.out.err" ), snapshot=$( snapfile "$TMP/s8.bin" )"; fi
if has "$TMP/s8b.out" 'unsaved_why=ok'; then ok "S8b ...and it held back nothing it built (unsaved_why=ok; RIPWIRE_NO_RECORD_FIRST=1 says reparsed, recordfirstcheck R2)"
else no "S8b the re-parsing run held back part of what it built: $( cat "$TMP/s8b.out.stats" )"; fi
run "$TMP/s8.bin" "$S8" "$TMP/s8b.next"; full "$S8" "$TMP/s8b.full"
if has "$TMP/s8b.next" 'tree=replayed'; then ok "S8b ...so the very next run after the edit REPLAYS the crawl ($( sed 's/^ripwire: snapshot-stats //' "$TMP/s8b.next.stats" ))"
else no "S8b the run after a re-parsing run walked the tree again: $( cat "$TMP/s8b.next.stats" )"; fi
if has "$TMP/s8b.next" 'model=loaded' && has "$TMP/s8b.next" 'graph=loaded'; then ok "S8b ...and is served the model and the graph the re-parsing run recorded"
else no "S8b the run after a re-parsing run rebuilt the model or the graph: $( cat "$TMP/s8b.next.stats" )"; fi
same "S8b the answer one run after the edit == built" "$TMP/s8b.next" "$TMP/s8b.full"

# S9: a SERVING run writes NOTHING — not the snapshot, not the blob. The in-blob placement could not have this arm at
#     all: there, recording meant republishing the blob, so a consuming run mutated the artifact it was handed.
S9="$TMP/s9"; snapof "$S9" "$TMP/s9.bin"
S9SNAP="$( snapfile "$TMP/s9.bin" )"
if [ -z "$S9SNAP" ]; then no "S9 VACUOUS: no snapshot was recorded for this tree"; else
S9OK=0
for attempt in 1 2 3 4; do                            # until a run both serves and grows no record (see `steady`)
    cp "$TMP/s9.bin" "$TMP/s9.blobwas"; cp "$S9SNAP" "$TMP/s9.snapwas"
    run "$TMP/s9.bin" "$S9" "$TMP/s9.out"
    if has "$TMP/s9.out" 'graph=loaded' && has "$TMP/s9.out" 'model=loaded' && steady "$TMP/s9.out"; then S9OK=1; break; fi
    sleep 1
done
if [ "$S9OK" -eq 0 ]; then no "S9 could not be evaluated: no run in four attempts both served the snapshot and grew no record ($( cat "$TMP/s9.out.stats" ); $( grep -o 'cache-stats.*' "$TMP/s9.out.err" ))"
else
    if has "$TMP/s9.out" 'saved=0'; then ok "S9 the serving run wrote no snapshot (saved=0)"; else no "S9 the serving run rewrote the snapshot: $( cat "$TMP/s9.out.stats" )"; fi
    if cmp -s "$TMP/s9.bin" "$TMP/s9.blobwas"; then ok "S9 ...and left the parse cache blob BYTE-IDENTICAL"; else no "S9 the serving run modified the blob ($( cmp "$TMP/s9.bin" "$TMP/s9.blobwas" 2>&1 | head -1 ))"; fi
    if cmp -s "$S9SNAP" "$TMP/s9.snapwas"; then ok "S9 ...and the snapshot it read byte-identical too"; else no "S9 the serving run rewrote the snapshot it had just read"; fi
    alone "$TMP/s9.bin" || no "S9 a file was written beside the blob by a serving run"
fi
fi

# S10: TWO CHECKOUTS, ONE COMMITTED BLOB — the case that decided the placement. `optionsKey` folds in the root
#      spelling, its realpath and the cwd, so the two can never agree on one snapshot; with the snapshot inside the
#      blob they refused and rewrote each other's on every run (#334's shape) and each run mutated a committed
#      artifact. Here each keeps its own file and neither touches the blob.
S10A="$TMP/s10a"; S10B="$TMP/s10b"; cp -R "$W" "$S10A"; cp -R "$W" "$S10B"
S10BLOB="$TMP/s10.bin"
run "$S10BLOB" "$S10A" "$TMP/s10.a1"; sleep 2; run "$S10BLOB" "$S10A" "$TMP/s10.a2"; run "$S10BLOB" "$S10A" "$TMP/s10.a3"
has "$TMP/s10.a3" 'graph=loaded' || no "S10 VACUOUS: checkout A was never served from its snapshot"
S10COUNT1="$( snapcount "$S10BLOB" )"
run "$S10BLOB" "$S10B" "$TMP/s10.b1"; run "$S10BLOB" "$S10B" "$TMP/s10.b2"; run "$S10BLOB" "$S10B" "$TMP/s10.b3"
if has "$TMP/s10.b3" 'graph=loaded'; then ok "S10 the second checkout, consuming the SAME committed blob, is served from a snapshot of its own"
else no "S10 the second checkout is never served: $( cat "$TMP/s10.b3.stats" )"; fi
S10COUNT2="$( snapcount "$S10BLOB" )"
if [ "$S10COUNT2" -gt "$S10COUNT1" ]; then ok "S10 ...from its OWN file: the blob's snapshots went $S10COUNT1 -> $S10COUNT2, so A's was not taken over"
else no "S10 the two checkouts share one snapshot name ($S10COUNT1 -> $S10COUNT2): that is the refuse-and-rewrite thrash"; fi
cp "$S10BLOB" "$TMP/s10.blobwas"
run "$S10BLOB" "$S10A" "$TMP/s10.a4"; run "$S10BLOB" "$S10B" "$TMP/s10.b4"
if has "$TMP/s10.a4" 'graph=loaded' && has "$TMP/s10.b4" 'graph=loaded'; then ok "S10 ...and alternating between the two checkouts serves BOTH: neither refuses what the other recorded"
else no "S10 alternating checkouts refused: A=$( cat "$TMP/s10.a4.stats" ) B=$( cat "$TMP/s10.b4.stats" )"; fi
if ! steady "$TMP/s10.a4" || ! steady "$TMP/s10.b4"; then no "S10 the no-mutation arm could not be evaluated: a run grew a record and republished the blob for its own reasons"
elif cmp -s "$S10BLOB" "$TMP/s10.blobwas"; then ok "S10 ...and the committed blob is BYTE-IDENTICAL after both: a consuming run never mutates the artifact another checkout owns"
else no "S10 the committed blob was mutated by a consuming run ($( cmp "$S10BLOB" "$TMP/s10.blobwas" 2>&1 | head -1 )) — test/portablecachecheck.sh arm (a)'s contract"; fi

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

# ── K: the two inputs the snapshot's key once missed (lane C1-KEYFIX) ──────────────────────────────
# (KA) --ignore-tests. main() drops the test files' symbols, references and bindings between the model and the graph
#      (filter.h applyIgnoreTests), and the GRAPH section's own guard is three counts. A test file that contributes
#      BINDINGS ONLY (`let x: Foo;`, `export default helper;`, `using namespace std;`, `extern int counter;`) leaves
#      all three equal, so a graph resolved from one view was served to the other. The flag is now in the options key
#      (warmsnap.h optionsKeyOf): each view is its own configuration, and both keep their snapshot.
KA="$TMP/ka"; mkdir -p "$KA/src" "$KA/test"
printf 'export class Foo { go() { return 1; } }\nexport class Bar { go() { return 2; } }\n' >"$KA/src/types.ts"
printf 'import { Foo } from "./types";\nexport function run( f: Foo ) { return f.go(); }\n' >"$KA/src/use.ts"
printf 'let x: Foo;\nexport default helper;\n' >"$KA/test/view.ts"
printf 'using namespace std;\nextern int counter;\n' >"$KA/test/view.cpp"
printf 'int kept( void ) { return 1; }\n' >"$KA/src/kept.cpp"
# KA0, the premise: the flag removes bindings and NOTHING the count guard reads, else the arms below test nothing new
kcounts(){ RIPWIRE_NO_WARMSNAP=1 RIPWIRE_STATS=1 "$BIN" "$KA" --no-cache "$@" 2>&1 >/dev/null | sed -nE 's/^\[mem\] family (files|symbols|references|bindings) size=([0-9]+).*/\1=\2/p' | tr '\n' ' '; }
ka_all="$( kcounts )"; ka_view="$( kcounts --ignore-tests )"
ka_b0="$( printf '%s' "$ka_all" | sed -n 's/.*bindings=\([0-9]*\).*/\1/p' )"; ka_b1="$( printf '%s' "$ka_view" | sed -n 's/.*bindings=\([0-9]*\).*/\1/p' )"
if [ -z "$ka_b0" ] || [ -z "$ka_b1" ]; then no "KA0 VACUOUS: no family counts under RIPWIRE_STATS ('$ka_all' / '$ka_view')"
elif [ "${ka_all% bindings=*}" != "${ka_view% bindings=*}" ] || [ "$ka_b0" -le "$ka_b1" ]; then no "KA0 the fixture is not bindings-only: all=[$ka_all] view=[$ka_view]"
else ok "KA0 premise: --ignore-tests drops $(( ka_b0 - ka_b1 )) binding(s) and leaves files/symbols/references equal ($ka_view)"; fi
# kprime CACHE [flag] — record the snapshot under one view, leave the racy window, and prove it serves (else vacuous)
kprime(){ run "$1" "$KA" "$TMP/ka.p1" ${2:+"$2"}; sleep 2; run "$1" "$KA" "$TMP/ka.p2" ${2:+"$2"}; run "$1" "$KA" "$TMP/ka.p3" ${2:+"$2"}
          has "$TMP/ka.p3" 'graph=loaded' || no "KA VACUOUS: the ${2:-flagless} view never served its own graph ($( cat "$TMP/ka.p3.stats" ))"; }
for kv in "" --callers=go; do
    kl="${kv:-the map}"
    rm -f "$TMP/ka1.bin"; kprime "$TMP/ka1.bin"
    run "$TMP/ka1.bin" "$KA" "$TMP/ka1.out" --ignore-tests ${kv:+"$kv"}; full "$KA" "$TMP/ka1.full" --ignore-tests ${kv:+"$kv"}
    refused "KA1 ($kl) a graph recorded WITHOUT --ignore-tests is not served WITH it" "$TMP/ka1.out" 'graph=loaded'
    same    "KA1 ($kl) ...and the answer == the full --ignore-tests build's" "$TMP/ka1.out" "$TMP/ka1.full"
    run "$TMP/ka1.bin" "$KA" "$TMP/ka2.out" --ignore-tests ${kv:+"$kv"}
    if has "$TMP/ka2.out" 'graph=loaded'; then ok "KA2 ($kl) the --ignore-tests view then serves its OWN graph"; else no "KA2 ($kl) the --ignore-tests view never serves: $( cat "$TMP/ka2.out.stats" )"; fi
    same    "KA2 ($kl) ...and that answer == the full --ignore-tests build's" "$TMP/ka2.out" "$TMP/ka1.full"
    if [ "$( snapcount "$TMP/ka1.bin" )" = 2 ]; then ok "KA3 ($kl) the two views keep one snapshot EACH (no refuse-and-rewrite when a caller alternates)"
    else no "KA3 ($kl) the two views share $( snapcount "$TMP/ka1.bin" ) snapshot(s), not 2"; fi
    run "$TMP/ka1.bin" "$KA" "$TMP/ka4.out" ${kv:+"$kv"}; full "$KA" "$TMP/ka4.full" ${kv:+"$kv"}
    if has "$TMP/ka4.out" 'graph=loaded'; then ok "KA4 ($kl) ...and the flagless view still serves its own"; else no "KA4 ($kl) the flagless snapshot did not survive: $( cat "$TMP/ka4.out.stats" )"; fi
    same    "KA4 ($kl) ...and that answer == the full flagless build's" "$TMP/ka4.out" "$TMP/ka4.full"
    rm -f "$TMP/ka5.bin"; kprime "$TMP/ka5.bin" --ignore-tests
    run "$TMP/ka5.bin" "$KA" "$TMP/ka5.out" ${kv:+"$kv"}
    refused "KA5 ($kl) a graph recorded WITH --ignore-tests is not served without it" "$TMP/ka5.out" 'graph=loaded'
    same    "KA5 ($kl) ...and the answer == the full flagless build's" "$TMP/ka5.out" "$TMP/ka4.full"
done

# (KB) the BUILD. The producer identity names the sources, so a dev and a Release build of one tree shared it and served
#      each other's snapshot — whose floats (ranks, prior weights, CSR values) they computed under -ffast-math with
#      different inlining and LTO. The header's build field now carries the build key (src/buildkey.h). The arm needs
#      the other flavour of THIS tree: RIPWIRE_BIN_OTHER=<path>. Premise: the two `--version` lines differ in the build
#      type and in nothing else, so a refusal can only be the build's (a binary of other sources is refused anyway).
OTHER="${RIPWIRE_BIN_OTHER:-}"
if [ -z "$OTHER" ]; then
    printf '  SKIP  KB needs the other build flavour of this tree: RIPWIRE_BIN_OTHER=<path> (a Release binary beside a dev one)\n'
elif [ ! -x "$OTHER" ]; then no "KB RIPWIRE_BIN_OTHER=$OTHER is not an executable"
else
    kver(){ "$1" --version 2>/dev/null | head -1; }
    kb_a="$( kver "$BIN" )"; kb_b="$( kver "$OTHER" )"
    kb_ta="$( printf '%s' "$kb_a" | sed -n 's/^[^(]*(\([^,]*\),.*/\1/p' )"; kb_tb="$( printf '%s' "$kb_b" | sed -n 's/^[^(]*(\([^,]*\),.*/\1/p' )"
    if [ -z "$kb_ta" ] || [ "$kb_ta" = "$kb_tb" ] || [ "${kb_a/"($kb_ta,"/(T,}" != "${kb_b/"($kb_tb,"/(T,}" ]; then
        no "KB premise: the two binaries must be one tree in two build types: '$kb_a' vs '$kb_b'"
    else
        ok "KB premise: one tree, two builds ($kb_ta / $kb_tb)"
        for kdir in fwd rev; do
            kr="$BIN"; ks="$OTHER"; [ "$kdir" = rev ] && { kr="$OTHER"; ks="$BIN"; }
            kc="$TMP/kb-$kdir.bin"; rm -f "$kc"
            for kp in 1 2 3; do RIPWIRE_SNAPSHOT_STATS=1 "$kr" "$W" --cache="$kc" >"$TMP/kb.p" 2>"$TMP/kb.p.err"; [ "$kp" = 1 ] && sleep 2; done
            grep -q 'graph=loaded' "$TMP/kb.p.err" || no "KB ($kdir) VACUOUS: the recording build never served its own graph ($( grep snapshot-stats "$TMP/kb.p.err" ))"
            RIPWIRE_SNAPSHOT_STATS=1 "$ks" "$W" --cache="$kc" >"$TMP/kb.out" 2>"$TMP/kb.out.err"
            grep '^ripwire: snapshot-stats ' "$TMP/kb.out.err" >"$TMP/kb.out.stats" || : >"$TMP/kb.out.stats"
            "$ks" "$W" --no-cache >"$TMP/kb.full" 2>/dev/null
            refused "KB ($kdir: $( kver "$kr" | sed -n 's/^[^(]*(\([^,]*\),.*/\1/p' ) recorded) the other build does not load its graph" "$TMP/kb.out" 'graph=loaded'
            if has "$TMP/kb.out" 'why=producer'; then ok "KB ($kdir) ...refused as another build's (why=producer)"; else no "KB ($kdir) not refused as another build's: $( cat "$TMP/kb.out.stats" )"; fi
            same "KB ($kdir) ...and the answer == the serving build's own full build" "$TMP/kb.out" "$TMP/kb.full"
        done
    fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "warmsnapcheck: ALL PASS"; exit 0; fi
echo "warmsnapcheck: FAILED"; exit 1
