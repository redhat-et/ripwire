#!/usr/bin/env bash
# lexicalnoskipcheck.sh — LARGE-PARTIAL-1: the LEXICAL readers read every file and blob, whatever its size.
#
# THE DEFECT (LARGE-PARTIAL Stage 0, 2026-11-14). --whereis read git blobs only up to 2 MiB (crossref kMaxBlobBytes) and
# skipped larger ones without a word: vscode `--whereis=withChatOverrides` answered on-head="0" hits="0" while --callers found
# the definition (in a 2.36 MB test file) and 39 callers. --grep skipped the files the crawl dropped over its size ceiling
# (corpus_oversize=) and still printed complete="1": vscode `--grep=NodeLinks` said hits="0" with the word in an 8 MB file.
# --stray-content reported a branch's change to a large file as diffable="0", none of its lines counted. Owner rule
# (2026-11-14): lexical readers skip nothing; a large input is read in line-aligned pieces in bounded memory
# (src/infra/pieceread.h). The crawl's PARSE ceiling is not this gate's subject (a sibling lane indexes oversize files).
#
# Every fixture is generated here, in a temp dir, so no whole-repo run ever sees a multi-MB file (PRODUCER rule 12).
#   A  whereis: a definition in a 5.8 MB tracked file (HEAD) is a row on its true line; on-head="1"
#   B  whereis: a name inside one 3 MB LINE (cut mid-line by the piece reader) is exactly one row, on that line
#   C  whereis: a name only a branch's 5.8 MB blob holds is a row of that branch
#   D  whereis: a DIRTY 5.8 MB working copy is read (worktree="read", the new name a ref="worktree" row)
#   E  grep: a word in an oversize (crawl-dropped) file is an unindexed hit on its true line
#   F  grep: three occurrences in one 3 MB line fold to one row with occ="3" (no double count across the cut's overlap)
#   G  stray-content: a branch's added line in the 5.8 MB file is counted (stray="1"), never diffable="0"
# Premise arms (P*) count what the fixture holds and FAIL on zero, so no arm passes vacuously.
#
# RED-FIRST (fade32332): A2, B, C, D1, D2, E, F and G fail; the P arms and A1 (caller.c names it) hold on both binaries.
#
# Usage:  bash test/lexicalnoskipcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "lexicalnoskipcheck: BIN=$BIN"

FIX="$( mktemp -d )"; trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"; mkdir -p "$R"
python3 - "$R" <<'EOF'
import sys
r = sys.argv[1]
lines = [f"int filler_{i}( int x ) {{ return x + {i}; }}" for i in range(60000)]
lines.append("int deep_target_fn( int y ) { return y * 2; }")                       # line 60001
lines.append("static const char* blob_line = \"" + "a" * 1500000 + " LongLineNeedle " + "b" * 1500000 + "\";")   # line 60002
lines.append("static const char* trio = \"" + ( "c" * 1000000 + " TrioWord " ) * 3 + "\";")                   # line 60003
open(f"{r}/huge.c", "w").write("\n".join(lines) + "\n")
open(f"{r}/caller.c", "w").write("int deep_target_fn( int y );\nint use( void ) { return deep_target_fn( 3 ); }\n")
pad = "const pad = '" + "z" * 80 + "';\n"
open(f"{r}/data.ts", "w").write("export const x = 1;\n" * 10 + "// NodeLinksMarker here\n" + pad * 70000)   # marker on line 11
EOF
g(){ git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
g init -q -b main && g add -A && g commit -qm init
g checkout -qb feat/big && echo "int branch_only_fn( int z ) { return z - 1; }" >> "$R/huge.c" && g commit -qam branch && g checkout -q main

run(){ ( cd "$R" && "$BIN" . "$@" --no-cache 2>/dev/null ); }
root(){ sed 's/<!--[^>]*-->//g' | grep -o "<$1 [^>]*>" | head -1; }

# ── premises ─────────────────────────────────────────────────────────────────────────────────────────────
hb=$( wc -c < "$R/huge.c" ); db=$( wc -c < "$R/data.ts" )
[ "$hb" -gt 4194304 ] \
    && ok "P1 huge.c is $hb bytes, past the 2 MiB blob read size and the 4 MiB crawl ceiling" \
    || no "P1 huge.c is only $hb bytes"
[ "$db" -gt 4194304 ] \
    && ok "P2 data.ts is $db bytes" \
    || no "P2 data.ts is only $db bytes"
ov=$( run --grep=NodeLinksMarker | root grep | grep -o 'corpus_oversize="[0-9]*"' )
[ -n "$ov" ] \
    && ok "P3 the crawl dropped the large files ($ov), so E/F test the oversize path" \
    || no "P3 no corpus_oversize= — the grep arms would prove nothing"

# ── whereis ──────────────────────────────────────────────────────────────────────────────────────────────
out=$( run --whereis=deep_target_fn --whereis-listing=all )
r=$( printf '%s' "$out" | root whereis )
printf '%s' "$r" | grep -q 'on-head="1"' \
    && ok "A1 on-head=1" \
    || no "A1 on-head is not 1: $r"
printf '%s' "$out" | grep -q '<hit ref="HEAD" p="huge.c" l="60001"' \
    && ok "A2 HEAD row in huge.c at l=60001" \
    || no "A2 no HEAD row for huge.c:60001"

out=$( run --whereis=LongLineNeedle --whereis-listing=all )
n=$( printf '%s' "$out" | grep -o '<hit ref="HEAD" p="huge.c" l="60002"' | wc -l | tr -d ' ' )
[ "$n" = "1" ] \
    && ok "B one HEAD row for the needle inside a 3 MB line (l=60002)" \
    || no "B $n HEAD rows for the 3 MB line's needle (want 1)"

out=$( run --whereis=branch_only_fn --whereis-listing=all )
printf '%s' "$out" | grep -q '<hit ref="feat/big"[^>]*p="huge.c" l="60004"' && ok "C the branch's large blob holds branch_only_fn at l=60004" \
    || no "C no feat/big row for branch_only_fn: $( printf '%s' "$out" | root whereis )"

echo "int dirty_only_fn( void ) { return 0; }" >> "$R/huge.c"
out=$( run --whereis=dirty_only_fn --whereis-listing=all )
r=$( printf '%s' "$out" | root whereis )
printf '%s' "$r" | grep -q 'worktree="read"' \
    && ok "D1 worktree=read over a 5.8 MB dirty copy" \
    || no "D1 not worktree=read: $r"
printf '%s' "$out" | grep -q '<hit ref="worktree"[^>]*p="huge.c" l="60004"' \
    && ok "D2 the dirty copy's new line is a worktree row" \
    || no "D2 no worktree row for dirty_only_fn"
g checkout -q -- huge.c

# ── grep ─────────────────────────────────────────────────────────────────────────────────────────────────
out=$( run --grep=NodeLinksMarker )
printf '%s' "$out" | grep -q 'unindexed_hits="1"' && printf '%s' "$out" | grep -q '<hit l="11"' \
    && ok "E the oversize data.ts holds NodeLinksMarker at l=11 (unindexed)" \
    || no "E no unindexed hit at data.ts:11: $( printf '%s' "$out" | root grep )"

out=$( run --grep=TrioWord )
printf '%s' "$out" | grep -q '<hit l="60003" [^>]*occ="3"' && ok "F three occurrences on one 3 MB line: one row, occ=3" \
    || no "F want one row l=60003 occ=3: $( printf '%s' "$out" | grep -o '<hit l="60003"[^>]*>' | head -3 | tr '\n' ' ' )"

# ── stray-content ────────────────────────────────────────────────────────────────────────────────────────
out=$( run --stray-content )
row=$( printf '%s' "$out" | grep -o '<file p="huge.c"[^>]*>' | head -1 )
printf '%s' "$row" | grep -q 'stray="1"' && ! printf '%s' "$row" | grep -q 'diffable="0"' \
    && ok "G the branch's line added to the 5.8 MB file is counted: $row" \
    || no "G huge.c row not counted: ${row:-<none>}"

[ "$fail" = 0 ] && echo "lexicalnoskipcheck: PASS" || echo "lexicalnoskipcheck: FAILURES ABOVE"
exit $fail
