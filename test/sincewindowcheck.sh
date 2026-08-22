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

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
