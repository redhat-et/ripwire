#!/usr/bin/env bash
# prrenamecheck.sh — gate for A4-F3: renamed+edited files must NOT vanish from --pr-context.
#
# --pr-context builds its changed-file mask from `git diff --numstat`. A rename+edit row renders the
# path column as `pre{old => new}post` (common prefix/suffix factored out) or the bare `old => new`
# form — NOT the plain new path. Taken verbatim (the pre-F3 bug) that column suffix-matches no ingested
# file, so the file — exactly the change a reviewer most needs — silently disappears from the bundle.
# This gate stages a real `git mv` + content edit and asserts the NEW path appears as a changed <file>.
# It exercises BOTH numstat rename spellings: a same-directory rename (brace form) and a cross-directory
# move (which git also renders with a brace at the divergence point).
#
# Usage:
#   test/prrenamecheck.sh
#   CTXPACK_BIN=asan/ctxpack test/prrenamecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "prrenamecheck: BIN=$BIN"

REPO="$TMP/repo"
mkdir -p "$REPO/src" "$REPO/lib"
git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"

cat >"$REPO/src/oldname.cpp" <<'EOF'
int alpha() { return 1; }
int beta()  { return alpha(); }
EOF
cat >"$REPO/src/mover.cpp" <<'EOF'
int gamma() { return 2; }
EOF
git -C "$REPO" add -A
git -C "$REPO" commit -qm init

# (1) same-directory rename + edit → numstat "src/{oldname.cpp => newname.cpp}"
git -C "$REPO" mv src/oldname.cpp src/newname.cpp
cat >"$REPO/src/newname.cpp" <<'EOF'
int alpha() { return 99; }
int beta()  { return alpha(); }
EOF
git -C "$REPO" add -A

# (2) cross-directory move + edit → numstat "{src => lib}/mover.cpp"
git -C "$REPO" mv src/mover.cpp lib/mover.cpp
cat >"$REPO/lib/mover.cpp" <<'EOF'
int gamma() { return 42; }
EOF
git -C "$REPO" add -A

echo "--- git diff --numstat (staged) ---"
git -C "$REPO" -c core.quotepath=false diff --numstat HEAD
echo "-----------------------------------"

OUT="$( "$BIN" "$REPO" --pr-context --no-cache 2>/dev/null )"
echo "pr-context output:"; echo "$OUT"; echo

# The renamed NEW paths must both surface as changed <file> sections.
echo "$OUT" | grep -q '<file p="[^"]*src/newname\.cpp"' \
    && ok "brace-form rename resolves to NEW path (src/newname.cpp present)" \
    || no "renamed src/newname.cpp missing from --pr-context (A4-F3 regression)"

echo "$OUT" | grep -q '<file p="[^"]*lib/mover\.cpp"' \
    && ok "cross-dir move resolves to NEW path (lib/mover.cpp present)" \
    || no "moved lib/mover.cpp missing from --pr-context (A4-F3 regression)"

# The OLD paths must NOT appear (they no longer exist / are not indexed).
echo "$OUT" | grep -q 'p="[^"]*src/oldname\.cpp"' \
    && no "stale OLD path src/oldname.cpp wrongly present" \
    || ok "OLD path src/oldname.cpp correctly absent"

# xmllint-clean (wrap so multiple top nodes are legal).
{ echo "<root>"; echo "$OUT"; echo "</root>"; } | xmllint --noout - 2>/dev/null \
    && ok "xmllint clean (wrapped)" \
    || no "xmllint reported malformed XML"

# ══ §B13.2 — a PURE rename (no content edit) is a CHANGED FILE, not a mode flip ════════════════════════
# The arms above stage rename+EDIT, so numstat reports non-zero added/deleted and the row was never at risk.
# A pure `git mv` is content-identical, so numstat reports `0\t0\tsrc/{a.h => b.h}` — the SAME two zeros a
# chmod produces. numstatRowPath classed every 0/0 row as mode-only, so measured on this fixture the pre-fix
# binary gave --pr-context files="0" skipped_mode_only="2" with ZERO <file> rows at exit 0, while --test-gate
# on the identical tree gave changed="2" impacted="1" untested="1" and exit 4: a pure-refactor / file-move PR
# reviewed as an EMPTY bundle, and the only signal was an attribute named after file modes.
# The fixture carries BOTH kinds in one diff, so the arm proves the split, not just the survival: one pure
# rename (must be changed, at its new path) + one real chmod (must stay counted as mode-only).
echo
echo "--- §B13.2: pure rename vs real chmod, same diff ---"
PURE="$TMP/pure"
mkdir -p "$PURE/src"
git -C "$PURE" init -q
git -C "$PURE" config user.email "dev@x.com"
git -C "$PURE" config user.name  "Dev"
git -C "$PURE" config core.fileMode true
cat >"$PURE/src/util.h" <<'EOF'
int helperOne( int a ) { return a + 1; }
int helperTwo( int b ) { return helperOne( b ) * 2; }
EOF
cat >"$PURE/src/app.cpp" <<'EOF'
#include "util.h"
int mainEntry() { return helperTwo( 3 ); }
EOF
cat >"$PURE/src/modeonly.cpp" <<'EOF'
int chmodMe() { return 7; }
EOF
chmod 644 "$PURE/src/modeonly.cpp"
git -C "$PURE" add -A
git -C "$PURE" commit -qm init
git -C "$PURE" mv src/util.h src/renamed.h      # pure rename: content byte-identical
chmod +x "$PURE/src/modeonly.cpp"                # real mode flip: content byte-identical
git -C "$PURE" add -A

echo "--- git diff --numstat (staged) ---"
git -C "$PURE" -c core.quotepath=false diff --numstat HEAD
echo "-----------------------------------"

# premise: both rows must really be 0/0, or this fixture is not testing what it claims
ZEROROWS="$( git -C "$PURE" -c core.quotepath=false diff --numstat HEAD | grep -c '^0	0	' )"
[ "${ZEROROWS:-0}" = "2" ] \
    && ok "premise: git reports BOTH the rename and the chmod as 0/0 rows (indistinguishable by counts alone)" \
    || no "premise FAILED: expected 2 zero-rows in the fixture diff, got ${ZEROROWS:-0} — the arms below cannot discriminate"

POUT="$( "$BIN" "$PURE" --pr-context --no-cache 2>/dev/null )"
PHDR="$( printf '%s' "$POUT" | grep -o '<pr-context[^>]*>' | head -1 )"
PFILES="$( printf '%s' "$PHDR" | grep -o 'files="[0-9]*"' | head -1 | grep -o '[0-9]*' )"
PMODE="$( printf '%s' "$PHDR" | grep -o 'skipped_mode_only="[0-9]*"' | head -1 | grep -o '[0-9]*' )"
[ "${PFILES:-0}" = "1" ] \
    && ok "pure rename is a CHANGED file: files=\"$PFILES\" (was 0 — the whole bundle was empty)" \
    || no "pure rename dropped: files=\"${PFILES:-<none>}\" expected 1 — header was: $PHDR"
[ "${PMODE:-0}" = "1" ] \
    && ok "the real chmod is still counted: skipped_mode_only=\"$PMODE\" (1 = the chmod alone, not 1 rename + 1 chmod)" \
    || no "skipped_mode_only=\"${PMODE:-<none>}\" expected 1 — header was: $PHDR"
printf '%s' "$POUT" | grep -q '<file p="[^"]*src/renamed\.h"' \
    && ok "the renamed file appears at its NEW path (src/renamed.h)" \
    || no "src/renamed.h missing from the bundle even though files=$PFILES"
printf '%s' "$POUT" | grep -q '<file p="[^"]*src/modeonly\.cpp"' \
    && no "the chmod'd file wrongly entered the changed set (the mode-only filter is gone, A3-F10 regression)" \
    || ok "the chmod'd file is correctly NOT a changed file"

# and the two verbs must stop disagreeing about the same tree: --pr-context saw nothing, --test-gate saw
# the blast radius and exited 4. Compare the CHANGED-FILE counts each reports.
TGH="$( "$BIN" "$PURE" --test-gate --no-cache 2>/dev/null | grep -o '<test-gate[^>]*>' | head -1 )"
TGC="$( printf '%s' "$TGH" | grep -o 'changed="[0-9]*"' | head -1 | grep -o '[0-9]*' )"
[ -n "${TGC:-}" ] && [ "${PFILES:-0}" -gt 0 ] \
    && ok "--test-gate sees changed=\"$TGC\" and --pr-context now sees files=\"$PFILES\" — neither reviews the move as an empty diff" \
    || no "--pr-context files=\"${PFILES:-0}\" vs --test-gate changed=\"${TGC:-?}\": one verb still reviews a pure move as empty"

# the MCP siblings read the SAME mask builder (situ.h delegates to gitDiffChangedMaskNumstat) — the fix must
# not be CLI-only, which is how a dialect divergence is born.
if command -v python3 >/dev/null 2>&1; then
    MSITU="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"'"$PURE"'"}}}' \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__" if "error" in r else r["result"]["content"][0]["text"])
' )"
    MCHANGED="$( printf '%s' "$MSITU" | python3 -c '
import sys, json
try:    print(len(json.load(sys.stdin).get("changed_files", [])))
except Exception: print("ERR")
' )"
    [ "${MCHANGED:-ERR}" = "1" ] \
        && ok "MCP situational_awareness (the numstat mask builder) also sees the pure rename: changed_files=1" \
        || no "MCP situational_awareness reports changed_files=${MCHANGED:-ERR}, expected 1 — pre-fix it also claimed \"working tree is clean\""
    # ...and it must not SAY the tree is clean while a file moved
    case "$MSITU" in
        *"working tree is clean"* ) no "MCP situational_awareness calls a tree with a staged rename 'clean'" ;;
        * ) ok "MCP situational_awareness does not call the moved-file tree 'clean'" ;;
    esac
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
