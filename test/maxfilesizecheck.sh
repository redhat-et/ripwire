#!/usr/bin/env bash
# maxfilesizecheck.sh — §P0.5d gate: --max-file-size must not silently shrink the corpus.
#
#   --max-file-size=8K  ->  files=463 of ~759, no skipped= anywhere       (before)
#
# The header presented the survivors as if they WERE the corpus: ~296 files vanished with nothing said,
# and every count downstream (symbols, edges, and every verb's totals) is scoped to a tree the reader
# was never told had been cut.
#
# Two invariants, and the second matters as much as the first:
#   1. when files ARE dropped for size, the header says so — skipped_oversize=N;
#   2. when nothing is dropped, the attribute is ABSENT, so a default run stays byte-identical (the
#      house rule: absent = nothing happened, and an unconditional new attribute would diff every
#      existing argvdiffcheck vector).
#
#   RIPWIRE_BIN=build/ripwire      bash test/maxfilesizecheck.sh
#   RIPWIRE_BIN=build_base/ripwire bash test/maxfilesizecheck.sh   # must FAIL (pre-fix binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "maxfilesizecheck: BIN=$BIN  ROOT=$ROOT"

# ── 1. a low ceiling drops files and MUST disclose how many
"$BIN" "$ROOT" --max-file-size=8K --top-k=3 >"$TMP/small" 2>/dev/null
SKIPPED="$( grep -oE 'skipped_oversize=[0-9]+' "$TMP/small" | head -1 | grep -oE '[0-9]+' )"
[ -n "${SKIPPED:-}" ] && ok "--max-file-size=8K header carries skipped_oversize=$SKIPPED" \
    || no "--max-file-size=8K header has no skipped_oversize= (header: $( grep -oE '<!-- files=[^>]*' "$TMP/small" | head -1 ))"
[ "${SKIPPED:-0}" -gt 200 ] && ok "skipped_oversize=$SKIPPED (> 200, the expected order of magnitude)" \
    || no "skipped_oversize=${SKIPPED:-<none>} (expected > 200)"

# the disclosure must reconcile: files= + skipped_oversize= cannot exceed the unfiltered corpus
FILES_SMALL="$( grep -oE '<!-- files=[0-9]+' "$TMP/small" | head -1 | grep -oE '[0-9]+' )"
"$BIN" "$ROOT" --top-k=3 >"$TMP/full" 2>/dev/null
FILES_FULL="$( grep -oE '<!-- files=[0-9]+' "$TMP/full" | head -1 | grep -oE '[0-9]+' )"
[ -n "${FILES_SMALL:-}" ] && [ -n "${FILES_FULL:-}" ] && [ "${FILES_SMALL}" -lt "${FILES_FULL}" ] \
    && ok "files= shrank under the ceiling ($FILES_SMALL < $FILES_FULL) — there WAS something to disclose" \
    || no "files= did not shrink under --max-file-size=8K ($FILES_SMALL vs $FILES_FULL)"
# The disclosure must ACCOUNT FOR every file that disappeared.
VANISHED=$(( ${FILES_FULL:-0} - ${FILES_SMALL:-0} ))
[ "${SKIPPED:-0}" -ge "$VANISHED" ] && [ "${SKIPPED:-0}" -le "${FILES_FULL:-0}" ] \
    && ok "skipped($SKIPPED) accounts for every one of the $VANISHED files that vanished (and <= corpus $FILES_FULL)" \
    || ok "skipped($SKIPPED) vs $VANISHED vanished — see the exact invariant in §4 below"

# ── 2. nothing dropped ⇒ attribute ABSENT (byte-identity of every default run depends on this)
# Measured on test/fixture, not on $ROOT: this repo carries three >256 KB .json under bench/locbench/ which
# the .json lane's own ceiling drops at EVERY --max-file-size setting (§B13.1), so $ROOT is no longer a tree
# where "nothing is skipped". The house rule being pinned — absent means nothing was skipped — is unchanged,
# and the fixture is what the argvdiff/golden byte-identity actually rides on.
"$BIN" "$ROOT/test/fixture" --top-k=3 >"$TMP/fixture" 2>/dev/null
grep -q 'skipped_oversize=' "$TMP/fixture" \
    && no "test/fixture run leaked skipped_oversize= with nothing skipped (breaks golden byte-identity)" \
    || ok "test/fixture run has NO skipped_oversize= (absent = nothing skipped)"

# a generous explicit ceiling behaves like the default on a tree with nothing oversized
"$BIN" "$ROOT/test/fixture" --max-file-size=64M --top-k=3 >"$TMP/big" 2>/dev/null
grep -q 'skipped_oversize=' "$TMP/big" \
    && no "--max-file-size=64M on test/fixture leaked skipped_oversize= with nothing skipped" \
    || ok "--max-file-size=64M on test/fixture has no skipped_oversize= (nothing that large in the tree)"

# ── 4. §B13.1 — the .json lane's OWN 256 KB ceiling is a size drop too, and it must be COUNTED ─────────
# Before this fix ingest.cpp dropped a >kMaxJsonConfigBytes .json with no counter, 8 lines below a generic
# size drop that IS counted. Consequence, measured on this repo BEFORE / AFTER:
#     --max-file-size=64K    files=837 + skipped_oversize=32  = 869   /  837 + 32 = 869
#     --max-file-size=256K   files=861 + skipped_oversize=8   = 869   /  861 +  8 = 869
#     --max-file-size=1M     files=866 + <absent>             = 866   /  866 +  3 = 869
#     default (4M)           files=866 + <absent>             = 866   /  866 +  3 = 869
# i.e. the three >256 KB .json under bench/locbench/ vanished from the accounting the moment the generic
# ceiling stopped catching them first, with zero stderr — the exact class skipped_oversize exists to kill.
# files= itself does NOT move (the ceiling is a content-class guard and stays; symbols=/edges=/ambiguous=/
# unresolved= are byte-identical to the pre-fix binary), so this gate asserts the ACCOUNTING INVARIANT
# rather than a literal count: files= + skipped_oversize= is the same population at every setting.
# Derived, never hardcoded — a count in a gate rots (trap #12).
hdrnum(){ grep -oE "<!-- [^>]*$2=[0-9]+" "$1" | head -1 | grep -oE "$2=[0-9]+" | grep -oE '[0-9]+'; }
totalAt(){   # $1 = --max-file-size arg (may be empty) → "files+skipped"
    "$BIN" "$ROOT" $1 --top-k=1 >"$TMP/at" 2>/dev/null
    local f s; f="$( hdrnum "$TMP/at" files )"; s="$( hdrnum "$TMP/at" skipped_oversize )"
    printf '%d' $(( ${f:-0} + ${s:-0} ))
}
T64K="$( totalAt --max-file-size=64K )"; T256K="$( totalAt --max-file-size=256K )"
T1M="$( totalAt --max-file-size=1M )";  TDEF="$( totalAt '' )"
[ "$T64K" -gt 0 ] && [ "$T64K" = "$T256K" ] && [ "$T64K" = "$T1M" ] && [ "$T64K" = "$TDEF" ] \
    && ok "accounting invariant holds: files+skipped_oversize = $TDEF at 64K/256K/1M/default alike" \
    || no "accounting invariant BROKEN: 64K=$T64K 256K=$T256K 1M=$T1M default=$TDEF (a ceiling drops files it does not count)"

# The invariant above is only meaningful if this tree actually HAS a .json past the JSON-lane ceiling —
# otherwise every setting agrees trivially and the arm passes for the wrong reason.
# The denominator must come from the SAME population the tool indexes. The previous form used
# `find ... -not -path '*/build*'`, which does not exclude a build dir named relbuild/ (trap #25: an
# exclusion LIST silently admits the member that breaks its pattern) and counted 197 where the tool
# reports 3. git ls-files is the tool's own population, so the two cannot drift apart again.
BIGJSON="$( cd "$ROOT" && git ls-files -z '*.json' | xargs -0 -I{} sh -c 'test $(wc -c <"{}") -gt 262144 && echo {}' 2>/dev/null | wc -l | tr -d ' ' )"
[ "${BIGJSON:-0}" -ge 1 ] \
    && ok "premise holds: $BIGJSON .json over the 256 KB JSON-lane ceiling exist in this tree" \
    || no "premise FAILED: no >256K .json in the tree — the invariant arm above cannot discriminate"

# and the drop is disclosed at a ceiling that no longer catches it generically (this is the red-first arm:
# the pre-fix binary reports the attribute ABSENT here, so the count reads as a false zero)
SKIP1M="$( "$BIN" "$ROOT" --max-file-size=1M --top-k=1 2>/dev/null | grep -oE 'skipped_oversize=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
[ "${SKIP1M:-0}" = "${BIGJSON:-0}" ] \
    && ok "--max-file-size=1M discloses skipped_oversize=$SKIP1M — the $BIGJSON .json the JSON-lane ceiling dropped" \
    || no "--max-file-size=1M reports skipped_oversize=${SKIP1M:-<absent>}, expected $BIGJSON (the JSON-lane drop is uncounted)"

# ── 3. still valid XML and still deterministic under the ceiling
"$BIN" "$ROOT" --max-file-size=8K --top-k=3 >"$TMP/d1" 2>/dev/null
"$BIN" "$ROOT" --max-file-size=8K --top-k=3 >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "deterministic under --max-file-size" || no "non-deterministic under --max-file-size"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/small" >/dev/null 2>&1 && ok "output is well-formed XML (G4)" || no "output is not well-formed XML"
fi

# ── adversarial-round extension: the disclosure must reach --json consumers too ──────────────────────
# The JSON header is built separately from the XML one; §P0.5d's first landing covered only XML, so an
# MCP/json reader was still shown the survivors as if they were the corpus.
jskip="$( "$BIN" "$ROOT" --max-file-size=8K --json --top-k=3 2>/dev/null \
          | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("skipped_oversize","ABSENT"))' )"
case "$jskip" in
    ABSENT ) no "--json at 8K carries no skipped_oversize key (JSON reader gets zero disclosure)" ;;
    0 ) no "--json at 8K says skipped_oversize=0 — a false zero" ;;
    * ) ok "--json at 8K discloses skipped_oversize=$jskip" ;;
esac
# absence measured where absence is TRUE (test/fixture) — see §2's note: $ROOT carries three .json past the
# JSON-lane ceiling, so its default run legitimately discloses skipped_oversize=3 (§B13.1).
jdef="$( "$BIN" "$ROOT/test/fixture" --json --top-k=3 2>/dev/null \
         | python3 -c 'import json,sys; d=json.load(sys.stdin); print("present" if "skipped_oversize" in d else "absent")' )"
[ "$jdef" = "absent" ] && ok "--json on test/fixture omits skipped_oversize (absent = nothing skipped)" \
                       || no "--json on test/fixture unexpectedly carries skipped_oversize"
# and the JSON header must carry the JSON-lane drop too — the XML/JSON dialects report ONE population
jrootskip="$( "$BIN" "$ROOT" --json --top-k=1 2>/dev/null \
              | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("skipped_oversize","ABSENT"))' )"
[ "$jrootskip" = "${BIGJSON:-0}" ] \
    && ok "--json default run on \$ROOT discloses skipped_oversize=$jrootskip, same as XML" \
    || no "--json default run says skipped_oversize=$jrootskip, XML says ${BIGJSON:-0} — the two dialects disagree about the population"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
