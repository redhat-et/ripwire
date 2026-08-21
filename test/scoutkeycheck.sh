#!/usr/bin/env bash
# scoutkeycheck.sh — --merge-scout's comparison key must be PATH-QUALIFIED.
#
# The bug: canonicalId( path, scope, name ) returns the BARE NAME when a symbol has no scope
# (resolve.h). That is right for display, and catastrophic as a cross-branch comparison key — every
# scope-less `ok()` in a tree folds to ONE identity. Measured on the ripwire repo itself, 29% of map
# rows carried a non-unique id, 238 shell `ok()` helpers among them.
#
# The consequence was a FABRICATED conflict: two branches touching completely disjoint files were
# reported as changing the same symbol. That is the worst possible failure for this verb — a conflict
# tool dies on its second false positive, and this one told you to serialize work that never collided.
#
# A conflict gate is only as good as its NEGATIVE case, so this pins both directions: the false
# positive must be gone AND the true positives must survive.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }
echo "scoutkeycheck: BIN=$BIN"

pairline(){ "$BIN" "$1" --merge-scout=laneA,laneB 2>/dev/null | grep -oE '<pair [^>]*>' | head -1; }
attr(){ printf '%s' "$1" | grep -oE "$2=\"[0-9]+\"" | grep -oE '[0-9]+' | head -1; }

# ── 1) THE NEGATIVE CASE: disjoint files, same scope-less function name ───────────────────────────────
R="$TMP/disjoint"; mkdir -p "$R"; cd "$R"
git init -q .; git config user.email t@t; git config user.name t
printf '#!/bin/sh\necho base\n' > common.sh; git add -A; git commit -qm base
BASE="$( git rev-parse --abbrev-ref HEAD )"
git checkout -q -b laneA; printf '#!/bin/sh\nok(){ echo "A: $*"; }\nok hello\n' > a.sh; git add a.sh; git commit -qm "laneA: a.sh"
git checkout -q "$BASE"; git checkout -q -b laneB; printf '#!/bin/sh\nok(){ echo "B: $*"; }\nok world\n' > b.sh; git add b.sh; git commit -qm "laneB: b.sh"
git checkout -q "$BASE"

# the arms are disjoint BY CONSTRUCTION — assert that, so the gate cannot pass on a broken fixture
A_FILES="$( git diff --name-only "$BASE..laneA" )"; B_FILES="$( git diff --name-only "$BASE..laneB" )"
[ "$A_FILES" = "a.sh" ] && [ "$B_FILES" = "b.sh" ] \
    && ok "fixture: laneA touched only a.sh, laneB only b.sh (disjoint)" \
    || no "fixture is not disjoint (A='$A_FILES' B='$B_FILES') — the rest of this gate is meaningless"

P="$( pairline . )"
[ "$( attr "$P" conflicts )" = "0" ] \
    && ok "disjoint arms sharing a scope-less name report conflicts=\"0\"" \
    || { no "FABRICATED conflict between disjoint arms: $P"; "$BIN" . --merge-scout=laneA,laneB 2>/dev/null | grep -oE '<conflict[^>]*/>' | sed 's/^/        /'; }
[ "$( attr "$P" risks )" = "0" ] \
    && ok "…and no textual risk either (they share no file)" \
    || no "fabricated textual risk between disjoint arms: $P"

# ── 2) TRUE POSITIVE: both arms change the SAME symbol in the SAME file ───────────────────────────────
R2="$TMP/samesym"; mkdir -p "$R2"; cd "$R2"
git init -q .; git config user.email t@t; git config user.name t
printf 'int shared( int a ) { return a; }\nint other( int b ) { return b + 1; }\n' > shared.c
git add -A; git commit -qm base; BASE2="$( git rev-parse --abbrev-ref HEAD )"
git checkout -q -b laneA; printf 'int shared( int a ) { return a * 2; }\nint other( int b ) { return b + 1; }\n' > shared.c; git commit -qam "laneA edits shared"
git checkout -q "$BASE2"; git checkout -q -b laneB; printf 'int shared( int a ) { return a * 3; }\nint other( int b ) { return b + 1; }\n' > shared.c; git commit -qam "laneB edits shared"
git checkout -q "$BASE2"
P2="$( pairline . )"
[ "$( attr "$P2" conflicts )" = "1" ] \
    && ok "same symbol on both arms still reports conflicts=\"1\" (detection not weakened)" \
    || no "TRUE POSITIVE LOST — same-symbol change no longer detected: $P2"
"$BIN" . --merge-scout=laneA,laneB 2>/dev/null | grep -q '<conflict p="shared.c" id="shared"/>' \
    && ok "…naming the right file and symbol" || no "…but the conflict row does not name shared.c::shared"

# ── 3) SAME FILE, DIFFERENT SYMBOL: a textual risk, never a same-symbol conflict ──────────────────────
git checkout -q laneB; printf 'int shared( int a ) { return a; }\nint other( int b ) { return b + 99; }\n' > shared.c; git commit -qam "laneB edits other"
git checkout -q "$BASE2"
P3="$( pairline . )"
[ "$( attr "$P3" conflicts )" = "0" ] && [ "$( attr "$P3" risks )" = "1" ] \
    && ok "same file, different symbols = risk 1 / conflict 0 (the distinction survives)" \
    || no "same-file/different-symbol classification broke: $P3"

# ── 4) determinism — the key is a hash of text, so it must not vary run to run ────────────────────────
cd "$R2"
"$BIN" . --merge-scout=laneA,laneB >"$TMP/s1" 2>/dev/null
"$BIN" . --merge-scout=laneA,laneB >"$TMP/s2" 2>/dev/null
cmp -s "$TMP/s1" "$TMP/s2" && ok "merge-scout output byte-identical run-to-run" || no "merge-scout is non-deterministic"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
