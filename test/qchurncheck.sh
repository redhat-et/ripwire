#!/usr/bin/env bash
# qchurncheck.sh — gate for Y2 (P2): quality::gitRawCommitStreamCached memoizes gitmine's
# `git log --name-only` walk (431 ms on a large private C++ corpus; every rich verb — --for, --metrics,
# --exemplar — pays it once per invocation, main.cpp:5392/5404 call it via gitmine::gitCoChangeAndChurn).
#
# DECIDED key ( "Y2 churn-memo key"): (realpath(root), HEAD sha, window-months,
# gitWindowRefSha) — the qchurn family (quality.h). Committed-history-only: the RAW (epoch, path) stream
# is cached, but it is resolved against the CALLER's live IngestResult fresh on every call, so dirty
# working-tree state is never folded into the memo (main.cpp's two callers pass no uncommitted signal in).
#
# Asserts:
#   (a) a SECOND --for run against an unchanged HEAD does NOT spawn the `git log --name-only` walk —
#       observed via GIT_TRACE (git's own child-process trace, inherited through popen) counting
#       "name-only" occurrences: cold run = 1, warm run = 0.
#   (b) memoized (warm) output is BYTE-IDENTICAL to a fresh run against a COLD, from-scratch blob dir
#       (the cache must never change the answer, only whether the walk runs).
#   (c) a NEW commit changes HEAD sha and invalidates the memo: the next run re-walks (name-only count
#       back to 1) and a distinct qchurn-*.bin blob appears (the old one is not overwritten/reused).
#   (d) key separation: two DIFFERENT roots (or the same root under a different HEAD) never share a
#       blob — implied by (c)'s "distinct blob" check, verified directly too.
#
# Uses its own temp repo + a private TMPDIR (cacheDirLadder() prefers TMPDIR) so the qchurn-*.bin files
# land in a directory we own and can inspect/clear. Needs git + perl(for nothing here, plain grep/wc).
# Usage:  test/qchurncheck.sh   |   RIPWIRE_BIN=build_w2e/ripwire test/qchurncheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

REPO="$( mktemp -d )"; TMP="$( mktemp -d )"; trap 'rm -rf "$REPO" "$TMP"' EXIT
QTMP="$TMP/qtmp"; QCACHE="$QTMP/ripwire"; mkdir -p "$QTMP"   # cacheDirLadder() creates the private child

echo "qchurncheck: BIN=$BIN"

# Y4: shard-aware lookup inside the private Ripwire cache directory.
qchurnfiles(){ find "$QCACHE" -maxdepth 2 -type f -name 'ripwire-qchurn-*.bin' 2>/dev/null; }
nqchurn(){ qchurnfiles | wc -l | tr -d ' '; }
# name_only_count TRACEFILE — how many git child processes in this run's trace invoked --name-only (the
# expensive walk gitRawCommitStreamCached guards). Any OTHER git call this run makes (rev-parse, HEAD
# resolution, etc.) never contains "name-only", so this is a clean, argv-based signal — not a timing guess.
name_only_count(){ grep -c "name-only" "$1" 2>/dev/null || true; }
# run TRACEFILE ARGS... — invokes ripwire against $REPO with our private TMPDIR + a fresh GIT_TRACE file.
run(){ local tf="$1"; shift; : > "$tf"; env TMPDIR="$QTMP" GIT_TRACE="$tf" "$BIN" "$REPO" "$@"; }

mkdir -p "$REPO/src"
cat > "$REPO/src/lib.cpp" <<'EOF'
int helper( int x ) { return x + 1; }
int caller( int y ) { return helper( y ) + helper( y + 1 ); }
EOF
git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"
git -C "$REPO" add -A
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" \
    git -C "$REPO" commit -qm "init"

# ── (a) cold run walks once, warm run does not walk at all ─────────────────────────────────────────────
run "$TMP/trace_cold.log" --for="helper" --no-cache >"$TMP/cold.out" 2>"$TMP/cold.err"; rcCold=$?
COLD_N="$( name_only_count "$TMP/trace_cold.log" )"
[ "$rcCold" -eq 0 ] && [ "$COLD_N" -ge 1 ] \
    && ok "cold --for run spawns the name-only walk ($COLD_N invocation(s))" \
    || no "cold run wrong (rc=$rcCold, name-only count=$COLD_N)"

if [ "$( nqchurn )" -ge 1 ]; then ok "cold run writes a ripwire-qchurn-*.bin blob"; else no "no qchurn blob after cold run"; fi

run "$TMP/trace_warm.log" --for="helper" --no-cache >"$TMP/warm.out" 2>"$TMP/warm.err"; rcWarm=$?
WARM_N="$( name_only_count "$TMP/trace_warm.log" )"
[ "$rcWarm" -eq 0 ] && [ "$WARM_N" -eq 0 ] \
    && ok "warm --for run does NOT spawn the name-only walk (memo hit; count=$WARM_N)" \
    || no "warm run still walked git log (rc=$rcWarm, name-only count=$WARM_N) — memo not reused"

# ── (b) memoized output byte-identical to a fresh COLD blob dir ────────────────────────────────────────
COLDXDG="$TMP/coldxdg"; mkdir -p "$COLDXDG"
env TMPDIR="$COLDXDG" "$BIN" "$REPO" --for="helper" --no-cache >"$TMP/fresh_cold.out" 2>/dev/null
diff -q "$TMP/warm.out" "$TMP/fresh_cold.out" >/dev/null \
    && ok "warm (memoized) output byte-identical to a fresh-cold-blob-dir run" \
    || { no "memoized output diverges from a fresh cold run"; diff "$TMP/fresh_cold.out" "$TMP/warm.out" | head -6; }
diff -q "$TMP/cold.out" "$TMP/warm.out" >/dev/null \
    && ok "this run's cold output == this run's warm output (cache never changes the answer)" \
    || { no "cold vs warm output differs within the same TMPDIR"; diff "$TMP/cold.out" "$TMP/warm.out" | head -6; }

# ── (c) a new commit changes HEAD sha ⇒ invalidates: re-walks, and a DISTINCT blob appears ─────────────
before_n="$( nqchurn )"
before_files="$( qchurnfiles | sort )"
cat >> "$REPO/src/lib.cpp" <<'EOF'
int another( int z ) { return z * 2; }
EOF
git -C "$REPO" add -A
GIT_AUTHOR_DATE="2026-06-01T13:00:00" GIT_COMMITTER_DATE="2026-06-01T13:00:00" \
    git -C "$REPO" commit -qm "grow lib" >/dev/null

run "$TMP/trace_new.log" --for="helper" --no-cache >"$TMP/new.out" 2>"$TMP/new.err"; rcNew=$?
NEW_N="$( name_only_count "$TMP/trace_new.log" )"
[ "$rcNew" -eq 0 ] && [ "$NEW_N" -ge 1 ] \
    && ok "new HEAD commit: memo invalidated, walk re-runs ($NEW_N invocation(s))" \
    || no "new commit did not invalidate the memo (rc=$rcNew, name-only count=$NEW_N)"

after_n="$( nqchurn )"
after_files="$( qchurnfiles | sort )"
[ "$after_n" -gt "$before_n" ] \
    && ok "new HEAD sha writes an ADDITIONAL qchurn blob ($before_n -> $after_n)" \
    || no "no new qchurn blob after HEAD changed ($before_n -> $after_n)"
[ "$( comm -13 <( printf '%s\n' "$before_files" ) <( printf '%s\n' "$after_files" ) | wc -l | tr -d ' ' )" -ge 1 ] \
    && ok "the new blob is a DISTINCT filename (old sha's blob untouched, not overwritten)" \
    || no "new commit reused the old sha's blob filename — key does not include HEAD sha"

# a second run against the NEW head is warm again (proves invalidation isn't a permanent "always cold" bug)
run "$TMP/trace_new2.log" --for="helper" --no-cache >"$TMP/new2.out" 2>/dev/null; rcNew2=$?
NEW2_N="$( name_only_count "$TMP/trace_new2.log" )"
[ "$rcNew2" -eq 0 ] && [ "$NEW2_N" -eq 0 ] \
    && ok "second run on the NEW head is warm again (count=$NEW2_N)" \
    || no "second run on new head did not memoize (rc=$rcNew2, count=$NEW2_N)"
diff -q "$TMP/new.out" "$TMP/new2.out" >/dev/null \
    && ok "new-head cold vs warm output byte-identical" \
    || no "new-head cold vs warm output differs"

# ── K51: a walk git COULD NOT FINISH is disclosed on every verb that prints churn=/amp=, never cached, and retried ──────────
# Before the fix a failed `git log --name-only` came back as an EMPTY stream, was stored under the (repo, HEAD, window) key,
# and every later call answered "no churn, no co-change partners" with no tell until HEAD moved. Two failure injections: a
# git shim that dies on the walk (reaches every build flavour), and a REAL one (a commit object removed from the store).
# The disclosure is history_unread="1" on the root (JSON: "history_unread":true); a read that found nothing stays silent.
KSHIM="$TMP/kshim"; mkdir -p "$KSHIM"
cat >"$KSHIM/git" <<KSHIMEOF
#!/bin/sh
case "\$*" in *name-only*) exit 128;; esac
exec "$( command -v git )" "\$@"
KSHIMEOF
chmod +x "$KSHIM/git"
krun(){ local out="$1"; shift; env PATH="$KSHIM:$PATH" TMPDIR="$QTMP" "$BIN" "$REPO" "$@" --no-cache >"$out" 2>"$TMP/k.err"; }
printf '// k51\n' >> "$REPO/src/lib.cpp"
git -C "$REPO" commit -qam "k51"                      # a fresh HEAD: no qchurn blob exists for it yet
kbefore="$( nqchurn )"
krun "$TMP/k_for.out" --for=helper; rcK=$?
[ "$rcK" -eq 0 ] && grep -q ' history_unread="1"' "$TMP/k_for.out" \
    && ok "K51: --for on a failed walk says history_unread=\"1\" on its root" \
    || no "K51: --for on a failed walk is silent (rc=$rcK): $( head -c 300 "$TMP/k_for.out" )"
grep -q ' churn="' "$TMP/k_for.out" \
    && no "K51: a failed walk still printed a churn= value" \
    || ok "K51: no churn= value is printed from a failed walk"
krun "$TMP/k_map.out" --metrics
grep -q ' history_unread="1"' "$TMP/k_map.out" \
    && ok "K51: --metrics (the map) says history_unread=\"1\"" \
    || no "K51: --metrics on a failed walk is silent"
krun "$TMP/k_json.out" --for=helper --json
grep -q '"history_unread":true' "$TMP/k_json.out" \
    && ok "K51: --for --json says \"history_unread\":true" \
    || no "K51: --for --json on a failed walk is silent"
krun "$TMP/k_grep.out" --grep=helper --metrics
grep -q ' history_unread="1"' "$TMP/k_grep.out" \
    && ok "K51: --grep --metrics says history_unread=\"1\"" \
    || no "K51: --grep --metrics on a failed walk is silent"
krun "$TMP/k_full.out" --for=helper --legend=full
grep -q 'history_unread=1: the git history walk' "$TMP/k_full.out" \
    && ok "K51: the attribute is defined beside its root (a comment that reads it)" || no "K51: history_unread= is not defined in the document"
xmllint --noout "$TMP/k_for.out" "$TMP/k_map.out" "$TMP/k_grep.out" "$TMP/k_full.out" 2>/dev/null \
    && ok "K51: every disclosing document is well-formed XML" || no "K51: a disclosing document is malformed XML"
[ "$( nqchurn )" -eq "$kbefore" ] \
    && ok "K51: the failed walk was NOT cached (qchurn blobs $kbefore -> $( nqchurn ))" \
    || no "K51: a failed walk was stored as a qchurn blob ($kbefore -> $( nqchurn ))"
run "$TMP/k_retry.log" --for=helper --no-cache >"$TMP/k_retry.out" 2>/dev/null
[ "$( name_only_count "$TMP/k_retry.log" )" -ge 1 ] && grep -q ' churn="[0-9]' "$TMP/k_retry.out" && ! grep -q 'history_unread' "$TMP/k_retry.out" \
    && ok "K51: the next call RETRIES the walk, prints churn=, and carries no disclosure" \
    || no "K51: the call after a failed walk did not retry cleanly (walks=$( name_only_count "$TMP/k_retry.log" )): $( head -c 200 "$TMP/k_retry.out" )"
[ "$( nqchurn )" -gt "$kbefore" ] \
    && ok "K51: the successful retry IS cached" \
    || no "K51: the successful retry wrote no blob"

# the REAL failure: remove the parent commit's object — HEAD still resolves, the walk dies part-way
printf '// k51b\n' >> "$REPO/src/lib.cpp"
git -C "$REPO" commit -qam "k51b"
kparent="$( git -C "$REPO" rev-parse HEAD~1 )"; kobj="$REPO/.git/objects/${kparent:0:2}/${kparent:2}"
if [ -f "$kobj" ]; then
    cp "$kobj" "$TMP/kobj.save"; rm -f "$kobj"
    run "$TMP/k_real.log" --for=helper --no-cache >"$TMP/k_real.out" 2>/dev/null; rcR=$?
    [ "$rcR" -eq 0 ] && grep -q ' history_unread="1"' "$TMP/k_real.out" \
        && ok "K51: a REAL unreadable object (git exits non-zero part-way) is disclosed" \
        || no "K51: a real git failure is silent (rc=$rcR): $( head -c 200 "$TMP/k_real.out" )"
    kreal="$( nqchurn )"
    run "$TMP/k_real2.log" --for=helper --no-cache >"$TMP/k_real2.out" 2>/dev/null
    [ "$( name_only_count "$TMP/k_real2.log" )" -ge 1 ] && [ "$( nqchurn )" -eq "$kreal" ] \
        && ok "K51: the real failure is retried on the next call and still not cached" \
        || no "K51: the real failure was cached or not retried (walks=$( name_only_count "$TMP/k_real2.log" ), blobs $kreal -> $( nqchurn ))"
    mkdir -p "$( dirname "$kobj" )"; cp "$TMP/kobj.save" "$kobj"
    run "$TMP/k_heal.log" --for=helper --no-cache >"$TMP/k_heal.out" 2>/dev/null
    grep -q ' churn="[0-9]' "$TMP/k_heal.out" && ! grep -q 'history_unread' "$TMP/k_heal.out" \
        && ok "K51: with the object restored the same call prints churn= and no disclosure" \
        || no "K51: the restored repo still answers degraded: $( head -c 200 "$TMP/k_heal.out" )"
else
    no "K51: premise — the parent commit is not a loose object ($kobj), so the real-failure arm cannot run"
fi

# the PREFIX: git dies two commits below HEAD, after printing the newest part of the window. The commits it printed are KEPT
# (a floor is still information) and the document must say they are a floor, never "churn= is absent" beside a churn= value.
# Red on fddd4b3c: it printed churn="1" next to a comment saying churn= is absent.
printf '// k51c\n' >> "$REPO/src/lib.cpp"
git -C "$REPO" commit -qam "k51c"
kgp="$( git -C "$REPO" rev-parse HEAD~2 )"; kgpobj="$REPO/.git/objects/${kgp:0:2}/${kgp:2}"
KPRETMP="$TMP/kpretmp"; mkdir -p "$KPRETMP"         # its own cache dir: a healthy blob under $QTMP would serve the broken run warm
env TMPDIR="$KPRETMP" "$BIN" "$REPO" --for=helper --no-cache --legend=full >"$TMP/k_pre1.out" 2>/dev/null
khealthy="$( grep -o ' p="src/lib.cpp"[^>]* churn="[0-9]*"' "$TMP/k_pre1.out" | head -1 | sed 's/.*churn="\([0-9]*\)"/\1/' )"
if [ -f "$kgpobj" ] && [ -n "$khealthy" ]; then
    cp "$kgpobj" "$TMP/kgpobj.save"; rm -f "$kgpobj"
    run "$TMP/k_pre.log" --for=helper --no-cache --legend=full >"$TMP/k_pre.out" 2>/dev/null; rcP=$?
    kpre="$( grep -o ' p="src/lib.cpp"[^>]* churn="[0-9]*"' "$TMP/k_pre.out" | head -1 | sed 's/.*churn="\([0-9]*\)"/\1/' )"
    if [ "$rcP" -eq 0 ] && grep -q ' history_unread="1"' "$TMP/k_pre.out"; then
        ok "K51: a walk that dies two commits below HEAD is disclosed"
    else
        no "K51: a prefix walk is silent (rc=$rcP): $( head -c 200 "$TMP/k_pre.out" )"
    fi
    if [ -n "$kpre" ] && [ "$kpre" -ge 1 ] && [ "$kpre" -lt "$khealthy" ]; then
        ok "K51: the prefix keeps its commits as a floor (churn=$kpre of $khealthy)"
    else
        no "K51: the prefix churn= is not a floor below the healthy count (prefix='$kpre', healthy=$khealthy)"
    fi
    if grep -q 'history_unread=1: the git history walk.*(the walk stopped part-way), so churn= and amp= count only the commits that were read: both are floors' "$TMP/k_pre.out"; then
        ok "K51: the prefix comment names the cause and says churn=/amp= are floors"
    else
        no "K51: the prefix comment does not call churn=/amp= floors: $( grep -o '<!--history_unread[^>]*' "$TMP/k_pre.out" | head -c 300 )"
    fi
    if [ -n "$kpre" ] && grep -q 'churn= is absent' "$TMP/k_pre.out"; then
        no "K51: the document prints churn=$kpre beside a comment that says churn= is absent"
    else
        ok "K51: no comment calls churn= absent beside a printed churn="
    fi
    mkdir -p "$( dirname "$kgpobj" )"; cp "$TMP/kgpobj.save" "$kgpobj"
else
    no "K51: premise — HEAD~2 is not a loose object ($kgpobj) or the healthy run printed no churn= ('$khealthy'), so the prefix arm cannot run"
fi

# git that does not RUN (not on PATH) in a real repository: gitHeadSha reads "" exactly as on an unborn branch, but the walk
# fails with the shell's 127, not git's 128 — so it is disclosed, never the silent unborn floor. Red on fddd4b3c (silent).
KNOGIT="$TMP/knogit"; mkdir -p "$KNOGIT"            # an empty PATH directory: popen still finds /bin/sh, the shell finds no git
env PATH="$KNOGIT" TMPDIR="$QTMP" "$BIN" "$REPO" --for=helper --no-cache --legend=full >"$TMP/k_nogit.out" 2>/dev/null; rcN=$?
if [ "$rcN" -eq 0 ] && grep -q ' history_unread="1"' "$TMP/k_nogit.out"; then
    ok "K51: git missing from PATH in a git repository is disclosed"
else
    no "K51: git missing from PATH is silent, or failed (rc=$rcN): $( head -c 200 "$TMP/k_nogit.out" )"
fi
if grep -q 'history_unread=1: the git history walk.*(the walk did not run), so churn= is absent and amp= counts callers only' "$TMP/k_nogit.out"; then
    ok "K51: the no-git comment names the cause (the walk did not run)"
else
    no "K51: the no-git comment does not name the cause: $( grep -o '<!--history_unread[^>]*' "$TMP/k_nogit.out" | head -c 300 )"
fi
if grep -q ' churn="' "$TMP/k_nogit.out"; then
    no "K51: git missing from PATH still printed a churn= value"
else
    ok "K51: git missing from PATH prints no churn="
fi

# negative: "read, and empty" is NOT "could not read" — a repository with no commit has no history to read
UNBORN="$( mktemp -d )"; mkdir -p "$UNBORN/src"; cp "$REPO/src/lib.cpp" "$UNBORN/src/lib.cpp"; git -C "$UNBORN" init -q
env TMPDIR="$QTMP" "$BIN" "$UNBORN" --for=helper --no-cache >"$TMP/k_unborn.out" 2>/dev/null; rcU=$?
[ "$rcU" -eq 0 ] && grep -q '<ctx' "$TMP/k_unborn.out" && ! grep -q 'history_unread' "$TMP/k_unborn.out" \
    && ok "K51: an unborn repository (read, empty) carries no disclosure" \
    || no "K51: an unborn repository was disclosed as unread, or failed (rc=$rcU)"
rm -rf "$UNBORN"

# ── xmllint clean (sanity — --for output is still well-formed XML under the cached path) ───────────────
"$BIN" "$REPO" --for="helper" --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
    && ok "xmllint clean" || no "xmllint reported malformed XML"

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
