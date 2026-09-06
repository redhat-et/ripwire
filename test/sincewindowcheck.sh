#!/usr/bin/env bash
# sincewindowcheck.sh — gate for the --since EMPTY-WINDOW fix (BUG 2). When git IS available and history
# EXISTS but the --since=REV|DATE window simply matched NO commits, that is a legitimate EMPTY result, NOT a
# "git unavailable" error. This gate builds a synthetic repo with real history and asserts, for BOTH
# --hotspots and --cochange:
#   1  --since=<far-future-date>  → exit 0, honest empty result (commits="0" / ranked="0" or pairs="0"),
#      and NOT the "git unavailable" stderr error.
#   2  a genuine NON-repo dir     → STILL errors (exit non-zero) — the real git-unavailable case is unchanged.
#   3  the empty-window output is deterministic run-to-run and well-formed XML.
# Usage:  test/sincewindowcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/sincewindowcheck.sh
# Exits non-zero on any failure. Self-contained (own temp dirs). Does NOT edit test/regression.sh. Needs git.
set -u
BIN="${1:-${RIPWIRE_BIN:-./build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

REPO="$(mktemp -d)"; NR="$(mktemp -d)"; trap 'rm -rf "$REPO" "$NR"' EXIT

# ── real repo with real history: two commits, two source files ───────────────────────────────────────────────
cd "$REPO" || exit 1
git init -q; git config user.email x@y; git config user.name x
printf 'int a(int x){ if(x>0){return 1;} else {return 2;} }\n' > A.cpp; git add A.cpp; git commit -qm A1
printf 'int b(int x){ if(x>0){return 1;} else {return 2;} }\n' > B.cpp; git add B.cpp; git commit -qm B1

# a far-future --since so ZERO commits match (git is fine, history exists — the empty-window case)
FUTURE="2099-01-01"

# ── 1) --hotspots --since=<future>: exit 0 + honest zero, NOT the git-unavailable error ───────────────────────
hout="$("$BIN" "$REPO" --hotspots --since="$FUTURE" --no-cache 2>"$REPO/h.err")"; hrc=$?
if [ "$hrc" -eq 0 ]; then ok "--hotspots empty since-window exits 0"; else no "--hotspots empty since-window should exit 0 (got $hrc)"; fi
if grep -qi "git unavailable" "$REPO/h.err"; then
  no "--hotspots empty since-window wrongly printed 'git unavailable'"; echo "     stderr: $(cat "$REPO/h.err")"
else
  ok "--hotspots empty since-window did NOT print 'git unavailable'"
fi
if printf '%s' "$hout" | grep -q 'ranked="0"' && printf '%s' "$hout" | grep -q 'commits="0"'; then
  ok "--hotspots empty since-window reports ranked=\"0\" commits=\"0\""
else
  no "--hotspots empty since-window should report ranked=\"0\" commits=\"0\""; echo "     got: $hout"
fi
printf '%s' "$hout" | xmllint --noout - 2>/dev/null && ok "--hotspots empty-window output is well-formed XML" || no "--hotspots empty-window XML malformed"

# ── 1b) --cochange --since=<future>: exit 0 + honest zero, NOT the git-unavailable error ──────────────────────
cout="$("$BIN" "$REPO" --cochange --since="$FUTURE" --no-cache 2>"$REPO/c.err")"; crc=$?
if [ "$crc" -eq 0 ]; then ok "--cochange empty since-window exits 0"; else no "--cochange empty since-window should exit 0 (got $crc)"; fi
if grep -qi "git unavailable" "$REPO/c.err"; then
  no "--cochange empty since-window wrongly printed 'git unavailable'"; echo "     stderr: $(cat "$REPO/c.err")"
else
  ok "--cochange empty since-window did NOT print 'git unavailable'"
fi
if printf '%s' "$cout" | grep -q 'pairs="0"' && printf '%s' "$cout" | grep -q 'commits="0"'; then
  ok "--cochange empty since-window reports pairs=\"0\" commits=\"0\""
else
  no "--cochange empty since-window should report pairs=\"0\" commits=\"0\""; echo "     got: $cout"
fi
printf '%s' "$cout" | xmllint --noout - 2>/dev/null && ok "--cochange empty-window output is well-formed XML" || no "--cochange empty-window XML malformed"

# ── 2) a genuine non-repo dir STILL errors (exit non-zero) for both verbs ─────────────────────────────────────
printf 'int c(int x){ if(x){return 1;} return 0; }\n' > "$NR/C.cpp"
"$BIN" "$NR" --hotspots --no-cache >/dev/null 2>&1; nrh=$?
[ "$nrh" -ne 0 ] && ok "--hotspots on a genuine non-repo still errors (exit $nrh)" || no "--hotspots on a non-repo should exit non-zero"
"$BIN" "$NR" --cochange --no-cache >/dev/null 2>&1; nrc=$?
[ "$nrc" -ne 0 ] && ok "--cochange on a genuine non-repo still errors (exit $nrc)" || no "--cochange on a non-repo should exit non-zero"

# ── 3) determinism of the empty-window outputs ───────────────────────────────────────────────────────────────
h1="$("$BIN" "$REPO" --hotspots --since="$FUTURE" --no-cache 2>/dev/null)"
h2="$("$BIN" "$REPO" --hotspots --since="$FUTURE" --no-cache 2>/dev/null)"
[ "$h1" = "$h2" ] && ok "--hotspots empty-window deterministic" || no "--hotspots empty-window not deterministic"
p1="$("$BIN" "$REPO" --cochange --since="$FUTURE" --no-cache 2>/dev/null)"
p2="$("$BIN" "$REPO" --cochange --since="$FUTURE" --no-cache 2>/dev/null)"
[ "$p1" = "$p2" ] && ok "--cochange empty-window deterministic" || no "--cochange empty-window not deterministic"


# ── 4) THE DEFAULT WINDOW'S ANCHOR (F1/F2/F3, round C lane D) ────────────────────────────────────────────────
# Arms 1-3 above cover an EXPLICIT --since. This arm covers the window nobody asks for: the DEFAULT one.
# `git log --since="18 months ago"` resolves against the WALL CLOCK, so a repo whose newest commit predates
# that cutoff — every pinned corpus, every archived release, every eval checkout — reads as if it had no
# history at all. Measured on the head-to-head corpus (RocksDB @0e2801ac3, HEAD 2024-10-17): --cochange
# returned zero rows where gortex, walking the same history, mined 9,854 co-change edges. The default window
# therefore anchors on HEAD's own committer epoch; an EXPLICIT --since stays wall-clock-relative, because
# that one is the user's own choice (arms 1-3 keep proving it).
#
# The fixture is a real repo with real history, every commit BACKDATED past the widest default window (18mo),
# which is what makes it a test of the anchor and not of git.
OLD="$(mktemp -d)"; trap 'rm -rf "$REPO" "$NR" "$OLD"' EXIT
cd "$OLD" || exit 1
git init -q; git config user.email x@y; git config user.name x
mkdir -p db
printf '#pragma once\nstruct WalManager\n{\n    int purge( int n );\n    int archive( int n );\n};\n' > db/wal_manager.h
printf '#include "db/wal_manager.h"\nint WalManager::purge( int n ) { if( n > 0 ) { return n; } return 0; }\nint WalManager::archive( int n ) { return purge( n ) + 1; }\n' > db/wal_manager.cc
printf '#include "db/wal_manager.h"\nint applyVersion( int n ) { WalManager w; return w.archive( n ); }\n' > db/version_set.cc
_c(){ export GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1"; git add -A; git commit -qm "$2"; }
_c "2019-01-05T10:00:00 +0000" seed
_i=1
while [ "$_i" -le 5 ]; do
  printf '// touch %s\n' "$_i" >> db/wal_manager.cc
  printf '// touch %s\n' "$_i" >> db/version_set.cc
  _c "2019-0$(( _i + 1 ))-05T10:00:00 +0000" "pair $_i"
  _i=$(( _i + 1 ))
done
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE

# 4a) --cochange must MINE this history, not refuse it. The refusal was factually false: git is present and
#     six commits exist; only the wall-clock window was empty.
oc="$("$BIN" "$OLD" --cochange --no-cache 2>"$NR/oc.err")"; ocrc=$?
[ "$ocrc" -eq 0 ] && ok "--cochange default window mines a >18mo-old history (exit 0)" \
                  || { no "--cochange default window refused a real history (exit $ocrc)"; echo "     stderr: $(cat "$NR/oc.err")"; }
grep -qi "git unavailable" "$NR/oc.err" \
  && no "--cochange said 'git unavailable' on a repo WITH git and WITH history" \
  || ok "--cochange did not claim 'git unavailable' on a real history"
if printf '%s' "$oc" | grep -q 'pairs="[1-9]'; then ok "--cochange default window found co-change pairs in a >18mo-old history"
else no "--cochange default window found 0 pairs in a 6-commit history of co-edited files"; echo "     got: $(printf '%s' "$oc" | grep -o '<cochange[^>]*>')"; fi
# the per-file form carries commits= — the floor --situ has to propagate (4d).
ocf="$("$BIN" "$OLD" --cochange=db/wal_manager.cc --no-cache 2>/dev/null)"
if printf '%s' "$ocf" | grep -q 'commits="[1-9]'; then ok "--cochange=FILE reports a non-zero in-window commit count"
else no "--cochange=FILE mined 0 commits from a 6-commit history"; echo "     got: $(printf '%s' "$ocf" | grep -o '<cochange[^>]*>')"; fi
printf '%s' "$oc" | grep -q 'window="18mo@HEAD"' \
  && ok "--cochange discloses the anchor (window=\"18mo@HEAD\")" \
  || { no "--cochange must name the anchor that produced its window (want window=\"18mo@HEAD\")"; echo "     got: $(printf '%s' "$oc" | grep -o 'window="[^\"]*"' | head -1)"; }

# 4b) --hotspots: same window, same anchor, same refusal to invent a missing repo.
oh="$("$BIN" "$OLD" --hotspots --no-cache 2>"$NR/oh.err")"; ohrc=$?
[ "$ohrc" -eq 0 ] && ok "--hotspots default window ranks a >18mo-old history (exit 0)" \
                  || { no "--hotspots default window refused a real history (exit $ohrc)"; echo "     stderr: $(cat "$NR/oh.err")"; }
if printf '%s' "$oh" | grep -q 'ranked="[1-9]'; then ok "--hotspots default window ranked a file on >18mo-old churn"
else no "--hotspots default window ranked nothing from a 6-commit history"; echo "     got: $(printf '%s' "$oh" | grep -o '<hotspots[^>]*>')"; fi

# 4c) --rank-by=churn must find churn evidence, and its stamp must name the anchor.
orc_out="$("$BIN" "$OLD" --rank-by=churn --no-cache 2>"$NR/or.err")"
printf '%s' "$orc_out" | grep -q 'no churn evidence' \
  && { no "--rank-by=churn found no churn in a 6-commit history (window unanchored)"; echo "     $(printf '%s' "$orc_out" | grep -o 'window="[^\"]*"' | head -1)"; } \
  || ok "--rank-by=churn found churn evidence in a >18mo-old history"
printf '%s' "$orc_out" | grep -q 'window="12mo@HEAD"\|window="18mo@HEAD"' \
  && ok "--rank-by=churn discloses the anchor in window=" \
  || { no "--rank-by=churn must name the anchor in window="; echo "     got: $(printf '%s' "$orc_out" | grep -o 'window="[^\"]*"' | head -1)"; }

# 4d) F2 — --situ COMPOSES co-change and must carry its component's floor through. `(0)` plus
#     `(none, or no git history)` conflates "no partners found" with "the window could not look", which is
#     exactly what non-negotiable #3 forbids; --cochange on the same tree refuses loudly.
os="$("$BIN" "$OLD" --situ=db/wal_manager.cc --no-cache 2>/dev/null)"
printf '%s' "$os" | grep -q 'window=' \
  && ok "--situ propagates the co-change window= disclosure" \
  || { no "--situ drops the commits=/window= disclosure its own --cochange component emits"; echo "     got: $(printf '%s' "$os" | grep -A1 'co-change')"; }
printf '%s' "$os" | grep -q 'commits=' \
  && ok "--situ propagates the co-change commits= floor" \
  || no "--situ must state how many commits its co-change window saw"

# 4e) F3 — the named file's OWN header. A structural relationship ripwire already knows: db/wal_manager.cc
#     declares its symbols in db/wal_manager.h. It was absent from --situ's output entirely while a
#     222-file transitive list was ranked by dependent-symbol count above it.
printf '%s' "$os" | grep -q 'db/wal_manager.h' \
  && ok "--situ surfaces the named file's own header" \
  || { no "--situ=db/wal_manager.cc never names db/wal_manager.h"; echo "     got: $(printf '%s' "$os" | head -c 600)"; }

# 4e2) F3 NEGATIVE CONTROL — the majority guard must be LIVE, not decorative. Two large files that share
#      exactly one common free-function name are NOT a decl/def pair, and reporting them would make the row
#      above worthless. Same tree, so this is a control on the same run, not a different fixture.
cd "$OLD" || exit 1
mkdir -p noise
{ echo 'int shared_helper( int x ) { return x; }'; _k=1; while [ "$_k" -le 12 ]; do printf 'int an_%s( int x ) { return x + %s; }\n' "$_k" "$_k"; _k=$(( _k + 1 )); done; } > noise/a.cc
{ echo 'int shared_helper2( int x ) { return x; }'; echo 'int shared_helper( int x ) { return x + 99; }'; _k=1; while [ "$_k" -le 12 ]; do printf 'int bn_%s( int x ) { return x + %s; }\n' "$_k" "$_k"; _k=$(( _k + 1 )); done; } > noise/b.cc
_c "2019-07-05T10:00:00 +0000" noise
on="$("$BIN" "$OLD" --situ=noise/a.cc --no-cache 2>/dev/null)"
printf '%s' "$on" | grep -q 'noise/b.cc' \
  && { no "F3 guard is inert: two 13-symbol files sharing ONE name were reported as a decl/def pair"; echo "     got: $(printf '%s' "$on" | grep -A3 'decl/def')"; } \
  || ok "F3 guard rejects a one-name collision between two large files (the majority test is live)"

# The sharper control, and the one dogfooding actually needed: two TINY files that each DEFINE the same one
# function pass any majority test on shared names, and are still not a decl/def pair — nothing is declared in
# one and defined in the other. Every shell gate in test/ defines ok/no/fail, which is how the first version
# of this rule answered `--situ` with `test/w2verbscheck.sh (10 shared symbols)`.
mkdir -p twin
printf 'int only_one( int x ) { return x + 1; }\n' > twin/p.cc
printf 'int only_one( int x ) { return x + 2; }\n' > twin/q.cc
_c "2019-08-05T10:00:00 +0000" twin
tw="$("$BIN" "$OLD" --situ=twin/p.cc --no-cache 2>/dev/null)"
printf '%s' "$tw" | grep -q 'twin/q.cc' \
  && { no "F3 pairs two files that both DEFINE the same name — that is a shared name, not a decl/def pair"; echo "     got: $(printf '%s' "$tw" | grep -A3 'decl/def')"; } \
  || ok "F3 refuses two files that both DEFINE the same symbol (the decl-vs-def half is live)"

# ...and the positive twin of that control, so the arm above cannot pass by the rule being inert: a header
# that DECLARES what a same-sized source DEFINES must still be found.
mkdir -p pair
printf 'int declared_only( int x );\n' > pair/r.h
printf '#include "pair/r.h"\nint declared_only( int x ) { return x + 3; }\n' > pair/r.cc
_c "2019-09-05T10:00:00 +0000" pair
pr="$("$BIN" "$OLD" --situ=pair/r.cc --no-cache 2>/dev/null)"
printf '%s' "$pr" | grep -q 'pair/r.h' \
  && ok "F3 still finds a one-symbol decl/def pair (the refusal above is selective, not blanket)" \
  || { no "F3 missed a one-symbol header/impl pair"; echo "     got: $(printf '%s' "$pr" | head -c 500)"; }

# 4e3) F2's EMPTY-WINDOW branch: a tree with git but NO commits must say the zero is not a measurement,
#      rather than the old "(none, or no git history)" that meant neither.
NH="$(mktemp -d)"; mkdir -p "$NH/db"
printf 'int f( int x ){ if( x ) { return 1; } return 0; }\n' > "$NH/db/x.cc"
( cd "$NH" && git init -q && git config user.email x@y && git config user.name x )
os0="$("$BIN" "$NH" --situ=db/x.cc --no-cache 2>/dev/null)"
printf '%s' "$os0" | grep -q 'commits="0"' && printf '%s' "$os0" | grep -q 'NOT a measurement' \
  && ok "--situ tells an empty WINDOW apart from an empty RESULT (non-negotiable #3)" \
  || { no "--situ still conflates 'no partners' with 'the window could not look'"; echo "     got: $(printf '%s' "$os0" | grep -A1 'co-change')"; }
printf '%s' "$os0" | grep -q 'window="18mo"' \
  && ok "the unanchorable window drops @HEAD rather than claiming an anchor it does not have" \
  || { no "a repo with no HEAD must stamp window=\"18mo\" (no @HEAD)"; echo "     got: $(printf '%s' "$os0" | grep -o 'window="[^\"]*"' | head -1)"; }
rm -rf "$NH"

# 4f) determinism + well-formedness on the anchored path (the anchor must not import the wall clock).
oc1="$("$BIN" "$OLD" --cochange --no-cache 2>/dev/null)"; oc2="$("$BIN" "$OLD" --cochange --no-cache 2>/dev/null)"
[ "$oc1" = "$oc2" ] && ok "--cochange anchored window deterministic" || no "--cochange anchored window not deterministic"
printf '%s' "$oc1" | xmllint --noout - 2>/dev/null && ok "--cochange anchored output is well-formed XML" || no "--cochange anchored XML malformed"

# 4g) an EXPLICIT --since is the user's own choice and stays wall-clock-relative — the opt-out, and the reason
#     no new flag exists. A future date must still be an honest empty window here.
oe="$("$BIN" "$OLD" --cochange --since="$FUTURE" --no-cache 2>/dev/null)"
printf '%s' "$oe" | grep -q 'commits="0"' \
  && ok "an explicit --since is NOT re-anchored (future date still empties the window)" \
  || { no "an explicit --since must stay literal — anchoring it would steal the user's own choice"; echo "     got: $(printf '%s' "$oe" | head -c 300)"; }

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
