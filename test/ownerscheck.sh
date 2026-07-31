#!/usr/bin/env bash
# ownerscheck.sh — gate for S5-C: --owners bus-factor analysis.
#
# Creates a synthetic git repo with controlled commit history, runs --owners, and asserts:
#   - file1.cpp: alice@x.com is top owner with bf=1 (she holds >80% of weighted commits)
#   - file2.cpp: bf=0 (ownership is split between alice and bob)
#   - Determinism: two runs produce byte-identical output
#
# Usage:
#   test/ownerscheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/ownerscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # BOTH seams: positional and RIPWIRE_BIN
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "ownerscheck: BIN=$BIN"

# ── Build a synthetic git repo ────────────────────────────────────────────────────────────────────
REPO="$TMP/testrepo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "setup@x.com"
git -C "$REPO" config user.name  "Setup"

# Create the source files (ripwire needs parseable source; use simple C)
cat >"$REPO/file1.cpp" <<'EOF'
// file1.cpp — owned mostly by alice (bf=1 expected)
void func1() {}
EOF

cat >"$REPO/file2.cpp" <<'EOF'
// file2.cpp — split ownership between alice and bob (bf=0 expected)
void func2() {}
EOF

# file3.cpp / file4.cpp: SOLE author (authors=1) — §P6.4's "uniform" case. authors=1 implies bf=1 and
# share=1.00 deterministically (a lone author's weighted-commit share, divided by itself, is exactly 1.0
# regardless of the recency decay applied — no float slop), so these are exactly the modal shape the
# default --owners listing collapses into one <uniform/> row instead of one <f/> row per file.
cat >"$REPO/file3.cpp" <<'EOF'
// file3.cpp — sole author carol (authors=1, bf=1, share=1.00 expected — the "uniform" shape)
void func3() {}
EOF

cat >"$REPO/file4.cpp" <<'EOF'
// file4.cpp — sole author carol (authors=1, bf=1, share=1.00 expected — the "uniform" shape)
void func4() {}
EOF

# Commit helper: commit with explicit author + date
commit_file() {
    local file="$1" name="$2" email="$3" ts="$4" msg="$5"
    git -C "$REPO" add "$file"
    GIT_AUTHOR_NAME="$name"    GIT_AUTHOR_EMAIL="$email"    GIT_AUTHOR_DATE="$ts" \
    GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email" GIT_COMMITTER_DATE="$ts" \
        git -C "$REPO" commit -q -m "$msg"
}

# ── file1.cpp: 5 recent commits by alice, 1 very old commit by bob ──────────────────────────────
# "now" anchor: use a fixed recent date so the test is not wall-clock-dependent.
# alice commits: all within the last 30 days (high recency weight)
# bob commit:    ~3 years ago (very low recency weight due to exponential decay)

# bob's old commit (3 years ago ≈ 1095 days; decay factor ≈ exp(-ln2/182.5 * 1095*86400) ≈ 0.016)
echo "// bob old" >>"$REPO/file1.cpp"
commit_file file1.cpp "Bob" "bob@x.com" "2022-01-01T00:00:00" "file1 bob old"

# alice's 5 recent commits (within last 30 days; decay ≈ 0.89–1.00 each)
for i in 1 2 3 4 5; do
    echo "// alice edit $i" >>"$REPO/file1.cpp"
    commit_file file1.cpp "Alice" "alice@x.com" "2026-06-0${i}T12:00:00" "file1 alice $i"
done

# ── file2.cpp: 2 recent commits each from alice and bob (even split → bf=0) ──────────────────────
for i in 1 2; do
    echo "// alice f2 $i" >>"$REPO/file2.cpp"
    commit_file file2.cpp "Alice" "alice@x.com" "2026-06-1${i}T12:00:00" "file2 alice $i"

    echo "// bob f2 $i" >>"$REPO/file2.cpp"
    commit_file file2.cpp "Bob" "bob@x.com" "2026-06-1${i}T13:00:00" "file2 bob $i"
done

# ── file3.cpp / file4.cpp: 2 commits each, sole author carol (authors=1 → the uniform shape) ──────
for f in file3.cpp file4.cpp; do
    for i in 1 2; do
        echo "// carol $f $i" >>"$REPO/$f"
        commit_file "$f" "Carol" "carol@x.com" "2026-06-2${i}T12:00:00" "$f carol $i"
    done
done

# ── Run --owners on the synthetic repo ───────────────────────────────────────────────────────────
OUT="$( "$BIN" "$REPO" --owners --no-cache 2>/dev/null )"
if [ -z "$OUT" ]; then
    no "owners: output is empty (git mine failed?)"
    echo
    echo "SOME CHECKS FAILED"
    exit 1
fi

echo "owners output:"
echo "$OUT"
echo

# ── Check file1.cpp: alice is top owner with bf=1 ────────────────────────────────────────────────
# The XML row for file1.cpp looks like:
#   <f p="...file1.cpp" authors="2" bf="1" top="alice@x.com" share="0.XX"/>
FILE1_LINE="$( echo "$OUT" | grep -o '<f p="[^"]*file1\.cpp[^"]*"[^/]*/>' | head -1 )"
if [ -z "$FILE1_LINE" ]; then
    no "file1.cpp: no <f> entry found in output"
else
    ok "file1.cpp: <f> entry found"

    # bf=1
    echo "$FILE1_LINE" | grep -q 'bf="1"' \
        && ok "file1.cpp: bf=1 (alice dominates)" \
        || no "file1.cpp: expected bf=1 but got: $FILE1_LINE"

    # top=alice@x.com
    echo "$FILE1_LINE" | grep -q 'top="alice@x.com"' \
        && ok "file1.cpp: top owner is alice@x.com" \
        || no "file1.cpp: expected top=alice@x.com but got: $FILE1_LINE"
fi

# ── Check file2.cpp: bf=0 (split ownership) ───────────────────────────────────────────────────────
FILE2_LINE="$( echo "$OUT" | grep -o '<f p="[^"]*file2\.cpp[^"]*"[^/]*/>' | head -1 )"
if [ -z "$FILE2_LINE" ]; then
    no "file2.cpp: no <f> entry found in output"
else
    ok "file2.cpp: <f> entry found"

    # bf=0 (neither alice nor bob holds >80%)
    echo "$FILE2_LINE" | grep -q 'bf="0"' \
        && ok "file2.cpp: bf=0 (ownership is split)" \
        || no "file2.cpp: expected bf=0 but got: $FILE2_LINE"

    # authors=2
    echo "$FILE2_LINE" | grep -q 'authors="2"' \
        && ok "file2.cpp: 2 unique authors" \
        || no "file2.cpp: expected authors=2 but got: $FILE2_LINE"
fi

# ── §P6.4: file3.cpp/file4.cpp (sole-author "uniform" shape) fold into ONE <uniform/> row ─────────
# Before the fix, 758 files on the real repo each printed authors="1" bf="1" share="1.00" individually
# (75KB of identical rows carrying zero extra information per row). Default output now emits one
# <uniform authors="1" bf="1" share="1.00" files="N"/> summary and OMITS the individual <f/> row for
# every file counted in it; --detail=1 restores the full per-file listing (including the uniform ones).
UNIFORM_LINE="$( echo "$OUT" | grep -o '<uniform [^/]*/>' | head -1 )"
if [ -z "$UNIFORM_LINE" ]; then
    no "no <uniform/> summary row found in default --owners output"
else
    ok "<uniform/> summary row found: $UNIFORM_LINE"
    echo "$UNIFORM_LINE" | grep -q 'authors="1" bf="1" share="1.00"' \
        && ok "<uniform/> carries the exact modal shape (authors=1 bf=1 share=1.00)" \
        || no "<uniform/> shape wrong: $UNIFORM_LINE"
    echo "$UNIFORM_LINE" | grep -q 'files="2"' \
        && ok "<uniform/> files=2 (file3.cpp + file4.cpp, the only sole-authored files)" \
        || no "<uniform/> files= count wrong (expected 2): $UNIFORM_LINE"
fi

# file3.cpp/file4.cpp must NOT get an individual <f/> row in the default (collapsed) output.
echo "$OUT" | grep -q '<f p="[^"]*file3\.cpp'  && no "file3.cpp still has an individual <f/> row (not collapsed into <uniform/>)"
echo "$OUT" | grep -q '<f p="[^"]*file4\.cpp'  && no "file4.cpp still has an individual <f/> row (not collapsed into <uniform/>)"
[ -z "$( echo "$OUT" | grep -o '<f p="[^"]*file3\.cpp[^/]*/>' )" ] && [ -z "$( echo "$OUT" | grep -o '<f p="[^"]*file4\.cpp[^/]*/>' )" ] \
    && ok "file3.cpp/file4.cpp carry no individual <f/> row in the default (collapsed) listing" \
    || no "collapsed listing leaked an individual row for a uniform file"

# file1.cpp/file2.cpp (authors=2, NOT uniform) must still print their own <f/> rows unchanged.
echo "$OUT" | grep -q '<f p="[^"]*file1\.cpp[^/]*/>' \
    && ok "file1.cpp (authors=2, not uniform) still prints its own <f/> row" \
    || no "file1.cpp row went missing from the default listing"
echo "$OUT" | grep -q '<f p="[^"]*file2\.cpp[^/]*/>' \
    && ok "file2.cpp (authors=2, not uniform) still prints its own <f/> row" \
    || no "file2.cpp row went missing from the default listing"

# ── §P6.4: --detail=1 lifts the collapse — file3.cpp/file4.cpp get their full row back ────────────
DETAIL_OUT="$( "$BIN" "$REPO" --owners --detail=1 --no-cache 2>/dev/null )"
FILE3_DETAIL="$( echo "$DETAIL_OUT" | grep -o '<f p="[^"]*file3\.cpp[^"]*"[^/]*/>' | head -1 )"
if [ -z "$FILE3_DETAIL" ]; then
    no "--detail=1: file3.cpp has no individual <f/> row"
else
    ok "--detail=1: file3.cpp: <f> entry found"
    echo "$FILE3_DETAIL" | grep -q 'authors="1" bf="1"' \
        && ok "--detail=1: file3.cpp: authors=1 bf=1" \
        || no "--detail=1: file3.cpp: expected authors=1 bf=1, got: $FILE3_DETAIL"
    echo "$FILE3_DETAIL" | grep -q 'share="1.00"' \
        && ok "--detail=1: file3.cpp: share=1.00" \
        || no "--detail=1: file3.cpp: expected share=1.00, got: $FILE3_DETAIL"
fi
echo "$DETAIL_OUT" | grep -q '<uniform ' \
    && no "--detail=1: <uniform/> summary row should be absent once the full listing is restored" \
    || ok "--detail=1: no <uniform/> row (full per-file listing, nothing collapsed)"

# ── Determinism: two runs produce byte-identical output ───────────────────────────────────────────
OUT_A="$( "$BIN" "$REPO" --owners --no-cache 2>/dev/null )"
OUT_B="$( "$BIN" "$REPO" --owners --no-cache 2>/dev/null )"
[ "$OUT_A" = "$OUT_B" ] \
    && ok "determinism: byte-identical run-to-run" \
    || no "determinism: non-identical output"


# ── §B11.3-class: --owners=SYM IS A FOLD, and the fold is now disclosed ───────────────────────────────────
# Found by §B11.3's own sweep ("a verb that folds a group and reports a scalar as if the group were one
# thing"). --owners=SYM resolves the name, takes defs[0] — ONE of N, the lowest node id — and reports that
# definition's file under files="1", which reads as "this symbol lives in one file", while --callers/--uses/
# --impact/--mentions on the SAME name all disclose defs="3". of=/defs= make the pick legible; the pick
# itself is unchanged (it is resolveFocus' rule, and narrowing is what file:name is for).
if command -v git >/dev/null 2>&1; then
    OF="$( mktemp -d )"; mkdir -p "$OF/a" "$OF/b"
    printf 'int twinned( int q ) { return q; }\n'      > "$OF/a/one.h"
    printf 'int twinned( double q ) { return 0; }\n'   > "$OF/b/two.h"
    ( cd "$OF" && git init -q && git config user.email t@t && git config user.name t \
      && git config commit.gpgsign false && git add -A && git commit -qm init ) >/dev/null 2>&1
    OW="$( "$BIN" "$OF" --owners=twinned --no-cache 2>/dev/null )"
    CD="$( "$BIN" "$OF" --callers=twinned --no-cache 2>/dev/null | grep -oE 'defs="[0-9]+"' | head -1 )"
    OD="$( printf '%s' "$OW" | grep -oE '<owners [^>]*' | grep -oE 'defs="[0-9]+"' | head -1 )"
    { [ -n "$OD" ] && [ "$OD" = "$CD" ]; } \
        && ok "B11.3-class: --owners=SYM discloses defs= and AGREES with --callers ($OD)" \
        || no "B11.3-class: --owners=SYM defs=[$OD] vs --callers defs=[$CD] — the fold is silent or disagrees"
    printf '%s' "$OW" | grep -q '<owners [^>]*of="twinned"' \
        && ok "B11.3-class: --owners=SYM echoes the selector in of=" \
        || { no "B11.3-class: --owners=SYM does not echo its selector"; printf '%s\n' "$OW" | sed 's/.*-->//'; }
    printf '%s' "$OW" | grep -oE '<!--.*-->' | head -1 | grep -q 'defs= is how many DEFINITIONS' \
        && ok "B11.3-class: the legend explains the pick (first definition; other files NOT analysed)" \
        || no "B11.3-class: defs= is emitted and unexplained"
    # GUARD: the all-files form gains nothing — no of=, no defs=, byte shape untouched.
    "$BIN" "$OF" --owners --no-cache 2>/dev/null | grep -qE '<owners [^>]*(of=|defs=)' \
        && no "B11.3-class: the all-files form wrongly grew of=/defs=" \
        || ok "B11.3-class: the all-files --owners form is untouched"
    # and at= stays LAST (the r26-stamp placement rule the new attributes had to respect).
    printf '%s' "$OW" | grep -qE '<owners [^>]*at="[^"]*">' \
        && ok "B11.3-class: at= is still the last attribute on <owners>" \
        || no "B11.3-class: the new attributes displaced at= from last"
    rm -rf "$OF"
else
    printf '  SKIP  B11.3-class --owners fold disclosure (no git)\n'
fi

# ── Summary ───────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
