#!/usr/bin/env bash
# cachehashcheck.sh — G-A1: the CLI incremental cache keys on CONTENT HASH, never mtime.
#
# Regression fence: the audit reproduced that the CLI
# `--cache=PATH` path survives the classic "mtime-lies" attack — edit a file's content, then
# `touch -r` its mtime back to the pre-edit value, and a warm re-run must STILL see the new content.
#
# WHAT THIS HEADER USED TO CLAIM, AND WHAT IT CLAIMS NOW (corrected twice, 2026-09-03). It first
# generalised its own pass into immunity: "the CLI path re-crawls and re-hashes bytes every invocation, so
# an equal mtime never masks a content change". The re-crawl half was true; the re-hash half stopped being
# true when the A4-P7 stat-gate landed, because a warm run SKIPS the read+hash for a file whose stat record
# still matches — so the CLI shared the MCP server's same-(mtime,size) residual rather than being immune to
# the class, and what this gate proved was the case it stages: the edit below changes the byte LENGTH, and
# the SIZE discriminator catches it.
#
# The residual is now CLOSED (docs/EVALS.md, "Closing the same-(mtime, size) warm-path residual"). The stat
# record carries a third field, st_ctime, which an unprivileged writer cannot restore — the `touch -r` below
# moves it — so this gate's own attack would now be caught by TWO independent discriminators. That is why it
# is still the size half that this gate proves: the arm is deliberately length-CHANGING, so it keeps fencing
# the size discriminator specifically and does not quietly become a duplicate of statgatecheck (b2) /
# freshnesscheck arm 6, which stage the length-PRESERVING attack the ctime field exists for.
#
# Still not immunity, and the boundary is stated rather than implied: a caller who can move the system clock
# backward, raw block-device manipulation, and a filesystem with no distinct ctime (FAT/exFAT, some SMB
# mounts) all remain outside it, and `--no-cache` remains the unconditional escape hatch.
#
# Recipe ( "G-A1"):
#   1. write a source file, run ripwire with --cache=<tmp>/c.bin to populate (cold)
#   2. save a copy of the file's bytes (for touch -r reference)
#   3. EDIT the file's content (remove the old symbol, add a new one)
#   4. touch -r <saved-ref> <file>          — restore the mtime EXACTLY (also restore dir mtime,
#                                              belt-and-suspenders; the CLI re-crawls so it shouldn't
#                                              matter, but keep the attack as hostile as possible)
#   5. run ripwire again with the SAME --cache=<tmp>/c.bin (warm)
#   6. the NEW symbol MUST appear in the warm output; the OLD symbol must be GONE
#
# Usage:
#   bash test/cachehashcheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/cachehashcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "cachehashcheck: BIN=$BIN  TMP=$TMP"

WORK="$TMP/proj"
mkdir -p "$WORK"
CACHE="$TMP/c.bin"

# ── step 1: populate the warm cache on the ORIGINAL content ──────────────────────────────────────
printf 'int oldSymbol( void )\n{\n    return 1;\n}\n' > "$WORK/f.cpp"
"$BIN" "$WORK" --cache="$CACHE" --no-stable >"$TMP/cold.xml" 2>"$TMP/cold.err"
rc_cold=$?
if [ "$rc_cold" -eq 0 ]; then
    ok "cold run (cache populate) exits 0"
else
    no "cold run expected exit 0, got $rc_cold"
    cat "$TMP/cold.err"
fi

if grep -q 'n="oldSymbol"' "$TMP/cold.xml" 2>/dev/null; then
    ok "cold run: oldSymbol present (fixture sanity)"
else
    no "cold run: oldSymbol missing — fixture did not parse as expected"
    head -3 "$TMP/cold.xml"
fi

# ── step 2: save a byte-identical reference copy (source of the mtime we restore to) ─────────────
cp "$WORK/f.cpp" "$TMP/f.cpp.ref"
DIR_REF="$TMP/dir.ref"
touch -r "$WORK" "$DIR_REF" 2>/dev/null || cp -p "$WORK/f.cpp" "$DIR_REF" 2>/dev/null

# Sleep past common coarse filesystem mtime granularity (1s on HFS+/some NFS/SMB) so that, absent
# the touch -r restore, the mtime WOULD visibly change — this keeps the attack honest.
sleep 1

# ── step 3: EDIT the content — remove oldSymbol, add newSymbol ───────────────────────────────────
printf 'int newSymbol( void )\n{\n    return 2;\n}\n' > "$WORK/f.cpp"

# ── step 4: restore the file's mtime EXACTLY to the pre-edit value (the "mtime lies" attack) ─────
touch -r "$TMP/f.cpp.ref" "$WORK/f.cpp"
# Best-effort: restore the parent dir's mtime too (belt-and-suspenders; CLI re-crawls every run so
# this should be immaterial, but keep the repro as hostile to the cache as possible).
touch -r "$DIR_REF" "$WORK" 2>/dev/null || true

# Confirm the mtime restore actually worked (sanity on the attack itself, not the tool under test).
# L3 (Linux probe): portable stat reader(s). GNU coreutils and BSD/macOS disagree on both the flag and the
# format directives, and the `stat -f FMT ... || stat -c FMT ...` fallback this gate used is a TRAP. On GNU,
# `-f` means FILESYSTEM status and takes NO format argument, so FMT is parsed as a second FILE: measured on
# coreutils 9.11, `stat -f %i FILE` PRINTS a six-line filesystem block for FILE on stdout and exits 1. The
# `||` arm then appends the right number under six lines of junk -- so a string compare fails, a numeric
# compare dies with "integer expression expected", and a `|| echo MISSING` variant reports MISSING forever
# (a gate that then passes by comparing nothing to nothing). Detect the flavour ONCE, use one form.
if stat --version >/dev/null 2>&1; then   # GNU coreutils
    mtime_of(){ stat -c '%Y'  "$1" 2>/dev/null; }
else                                     # BSD / macOS
    mtime_of(){ stat -f '%m' "$1" 2>/dev/null; }
fi
ref_mtime="$( mtime_of "$TMP/f.cpp.ref" )"
new_mtime="$( mtime_of "$WORK/f.cpp" )"
if [ "$ref_mtime" = "$new_mtime" ]; then
    ok "attack setup: file mtime restored exactly (touch -r verified: $new_mtime)"
else
    no "attack setup: touch -r did NOT restore mtime (ref=$ref_mtime got=$new_mtime) — attack is not hostile, results untrustworthy"
fi

# ── step 5: warm re-run with the SAME --cache path ────────────────────────────────────────────────
"$BIN" "$WORK" --cache="$CACHE" --no-stable >"$TMP/warm.xml" 2>"$TMP/warm.err"
rc_warm=$?
if [ "$rc_warm" -eq 0 ]; then
    ok "warm run (mtime-preserved edit) exits 0"
else
    no "warm run expected exit 0, got $rc_warm"
    cat "$TMP/warm.err"
fi

# ── step 6: the NEW symbol MUST appear — proves content-hash, not mtime, keys the cache ──────────
if grep -q 'n="newSymbol"' "$TMP/warm.xml" 2>/dev/null; then
    ok "warm run: newSymbol appears despite mtime-preserved edit (content-hash cache confirmed)"
else
    no "warm run: newSymbol MISSING — cache appears to key on mtime, not content (REGRESSION)"
    head -5 "$TMP/warm.xml"
fi

# The old symbol must be GONE — a stale/merged cache entry would leave it behind.
if grep -q 'n="oldSymbol"' "$TMP/warm.xml" 2>/dev/null; then
    no "warm run: oldSymbol STILL present — stale cache entry not replaced (REGRESSION)"
else
    ok "warm run: oldSymbol absent (stale entry correctly replaced)"
fi

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
    && { xmllint --noout "$TMP/warm.xml" 2>/dev/null \
         && ok "xml well-formed" || no "xml malformed"; } \
    || ok "xml well-formed (xmllint absent — skipped)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
