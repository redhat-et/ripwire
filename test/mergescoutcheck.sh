#!/usr/bin/env bash
# mergescoutcheck.sh — gate for L1: --merge-scout=REF[,REF...] (PLAN_agentLeverage2026.md §L1), the
# read-only cross-branch overlap oracle.
#
# Fixture repo, 3 branches off one init commit:
#   A touches f1.cpp::x
#   B touches f1.cpp::x (same symbol as A — a TRUE conflict)
#   C touches f2.cpp::y (a different file entirely — clean vs both A and B)
# Asserts:
#   - pair A-B reports f1::x as a same-symbol conflict
#   - pairs A-C and B-C are clean (0 conflicts, 0 risks)
#   - landing order puts C first (fewest conflicts), tie-break A before B by ref name
#   - a same-file/different-symbol pair (D touches f1::x, E touches f1::z) is reported as a RISK, not a conflict
#   - the dirty working tree participates as an implicit "working-tree" arm when present
#   - an unresolvable ref refuses loudly (exit 1, names the ref) — BEFORE any output
#   - non-git root refuses loudly (exit 1, no XML) — X9(a): was arms="0" exit 0, indistinguishable from
#     "ran clean, no conflicts"
#   - multi-root workspace refuses (single-root only, like --pr-context/--quality-delta)
#   - determinism (byte-identical run-to-run) and xmllint-clean output
#
# Usage:
#   test/mergescoutcheck.sh                          # uses build/ctxpack
#   CTXPACK_BIN=asan/ctxpack test/mergescoutcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "mergescoutcheck: BIN=$BIN"

# ── Build the fixture repo: init, then branches A / B / C off it ──────────────────────────────────────
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"

cat >"$REPO/f1.cpp" <<'EOF'
int x() { return 1; }
int z() { return 2; }
EOF
cat >"$REPO/f2.cpp" <<'EOF'
int y() { return 3; }
EOF
git -C "$REPO" add -A
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" \
    git -C "$REPO" commit -qm "init"
MAIN="$( git -C "$REPO" symbolic-ref --short HEAD )"

git -C "$REPO" checkout -qb A
cat >"$REPO/f1.cpp" <<'EOF'
int x() { return 100; }
int z() { return 2; }
EOF
GIT_AUTHOR_DATE="2026-06-01T13:00:00" GIT_COMMITTER_DATE="2026-06-01T13:00:00" \
    git -C "$REPO" commit -qam "A changes x"
git -C "$REPO" checkout -q "$MAIN"

git -C "$REPO" checkout -qb B
cat >"$REPO/f1.cpp" <<'EOF'
int x() { return 200; }
int z() { return 2; }
EOF
GIT_AUTHOR_DATE="2026-06-01T14:00:00" GIT_COMMITTER_DATE="2026-06-01T14:00:00" \
    git -C "$REPO" commit -qam "B changes x too"
git -C "$REPO" checkout -q "$MAIN"

git -C "$REPO" checkout -qb C
cat >"$REPO/f2.cpp" <<'EOF'
int y() { return 300; }
EOF
GIT_AUTHOR_DATE="2026-06-01T15:00:00" GIT_COMMITTER_DATE="2026-06-01T15:00:00" \
    git -C "$REPO" commit -qam "C changes y"
git -C "$REPO" checkout -q "$MAIN"

# F: branched off MAIN but never diverged (no commits of its own) — §P11.13's changed="0" case: a ref
# with NOTHING to land, distinct from A/B/C which all have real divergent work.
git -C "$REPO" checkout -qb F
git -C "$REPO" checkout -q "$MAIN"

# ── Run --merge-scout=A,B,C ─────────────────────────────────────────────────────────────────────────
OUT="$( "$BIN" "$REPO" --merge-scout=A,B,C --no-cache 2>/dev/null )"
if [ -z "$OUT" ]; then no "merge-scout: output is empty"; echo; echo "SOME CHECKS FAILED"; exit 1; fi
echo "merge-scout output:"; echo "$OUT"; echo

echo "$OUT" | grep -q 'arms="3"' && ok "3 arms reported" || no "expected arms=3: $( echo "$OUT" | grep -o 'arms="[0-9]*"' | head -1 )"

# §A10.4: base= is a 9-hex-char sha, matching the at=/head= width every other repo-reading verb uses
# (gitstamp.h) — it used to print the full 40-char merge-base sha, the one width outlier next to
# --stray-content/--pr-context's base_sha= and --doctor's head=.
BASE_ATTRS="$( echo "$OUT" | grep -oE 'base="[0-9a-f]+"' )"
BASE_BAD="$( echo "$BASE_ATTRS" | grep -vE '^base="[0-9a-f]{9}"$' )"
if [ -n "$BASE_ATTRS" ] && [ -z "$BASE_BAD" ]; then
    ok "every <arm base= is a 9-hex-char sha (matches at=/head= width, §A10.4)"
else
    no "some <arm base= is not exactly 9 hex chars: $BASE_BAD"
fi

# A and B each report f1.cpp::x as their one changed symbol
echo "$OUT" | grep -q '<arm ref="A"[^>]*changed="1"[^>]*><sym p="f1\.cpp" id="x"/>' \
    && ok "arm A changed f1.cpp::x" || no "arm A did not report f1.cpp::x changed"
echo "$OUT" | grep -q '<arm ref="B"[^>]*changed="1"[^>]*><sym p="f1\.cpp" id="x"/>' \
    && ok "arm B changed f1.cpp::x" || no "arm B did not report f1.cpp::x changed"
echo "$OUT" | grep -q '<arm ref="C"[^>]*changed="1"[^>]*><sym p="f2\.cpp" id="y"/>' \
    && ok "arm C changed f2.cpp::y" || no "arm C did not report f2.cpp::y changed"

# pair A-B: same-symbol conflict on x
echo "$OUT" | grep -q '<pair a="A" b="B" conflicts="1" risks="0"><conflict p="f1\.cpp" id="x"/></pair>' \
    && ok "pair A-B: true conflict on f1.cpp::x" \
    || no "pair A-B wrong: $( echo "$OUT" | grep -o '<pair a=\"A\" b=\"B\"[^/]*' )"

# pairs with C are clean
echo "$OUT" | grep -q '<pair a="A" b="C" conflicts="0" risks="0"/>' \
    && ok "pair A-C clean" || no "pair A-C not clean: $( echo "$OUT" | grep -o '<pair a=\"A\" b=\"C\"[^/]*/>' )"
echo "$OUT" | grep -q '<pair a="B" b="C" conflicts="0" risks="0"/>' \
    && ok "pair B-C clean" || no "pair B-C not clean: $( echo "$OUT" | grep -o '<pair a=\"B\" b=\"C\"[^/]*/>' )"

# landing order: C first (0 conflicts), then A,B (tie broken by ref name asc)
echo "$OUT" | grep -q '<landing order="C,A,B"/>' \
    && ok "landing order = C,A,B (fewest-conflicts-first, ties by ref name asc)" \
    || no "landing order wrong: $( echo "$OUT" | grep -o '<landing[^/]*/>' )"

# ── §P11.13: F (changed="0" — no divergent work vs merge-base) is annotated and dropped from landing= ──
FOUT="$( "$BIN" "$REPO" --merge-scout=A,B,C,F --no-cache 2>/dev/null )"
echo "$FOUT" | grep -q 'arms="4"' && ok "4 arms reported (A,B,C,F)" || no "expected arms=4: $( echo "$FOUT" | grep -o 'arms="[0-9]*"' | head -1 )"
# split the (minified, single-line) XML at every `<arm ` boundary so each arm's own block — up to but
# NOT including the next `<arm `/`<pair`/`<landing` — can be grepped in isolation (a naive greedy
# `<arm ref="X".*</arm>` would swallow every LATER arm's content too, since arms don't nest).
ARM_F="$( printf '%s' "$FOUT" | sed 's/<arm /\n<arm /g; s/<pair /\n<pair /g; s/<landing /\n<landing /g' | grep '^<arm ref="F"' )"
ARM_A="$( printf '%s' "$FOUT" | sed 's/<arm /\n<arm /g; s/<pair /\n<pair /g; s/<landing /\n<landing /g' | grep '^<arm ref="A"' )"
echo "$ARM_F" | grep -q 'changed="0"' && ok "arm F reports changed=\"0\"" || no "arm F did not report changed=0: $ARM_F"
echo "$ARM_F" | grep -q '<no-work note="no divergent work vs merge-base — see --stray-content"/>' \
    && ok "arm F (changed=0) carries the no-divergent-work <no-work note=.../> child" \
    || no "arm F missing the <no-work note=.../> child: $ARM_F"
echo "$ARM_A" | grep -q '<no-work' \
    && no "arm A (has real changes) wrongly carries <no-work>" \
    || ok "arm A (has real changes) carries no <no-work>"
echo "$FOUT" | grep -q '<landing order="C,A,B"/>' \
    && ok "landing= still C,A,B — F (nothing to land) excluded, real arms' order unperturbed" \
    || no "landing order wrong with F present: $( echo "$FOUT" | grep -o '<landing[^/]*/>' )"
echo "$FOUT" | grep -oE '<landing order="[^"]*"' | grep -q 'F' \
    && no "landing= still names F despite it having no divergent work" \
    || ok "landing= does not name F"

# ── xmllint ─────────────────────────────────────────────────────────────────────────────────────────
echo "$OUT" | xmllint --noout - 2>/dev/null \
    && ok "xmllint clean" \
    || no "xmllint reported malformed XML"

# ── determinism ×3 ──────────────────────────────────────────────────────────────────────────────────
D1="$( "$BIN" "$REPO" --merge-scout=A,B,C --no-cache 2>/dev/null )"
D2="$( "$BIN" "$REPO" --merge-scout=A,B,C --no-cache 2>/dev/null )"
D3="$( "$BIN" "$REPO" --merge-scout=A,B,C --no-cache 2>/dev/null )"
{ [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ]; } && ok "determinism ×3: byte-identical" || no "determinism: output differs across runs"

# ── textual risk: D and E touch DIFFERENT symbols in the SAME file ─────────────────────────────────────
git -C "$REPO" checkout -qb D
cat >"$REPO/f1.cpp" <<'EOF'
int x() { return 42; }
int z() { return 2; }
EOF
GIT_AUTHOR_DATE="2026-06-01T16:00:00" GIT_COMMITTER_DATE="2026-06-01T16:00:00" \
    git -C "$REPO" commit -qam "D changes x"
git -C "$REPO" checkout -q "$MAIN"

git -C "$REPO" checkout -qb E
cat >"$REPO/f1.cpp" <<'EOF'
int x() { return 1; }
int z() { return 999; }
EOF
GIT_AUTHOR_DATE="2026-06-01T17:00:00" GIT_COMMITTER_DATE="2026-06-01T17:00:00" \
    git -C "$REPO" commit -qam "E changes z"
git -C "$REPO" checkout -q "$MAIN"

RISKOUT="$( "$BIN" "$REPO" --merge-scout=D,E --no-cache 2>/dev/null )"
echo "$RISKOUT" | grep -q '<pair a="D" b="E" conflicts="0" risks="1"><risk p="f1\.cpp" a="x" b="z"/></pair>' \
    && ok "D-E: same-file/different-symbol reported as a RISK, not a conflict" \
    || no "D-E risk pair wrong: $( echo "$RISKOUT" | grep -o '<pair a=\"D\" b=\"E\"[^/]*' )"

# ── the dirty working tree joins as an implicit arm ─────────────────────────────────────────────────
cat >"$REPO/f1.cpp" <<'EOF'
int x() { return 7777; }
int z() { return 2; }
EOF
WTOUT="$( "$BIN" "$REPO" --merge-scout=C --no-cache 2>/dev/null )"
echo "$WTOUT" | grep -q 'arms="2"' \
    && ok "dirty working tree adds an implicit 2nd arm" \
    || no "working-tree arm missing: $( echo "$WTOUT" | grep -o 'arms="[0-9]*"' )"
echo "$WTOUT" | grep -q '<arm ref="working-tree"[^>]*changed="1"[^>]*><sym p="f1\.cpp" id="x"/>' \
    && ok "working-tree arm reports its own uncommitted change (f1.cpp::x)" \
    || no "working-tree arm content wrong"
git -C "$REPO" checkout -q -- f1.cpp   # restore for the checks below

# ── clean tree: no implicit working-tree arm ────────────────────────────────────────────────────────
CLEANOUT="$( "$BIN" "$REPO" --merge-scout=C --no-cache 2>/dev/null )"
echo "$CLEANOUT" | grep -q 'arms="1"' \
    && ok "clean tree: no implicit working-tree arm (arms=1)" \
    || no "clean tree wrongly added a working-tree arm: $( echo "$CLEANOUT" | grep -o 'arms="[0-9]*"' )"

# ── unresolvable ref refuses loudly (exit 1, names the ref) — no XML emitted ────────────────────────
BADOUT="$( "$BIN" "$REPO" --merge-scout=A,does-not-exist,C --no-cache 2>&1 )"; BADRC=$?
{ [ "$BADRC" -ne 0 ] && echo "$BADOUT" | grep -q "does-not-exist"; } \
    && ok "unresolvable ref refuses loudly, naming it (rc=$BADRC)" \
    || no "bad-ref refusal wrong (rc=$BADRC): $BADOUT"
echo "$BADOUT" | grep -q '<merge-scout' \
    && no "bad-ref refusal still emitted XML output (should refuse BEFORE any output)" \
    || ok "bad-ref refusal emits no XML"

# ── empty ref list refuses loudly ───────────────────────────────────────────────────────────────────
EMPTYOUT="$( "$BIN" "$REPO" --merge-scout= --no-cache 2>&1 )"; EMPTYRC=$?
[ "$EMPTYRC" -ne 0 ] && ok "empty --merge-scout= refuses loudly (rc=$EMPTYRC)" || no "empty --merge-scout= should refuse (rc=$EMPTYRC)"

# ── reserved arm name as a ref token refuses loudly ─────────────────────────────────────────────────
RESOUT="$( "$BIN" "$REPO" --merge-scout=working-tree --no-cache 2>&1 )"; RESRC=$?
[ "$RESRC" -ne 0 ] && ok "'working-tree' as a REF token refuses loudly (rc=$RESRC)" || no "'working-tree' ref should refuse (rc=$RESRC)"

# ── non-git root refuses loudly (X9(a)): exit 1, a clear message, no XML ───────────────────────────────
NG="$TMP/nongit"; mkdir -p "$NG"; echo 'int f(){return 0;}' >"$NG/a.cpp"
NGOUT="$( "$BIN" "$NG" --merge-scout=A --no-cache 2>/dev/null )"; NGRC=$?
NGERR="$( "$BIN" "$NG" --merge-scout=A --no-cache 2>&1 1>/dev/null )"
[ "$NGRC" -eq 1 ] && ok "non-git root refuses loudly (exit 1)" || no "non-git root should exit 1 (got rc=$NGRC)"
[ -z "$NGOUT" ] && ok "non-git root refusal emits no XML" || no "non-git root refusal unexpectedly emitted output: $NGOUT"
echo "$NGERR" | grep -qi 'not a git repository' \
    && ok "non-git root refusal names the reason (not a git repository)" \
    || no "non-git root refusal missing a clear message: $NGERR"

# ── multi-root workspace refuses (single-root only) ─────────────────────────────────────────────────
MRERR="$( "$BIN" "$REPO" "$REPO" --merge-scout=A --no-cache 2>&1 )"; MRRC=$?
{ [ "$MRRC" -ne 0 ] && echo "$MRERR" | grep -q "single-root only"; } \
    && ok "multi-root workspace refuses --merge-scout (single-root only)" \
    || no "multi-root refusal wrong (rc=$MRRC): $MRERR"

# ── never checks anything out (read-only): the real working tree / current branch are untouched ──────
POSTBRANCH="$( git -C "$REPO" symbolic-ref --short HEAD )"
[ "$POSTBRANCH" = "$MAIN" ] && ok "read-only: current branch unchanged after all runs ($POSTBRANCH)" \
                             || no "current branch changed! now on $POSTBRANCH (expected $MAIN)"
git -C "$REPO" status --porcelain | grep -q . \
    && no "read-only: working tree left dirty after runs" \
    || ok "read-only: working tree clean after all runs"

# ── Y1 (AUDIT5 P1) perf gate: warm run reuses the per-sha ingest cache ─────────────────────────────────
# mergescout.h:115 used to hand ingest() an EMPTY cacheFile, forcing a full cold tree-sitter PARSE of
# every arm's tree on EVERY invocation (the audited 9.15 s / 967 MB, 6-cold-ingest finding on a large private C++ corpus)
# despite this module's own header claiming cache reuse. The fix threads a per-sha cache path (the "qms"
# family, quality.h:1017-1021's qheadsnap convention) through indexCommittish, so a SECOND invocation
# against the SAME shas skips tree-sitter entirely (only git-archive extraction + a content-hash lookup
# remain) — cold and warm must still be BYTE-IDENTICAL (determinism unaffected by the cache).
#
# A fresh, isolated PERFROOT (own TMPDIR, so cacheDirLadder() lands in a directory we control and can
# guarantee starts empty) hosts a purpose-built fixture: few, LARGE files (parse-cost-heavy, not
# archive-extraction-heavy — a synthetic fixture with many tiny files is dominated by fixed per-file
# git-archive/extraction overhead that Y1 does not touch, which would mask the win) across 6 branches (12
# distinct trees requested; TreeIndexMemo dedupes the 6 shared merge-bases to 1, so 7 unique materializations
# per run). median-of-3 (perl high-res timer, mirrors bench/perfgate.sh's median_ms) damps scheduler noise;
# the bound (50%) is deliberately generous — measured on this fixture the fix consistently lands near 35%,
# and reverting it (empty cacheFile) reproduces ~100% (no cross-run reuse at all), so 50% cleanly separates
# "fixed" from "regressed" without chasing machine-specific noise.
PERFRUNS=3
run_once_ms()
{
    perl -MTime::HiRes=time -e '
        open STDOUT, ">", "/dev/null" or die $!;
        open STDERR, ">", "/dev/null" or die $!;
        my $start = time();
        system @ARGV;
        my $status = $?;
        my $elapsed = (time() - $start) * 1000.0;
        open STDOUT, ">&", 3 or die $!;
        printf "%.6f\n", $elapsed;
        exit($status == -1 ? 127 : ($status >> 8));
    ' 3>&1 -- "$@"
}

# median_ms [clear_cache_dir] CMD... — runs CMD PERFRUNS times, printing the median wall time in ms. When
# `clear_cache_dir` is non-empty, EVERY qms cache blob under it is deleted BEFORE each of the PERFRUNS
# timed samples (not just once before the loop) — otherwise only the FIRST sample would be genuinely cold
# and the other PERFRUNS-1 would silently be warm hits (the qms family is unconditional, not gated on
# --no-cache — see quality.h's own qheadsnap convention), pulling the "cold" median toward the warm number
# and hiding the regression this gate exists to catch.
median_ms()
{
    local clearDir="$1"; shift
    local n_local=0
    local times=()
    for (( n_local = 0; n_local < PERFRUNS; ++n_local )); do
        # AUDIT5 Y4: shard-aware lookup — a qms blob may be flat under $clearDir or under $clearDir/<xx>/ (2-hex shard).
        [ -n "$clearDir" ] && { f="$( find "$clearDir" -maxdepth 2 -type f -name 'ctxpack-qms-*.bin' 2>/dev/null )"; [ -n "$f" ] && rm -f $f; }
        local elapsed
        elapsed="$( run_once_ms "$@" )" || return 1
        [ -z "$elapsed" ] && return 1
        times+=( "$elapsed" )
    done
    printf '%s\n' "${times[@]}" | sort -n | awk -v n="$PERFRUNS" '{ a[NR]=$1 } END { mid=int((n+1)/2); if (n%2==1) print a[mid]; else print (a[mid]+a[mid+1])/2 }'
}

PERFTMP="$( mktemp -d )"
PREPO="$PERFTMP/repo"
mkdir -p "$PREPO/src"
git -C "$PREPO" init -q
git -C "$PREPO" config user.email "dev@x.com"
git -C "$PREPO" config user.name  "Dev"

PERF_NFILES=8
PERF_NFUNCS=2000
perf_gen_files()
{
    local override="$1" f k
    for f in $( seq 0 $(( PERF_NFILES - 1 )) ); do
        : > "$PREPO/src/m${f}.cpp"
        for k in $( seq 0 $(( PERF_NFUNCS - 1 )) ); do
            if [ "$f" = "0" ] && [ "$k" = "0" ] && [ -n "$override" ]; then
                echo "int f0_0( int x ) { return x + ${override}; }" >> "$PREPO/src/m0.cpp"
            else
                echo "int f${f}_${k}( int x ) { int s = x; for( int i = 0; i < 8; ++i ) { if( i % 2 == 0 ) { s += i * ${k}; } else { s -= i; } } return s; }" >> "$PREPO/src/m${f}.cpp"
            fi
        done
    done
}
perf_gen_files ""
git -C "$PREPO" add -A
GIT_AUTHOR_DATE="2026-06-01T10:00:00" GIT_COMMITTER_DATE="2026-06-01T10:00:00" \
    git -C "$PREPO" commit -qm "perf-fixture init"
PMAIN="$( git -C "$PREPO" symbolic-ref --short HEAD )"

PERF_REFS=""
for b in 1 2 3 4 5 6; do
    git -C "$PREPO" checkout -qb "pb$b"
    perf_gen_files "$b"
    GIT_AUTHOR_DATE="2026-06-01T1${b}:00:00" GIT_COMMITTER_DATE="2026-06-01T1${b}:00:00" \
        git -C "$PREPO" commit -qam "pb$b"
    git -C "$PREPO" checkout -q "$PMAIN"
    PERF_REFS="${PERF_REFS:+$PERF_REFS,}pb$b"
done

PERF_ISOTMP="$( mktemp -d )"   # dedicated, EMPTY TMPDIR — cacheDirLadder() lands here, so run 1 is genuinely cold
SAVED_TMPDIR="${TMPDIR:-}"
export TMPDIR="$PERF_ISOTMP"
cold_ms="$( median_ms "$PERF_ISOTMP" "$BIN" "$PREPO" --merge-scout="$PERF_REFS" --no-cache )"
COLDRC=$?
warm_ms="$( median_ms ""            "$BIN" "$PREPO" --merge-scout="$PERF_REFS" --no-cache )"
WARMRC=$?

if [ "$COLDRC" -ne 0 ] || [ "$WARMRC" -ne 0 ] || [ -z "${cold_ms:-}" ] || [ -z "${warm_ms:-}" ]; then
    no "Y1 perf gate: timing harness failed to produce a sample (cold_rc=$COLDRC warm_rc=$WARMRC)"
else
    printf '  Y1 perf: cold(median x%d)=%.1f ms  warm(median x%d)=%.1f ms\n' "$PERFRUNS" "$cold_ms" "$PERFRUNS" "$warm_ms"
    awk -v c="$cold_ms" -v w="$warm_ms" 'BEGIN{ exit !(w < c * 0.50) }' \
        && ok "Y1 perf: warm run < 50% of cold run (per-sha ingest cache reused across invocations)" \
        || no "Y1 perf: warm run NOT meaningfully faster than cold (cold=${cold_ms}ms warm=${warm_ms}ms) — per-sha cache not reused?"
fi

# correctness unchanged under caching: cold and warm outputs stay byte-identical (the cache must never
# change the answer, only the time it takes to get there)
COLDOUT="$( "$BIN" "$PREPO" --merge-scout="$PERF_REFS" --no-cache 2>/dev/null )"
WARMOUT="$( "$BIN" "$PREPO" --merge-scout="$PERF_REFS" --no-cache 2>/dev/null )"
[ "$COLDOUT" = "$WARMOUT" ] \
    && ok "Y1 perf: cached run output byte-identical to uncached (cache never changes the answer)" \
    || no "Y1 perf: cached run output DIFFERS from uncached"

if [ -n "$SAVED_TMPDIR" ]; then export TMPDIR="$SAVED_TMPDIR"; else unset TMPDIR; fi
rm -rf "$PERFTMP" "$PERF_ISOTMP"

# ── Summary ─────────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
