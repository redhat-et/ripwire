#!/usr/bin/env bash
# noskipingestcheck.sh — NO-SKIP-INGEST (owner 2026-11-14: "we should not be skipping files"; "make that much bigger
# and print a warning to the user whenever the limit is found").
#
# Until this lane a file over 4 MB (--max-file-size), a .json over 256 KB or a .yml over 512 KB was SKIPPED: absent
# from the index, its symbols unreachable (--callers=huge_target count=0 beside ~110k call sites in the skipped file,
# --callees=filler_7 found nothing), with only the map's skipped_oversize= to say so. Now every crawled file is indexed:
#   * a file over --max-file-size (default 64 MiB) is read LEXICALLY (definitions by line shape, calls by `name(`);
#   * a parse past its budget (4 s + 1 s/MiB, RIPWIRE_PARSE_BUDGET scales it) is cancelled and read lexically;
#   * a .json/.yml past its full-index ceiling yields at most 256 keys (RIPWIRE_DATA_KEYS raises it), keys_cut= the rest;
# and each such file is disclosed in the answer (lexical_files= / keys_cut= / graph_lexical= / --skipped <h> rows) and
# WARNED once on stderr — never on stdout. Every arm builds its own fixture at test time (nothing large is committed
# where whole-repo runs would see it). Negative arms count what they saw and FAIL on zero.
#
#   bash test/noskipingestcheck.sh [BIN]     # main d624cff5f FAILS arms 1-5 (the files are skipped; arm 2 hits its alarm)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "noskipingestcheck: BIN=$BIN"

hdr(){ grep -oE '<!-- files=[^>]*-->' "$1" | head -1; }
attr(){ grep -oE "$2=\"?[0-9]+" "$1" | head -1 | grep -oE '[0-9]+$'; }
warns(){ grep -c '^ripwire: warning: ' "$1"; }

# ── fixtures, generated here ────────────────────────────────────────────────────────────────────────────────────────
python3 - "$TMP" <<'EOF'
import json, os, sys
t = sys.argv[1]
def w(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write(s)
# 1. a 5 MiB C file: 40k+ functions that each call huge_target, plus a small caller of filler_7
parts, n, i = [], 0, 0
while n < 5 * 1024 * 1024:
    f = f"int filler_{i}(int x)\n{{\n    int a = huge_target(x);\n    return a + {i};\n}}\n\n"
    parts.append(f); n += len(f); i += 1
w(f"{t}/c5/big.c", "int huge_target(int x);\n" + "".join(parts))
w(f"{t}/c5/caller.c", "int filler_7(int x);\nint huge_target(int x)\n{\n    return x + 1;\n}\nint main(void)\n{\n    return filler_7(3);\n}\n")
# 2. a degenerate C file (1 MiB of '{'): tree-sitter's error recovery is quadratic on it
w(f"{t}/patho/deep.c", "void deep_entry(void)\n{\n}\n" + "{" * (1024 * 1024))
# 3. a 3 MiB JSON data file and a 1 MiB YAML one, past their full-index ceilings
d, i = {}, 0
while True:
    d[f"record_{i}"] = {"id": i, "name": f"n{i}", "nested": {"x": 1}}
    i += 1
    if i % 1000 == 0 and len(json.dumps(d, indent=2)) > 3 * 1024 * 1024:
        break
w(f"{t}/json3/data.json", json.dumps(d, indent=2))
y, i = [], 0
while sum(map(len, y)) < 1024 * 1024:
    y.append(f"item_{i}:\n  id: {i}\n  label: thing {i}\n"); i += 1
w(f"{t}/yaml1/big.yaml", "".join(y))
# 4. seven data files past the ceiling: the warning collapses after five lines
for k in range(7):
    w(f"{t}/many/d{k}.json", json.dumps({f"k{k}_{j}": {"v": j} for j in range(9000)}, indent=2))
# 5. the negative corpus: small code and config, nothing near any limit
w(f"{t}/small/a.c", "int f(void)\n{\n    return g();\n}\nint g(void)\n{\n    return 1;\n}\n")
w(f"{t}/small/cfg.json", json.dumps({"name": "x", "scripts": {"build": "make"}}, indent=2))
w(f"{t}/small/c.yaml", "top:\n  inner: 1\n")
EOF

# ── 1. a code file over --max-file-size is read lexically, its symbols and calls reachable ───────────────────────────
"$BIN" "$TMP/c5" --no-cache --max-file-size=1M --legend=compact >"$TMP/1.map" 2>"$TMP/1.err"
lex="$( attr "$TMP/1.map" lexical_files )"
[ "${lex:-0}" = 1 ] && ok "1: --max-file-size=1M map: lexical_files=1 ($( hdr "$TMP/1.map" ))" || no "1: no lexical_files=1 ($( hdr "$TMP/1.map" ))"
grep -q 'skipped_oversize=' "$TMP/1.map" && no "1: skipped_oversize= still on the map (the file was dropped)" || ok "1: nothing dropped (no skipped_oversize=)"
"$BIN" "$TMP/c5" --no-cache --max-file-size=1M --callers=huge_target --legend=compact >"$TMP/1.callers" 2>/dev/null
c="$( grep -oE '<callers [^>]*' "$TMP/1.callers" | grep -oE ' count="[0-9]+' | grep -oE '[0-9]+' )"
[ "${c:-0}" -ge 1000 ] && ok "1: --callers=huge_target count=$c (lexical call sites reach it)" || no "1: --callers=huge_target count=${c:-none}"
grep -q 'graph_lexical="1"' "$TMP/1.callers" && ok "1: --callers root carries graph_lexical=\"1\"" || no "1: --callers root lacks graph_lexical="
"$BIN" "$TMP/c5" --no-cache --max-file-size=1M --callees=filler_7 --legend=compact >"$TMP/1.callees" 2>/dev/null
grep -qE '<callees [^>]* count="[1-9]' "$TMP/1.callees" && ok "1: --callees=filler_7 finds huge_target" || no "1: --callees=filler_7: $( grep -oE '<callees [^>]*' "$TMP/1.callees" )"
n="$( grep -c 'exceeds --max-file-size 1.0 MiB; indexed lexically (raise with --max-file-size=N)' "$TMP/1.err" )"
[ "$n" = 1 ] && ok "1: exactly one stderr warning naming the limit and the flag" || no "1: $n warnings ($( head -3 "$TMP/1.err" ))"
grep -q 'ripwire: warning' "$TMP/1.map" && no "1: a warning reached stdout" || ok "1: stdout carries no warning"
"$BIN" "$TMP/c5" --no-cache --max-file-size=1M --skipped >"$TMP/1.sk" 2>/dev/null
grep -qE '<h p="[^"]*big\.c" why="lexical-size"' "$TMP/1.sk" && ok "1: --skipped rows big.c why=lexical-size" || no "1: no lexical-size row in --skipped"
# the default ceiling (64 MiB) parses it: no lexical read, no warning (negative arm: the map was seen)
"$BIN" "$TMP/c5" --no-cache --legend=compact >"$TMP/1d.map" 2>"$TMP/1d.err"
files="$( attr "$TMP/1d.map" files )"
if [ "${files:-0}" = 2 ]; then
    grep -q 'lexical_files=' "$TMP/1d.map" && no "1: the default run read big.c lexically" || ok "1: default 64 MiB ceiling parses the 5 MiB file (files=2, no lexical_files=)"
    [ "$( warns "$TMP/1d.err" )" = 0 ] && ok "1: default run printed no warning (saw files=$files)" || no "1: default run warned: $( head -2 "$TMP/1d.err" )"
else
    no "1: default run saw files=${files:-none}, expected 2"
fi

# ── 2. a degenerate file runs past its parse budget, is cancelled and read lexically, in bounded time ─────────────
t0=$( date +%s )
# perl's alarm bounds the arm: a binary without the budget parses this for many minutes (quadratic), and must FAIL, not hang
RIPWIRE_PARSE_BUDGET=0.25 perl -e 'alarm 90; exec @ARGV' "$BIN" "$TMP/patho" --no-cache --legend=compact >"$TMP/2.map" 2>"$TMP/2.err"
t1=$( date +%s )
[ $(( t1 - t0 )) -le 60 ] && ok "2: degenerate 1 MiB file finished in $(( t1 - t0 )) s (main: quadratic, minutes)" || no "2: took $(( t1 - t0 )) s"
[ "$( attr "$TMP/2.map" lexical_files )" = 1 ] && ok "2: lexical_files=1" || no "2: $( hdr "$TMP/2.map" )"
grep -q 'ran past its parse budget of .* s; indexed lexically (raise with RIPWIRE_PARSE_BUDGET=<scale>)' "$TMP/2.err" \
    && ok "2: the budget warning names the knob" || no "2: no budget warning ($( head -2 "$TMP/2.err" ))"
grep -q 'n="deep_entry"' "$TMP/2.map" && ok "2: deep_entry still indexed (lexical definition)" || no "2: deep_entry missing"
RIPWIRE_PARSE_BUDGET=0.25 perl -e 'alarm 90; exec @ARGV' "$BIN" "$TMP/patho" --no-cache --skipped >"$TMP/2.sk" 2>/dev/null
grep -q 'why="lexical-budget"' "$TMP/2.sk" && ok "2: --skipped rows it why=lexical-budget" || no "2: no lexical-budget row"

# ── 3. data files past the ceiling: bounded keys, disclosed, raisable ─────────────────────────────────────────────
for d in json3 yaml1; do
    "$BIN" "$TMP/$d" --no-cache --legend=compact >"$TMP/3$d.map" 2>"$TMP/3$d.err"
    sy="$( attr "$TMP/3$d.map" symbols )"; cut="$( attr "$TMP/3$d.map" keys_cut )"
    [ "${sy:-0}" = 256 ] && [ "${cut:-0}" -gt 1000 ] && ok "3: $d symbols=256 keys_cut=$cut" || no "3: $d $( hdr "$TMP/3$d.map" )"
    grep -q 'full-index ceiling .* cut at 256 (raise with RIPWIRE_DATA_KEYS=N)' "$TMP/3$d.err" && ok "3: $d warning names the cap and the knob" || no "3: $d warning: $( head -1 "$TMP/3$d.err" )"
done
RIPWIRE_DATA_KEYS=1000 "$BIN" "$TMP/json3" --no-cache --legend=compact >"$TMP/3r.map" 2>/dev/null
[ "$( attr "$TMP/3r.map" symbols )" = 1000 ] && ok "3: RIPWIRE_DATA_KEYS=1000 raises it to 1000 keys" || no "3: raised: $( hdr "$TMP/3r.map" )"
grep -q 'n="record_0"' "$TMP/3json3.map" && ok "3: the first top-level key is a symbol" || no "3: record_0 missing"

# ── 4. warm runs keep the mode and the warning; a changed ceiling re-extracts ────────────────────────────────────────
C="$TMP/c5.cache"
"$BIN" "$TMP/c5" --cache="$C" --max-file-size=1M --legend=compact >"$TMP/4a" 2>"$TMP/4a.err"
"$BIN" "$TMP/c5" --cache="$C" --max-file-size=1M --legend=compact >"$TMP/4b" 2>"$TMP/4b.err"
cmp -s "$TMP/4a" "$TMP/4b" && [ "$( attr "$TMP/4b" lexical_files )" = 1 ] && ok "4: warm run byte-identical, lexical_files=1 kept" || no "4: warm differs or lost the mode"
[ "$( warns "$TMP/4b.err" )" = 1 ] && ok "4: the warm run warns again" || no "4: warm warnings: $( warns "$TMP/4b.err" )"
"$BIN" "$TMP/c5" --cache="$C" --legend=compact >"$TMP/4c" 2>"$TMP/4c.err"
"$BIN" "$TMP/c5" --no-cache --legend=compact >"$TMP/4d" 2>/dev/null
cmp -s "$TMP/4c" "$TMP/4d" && ok "4: warm run at the default ceiling equals the cold one (the lexical record was re-extracted)" || no "4: stale lexical record reused at the default ceiling"

# ── 5. the warning collapses after five lines ───────────────────────────────────────────────────────────────────────
"$BIN" "$TMP/many" --no-cache --legend=compact >"$TMP/5.map" 2>"$TMP/5.err"
[ "$( warns "$TMP/5.err" )" = 6 ] && grep -q 'and 2 more file(s) met an index limit' "$TMP/5.err" \
    && ok "5: seven events → five lines + 'and 2 more'" || no "5: $( warns "$TMP/5.err" ) warning lines: $( tail -1 "$TMP/5.err" )"
[ "$( attr "$TMP/5.map" lexical_files )" = 7 ] && ok "5: lexical_files=7 (every file disclosed in the answer)" || no "5: $( hdr "$TMP/5.map" )"

# ── 6. negative arm: a small corpus meets no limit — no warning, no attribute (counts what it saw) ─────────────────
"$BIN" "$TMP/small" --no-cache --legend=compact >"$TMP/6.map" 2>"$TMP/6.err"
"$BIN" "$TMP/small" --no-cache --callers=g --legend=compact >"$TMP/6.callers" 2>>"$TMP/6.err"
files="$( attr "$TMP/6.map" files )"; sy="$( attr "$TMP/6.map" symbols )"
if [ "${files:-0}" -ge 3 ] && [ "${sy:-0}" -ge 3 ]; then
    [ "$( warns "$TMP/6.err" )" = 0 ] && ok "6: no warning on a corpus under every limit (saw files=$files symbols=$sy)" || no "6: warned: $( head -1 "$TMP/6.err" )"
    grep -qE 'lexical_files=|keys_cut=|graph_lexical=' "$TMP/6.map" "$TMP/6.callers" && no "6: a lexical attribute with nothing lexical" || ok "6: no lexical attribute anywhere"
else
    no "6: the negative corpus was not seen (files=${files:-none} symbols=${sy:-none})"
fi

[ "$fail" = 0 ] && echo "noskipingestcheck: PASS" || echo "noskipingestcheck: FAIL"
exit "$fail"
