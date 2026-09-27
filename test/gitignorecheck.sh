#!/usr/bin/env bash
# gitignorecheck.sh — the crawl HONOURS .gitignore by default; --no-ignore restores the old walk.
#
# Registered in docs/EVALS.md ("`.gitignore` honoured by default, `--no-ignore` to override —
# PRE-REGISTERED 2026-09-03"). This gate is band (1) of that registration and it was written RED,
# against a binary that had neither the behaviour nor the flag, before the crawl was touched.
#
# WHY. ripwire is named for ripgrep, whose defining default is that ignored files are not searched.
# The crawl walked them: on the development machine this repository's own root is a >150K-file corpus
# of twelve gitignored checkouts under bench/external, a pair of multi-hundred-MB cache blobs that
# evict each other, and every gate that touches the un-excluded root timing out. For everyone else it
# is node_modules/, .venv/, target/, build/, dist/ — the directories the repository itself already
# declared uninteresting.
#
# THE SIX THINGS THIS PINS, and each is a way the feature could ship wrong:
#   1. an ignored SUBTREE and an ignored LOOSE FILE both leave the map, and both are DISCLOSED
#      (ignored_dirs= / ignored_files=) rather than silently absent — the honesty rule this tree
#      applies to every other drop class (skipped_oversize=, excluded_dirs=, pruned_dirs=).
#   2. a TRACKED file that happens to match a .gitignore pattern STAYS INDEXED. git itself ignores
#      nothing that is tracked; a matcher that reasons from the pattern text alone gets this wrong and
#      silently deletes committed source from the corpus.
#   3. --no-ignore restores exactly today's corpus, and carries NO ignored_* attribute (the escape
#      hatch has to be a real escape hatch, not a differently-shaped default).
#   4. a NON-GIT root is unchanged — the feature is not allowed to shrink a corpus it cannot explain.
#   5. absent-means-nothing-happened: a git tree with nothing ignored emits no ignored_* attribute at
#      all, so every existing golden/argvdiff byte-identity survives.
#   6. --exclude still composes on top, --skipped lists the ignored set, multi-root applies the rule
#      PER ROOT, and the ignore path is deterministic and cold == warm.
#
#   RIPWIRE_BIN=build/ripwire bash test/gitignorecheck.sh
#
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
command -v git >/dev/null 2>&1 || { echo "gitignorecheck: no git on PATH — the feature's whole premise; SKIP"; exit 0; }
echo "gitignorecheck: BIN=$BIN"

# ── the fixture: one git repo whose .gitignore hides a SUBTREE, a LOOSE FILE, and (deliberately) a
#    file that is nevertheless TRACKED. Symbol names are unique strings so a grep for them cannot
#    collide with anything else the map emits.
mkrepo(){
    local d="$1"
    mkdir -p "$d/keep" "$d/gen_out/deep"
    printf 'gen_out/\ngenerated.cpp\ntracked_anyway.cpp\n' >"$d/.gitignore"
    printf 'int rwGateMainSymbol( int a ) { return a + 1; }\n'          >"$d/main.cpp"
    printf 'int rwGateKeepSymbol( int a ) { return a + 2; }\n'          >"$d/keep/util.cpp"
    printf 'int rwGateTrackedAnywaySymbol( int a ) { return a + 3; }\n' >"$d/tracked_anyway.cpp"
    printf 'int rwGateVendorSymbol( int a ) { return a + 4; }\n'        >"$d/gen_out/dep.cpp"
    printf 'int rwGateDeepSymbol( int a ) { return a + 5; }\n'          >"$d/gen_out/deep/deeper.cpp"
    printf 'int rwGateGeneratedSymbol( int a ) { return a + 6; }\n'     >"$d/generated.cpp"
    (
        cd "$d" || exit 1
        git init -q . >/dev/null 2>&1
        git config user.email gate@example.invalid
        git config user.name  gate
        # tracked_anyway.cpp is force-added THOUGH .gitignore names it — that is the point of arm 2.
        git add .gitignore main.cpp keep/util.cpp >/dev/null 2>&1
        git add -f tracked_anyway.cpp >/dev/null 2>&1
        git commit -qm fixture >/dev/null 2>&1
    )
}
mkrepo "$TMP/repo"

run(){ "$BIN" "$@" --top-k=400 --no-cache 2>"$TMP/err"; }

# ── 1. DEFAULT: the ignored subtree and the ignored loose file are GONE, the tracked ones are not.
run "$TMP/repo" >"$TMP/def"
for s in rwGateMainSymbol rwGateKeepSymbol; do
    grep -q "$s" "$TMP/def" && ok "default map keeps the tracked symbol $s" \
        || no "default map lost the TRACKED symbol $s"
done
for s in rwGateVendorSymbol rwGateDeepSymbol rwGateGeneratedSymbol; do
    grep -q "$s" "$TMP/def" && no "default map still carries the GITIGNORED symbol $s" \
        || ok "default map drops the gitignored symbol $s"
done

# ── 2. a TRACKED file matching a .gitignore pattern is NOT ignored (git's own rule).
grep -q rwGateTrackedAnywaySymbol "$TMP/def" \
    && ok "a TRACKED file matching .gitignore stays indexed (rwGateTrackedAnywaySymbol)" \
    || no "a TRACKED file matching .gitignore was dropped — the matcher is reasoning from patterns, not from git"

# ── 3. the drop is DISCLOSED, not silent.
IGF="$( grep -oE 'ignored_files=[0-9]+' "$TMP/def" | head -1 | grep -oE '[0-9]+' )"
IGD="$( grep -oE 'ignored_dirs=[0-9]+'  "$TMP/def" | head -1 | grep -oE '[0-9]+' )"
[ "${IGF:-0}" -ge 1 ] && ok "header discloses ignored_files=$IGF" \
    || no "header has no ignored_files= though generated.cpp left the corpus (header: $( grep -oE '<!-- files=[^>]*' "$TMP/def" | head -1 ))"
[ "${IGD:-0}" -ge 1 ] && ok "header discloses ignored_dirs=$IGD" \
    || no "header has no ignored_dirs= though gen_out/ was pruned"

# ── 4. --no-ignore restores the pre-change corpus AND carries no ignored_* attribute.
run "$TMP/repo" --no-ignore >"$TMP/noig"
allback=1
for s in rwGateVendorSymbol rwGateDeepSymbol rwGateGeneratedSymbol rwGateMainSymbol rwGateKeepSymbol rwGateTrackedAnywaySymbol; do
    grep -q "$s" "$TMP/noig" || allback=0
done
[ "$allback" -eq 1 ] && ok "--no-ignore restores every symbol, ignored or not" \
    || no "--no-ignore did not restore the full corpus"
grep -qE 'ignored_(files|dirs)=' "$TMP/noig" \
    && no "--no-ignore leaked an ignored_* attribute (nothing was ignored under it)" \
    || ok "--no-ignore emits no ignored_* attribute"
FD="$( grep -oE '<!-- files=[0-9]+' "$TMP/def"  | head -1 | grep -oE '[0-9]+' )"
FN="$( grep -oE '<!-- files=[0-9]+' "$TMP/noig" | head -1 | grep -oE '[0-9]+' )"
[ -n "${FD:-}" ] && [ -n "${FN:-}" ] && [ "$FD" -lt "$FN" ] \
    && ok "files= shrank under the default ($FD < $FN with --no-ignore)" \
    || no "files= did not shrink: default=$FD --no-ignore=$FN"
# THE ACCOUNTING INVARIANT for the loose-file half: the files the ignore rule dropped INDIVIDUALLY are
# exactly ignored_files=. The subtree half is deliberately not in it — the walk stopped at the directory,
# so its contents are UNKNOWN, which is what ignored_dirs= says (the excluded_dirs=/pruned_dirs= rule).
[ $(( FN - FD )) -ge "${IGF:-0}" ] \
    && ok "ignored_files=$IGF is inside the $(( FN - FD )) files the rule removed (the rest is the pruned subtree)" \
    || no "ignored_files=$IGF exceeds the $(( FN - FD )) files that actually left the corpus"

# ── 5. a NON-GIT root is UNCHANGED: same tree, .git removed.
cp -R "$TMP/repo" "$TMP/nogit"; rm -rf "$TMP/nogit/.git"
run "$TMP/nogit" >"$TMP/plain"
plainall=1
for s in rwGateVendorSymbol rwGateDeepSymbol rwGateGeneratedSymbol; do
    grep -q "$s" "$TMP/plain" || plainall=0
done
[ "$plainall" -eq 1 ] && ok "a non-git root is unchanged (every symbol still indexed)" \
    || no "a non-git root lost symbols — the feature shrank a corpus it cannot explain"
grep -qE 'ignored_(files|dirs)=' "$TMP/plain" \
    && no "non-git root emitted an ignored_* attribute" \
    || ok "non-git root emits no ignored_* attribute"

# ── 6. ABSENT MEANS NOTHING HAPPENED: a git tree with nothing ignored is byte-identical to --no-ignore.
mkdir -p "$TMP/clean/src"
printf 'int rwGateCleanSymbol( int a ) { return a + 7; }\n' >"$TMP/clean/src/c.cpp"
( cd "$TMP/clean" && git init -q . >/dev/null 2>&1 && git config user.email g@example.invalid && git config user.name g \
  && git add -A >/dev/null 2>&1 && git commit -qm c >/dev/null 2>&1 )
run "$TMP/clean" >"$TMP/clean.def"
run "$TMP/clean" --no-ignore >"$TMP/clean.noig"
grep -qE 'ignored_(files|dirs)=' "$TMP/clean.def" \
    && no "a git tree with nothing ignored still emitted an ignored_* attribute (breaks golden byte-identity)" \
    || ok "nothing ignored ⇒ no ignored_* attribute (absent = nothing happened)"
diff -q "$TMP/clean.def" "$TMP/clean.noig" >/dev/null \
    && ok "nothing ignored ⇒ default output is byte-identical to --no-ignore" \
    || no "default and --no-ignore differ on a tree with nothing ignored"

# ── 7. --exclude composes ON TOP of the ignore rule.
run "$TMP/repo" --exclude=keep >"$TMP/exc"
grep -q rwGateKeepSymbol "$TMP/exc" && no "--exclude=keep did not drop keep/util.cpp under the ignore default" \
    || ok "--exclude composes on top of the gitignore default"
grep -q rwGateMainSymbol "$TMP/exc" && ok "--exclude=keep left main.cpp alone" \
    || no "--exclude=keep over-pruned"

# ── 8. --skipped LISTS the ignored set and counts it.
"$BIN" "$TMP/repo" --skipped --no-cache >"$TMP/skip" 2>/dev/null
grep -q 'ignored="' "$TMP/skip" && ok "--skipped header carries ignored=" \
    || no "--skipped header has no ignored= counter"
grep -q 'why="ignored"' "$TMP/skip" && ok "--skipped rows name the ignored files (why=\"ignored\")" \
    || no "--skipped does not row the ignored set"
grep -q 'generated.cpp' "$TMP/skip" && ok "--skipped names generated.cpp, the file that vanished" \
    || no "--skipped does not name the ignored file generated.cpp"
grep -q 'gen_out' "$TMP/skip" && ok "--skipped names the pruned gen_out subtree" \
    || no "--skipped does not name the pruned subtree"
"$BIN" "$TMP/repo" --skipped --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
    && ok "--skipped stays well-formed with the ignored rows" || no "--skipped XML broke"

# ── 9. MULTI-ROOT applies the rule PER ROOT.
mkrepo "$TMP/repo2"
"$BIN" "$TMP/repo" "$TMP/repo2" --top-k=400 --no-cache >"$TMP/multi" 2>/dev/null
grep -q rwGateVendorSymbol "$TMP/multi" && no "multi-root run carried a gitignored symbol" \
    || ok "multi-root applies the ignore rule per root"
MIGF="$( grep -oE 'ignored_files=[0-9]+' "$TMP/multi" | head -1 | grep -oE '[0-9]+' )"
[ "${MIGF:-0}" -ge 2 ] && ok "multi-root ignored_files=$MIGF sums both roots" \
    || no "multi-root ignored_files=${MIGF:-<none>} did not sum both roots (expected >= 2)"

# ── 10. DETERMINISM and COLD == WARM on the ignore path.
run "$TMP/repo" >"$TMP/d1"; run "$TMP/repo" >"$TMP/d2"
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "ignore path is deterministic (x2 byte-identical)" \
    || no "ignore path is not deterministic"
CACHEDIR="$TMP/cache"; mkdir -p "$CACHEDIR"
TMPDIR="$CACHEDIR" "$BIN" "$TMP/repo" --top-k=400 >"$TMP/w1" 2>/dev/null
TMPDIR="$CACHEDIR" "$BIN" "$TMP/repo" --top-k=400 >"$TMP/w2" 2>/dev/null
diff -q "$TMP/w1" "$TMP/w2" >/dev/null && diff -q "$TMP/d1" "$TMP/w2" >/dev/null \
    && ok "cold == warm == warm on the ignore path" \
    || no "cold/warm disagree on the ignore path"
# The cache blob is keyed per FILE, not per ignore mode: a --no-ignore run writes a SUPERSET blob and a
# default run must not then serve the superset's extra files back into the map.
TMPDIR="$CACHEDIR" "$BIN" "$TMP/repo" --top-k=400 --no-ignore >/dev/null 2>&1
TMPDIR="$CACHEDIR" "$BIN" "$TMP/repo" --top-k=400 >"$TMP/w3" 2>/dev/null
diff -q "$TMP/d1" "$TMP/w3" >/dev/null \
    && ok "a default run after a --no-ignore run is unchanged (no cross-mode blob bleed)" \
    || no "a --no-ignore run's cache blob bled into the following default run"

# ── 11. THE ROOT-IGNORED TRAP. Pointing at a directory that is ITSELF gitignored (`ripwire build/` in a
#    repo whose .gitignore holds `build/`) makes git answer "./" — everything. Honouring that literally
#    hands back an EMPTY map for a directory the user pointed at deliberately, which is the worst available
#    reading of "map this". The full walk runs and ignore_mode= says why.
run "$TMP/repo/gen_out" >"$TMP/rooted"
grep -q rwGateVendorSymbol "$TMP/rooted" && ok "a root that is itself ignored is still mapped in full" \
    || no "mapping a gitignored directory directly returned an empty/short map"
"$BIN" "$TMP/repo/gen_out" --skipped --no-cache 2>/dev/null | grep -q 'ignore_mode="root-ignored"' \
    && ok '--skipped says ignore_mode="root-ignored" for a root inside an ignored subtree' \
    || no 'a root inside an ignored subtree does not disclose ignore_mode="root-ignored"'
"$BIN" "$TMP/nogit" --skipped --no-cache 2>/dev/null | grep -q 'ignore_mode="unavailable"' \
    && ok '--skipped says ignore_mode="unavailable" on a non-git root' \
    || no 'a non-git root does not disclose ignore_mode="unavailable"'
"$BIN" "$TMP/repo" --skipped --no-ignore --no-cache 2>/dev/null | grep -q 'ignore_mode="off"' \
    && ok '--skipped says ignore_mode="off" under --no-ignore' \
    || no '--no-ignore does not disclose ignore_mode="off"'

# ── 12. CodeRabbit thread (src/ingest_crawl.h:1365): the gitignore probe's `git ls-files … -z` running
#    but EXITING NON-ZERO (as opposed to git being altogether unrunnable, arm 12/§4 above, or a non-git
#    root) used to return silently with no DISCLOSE at all — `available` was already false by default, so
#    the fallback (a full walk, ignore_mode="unavailable") was always safe, but the degrade carried no
#    record for the self-check ledger. A PATH shim makes `git ls-files … --ignored …` fail inside an
#    otherwise-real git work tree (every OTHER git subcommand passes through), proving the crawl still
#    falls back cleanly (same ignore_mode="unavailable" as arms 12/§4) rather than crashing or hanging on
#    a probe that ran and refused.
REALGIT="$( command -v git )"; SHIM="$TMP/gitshim"; mkdir -p "$SHIM"
cat >"$SHIM/git" <<SHEOF
#!/usr/bin/env bash
case " \$* " in *" ls-files "*"--ignored"*) exit 1 ;; esac
exec "$REALGIT" "\$@"
SHEOF
chmod +x "$SHIM/git"
PATH="$SHIM:$PATH" "$BIN" "$TMP/repo" --skipped --no-cache >"$TMP/probefail.out" 2>"$TMP/probefail.err"; probefailRc=$?
if [ "$probefailRc" -eq 0 ] && grep -q 'ignore_mode="unavailable"' "$TMP/probefail.out"; then
    ok "gitignore probe: a git that runs but EXITS NON-ZERO still falls back cleanly (ignore_mode=\"unavailable\", exit 0)"
else
    no "gitignore probe: a failing (not missing) git broke the fallback (rc=$probefailRc): $( cat "$TMP/probefail.err" )"
fi
PATH="$SHIM:$PATH" "$BIN" "$TMP/repo" --top-k=400 --no-cache >"$TMP/probefail.map" 2>/dev/null
grep -q "rwGateMainSymbol" "$TMP/probefail.map" \
    && ok "gitignore probe failure still maps the tree in full (the safe fallback, not an empty map)" \
    || no "gitignore probe failure produced an empty/short map instead of falling back to a full walk"

# ── 14. TRACKED SOURCE UNDER A BUILD-OUTPUT NAME (build/dist/out/target…). The crawl prunes those names as
#    build OUTPUT, and before this arm existed it pruned them whatever git said: a repository's tracked
#    `lib/build/*.py` package (21 files on one real Python repository) vanished from files=, from --skipped's
#    rows and from every answer, with only an unnamed pruned_dirs= count to show for it. The name is a
#    heuristic about UNTRACKED output, so in a work tree the files git TRACKS there are indexed and the rest
#    stays pruned; outside git nothing can tell the two apart, so the name rule stands and every such
#    directory is DISCLOSED by name (unvetted_dirs= + why="unvetted-dir" rows). Languages are deliberately
#    mixed (py, rs, js): the rule is a directory name, never a grammar. vendor/ stays pruned even when
#    tracked — vendored code is skipped as a class, not as output.
TB="$TMP/tbrepo"
mkdir -p "$TB/build/nested" "$TB/target" "$TB/pkg/dist" "$TB/vendor" "$TB/src"
printf 'def rw_gate_tb_build_gen():\n    return 1\n'           >"$TB/build/gen.py"
printf 'def rw_gate_tb_build_nested():\n    return 2\n'        >"$TB/build/nested/deep.py"
printf 'pub fn rw_gate_tb_target_lib() -> i32 { 3 }\n'         >"$TB/target/lib.rs"
printf 'export function rwGateTbDistFn() { return 4; }\n'      >"$TB/pkg/dist/d.js"
printf 'def rw_gate_tb_vendor():\n    return 5\n'              >"$TB/vendor/v.py"
printf 'def rw_gate_tb_main():\n    return 6\n'                >"$TB/src/main.py"
(
    cd "$TB" || exit 1
    git init -q . >/dev/null 2>&1
    git config user.email gate@example.invalid
    git config user.name  gate
    git add -A >/dev/null 2>&1
    git commit -qm fixture >/dev/null 2>&1
)
# untracked build output beside the tracked source: a binary object, a generated .py, a whole out/ tree
printf '\177ELF\000\000' >"$TB/build/out.o"
printf 'def rw_gate_tb_untracked_gen():\n    return 7\n' >"$TB/build/untracked_gen.py"
mkdir -p "$TB/out" && printf 'def rw_gate_tb_untracked_out():\n    return 8\n' >"$TB/out/o.py"
run "$TB" >"$TMP/tb.map"
tbmiss=""
for s in rw_gate_tb_build_gen rw_gate_tb_build_nested rw_gate_tb_target_lib rwGateTbDistFn rw_gate_tb_main; do
    grep -q "$s" "$TMP/tb.map" || tbmiss="$tbmiss $s"
done
[ -z "$tbmiss" ] && ok "14a git: TRACKED files under build/ target/ pkg/dist/ (nested too) are indexed" \
    || no "14a git: tracked source under a build-output name is missing:$tbmiss"
tbleak=""
for s in rw_gate_tb_untracked_gen rw_gate_tb_untracked_out rw_gate_tb_vendor; do
    grep -q "$s" "$TMP/tb.map" && tbleak="$tbleak $s"
done
[ -z "$tbleak" ] && ok "14b git: untracked output (build/untracked_gen.py, out/) and tracked vendor/ stay pruned" \
    || no "14b git: pruned content leaked into the map:$tbleak"
"$BIN" "$TB" --skipped --no-cache >"$TMP/tb.sk" 2>/dev/null
grep -q 'unvetted' "$TMP/tb.sk" "$TMP/tb.map" \
    && no "14c git: an unvetted_dirs=/unvetted-dir disclosure on a work tree, where git's verdict exists" \
    || ok "14c git: no unvetted disclosure where git vetted every build-output dir"
grep -q 'pruned_dirs="6"' "$TMP/tb.sk" \
    && ok "14d git: pruned_dirs= still counts the six pruned subtrees (.git build target pkg/dist vendor out)" \
    || no "14d git: pruned_dirs moved: $( grep -o 'pruned_dirs="[0-9]*"' "$TMP/tb.sk" )"
# 14e: a .gitignore naming build/ does not hide what git tracks there (git lists such a dir file by file)
printf 'build/\nout/\n' >"$TB/.gitignore"
run "$TB" >"$TMP/tb.ign"
grep -q rw_gate_tb_build_gen "$TMP/tb.ign" && ! grep -q rw_gate_tb_untracked_gen "$TMP/tb.ign" \
    && ok "14e git: an ignored build/ still yields its tracked file, never its untracked one" \
    || no "14e git: .gitignore build/ changed the tracked/untracked split"
rm -f "$TB/.gitignore"
# 14f: cold and warm, twice: byte-identical
run "$TB" >"$TMP/tb.map2"
cmp -s "$TMP/tb.map" "$TMP/tb.map2" && ok "14f git: the map with tracked build-dir files is byte-identical across runs" \
    || no "14f git: two runs differ"
# 14g: NON-GIT copy — the name rule stands and is disclosed BY NAME
NG="$TMP/tbplain"; cp -R "$TB" "$NG"; rm -rf "$NG/.git"
run "$NG" >"$TMP/ng.map"
grep -q rw_gate_tb_build_gen "$TMP/ng.map" \
    && no "14g non-git: build/ was indexed without any tracked verdict" \
    || ok "14g non-git: build-output dirs stay pruned (no git verdict to override the name)"
grep -q 'unvetted_dirs=4 ' "$TMP/ng.map" \
    && ok "14h non-git: the map header discloses unvetted_dirs=4 (build out pkg/dist target)" \
    || no "14h non-git: map header lacks unvetted_dirs=4: $( grep -oE '<!-- files=[^>]*' "$TMP/ng.map" | head -1 )"
"$BIN" "$NG" --skipped --no-cache >"$TMP/ng.sk" 2>/dev/null
ngrows="$( grep -oE '<f p="[^"]*" why="unvetted-dir"' "$TMP/ng.sk" | sed 's/.*p="\([^"]*\)".*/\1/' | tr '\n' ' ' )"
[ "$ngrows" = "build out pkg/dist target " ] && grep -q 'unvetted_dirs="4"' "$TMP/ng.sk" \
    && ok "14i non-git: --skipped rows each unvetted dir by name ($ngrows) with unvetted_dirs=\"4\"" \
    || no "14i non-git: --skipped unvetted rows wrong: [$ngrows] $( grep -o 'unvetted_dirs="[0-9]*"' "$TMP/ng.sk" )"
# 14j: a git that cannot answer the tracked probe degrades to the non-git disclosure, never to silence
cat >"$SHIM/git" <<SHEOF
#!/usr/bin/env bash
case " \$* " in *" ls-files --cached "*) exit 1 ;; esac
exec "$REALGIT" "\$@"
SHEOF
chmod +x "$SHIM/git"
PATH="$SHIM:$PATH" "$BIN" "$TB" --skipped --no-cache >"$TMP/tbfail.sk" 2>/dev/null; tbfailRc=$?
[ "$tbfailRc" -eq 0 ] && grep -q 'unvetted_dirs="' "$TMP/tbfail.sk" && grep -q 'why="unvetted-dir"' "$TMP/tbfail.sk" \
    && ok "14j git: a failing tracked probe falls back to the name rule AND rows the unvetted dirs (rc=0)" \
    || no "14j git: a failing tracked probe was not disclosed (rc=$tbfailRc): $( grep -o 'unvetted_dirs="[0-9]*"' "$TMP/tbfail.sk" )"

# ── 13. the flag is in --help (the deckcheck allowlist row for --no-ignore retires with it).
"$BIN" --help=all 2>&1 | grep -q -- '--no-ignore' && ok "--no-ignore is documented in --help" \
    || no "--no-ignore is missing from --help"

[ "$fail" -eq 0 ] && { echo "gitignorecheck: PASS"; exit 0; }
echo "gitignorecheck: FAIL"; exit 1
