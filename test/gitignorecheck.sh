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
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
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
( cd "$TMP/clean" && git init -q . >/dev/null 2>&1 && git config user.email g@e.invalid && git config user.name g \
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

# ── 12. the flag is in --help (the deckcheck allowlist row for --no-ignore retires with it).
"$BIN" --help 2>&1 | grep -q -- '--no-ignore' && ok "--no-ignore is documented in --help" \
    || no "--no-ignore is missing from --help"

[ "$fail" -eq 0 ] && { echo "gitignorecheck: PASS"; exit 0; }
echo "gitignorecheck: FAIL"; exit 1
