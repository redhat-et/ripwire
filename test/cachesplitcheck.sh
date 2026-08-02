#!/usr/bin/env bash
# cachesplitcheck.sh — A4-P4 gate: the warm-by-default auto-cache is SPLIT by verb class (lean vs rich),
# so alternating verb classes never thrashes (full re-parse + full rewrite on every class switch).
#
# Background (§C A4-P4): parserVerFor(captureValueUses) version-gates the cache CONTENT to a
# DIFFERENT version for the "rich" class (--for/--metrics/--uses/--exemplar, captureValueUses=true) than
# for the "lean" class (everything else). When both classes shared ONE per-root cache file, every switch
# missed the parserVer guard → full reparse + full rewrite (measured: plain-map-after-`--for` 0.81 s vs
# 0.16 s warm). The fix suffixes the auto-cache filename with the class → each class keeps its own warm
# cache and alternation is a pure warm hit.
#
# This gate exercises the AUTO path (defaultCachePath), not an explicit --cache=PATH: the split lives in
# the auto-filename. XDG_CACHE_HOME is redirected (TMPDIR unset) so the auto-cache lands in a dir we own.
#
# (a) STRUCTURAL no-thrash: run rich → lean → rich. Assert (1) TWO distinct class files exist after the
#     rich→lean pair (under the old single-file scheme only ONE file would ever exist — a clean structural
#     proof of the split), and (2) the rich cache file's INODE is unchanged across the lean run AND the
#     third (warm) rich run. saveCache writes a temp then rename()s over the path → a reparse ALWAYS mints
#     a new inode; a warm hit (dirty=false) skips saveCache → inode is preserved. Inode is granularity-
#     independent (unlike mtime seconds), so this is a timing-free honest observable of "no reparse".
# (b) BYTE-IDENTITY: after arbitrary class alternation, lean output == --no-cache lean output, and rich
#     output == --no-cache rich output (the "faster must never change the answer" determinism contract).
#
# Usage:
#   bash test/cachesplitcheck.sh
#   RIPWIRE_BIN=build_w2a/ripwire bash test/cachesplitcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "cachesplitcheck: BIN=$BIN  TMP=$TMP"

CORPUS="$ROOT/test/fixture"
[ -d "$CORPUS" ] || { echo "no test/fixture corpus"; exit 2; }

XDG="$TMP/xdg"; mkdir -p "$XDG"
CACHEDIR="$XDG/ripwire"

# L3 (Linux probe): portable stat reader(s). GNU coreutils and BSD/macOS disagree on both the flag and the
# format directives, and the `stat -f FMT ... || stat -c FMT ...` fallback this gate used is a TRAP. On GNU,
# `-f` means FILESYSTEM status and takes NO format argument, so FMT is parsed as a second FILE: measured on
# coreutils 9.11, `stat -f %i FILE` PRINTS a six-line filesystem block for FILE on stdout and exits 1. The
# `||` arm then appends the right number under six lines of junk -- so a string compare fails, a numeric
# compare dies with "integer expression expected", and a `|| echo MISSING` variant reports MISSING forever
# (a gate that then passes by comparing nothing to nothing). Detect the flavour ONCE, use one form.
if stat --version >/dev/null 2>&1; then inode_of(){ stat -c %i "$1" 2>/dev/null; }   # GNU coreutils
else                                    inode_of(){ stat -f %i "$1" 2>/dev/null; }   # BSD / macOS
fi
# glob helper: echo the single matching class file (or empty). Y4: shard-aware lookup — a blob may
# live flat under $CACHEDIR or under $CACHEDIR/<xx>/ (2-hex-char shard), so search both via find -maxdepth 2.
richfile(){ find "$CACHEDIR" -maxdepth 2 -type f -name 'ripwire-*-rich.bin' 2>/dev/null | head -1; }
leanfile(){ find "$CACHEDIR" -maxdepth 2 -type f -name 'ripwire-*-lean.bin' 2>/dev/null | head -1; }

run(){ env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$CORPUS" "$@"; }

# ── (a) structural no-thrash: rich → lean → rich ─────────────────────────────────────────────────
run --for="distance between two points" >/dev/null 2>/dev/null   # rich (cold) — writes the rich class file
RF="$( richfile )"
[ -n "$RF" ] && ok "rich verb creates a -rich.bin auto-cache" || no "no -rich.bin created by a rich verb"
RI1="$( [ -n "$RF" ] && inode_of "$RF" )"

run >/dev/null 2>/dev/null                                        # lean (cold) — writes the lean class file
LF="$( leanfile )"
[ -n "$LF" ] && ok "lean verb creates a SEPARATE -lean.bin auto-cache" || no "no -lean.bin created by a lean verb"

# both class files coexist → proves the split (old single-file scheme could only ever have ONE file)
# Y4: shard-aware lookup — count matching blobs in either layout. Narrowed to the -rich.bin/-lean.bin
# CLASS files specifically (not the bare 'ripwire-*.bin' wildcard): Y2's qchurn family now also writes a
# ripwire-qchurn-*.bin blob during the --for pass, which the old broad wildcard would incorrectly count
# toward "class cache files" — the gate's stated intent here is exactly 2 class files (rich + lean).
NFILES="$( find "$CACHEDIR" -maxdepth 2 -type f \( -name 'ripwire-*-rich.bin' -o -name 'ripwire-*-lean.bin' \) 2>/dev/null | wc -l | tr -d ' ' )"
[ "$NFILES" = "2" ] && ok "rich + lean caches coexist (exactly 2 class files — split confirmed)" \
    || no "expected exactly 2 class cache files after rich→lean, found $NFILES"

# the lean (rich-class-missing-version) run must NOT have touched the rich file → inode unchanged
RI2="$( [ -n "$RF" ] && inode_of "$RF" )"
[ -n "$RI1" ] && [ "$RI1" = "$RI2" ] && ok "lean run leaves the rich cache file untouched (inode stable)" \
    || no "lean run rewrote the rich cache (inode $RI1 -> $RI2) — cross-class thrash"

run --for="distance between two points" >/dev/null 2>/dev/null   # rich AGAIN — must be a warm hit, no reparse
RI3="$( [ -n "$RF" ] && inode_of "$RF" )"
[ -n "$RI1" ] && [ "$RI1" = "$RI3" ] && ok "third run (rich-after-lean) is a warm hit — no reparse/rewrite (inode stable)" \
    || no "rich-after-lean reparsed+rewrote the cache (inode $RI1 -> $RI3) — the A4-P4 thrash"

# ── (b) byte-identity after alternation: warm == --no-cache, for BOTH classes ─────────────────────
# hammer the alternation once more so the caches are as warm/mixed as possible, then compare.
run                                        >/dev/null 2>/dev/null   # lean warm
run --for="distance between two points"    >/dev/null 2>/dev/null   # rich warm

run                                     >"$TMP/lean.warm" 2>/dev/null   # lean, warm (auto-cache)
"$BIN" "$CORPUS" --no-cache             >"$TMP/lean.cold" 2>/dev/null   # lean, cold ground truth
diff -q "$TMP/lean.warm" "$TMP/lean.cold" >/dev/null \
    && ok "lean warm output == --no-cache lean output (byte-identical after alternation)" \
    || { no "lean warm output diverges from --no-cache"; diff "$TMP/lean.cold" "$TMP/lean.warm" | head -6; }

run --for="distance between two points"             >"$TMP/rich.warm" 2>/dev/null   # rich, warm (auto-cache)
"$BIN" "$CORPUS" --for="distance between two points" --no-cache >"$TMP/rich.cold" 2>/dev/null   # rich, cold
diff -q "$TMP/rich.warm" "$TMP/rich.cold" >/dev/null \
    && ok "rich warm output == --no-cache rich output (byte-identical after alternation)" \
    || { no "rich warm output diverges from --no-cache"; diff "$TMP/rich.cold" "$TMP/rich.warm" | head -6; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
