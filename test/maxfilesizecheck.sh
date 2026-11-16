#!/usr/bin/env bash
# maxfilesizecheck.sh — §P0.5d gate, rewritten for NO-SKIP-INGEST (2026-11-14): --max-file-size must not silently
# shrink the corpus — and since NO-SKIP-INGEST it does not shrink it at all.
#
#   --max-file-size=8K  ->  files=463 of ~759, no skipped= anywhere       (before §P0.5d)
#   --max-file-size=8K  ->  files=463 + skipped_oversize=296              (§P0.5d: dropped, but counted)
#   --max-file-size=8K  ->  files=759 + lexical_files=296                 (NO-SKIP-INGEST: read lexically, not dropped)
#
# Invariants pinned:
#   1. a file over the ceiling is INDEXED (files= does not move) and disclosed — lexical_files=N on the header;
#   2. when nothing is over a ceiling, the attribute is ABSENT, so a default run stays byte-identical (the
#      house rule: absent = nothing happened);
#   3. the .json lane's 256 KB ceiling no longer drops a file either: such a file is indexed with bounded keys
#      (why="keys-bounded"), counted in the same lexical_files=, in both dialects.
#
#   RIPWIRE_BIN=build/ripwire      bash test/maxfilesizecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "maxfilesizecheck: BIN=$BIN  ROOT=$ROOT"

hdrnum(){ grep -oE "<!-- [^>]*$2=[0-9]+" "$1" | head -1 | grep -oE "(^| )$2=[0-9]+" | grep -oE '[0-9]+'; }

# ── 1. a low ceiling reads files lexically and MUST disclose how many — and drop none
"$BIN" "$ROOT" --max-file-size=8K --top-k=3 >"$TMP/small" 2>"$TMP/small.err"   # status: the map exits 0 on any corpus; the header counts and rows read here are the verdict, and a missing one FAILs
LEX="$( hdrnum "$TMP/small" lexical_files )"
[ "${LEX:-0}" -gt 200 ] && ok "--max-file-size=8K header carries lexical_files=$LEX (> 200, the expected order of magnitude)" \
    || no "--max-file-size=8K lexical_files=${LEX:-<none>} (header: $( grep -oE '<!-- files=[^>]*' "$TMP/small" | head -1 ))"
grep -q 'skipped_oversize=' "$TMP/small" && no "--max-file-size=8K still drops files (skipped_oversize= on the header)" \
    || ok "--max-file-size=8K drops nothing (no skipped_oversize=)"
FILES_SMALL="$( hdrnum "$TMP/small" files )"
"$BIN" "$ROOT" --top-k=3 >"$TMP/full" 2>/dev/null
FILES_FULL="$( hdrnum "$TMP/full" files )"
[ -n "${FILES_SMALL:-}" ] && [ "${FILES_SMALL:-0}" = "${FILES_FULL:-x}" ] \
    && ok "files= is the same under the ceiling ($FILES_SMALL = $FILES_FULL): every file is indexed" \
    || no "files= moved under --max-file-size=8K ($FILES_SMALL vs $FILES_FULL)"
grep -q '^ripwire: warning: .* exceeds --max-file-size 8.0 KiB; indexed lexically' "$TMP/small.err" \
    && ok "stderr warns, naming the flag" || no "no stderr warning under --max-file-size=8K: $( head -1 "$TMP/small.err" )"

# ── 2. nothing over a ceiling ⇒ attribute ABSENT (byte-identity of every default run depends on this)
"$BIN" "$ROOT/test/fixture" --top-k=3 >"$TMP/fixture" 2>/dev/null
grep -qE 'skipped_oversize=|lexical_files=' "$TMP/fixture" \
    && no "test/fixture run leaked skipped_oversize=/lexical_files= with nothing over a ceiling (breaks golden byte-identity)" \
    || ok "test/fixture run has NO skipped_oversize=/lexical_files= (absent = nothing happened)"
"$BIN" "$ROOT/test/fixture" --max-file-size=64M --top-k=3 >"$TMP/big" 2>/dev/null
grep -qE 'skipped_oversize=|lexical_files=' "$TMP/big" \
    && no "--max-file-size=64M on test/fixture leaked a lexical/oversize attribute" \
    || ok "--max-file-size=64M on test/fixture has no lexical/oversize attribute (nothing that large in the tree)"

# ── 4. the .json lane's 256 KB ceiling indexes with bounded keys, and nothing drops at any setting ──────────
# files= is the SAME population at every --max-file-size setting (nothing is dropped below the 1 GiB hard limit), and
# the JSON-lane files past the ceiling are rowed why="keys-bounded" at every setting. Derived, never hardcoded.
filesAt(){ "$BIN" "$ROOT" $1 --top-k=1 >"$TMP/at" 2>/dev/null; hdrnum "$TMP/at" files; }   # status: the map exits 0 on any corpus; the header counts and rows read here are the verdict, and a missing one FAILs
F64K="$( filesAt --max-file-size=64K )"; F1M="$( filesAt --max-file-size=1M )"; FDEF="$( filesAt '' )"
[ "${F64K:-0}" -gt 0 ] && [ "$F64K" = "$F1M" ] && [ "$F64K" = "$FDEF" ] \
    && ok "files= = $FDEF at 64K/1M/default alike (no ceiling drops a file)" \
    || no "files= moves with the ceiling: 64K=$F64K 1M=$F1M default=$FDEF"
# The premise: this tree HAS a .json past the JSON-lane ceiling (git ls-files: the tool's own population).
BIGJSON="$( cd "$ROOT" && git ls-files -z '*.json' | xargs -0 -I{} sh -c 'test $(wc -c <"{}") -gt 262144 && echo {}' 2>/dev/null | wc -l | tr -d ' ' )"
[ "${BIGJSON:-0}" -ge 1 ] \
    && ok "premise holds: $BIGJSON .json over the 256 KB JSON-lane ceiling exist in this tree" \
    || no "premise FAILED: no >256K .json in the tree — the keys-bounded arm below cannot discriminate"
"$BIN" "$ROOT" --max-file-size=1M --skipped 2>/dev/null | tr '>' '\n' >"$TMP/sk1m"   # status: the map exits 0 on any corpus; the header counts and rows read here are the verdict, and a missing one FAILs
JSONROWS="$( grep 'why="keys-bounded"' "$TMP/sk1m" | grep -c '\.json"' | tr -d ' ' )"
SIZEROWS="$( grep -c 'why="lexical-size"' "$TMP/sk1m" | tr -d ' ' )"
[ "${JSONROWS:-0}" = "${BIGJSON:-0}" ] \
    && ok "--max-file-size=1M rows the $BIGJSON big .json why=keys-bounded, one row each" \
    || no "--max-file-size=1M rows $JSONROWS keys-bounded .json, expected $BIGJSON"
UNDER=0
while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ "$( wc -c <"$ROOT/$p" | tr -d ' ' )" -gt 1048576 ] || UNDER=$(( UNDER + 1 ))
done <<EOF_ROWS
$( grep 'why="lexical-size"' "$TMP/sk1m" | grep -oE ' p="[^"]+"' | sed 's/ p="//;s/"$//' )
EOF_ROWS
[ "$UNDER" = 0 ] \
    && ok "every lexical-size row at 1M ($SIZEROWS) names a file really over 1,048,576 B (a ceiling never fires under it)" \
    || no "$UNDER lexical-size row(s) at 1M name files UNDER the ceiling"
LEX1M="$( "$BIN" "$ROOT" --max-file-size=1M --top-k=1 2>/dev/null | grep -oE ' lexical_files=[0-9]+' | head -1 | grep -oE '[0-9]+' )"   # status: the map exits 0 on any corpus; the header counts and rows read here are the verdict, and a missing one FAILs
ALLLEX="$( grep -cE 'why="(lexical-size|lexical-budget|keys-bounded)"' "$TMP/sk1m" | tr -d ' ' )"
[ "${LEX1M:-0}" = "${ALLLEX:-x}" ] \
    && ok "lexical_files=$LEX1M equals the rows itemized ($ALLLEX)" \
    || no "lexical_files=${LEX1M:-<absent>} disagrees with the $ALLLEX itemized rows"

# ── 3. still valid XML and still deterministic under the ceiling
"$BIN" "$ROOT" --max-file-size=8K --top-k=3 >"$TMP/d1" 2>/dev/null
"$BIN" "$ROOT" --max-file-size=8K --top-k=3 >"$TMP/d2" 2>/dev/null
if diff -q "$TMP/d1" "$TMP/d2" >/dev/null; then ok "deterministic under --max-file-size"; else no "non-deterministic under --max-file-size"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/small" >/dev/null 2>&1; then ok "output is well-formed XML (G4)"; else no "output is not well-formed XML"; fi
fi

# ── adversarial-round extension: the disclosure must reach --json consumers too ──────────────────────
# The JSON header is built separately from the XML one; §P0.5d's first landing covered only XML, so an
# MCP/json reader was still shown the survivors as if they were the corpus.
"$BIN" "$ROOT" --max-file-size=8K --json --top-k=3 >"$TMP/jlex.json" 2>/dev/null   # status: --json exits 0 on any corpus; the lexical_files key read next is the verdict and ABSENT FAILs
jlex="$( python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("lexical_files","ABSENT"))' <"$TMP/jlex.json" )"
case "$jlex" in
    ABSENT ) no "--json at 8K carries no lexical_files key (JSON reader gets zero disclosure)" ;;
    0 ) no "--json at 8K says lexical_files=0 — a false zero" ;;
    * ) ok "--json at 8K discloses lexical_files=$jlex" ;;
esac
jdef="$( "$BIN" "$ROOT/test/fixture" --json --top-k=3 2>/dev/null \
         | python3 -c 'import json,sys; d=json.load(sys.stdin); print("present" if ("skipped_oversize" in d or "lexical_files" in d) else "absent")' )"
[ "$jdef" = "absent" ] && ok "--json on test/fixture omits skipped_oversize/lexical_files (absent = nothing happened)" \
                       || no "--json on test/fixture unexpectedly carries skipped_oversize/lexical_files"
# the two dialects report ONE population on the default run
"$BIN" "$ROOT" --json --top-k=1 >"$TMP/jroot.json" 2>/dev/null   # status: --json exits 0 on any corpus; the lexical_files key read next is the verdict and ABSENT FAILs
jroot="$( python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("lexical_files","ABSENT"))' <"$TMP/jroot.json" )"
xroot="$( hdrnum "$TMP/full" lexical_files )"
[ "$jroot" = "${xroot:-ABSENT}" ] \
    && ok "--json default run on \$ROOT says lexical_files=$jroot, same as XML" \
    || no "--json default run says lexical_files=$jroot, XML says ${xroot:-ABSENT} — the two dialects disagree"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
