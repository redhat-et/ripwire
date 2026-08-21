#!/usr/bin/env bash
# mergescoutlonglinecheck.sh — gate for the 2026-08-21 long-line fix to L1 (--merge-scout).
#
# Found live: PLAN_HARVEST_REPORTS_2026-08-20/merge-phase.md §1/§6 — test/regression.sh's absorb loop is
# one ~6.7 KB physical line (a top-level bash `for`, never wrapped in a function_definition —
# queries/bash/tags.scm only captures functions), so it contributes ZERO tree-sitter symbols and was
# invisible to merge-scout's symbol-keyed diff: it conflicted on 3 of 5 harvest-exec merges and NEVER
# appeared in a single merge-scout conflict row.
#
# Fixture repo, 2 branches off one init commit:
#   absorb.sh   — ONE long top-level physical line (a bash `for` loop over many tokens, ~7 KB, no
#                 function_definition wrapping it) — the exact shape that produces zero real-body symbols.
#   helper.cpp  — an ordinary function, for a same-run control on normal symbol-level attribution.
#   A appends one token to absorb.sh's loop AND changes helper.cpp::hlp
#   B appends a DIFFERENT token to absorb.sh's loop AND changes helper.cpp::hlp too
#
# Both arms touch absorb.sh; neither edit can be attributed to a symbol inside it (there is none). Asserts:
#   - each arm reports changed="2": one ordinary <sym .../> row for helper.cpp::hlp, one
#     <sym p="absorb.sh" ... anchoring="file-level"/> row for the long-line file — COUNTED, never omitted
#   - pair A-B reports conflicts="2": the ordinary hlp conflict (no anchoring=) AND the absorb.sh
#     file-level conflict (anchoring="file-level") — same-file overlap detected WITHOUT symbol attribution
#   - a file with real symbol coverage never gets anchoring="file-level" (no false positives)
#   - xmllint-clean, byte-identical determinism ×3
#
# Usage:
#   test/mergescoutlonglinecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/mergescoutlonglinecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "mergescoutlonglinecheck: BIN=$BIN"

# ── Build the fixture repo ─────────────────────────────────────────────────────────────────────────────
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"

# absorb.sh: one long top-level physical line, no function wrapping it — mirrors test/regression.sh's
# absorb loop exactly (a bash `for` over many bare-word tokens, one line, ~7 KB).
gen_absorb()
{
    local extra="$1"
    python3 - "$REPO/absorb.sh" "$extra" <<'PYEOF'
import sys
path, extra = sys.argv[1], sys.argv[2]
tokens = " ".join("token_number_%04d" % i for i in range(500))
if extra:
    tokens += " " + extra
line = "for _g in %s; do [ -f \"$_g\" ] && echo \"$_g\"; done" % tokens
with open(path, "w") as f:
    f.write("#!/usr/bin/env bash\n")
    f.write(line + "\n")
PYEOF
}

gen_absorb ""
LINE_BYTES="$( awk 'NR==2{print length($0)}' "$REPO/absorb.sh" )"
[ "${LINE_BYTES:-0}" -gt 4000 ] \
    && ok "fixture: absorb.sh's one payload line is ${LINE_BYTES} bytes (>4000, a genuine long line)" \
    || no "fixture: absorb.sh payload line too short (${LINE_BYTES:-0} bytes) — not a realistic repro"

cat >"$REPO/helper.cpp" <<'EOF'
int hlp() { return 1; }
EOF

git -C "$REPO" add -A
GIT_AUTHOR_DATE="2026-08-21T09:00:00" GIT_COMMITTER_DATE="2026-08-21T09:00:00" \
    git -C "$REPO" commit -qm "init"
MAIN="$( git -C "$REPO" symbolic-ref --short HEAD )"

git -C "$REPO" checkout -qb A
gen_absorb "extraA"
cat >"$REPO/helper.cpp" <<'EOF'
int hlp() { return 100; }
EOF
GIT_AUTHOR_DATE="2026-08-21T10:00:00" GIT_COMMITTER_DATE="2026-08-21T10:00:00" \
    git -C "$REPO" commit -qam "A: extend absorb loop + change hlp"
git -C "$REPO" checkout -q "$MAIN"

git -C "$REPO" checkout -qb B
gen_absorb "extraB"
cat >"$REPO/helper.cpp" <<'EOF'
int hlp() { return 200; }
EOF
GIT_AUTHOR_DATE="2026-08-21T11:00:00" GIT_COMMITTER_DATE="2026-08-21T11:00:00" \
    git -C "$REPO" commit -qam "B: extend absorb loop (differently) + change hlp too"
git -C "$REPO" checkout -q "$MAIN"

# ── Run --merge-scout=A,B ───────────────────────────────────────────────────────────────────────────────
OUT="$( "$BIN" "$REPO" --merge-scout=A,B --no-cache 2>/dev/null )"
if [ -z "$OUT" ]; then no "merge-scout: output is empty"; echo; echo "SOME CHECKS FAILED"; exit 1; fi
echo "merge-scout output:"; echo "$OUT"; echo

echo "$OUT" | grep -q 'arms="2"' && ok "2 arms reported" || no "expected arms=2: $( echo "$OUT" | grep -o 'arms="[0-9]*"' | head -1 )"

# ── the core fix: absorb.sh (zero real-body symbols) is COUNTED, not silently omitted ────────────────────
echo "$OUT" | grep -q '<arm ref="A"[^>]*changed="2"' \
    && ok "arm A reports changed=\"2\" (hlp + absorb.sh — the long-line file is counted)" \
    || no "arm A wrong changed= count: $( echo "$OUT" | grep -o '<arm ref=\"A\"[^>]*' )"
echo "$OUT" | grep -q '<arm ref="B"[^>]*changed="2"' \
    && ok "arm B reports changed=\"2\" (hlp + absorb.sh — the long-line file is counted)" \
    || no "arm B wrong changed= count: $( echo "$OUT" | grep -o '<arm ref=\"B\"[^>]*' )"

echo "$OUT" | grep -q '<sym p="absorb\.sh" id="absorb\.sh" anchoring="file-level"/>' \
    && ok "absorb.sh appears as a <sym ... anchoring=\"file-level\"/> row (honest disclosure, non-negotiable #3)" \
    || no "absorb.sh never appears with anchoring=\"file-level\" — the long-line blind spot is NOT fixed"

# ── the ordinary symbol row for helper.cpp::hlp is UNCHANGED — no anchoring= noise on a real attribution ─
echo "$OUT" | grep -q '<sym p="helper\.cpp" id="hlp"/>' \
    && ok "helper.cpp::hlp is an ordinary <sym p= id=/> row, no anchoring= attribute" \
    || no "helper.cpp::hlp row malformed: $( echo "$OUT" | grep -o '<sym[^/]*helper[^/]*/>' )"
echo "$OUT" | grep -q 'id="hlp"[^/]*anchoring' \
    && no "helper.cpp::hlp wrongly carries anchoring= (false positive — it DOES have symbol coverage)" \
    || ok "helper.cpp::hlp never carries anchoring= (no false positive on a real symbol)"

# ── pair A-B: BOTH a same-symbol conflict (hlp) AND a same-file-level conflict (absorb.sh) ────────────────
PAIR="$( printf '%s' "$OUT" | sed 's/<pair /\n<pair /g' | grep '^<pair a="A" b="B"' )"
echo "$PAIR" | grep -q 'conflicts="2" risks="0"' \
    && ok "pair A-B: conflicts=\"2\" risks=\"0\" (hlp + absorb.sh, both true conflicts)" \
    || no "pair A-B conflicts/risks count wrong: $PAIR"
echo "$PAIR" | grep -q '<conflict p="helper\.cpp" id="hlp"/>' \
    && ok "pair A-B: ordinary conflict row for helper.cpp::hlp" \
    || no "pair A-B missing the ordinary hlp conflict row: $PAIR"
echo "$PAIR" | grep -q '<conflict p="absorb\.sh" id="absorb\.sh" anchoring="file-level"/>' \
    && ok "pair A-B: absorb.sh reported as a same-file conflict with anchoring=\"file-level\" — the fix's headline claim" \
    || no "pair A-B: absorb.sh conflict missing or missing anchoring=\"file-level\": $PAIR"

# ── landing order still names both arms (neither is silently dropped as changed="0") ──────────────────────
echo "$OUT" | grep -oE '<landing order="[^"]*"' | grep -q 'A' \
    && echo "$OUT" | grep -oE '<landing order="[^"]*"' | grep -q 'B' \
    && ok "landing order names both A and B" \
    || no "landing order missing an arm: $( echo "$OUT" | grep -o '<landing[^/]*/>' )"

# ── xmllint ─────────────────────────────────────────────────────────────────────────────────────────────
echo "$OUT" | xmllint --noout - 2>/dev/null \
    && ok "xmllint clean" \
    || no "xmllint reported malformed XML"

# ── determinism ×3 ──────────────────────────────────────────────────────────────────────────────────────
D1="$( "$BIN" "$REPO" --merge-scout=A,B --no-cache 2>/dev/null )"
D2="$( "$BIN" "$REPO" --merge-scout=A,B --no-cache 2>/dev/null )"
D3="$( "$BIN" "$REPO" --merge-scout=A,B --no-cache 2>/dev/null )"
{ [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ]; } && ok "determinism ×3: byte-identical" || no "determinism: output differs across runs"

# ── a lone arm touching ONLY absorb.sh (no companion symbol file) still reports changed="1", not "0" ──────
git -C "$REPO" checkout -qb C
gen_absorb "extraC"
GIT_AUTHOR_DATE="2026-08-21T12:00:00" GIT_COMMITTER_DATE="2026-08-21T12:00:00" \
    git -C "$REPO" commit -qam "C: extend absorb loop only, no symbol touched"
git -C "$REPO" checkout -q "$MAIN"

COUT="$( "$BIN" "$REPO" --merge-scout=C --no-cache 2>/dev/null )"
echo "$COUT" | grep -q '<arm ref="C"[^>]*changed="1"' \
    && ok "arm C (absorb.sh-only change) reports changed=\"1\", not silently dropped to 0" \
    || no "arm C wrong: $( echo "$COUT" | grep -o '<arm ref=\"C\"[^>]*' )"
echo "$COUT" | grep -q '<no-work' \
    && no "arm C wrongly carries <no-work> despite having a real (file-level) change" \
    || ok "arm C carries no <no-work> — file-level-only change correctly counted as real work"

# ── read-only: current branch / working tree unaffected ───────────────────────────────────────────────────
POSTBRANCH="$( git -C "$REPO" symbolic-ref --short HEAD )"
[ "$POSTBRANCH" = "$MAIN" ] && ok "read-only: current branch unchanged after all runs ($POSTBRANCH)" \
                             || no "current branch changed! now on $POSTBRANCH (expected $MAIN)"
git -C "$REPO" status --porcelain | grep -q . \
    && no "read-only: working tree left dirty after runs" \
    || ok "read-only: working tree clean after all runs"

# ── Summary ─────────────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
