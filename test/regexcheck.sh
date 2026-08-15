#!/usr/bin/env bash
# regexcheck.sh — soundness gate for the Russ-Cox regex→trigram prefilter (--regex).
# The whole point of the prefilter is to be a SOUND over-approximation: it may open extra
# files, but it must NEVER drop a file that genuinely matches. So for a battery of patterns
# (a literal, an alternation, a char-class, an anchored ^, a spanning Foo.*Bar, and a
# no-trigram .*) we assert THREE things:
#   (S) prefiltered output == full-scan output   (--regex=PAT  vs  --regex=PAT --no-prefilter)
#       — the full scan opens every file, so equality proves the prefilter dropped no match.
#   (O) the file set ripwire reports ⊇ the file set an INDEPENDENT `grep -lE` finds
#       — a second, external oracle that the verifier itself can't bias.
#   (D) output is byte-identical run-to-run (determinism contract).
# Plus a NARROWING check: a pattern keyed on a token unique to one file must report fewer
# candidate files than `.*` (all files) — proving the prefilter actually excludes files
# (otherwise "sound" would be trivially satisfied by always scanning everything).
#
# Does NOT edit test/regression.sh.  Usage:
#   RIPWIRE_BIN=build/ripwire bash test/regexcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/regexcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/regexfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/regexfix dir — fixture missing"; exit 2; }
cd "$ROOT"   # repo-relative paths in the XML, so the oracle paths line up

echo "regexcheck: BIN=$BIN  CORPUS=test/regexfix"

# The required-by-the-gate battery: one of each shape, plus extra adjacency/escape stressors.
#   literal · alternation · char-class · anchored ^ · spanning Foo.*Bar · no-trigram .*
PATS=(
  'compute'                # a plain literal (>=3 chars → real trigram constraint)
  'open|close'             # alternation of two literals
  '[A-Z]\w+'               # a char class + \w (CamelCase identifiers)
  '^int '                  # an anchored line start
  'Foo.*Bar'               # a SPANNING pattern — the unsound-seam trap (Foo and Bar non-adjacent)
  '.*'                     # NO usable trigram ⇒ must fall back to scanning ALL files
  'zylophoneXyzzy'         # a rare literal unique to one file (narrowing probe)
  'Foo .* Bar'             # spanning with literal spaces around .*
  'a.*b.*c'                # multiple gaps
  '(Foo|Quux)'             # grouped alternation
  'Wid[g]et'               # a single-element char class inside a literal run
  'comp.te'                # a '.' wildcard inside a literal
  'open\('                 # an escaped metacharacter (literal paren)
)

# ── (S) soundness + (D) determinism, per pattern ──────────────────────────────────────────────
for p in "${PATS[@]}"; do
    "$BIN" "$CORPUS" --regex="$p" --no-cache               >"$TMP/pf"  2>/dev/null
    "$BIN" "$CORPUS" --regex="$p" --no-cache               >"$TMP/pf2" 2>/dev/null   # determinism: run twice
    "$BIN" "$CORPUS" --regex="$p" --no-prefilter --no-cache >"$TMP/fs" 2>/dev/null   # full-scan oracle

    det="ok"; diff -q "$TMP/pf" "$TMP/pf2" >/dev/null || det="BAD"
    snd="ok"; diff -q "$TMP/pf" "$TMP/fs"  >/dev/null || snd="BAD"

    if [ "$snd" = ok ] && [ "$det" = ok ]; then
        ok "$(printf '%-12s' "$p") prefiltered==full-scan + deterministic  $(grep -o 'files="[0-9]*" hits="[0-9]*"' "$TMP/pf")"
    else
        [ "$snd" = ok ] || { no "$(printf '%-12s' "$p") prefiltered != full-scan (DROPPED A MATCH)"; diff "$TMP/fs" "$TMP/pf" | head -4; }
        [ "$det" = ok ] || no "$(printf '%-12s' "$p") non-deterministic (run-to-run differs)"
    fi
done

# ── (O) independent grep oracle: ripwire's matched-FILE set must be a SUPERSET of grep -lE's ──
# (BRE-safe subset of the battery; uses grep -E so the pattern syntax matches.)
for p in 'compute' 'Widget' 'open|close' '[A-Z][a-z]+' 'Foo.*Bar' 'zylophoneXyzzy' '(open|close)'; do
    # G1 (2026-08-15): a matched file's path now lives ONLY on the wrapping <f p="…"> (no ":LINE" suffix —
    # that moved to the nested <hit l="…">), so the old "strip at the first colon" sed left a trailing
    # unstripped quote on every path (no colon to truncate at) and every comparison below false-missed.
    # Extract <f p="…"> distinctly, past the legend comment (whose own prose illustrates that exact shape).
    cx="$( "$BIN" "$CORPUS" --regex="$p" --no-cache 2>/dev/null | python3 -c '
import re, sys
xml = sys.stdin.read().split( "-->", 1 )[ -1 ]
for m in re.finditer( r"<f p=\"([^\"]*)\"", xml ):
    print( m.group( 1 ) )
' | sort -u )"
    # G1: $CORPUS is an absolute single-root, so ripwire's p= is now root-relative to it — strip the same
    # prefix from the independent grep oracle's paths so both sides compare the same spelling.
    gp="$( grep -rlE -- "$p" "$CORPUS" 2>/dev/null | sed "s|^$CORPUS/||" | sort -u )"
    miss=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        printf '%s\n' "$cx" | grep -qxF "$f" || { miss=1; echo "      grep matched $f but ripwire dropped it"; }
    done <<< "$gp"
    [ "$miss" -eq 0 ] && ok "oracle ⊇ grep   $(printf '%-14s' "$p")" || no "oracle dropped a grep-matched file for /$p/"
done

# ── NARROWING: the prefilter must EXCLUDE files (else soundness is trivial). A token unique to one
#    file ⇒ fewer candidate files than '.*' (which has no trigram constraint ⇒ all files). ─────────
allF="$(  "$BIN" "$CORPUS" --regex='.*'            --no-cache 2>/dev/null | grep -o 'files="[0-9]*"' | grep -o '[0-9]*' )"
rareF="$( "$BIN" "$CORPUS" --regex='zylophoneXyzzy' --no-cache 2>/dev/null | grep -o 'files="[0-9]*"' | grep -o '[0-9]*' )"
if [ -n "$allF" ] && [ -n "$rareF" ] && [ "$rareF" -lt "$allF" ]; then
    ok "narrowing (rare pattern files=$rareF < all files=$allF — prefilter excludes files)"
else
    no "narrowing FAILED (rare=$rareF, all=$allF — prefilter is scanning everything)"
fi

# ── no-trigram FALLBACK: '.*' must behave EXACTLY like the full scan (already covered by (S) above,
#    asserted explicitly here for clarity — the correctness-over-speed fallback). ─────────────────
"$BIN" "$CORPUS" --regex='.*' --no-cache               >"$TMP/dotpf" 2>/dev/null
"$BIN" "$CORPUS" --regex='.*' --no-prefilter --no-cache >"$TMP/dotfs" 2>/dev/null
diff -q "$TMP/dotpf" "$TMP/dotfs" >/dev/null \
    && ok "no-trigram fallback ('.*' prefiltered == full-scan == every file)" \
    || no "no-trigram fallback broken ('.*' differs from full scan)"

# ── malformed vs exotic: §P0.4 changed this contract. A regex std::regex REJECTS must REFUSE —
# exit 1, a diagnostic on stderr, and NO hits= element (a silent hits="0" was the false-zero bug).
# A pattern that merely LOOKS exotic but compiles must still search at exit 0. Either way, never a
# crash: exit codes above 1 (signals, aborts) fail both arms.
for p in '(' '[' 'a{2,' '\Q\E'; do
    err="$( "$BIN" "$CORPUS" --regex="$p" --no-cache 2>&1 >"$TMP/refuse.out" )"; rc=$?
    if [ "$rc" -eq 1 ] && [ -n "$err" ] && ! grep -q '<grep' "$TMP/refuse.out"; then
        ok "malformed pattern /$p/ refuses (exit 1 + stderr, no hits element)"
    else
        no "malformed pattern /$p/: want exit 1 + stderr + no hits element, got exit $rc (stderr ${#err}B)"
    fi
done
for p in '(?:foo)' '[^x]+'; do
    "$BIN" "$CORPUS" --regex="$p" --no-cache >/dev/null 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && ok "exotic-but-valid pattern /$p/ still searches (exit 0)" \
                    || no "exotic-but-valid pattern /$p/ no longer searches (exit $rc)"
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
