#!/usr/bin/env bash
# trackedbuilddircheck.sh — a build/ directory that git TRACKS files under is SOURCE, and its TRACKED files are crawled;
# the same name untracked stays pruned (lane M1B, from LP1's ga-bat-06 loss).
#
# WHY. kCrawlSkipDirs prunes those four names on a guess that they hold generated output. bat's build/ holds its Cargo
# build script — committed source — and the name prune removed it from every answer while a peer indexed it (LP1
# MEASURED: with build/ renamed, all 5 gold functions of the task reach page 1). git can falsify the guess, so the crawl
# asks it (ingest_crawl.h TrackedBuildDirs), once per root and only when a non-ignored build-output name is met.
# ONLY build/: round 1 also lifted dist/ out/ target/, and on GA3 DEV the only trees affected were axios's tracked dist/
# BUNDLES (28-36 of ~135 page-1 rows, one body lost); none of the house's bundle/minified/vendored verdicts flags them.
#
# THE ARMS, and what each would catch:
#   1. default map: tracked build/ and tracked sub/build/ are INDEXED (RED on the pre-change binary); untracked out/,
#      ignored target/, tracked vendor/, TRACKED web/dist/ (dist/ is not falsifiable), an untracked lib/build/, an
#      ignored file INSIDE the tracked build/ and an untracked-NOT-ignored file inside it (build/scratch.c: inside a
#      crawled build/ only what git tracks is indexed) all stay OUT.
#   2. --skipped rows out/ target/ vendor/ web/dist lib/build as pruned-dir, no longer rows build/ sub/build, and rows
#      build/scratch.c as why="untracked-build" under untracked_build="1"; the map header carries untracked_build=1.
#   3. CONTROL for every "stays out" arm: the same tree with the four dirs RENAMED indexes every symbol, so an absent
#      symbol in arm 1 is the prune's doing and not a grep that cannot see it (a prohibition is vacuous by default).
#   4. a NON-GIT copy keeps the name prune (nothing vouches). --no-ignore crawls the TRACKED build/ too, with every file
#      in it (scratch.c and the ignored x.gen.c — the flag stops filtering), and no untracked_build= drop; untracked
#      out/ and lib/build/ stay pruned (built-in policy, which --no-ignore never lifted).
#   5. a SUBDIRECTORY root sees its own tracked sub/build/ (the probe's pathspec and paths are root-relative).
#   6. --quality-delta: a regression inside the tracked build/ GATES as preexisting-worse. Against a HEAD snapshot that
#      still pruned build/ it would read as new-symbol (never gating) — the materialized-tree scope (CrawlTreeAllTracked).
#   7. --merge-scout: two branches editing the same function in build/ conflict on it — the scouted arms' `git archive`
#      no longer excludes the four names (quality.h crawlSkipDirPathspecs).
#   8. MCP: a server that warmed its index sees a NEW file added under the tracked build/ (mcpindex.h collectDirMtimes
#      watches a name-pruned dir that holds an indexed file).
#   9. determinism: two cold runs are byte-identical, and cold == warm through the cache.
#  10. the warm snapshot under --no-ignore, in a LINKED worktree (its .git is a file, so an index write moves no
#      watched directory): a replayed crawl must be refused once `git add` makes an untracked build/ tracked.
#
#   RIPWIRE_BIN=build/ripwire bash test/trackedbuilddircheck.sh
# Takes $1 = BIN (the house convention), else $RIPWIRE_BIN, else ./build/ripwire.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "trackedbuilddircheck: no git on PATH — the feature's whole premise; SKIP"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the MCP arm"; exit 2; }
echo "trackedbuilddircheck: BIN=$BIN"
export XDG_CACHE_HOME="$TMP/xc" TMPDIR="$TMP/tmpd"
mkdir -p "$XDG_CACHE_HOME" "$TMPDIR"

cfn(){ printf 'int %s( int a ) { return a + %s; }\n' "$1" "$2" >"$3"; }
mkrepo(){
    local d="$1"
    mkdir -p "$d/src" "$d/build" "$d/web/dist" "$d/out" "$d/target/debug" "$d/vendor" "$d/sub/build" "$d/lib/build"
    printf 'target/\n*.gen.c\n' >"$d/.gitignore"
    cfn rwTbMainFn          1 "$d/src/main.c"
    cfn rwTbBuildFn         2 "$d/build/tool.c"
    cfn rwTbBuildSteadyFn   3 "$d/build/steady.c"
    cfn rwTbBuildIgnoredFn  4 "$d/build/x.gen.c"         # untracked AND ignored, inside the tracked build/
    cfn rwTbDistFn          5 "$d/web/dist/bundle.c"
    cfn rwTbOutFn           6 "$d/out/gen.c"             # untracked, NOT ignored: the name prune must still hold
    cfn rwTbTargetFn        7 "$d/target/debug/t.c"      # untracked, ignored
    cfn rwTbVendorFn        8 "$d/vendor/lib.c"          # TRACKED, but vendor/ is not a build-output name
    cfn rwTbSubBuildFn      9 "$d/sub/build/s.c"
    cfn rwTbSubFn          10 "$d/sub/x.c"
    cfn rwTbScratchFn      12 "$d/build/scratch.c"       # untracked, NOT ignored, inside the TRACKED build/
    cfn rwTbLibBuildFn     13 "$d/lib/build/later.c"     # untracked dir named build/, NOT ignored
    (
        cd "$d" || exit 1
        git init -q . >/dev/null 2>&1
        git config user.email gate@example.invalid
        git config user.name  gate
        git add .gitignore src build/tool.c build/steady.c web vendor sub >/dev/null 2>&1
        git commit -qm fixture >/dev/null 2>&1
        git branch -M main >/dev/null 2>&1
    )
}
R="$TMP/repo"
mkrepo "$R"
IN="rwTbMainFn rwTbBuildFn rwTbBuildSteadyFn rwTbSubBuildFn rwTbSubFn"
OUT="rwTbOutFn rwTbTargetFn rwTbVendorFn rwTbBuildIgnoredFn rwTbDistFn rwTbScratchFn rwTbLibBuildFn"
run(){ "$BIN" "$@" --top-k=400 --no-cache 2>>"$TMP/err"; }
syms(){ grep -oE 'rwTb[A-Za-z]+' "$1" | sort -u | tr '\n' ' '; }

# ── 1. the default map
run "$R" >"$TMP/def"
for s in $IN;  do if grep -q "\b$s\b" "$TMP/def"; then ok "1: indexed $s"; else no "1: $s is MISSING from the default map (indexed: $( syms "$TMP/def" ))"; fi; done
for s in $OUT; do grep -q "\b$s\b" "$TMP/def" && no "1: $s is indexed — the prune is gone where git does not vouch" || ok "1: kept out $s"; done

# ── 2. --skipped
"$BIN" "$R" --skipped --no-cache >"$TMP/sk" 2>>"$TMP/err"
for d in out target vendor web/dist lib/build; do
    if grep -q "<f p=\"$d\" why=\"pruned-dir\"" "$TMP/sk"; then ok "2: --skipped rows $d/ as pruned-dir"; else no "2: --skipped lost the pruned-dir row for $d/"; fi
done
grep -q '<f p="build/scratch.c" why="untracked-build"' "$TMP/sk" && grep -q 'untracked_build="1"' "$TMP/sk" \
    && ok "2: --skipped rows build/scratch.c as untracked-build, untracked_build=\"1\"" \
    || no "2: --skipped does not disclose the untracked file inside the tracked build/: $( grep -oE '<skipped [^>]*>' "$TMP/sk" | cut -c1-300 )"
grep -q 'untracked_build=1' "$TMP/def" && ok "2: the map header discloses untracked_build=1" \
    || no "2: the map header does not disclose the untracked build/ file: $( grep -oE '<!-- files=[^>]{0,200}' "$TMP/def" | head -1 )"
for d in build sub/build; do
    grep -q "<f p=\"$d\" why=\"pruned-dir\"" "$TMP/sk" && no "2: --skipped still rows the tracked $d/ as pruned" || ok "2: --skipped no longer rows the tracked $d/"
done

# ── 3. CONTROL: renamed dirs index every symbol, so arm 1's absences are the prune's
cp -R "$R" "$TMP/ctl"; rm -rf "$TMP/ctl/.git"
for d in build out target vendor sub/build lib/build; do mv "$TMP/ctl/$d" "$TMP/ctl/${d}_x"; done
mv "$TMP/ctl/web/dist" "$TMP/ctl/web/dist_x"
run "$TMP/ctl" >"$TMP/ctlmap"
miss=""; for s in $IN $OUT; do grep -q "\b$s\b" "$TMP/ctlmap" || miss="$miss $s"; done
if [ -z "$miss" ]; then ok "3: control — every fixture symbol is visible when nothing is name-pruned"; else no "3: control cannot see:$miss"; fi

# ── 4. non-git keeps the name prune; --no-ignore crawls the tracked build/ whole
cp -R "$R" "$TMP/nogit"; rm -rf "$TMP/nogit/.git"
run "$TMP/nogit" >"$TMP/ng"
grep -q '\brwTbBuildFn\b' "$TMP/ng" && no "4: a non-git root crawled build/ (no git, nothing vouches)" || ok "4: non-git root keeps the build/ prune"
if grep -q '\brwTbMainFn\b' "$TMP/ng"; then ok "4: non-git root still indexes src/"; else no "4: non-git root lost src/ (instrument broken)"; fi
run "$R" --no-ignore >"$TMP/noig"
for s in rwTbMainFn rwTbBuildFn rwTbScratchFn rwTbBuildIgnoredFn rwTbSubBuildFn; do
    if grep -q "\b$s\b" "$TMP/noig"; then ok "4: --no-ignore indexes $s"; else no "4: --no-ignore misses $s (indexed: $( syms "$TMP/noig" ))"; fi
done
for s in rwTbOutFn rwTbLibBuildFn rwTbDistFn rwTbVendorFn rwTbTargetFn; do
    grep -q "\b$s\b" "$TMP/noig" && no "4: --no-ignore indexed $s (an untracked or non-falsifiable dir)" || ok "4: --no-ignore keeps out $s"
done
grep -q 'untracked_build=' "$TMP/noig" && no "4: --no-ignore disclosed an untracked_build= drop (it filters nothing)" || ok "4: --no-ignore drops no untracked build/ file"

# ── 5. a subdirectory root
run "$R/sub" >"$TMP/subm"
if grep -q '\brwTbSubBuildFn\b' "$TMP/subm"; then ok "5: a subdirectory root indexes its tracked build/"; else no "5: root=sub/ misses sub/build/ (indexed: $( syms "$TMP/subm" ))"; fi

# ── 6. --quality-delta: a regression in the tracked build/ gates as preexisting-worse
cat >"$R/build/tool.c" <<'EOF'
int rwTbBuildFn( int a )
{
    if( a > 1 ) { if( a > 2 ) { if( a > 3 ) { if( a > 4 ) { if( a > 5 ) { return 9; } } } } }
    if( a == 7 || a == 8 || a == 9 || a == 10 ) { return 3; }
    for( int i = 0; i < a; ++i ) { if( i > 2 ) { a += i; } else if( i > 3 ) { a -= 1; } else { a ^= i; } }
    return a + 2;
}
EOF
( cd "$R" && "$BIN" . --quality-delta --legend=compact >"$TMP/qd" 2>>"$TMP/err" ); qrc=$?
if [ "$qrc" = 2 ] && grep -q 'kind="complexity" sym="rwTbBuildFn"[^>]*p="build/tool.c:1" gating="1"' "$TMP/qd"; then
    ok "6: --quality-delta gates the build/ regression (rc=2, preexisting complexity row)"
else
    no "6: --quality-delta rc=$qrc did not gate rwTbBuildFn: $( grep -oE '<quality-delta [^>]*>|<r [^>]*>' "$TMP/qd" | head -3 | tr '\n' ' ' )"
fi
grep -q 'new-symbol="0"' "$TMP/qd" && ok "6: no build/ symbol reads as new (the HEAD snapshot crawled build/ too)" \
    || no "6: new-symbol is not 0 — the HEAD snapshot pruned what the working tree indexed: $( grep -oE '<quality-delta [^>]*>' "$TMP/qd" )"
git -C "$R" checkout -q -- build/tool.c

# ── 7. --merge-scout: two branches editing one build/ function conflict on it
(
    cd "$R" || exit 1
    git checkout -q -b ba main && cfn rwTbBuildFn 20 build/tool.c && git commit -qam a
    git checkout -q -b bb main && cfn rwTbBuildFn 30 build/tool.c && git commit -qam b
    git checkout -q main
) >/dev/null 2>&1
( cd "$R" && "$BIN" . --merge-scout=ba,bb >"$TMP/ms" 2>>"$TMP/err" ); msrc=$?
msrows(){ sed 's/<!--[^>]*-->//' "$TMP/ms" | grep -oE '<(arm|pair|sym)[^>]*>' | tr '\n' ' ' | head -c 600; }
[ "$msrc" = 0 ] && grep -q '<arm ref="ba" [^>]*changed="1"[^>]*><sym p="build/tool.c" id="rwTbBuildFn"/>' "$TMP/ms" \
    && grep -q '<pair a="ba" b="bb" conflicts="1"' "$TMP/ms" \
    && ok "7: --merge-scout sees both arms change rwTbBuildFn and the ba/bb conflict on it (rc=$msrc)" \
    || no "7: --merge-scout rc=$msrc misses the build/ conflict: $( msrows )"
# Against a scouted base archived WITHOUT build/ the clean working tree reads every build/ symbol as its own new work.
grep -q '<arm ref="working-tree" [^>]*changed="0"' "$TMP/ms" \
    && ok "7: the clean working tree changes nothing (the base archive carried build/ too)" \
    || no "7: the clean working tree reads as changed — the scouted base lost build/: $( msrows )"

# ── 8. MCP: a new file under the tracked build/ reaches a warmed server
W="$TMP/mcp"; mkrepo "$W"
FIFO="$TMP/in.fifo"; mkfifo "$FIFO"
"$BIN" --mcp <"$FIFO" >"$TMP/mcp.out" 2>/dev/null &
SRV=$!
exec 9>"$FIFO"
req(){ printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"%s","symbol":"%s"}}}\n' "$1" "$W" "$2" >&9; }
wait_for_id(){ local i; for i in $( seq 1 400 ); do grep -q "\"id\":$1[,}]" "$TMP/mcp.out" 2>/dev/null && return 0; sleep 0.05; done; return 1; }
inner(){ grep "\"id\":$1[,}]" "$TMP/mcp.out" | tail -1 | python3 -c 'import sys,json
r=json.load(sys.stdin); print("__ERROR__" if "error" in r else r["result"]["content"][0]["text"])'; }
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&9
req 2 rwTbBuildFn
wait_for_id 2 || no "8: server never answered the warm-up (id=2)"
case "$( inner 2 )" in *build/tool.c*) ok "8: the warmed MCP index resolves rwTbBuildFn in build/";; *) no "8: MCP index does not hold build/tool.c";; esac
cfn rwTbAddedFn 11 "$W/build/added.c"
git -C "$W" add build/added.c >/dev/null 2>&1
req 3 rwTbAddedFn
wait_for_id 3 || no "8: server never answered the post-add read (id=3)"
exec 9>&-
wait "$SRV" 2>/dev/null
case "$( inner 3 )" in *build/added.c*) ok "8: a file added under the tracked build/ reaches the warmed server";;
    *) no "8: the warmed server is STALE for build/added.c: $( inner 3 | head -c 200 )";; esac

# ── 9. determinism: cold twice, then cold == warm through the cache
run "$R" >"$TMP/d1"; run "$R" >"$TMP/d2"
if grep -q '\brwTbBuildFn\b' "$TMP/d1" && cmp -s "$TMP/d1" "$TMP/d2"; then ok "9: two cold runs are byte-identical"; else no "9: two cold runs differ"; fi
"$BIN" "$R" --top-k=400 >"$TMP/w1" 2>>"$TMP/err"; "$BIN" "$R" --top-k=400 >"$TMP/w2" 2>>"$TMP/err"
if cmp -s "$TMP/w1" "$TMP/w2" && cmp -s "$TMP/w1" "$TMP/d1"; then ok "9: cold == warm through the cache"; else no "9: the cached runs differ from the cold run"; fi

# ── 10. warm snapshot under --no-ignore: an index-only change must refuse the replayed crawl
V="$TMP/wtsrc"; mkrepo "$V"
git -C "$V" worktree add -q --detach "$TMP/wt" main >/dev/null 2>&1
[ -f "$TMP/wt/.git" ] && [ -f "$TMP/wt/build/tool.c" ] || no "10: could not create the linked worktree (instrument broken)"
mkdir -p "$TMP/wt/lib/build"; cfn rwTbLaterFn 14 "$TMP/wt/lib/build/later2.c"   # an untracked lib/build/ in the linked worktree
wrun(){ RIPWIRE_SNAPSHOT_STATS=1 "$BIN" "$TMP/wt" --no-ignore --top-k=400 --cache="$TMP/wt.bin" >"$1" 2>"$1.err"; }
sleep 3                                                   # leave the 2 s racy window, so the next run may record the tree
wrun "$TMP/w10a"; sleep 3; wrun "$TMP/w10b"
if grep -q 'tree=replayed' "$TMP/w10b.err" && ! grep -q '\brwTbLaterFn\b' "$TMP/w10b"; then
    ok "10: --no-ignore replays the crawl, untracked lib/build/ pruned (vacuity guard)"
else
    no "10: VACUOUS or wrong — no replay, or lib/build/ indexed while untracked: $( grep snapshot-stats "$TMP/w10b.err" )"
fi
git -C "$TMP/wt" add lib/build/later2.c >/dev/null 2>&1
wrun "$TMP/w10c"
grep -q '\brwTbLaterFn\b' "$TMP/w10c" && ok "10: after git add, the newly tracked lib/build/ is indexed (the index change refused the replay)" \
    || no "10: STALE — the warm snapshot replayed past an index change under --no-ignore: $( grep snapshot-stats "$TMP/w10c.err" )"

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAILURES (stderr tail:)"; tail -5 "$TMP/err"; exit 1
