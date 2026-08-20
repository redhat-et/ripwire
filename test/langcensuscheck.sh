#!/usr/bin/env bash
# langcensuscheck.sh — gate for W3-S item 3: corpus composition BY LANGUAGE.
#
# No verb answered "what languages is this corpus?" before this: unindexed= (--skipped, the map header)
# discloses only what the crawl could NOT read; nothing disclosed what it DID read, broken down. This
# gate covers the new --skipped <lang n= files= symbols=/> rows (src/main.cpp computeLangCounts /
# writeLangRows): exact per-language file/symbol counts, deterministic sort (files DESC, name ASC
# tiebreak — the same shape unindexedExts' own lessUnindexedExt uses), and absent-means-none (a language
# with zero files AND zero symbols gets no row at all, never a printed zero).
#
# Usage:
#   test/langcensuscheck.sh                      # uses build/ripwire
#   test/langcensuscheck.sh asan/ripwire
#   RIPWIRE_BIN=build_base/ripwire test/langcensuscheck.sh   # red-first: every arm below MUST fail here
#     — a pre-fix binary has no <lang> element in --skipped's output at all.
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# DO NOT edit regression.sh — this is a standalone gate invoked from there.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="$TMP/corpus"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "langcensuscheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "langcensuscheck: xmllint is required"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "langcensuscheck: git is required"; exit 2; }

echo "langcensuscheck: BIN=$BIN"

# ── the fixture corpus: a KNOWN population per language, chosen so the sort order exercises BOTH the
#    primary key (files DESC: py=3 > {rb,rs}=2 > go=1) and the tiebreak (name ASC: "rb" < "rs" — Ruby
#    before Rust when their file counts are equal). No C/C++/Java/etc. files at all, so those languages'
#    absence (never a zero row) is exercised for free.
mkdir -p "$CORPUS/src" || { echo "langcensuscheck: cannot create corpus under $TMP"; exit 2; }

for i in 1 2 3; do
  cat > "$CORPUS/src/mod$i.py" <<PY
def routineA$i( x ):
    return x + 1


def routineB$i( x ):
    return x + 2
PY
done

cat > "$CORPUS/src/a.rs" <<'EOF'
fn helperOne( x: i32 ) -> i32 { x + 1 }
EOF
cat > "$CORPUS/src/b.rs" <<'EOF'
fn helperTwo( x: i32 ) -> i32 { x + 2 }
EOF

cat > "$CORPUS/src/x.rb" <<'EOF'
def rubyOne(x)
  x + 1
end
EOF
cat > "$CORPUS/src/y.rb" <<'EOF'
def rubyTwo(x)
  x + 2
end
EOF

cat > "$CORPUS/src/main.go" <<'EOF'
package main

func goOne( x int ) int { return x + 1 }
func goTwo( x int ) int { return x + 2 }
func goThree( x int ) int { return x + 3 }
EOF

( cd "$CORPUS" && git init -q . && git add -A && git -c user.email=gate@example.invalid -c user.name=gate commit -qm init ) \
  || { echo "langcensuscheck: could not create the corpus git repo"; exit 2; }

OUT="$( "$BIN" "$CORPUS" --skipped --no-cache 2>/dev/null )"
[ -n "$OUT" ] || { echo "langcensuscheck: --skipped produced no output"; exit 2; }

rowOf(){ printf '%s' "$OUT" | grep -o "<lang n=\"$1\"[^/]*/>" | head -1; }
fieldOf(){ printf '%s' "$1" | sed -n "s/.*$2=\"\([0-9]*\)\".*/\1/p"; }

# ── arm 1: exact counts, per language ────────────────────────────────────────────────────────────────
check(){
    local lang="$1" wantFiles="$2" wantSyms="$3"
    local row; row="$( rowOf "$lang" )"
    if [ -z "$row" ]; then no "arm1: no <lang n=\"$lang\"> row at all (want files=$wantFiles symbols=$wantSyms)"; return; fi
    local gotFiles gotSyms; gotFiles="$( fieldOf "$row" files )"; gotSyms="$( fieldOf "$row" symbols )"
    if [ "$gotFiles" = "$wantFiles" ] && [ "$gotSyms" = "$wantSyms" ]; then
        ok "arm1: $lang files=$gotFiles symbols=$gotSyms (exact)"
    else
        no "arm1: $lang files=$gotFiles symbols=$gotSyms (want files=$wantFiles symbols=$wantSyms) — $row"
    fi
}
check py 3 6
check rs 2 2
check rb 2 2
check go 1 3

# ── arm 2: absent-means-none — languages with ZERO files in the fixture get NO row, never a zero ───────
for lang in cpp c java swift cs toml yaml json ts; do
    if [ -z "$( rowOf "$lang" )" ]; then
        ok "arm2: $lang has no <lang> row (absent, not a printed zero — correct, it never appeared)"
    else
        no "arm2: $lang has a <lang> row despite zero files/symbols in this fixture — $( rowOf "$lang" )"
    fi
done

# ── arm 3: deterministic sort — files DESC, name ASC tiebreak (py=3, then rb before rs at the 2-file
#    tie, then go=1 last) ─────────────────────────────────────────────────────────────────────────────
ORDER="$( printf '%s' "$OUT" | grep -o '<lang n="[a-z]*"' | sed 's/<lang n="//;s/"//' | tr '\n' ',' )"
case "$ORDER" in
    py,rb,rs,go,*) ok "arm3: sort order is py,rb,rs,go,... (files DESC, name ASC tiebreak) — full order: $ORDER" ;;
    *)             no "arm3: sort order is $ORDER (want py,rb,rs,go,... — files DESC, \"rb\"<\"rs\" tiebreak at the 2-file tie)" ;;
esac

# ── arm 4: well-formed + deterministic ──────────────────────────────────────────────────────────────
printf '%s' "$OUT" | xmllint --noout - 2>/dev/null && ok "arm4: --skipped with <lang> rows is well-formed (G4)" || no "arm4: not well-formed XML"
OUT2="$( "$BIN" "$CORPUS" --skipped --no-cache 2>/dev/null )"
[ "$OUT" = "$OUT2" ] && ok "arm4: output is byte-identical run-to-run" || no "arm4: output is not deterministic"

# ── arm 5: symbols= is never LESS than any single file's count could suggest — a sanity floor, not a
#    tight bound: every language row that exists has symbols >= files (each fixture file here has >=1
#    def), catching a swapped files=/symbols= pair (an easy transcription bug in a two-number row).
allok=1
for lang in py rs rb go; do
    row="$( rowOf "$lang" )"; f="$( fieldOf "$row" files )"; s="$( fieldOf "$row" symbols )"
    if [ "$s" -lt "$f" ] 2>/dev/null; then no "arm5: $lang symbols=$s < files=$f (looks swapped)"; allok=0; fi
done
[ "$allok" = 1 ] && ok "arm5: no row has symbols < files (files=/symbols= are not transposed)"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1
