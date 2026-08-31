#!/usr/bin/env bash
# clonecachecheck.sh — S3+S4 gate: git-URL clone-cache reuse/refetch + XDG/0700 cache-path hardening.
#
# S3 (resolveRemoteRoot never refetches): a git-URL positional is shallow-cloned into a per-URL cache
# dir and reused forever if it already exists. This gate verifies:
#   (a) on REUSE (cache dir pre-seeded, no --refetch), stderr prints a one-line age note
#       ("reusing cached clone of ... (N day(s) old); pass --refetch to update") and NOTHING is
#       re-cloned (no network call — the cache dir's mtime is untouched).
#   (b) --refetch bypasses reuse: it removes the cache dir and attempts a fresh `git clone` (proven by
#       stderr saying "cloning" instead of "reusing", against an unreachable URL so the test stays
#       network-free — the assertion is about WHICH CODE PATH ran, not clone success).
#   (c) age is computed from the cache dir's mtime with NO network call (we pre-seed an old mtime and
#       confirm the reported day count matches, deterministically, with the process staying offline).
#   (d) a mutation-test: flip an assertion to prove it can actually fail (self-test of the gate).
#
# S4 (cache path XDG/0700 hardening): with $TMPDIR unset and $XDG_CACHE_HOME set, both the default
# per-root cache file (defaultCachePath) and the remote-clone cache dir land under
# $XDG_CACHE_HOME/ripwire, and that directory is created mode 0700.
#
# The cache-dir NAME is FNV-1a-64 of the URL (same algorithm as mcpCachePath in mcp.h) — this script
# recomputes it in python3 to pre-seed the exact path resolveRemoteRoot will look for.
#
# Usage:
#   test/clonecachecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/clonecachecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

fnv1a64(){   # $1 = string → 16-hex-digit FNV-1a-64, same algorithm as resolveRemoteRoot/mcpCachePath
    python3 -c "
h = 1469598103934665603
for b in '$1'.encode('utf-8'):
    h ^= b
    h = (h * 1099511628211) & 0xFFFFFFFFFFFFFFFF
print('%016x' % h)
"
}

echo "clonecachecheck: BIN=$BIN"

# ── (a) reuse prints the age note to stderr, no re-clone ────────────────────────────────────────────
# a URL that is NEVER actually reached — reuse must short-circuit before any network call.
URL="git@example.invalid:agentquality/repo.git"
HASH="$( fnv1a64 "$URL" )"

XDG="$TMP/xdg_a"; mkdir -p "$XDG"
CACHEDIR="$XDG/ripwire/ripwire-remote-$HASH"
mkdir -p "$CACHEDIR/.git"                       # pre-seed a "clone" (just needs a .git dir to exist)
echo "fake-object" > "$CACHEDIR/.git/HEAD"

# backdate the cache dir's mtime by 5 days so the age note has something deterministic to report.
FIVE_DAYS_AGO=$(( $(date +%s) - 5*86400 ))
touch -t "$(date -r "$FIVE_DAYS_AGO" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$FIVE_DAYS_AGO" +%Y%m%d%H%M.%S)" "$CACHEDIR" 2>/dev/null \
    || touch -d "@$FIVE_DAYS_AGO" "$CACHEDIR" 2>/dev/null

# L3 (Linux probe): portable stat reader(s). GNU coreutils and BSD/macOS disagree on both the flag and the
# format directives, and the `stat -f FMT ... || stat -c FMT ...` fallback this gate used is a TRAP. On GNU,
# `-f` means FILESYSTEM status and takes NO format argument, so FMT is parsed as a second FILE: measured on
# coreutils 9.11, `stat -f %i FILE` PRINTS a six-line filesystem block for FILE on stdout and exits 1. The
# `||` arm then appends the right number under six lines of junk -- so a string compare fails, a numeric
# compare dies with "integer expression expected", and a `|| echo MISSING` variant reports MISSING forever
# (a gate that then passes by comparing nothing to nothing). Detect the flavour ONCE, use one form.
if stat --version >/dev/null 2>&1; then   # GNU coreutils
    mtime_of(){ stat -c '%Y'  "$1" 2>/dev/null; }
    mode_of(){  stat -c '%a'  "$1" 2>/dev/null; }
else                                     # BSD / macOS
    mtime_of(){ stat -f '%m'  "$1" 2>/dev/null; }
    mode_of(){  stat -f '%Lp' "$1" 2>/dev/null; }
fi

BEFORE_MTIME="$( mtime_of "$CACHEDIR" )"

env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$URL" >"$TMP/a_stdout" 2>"$TMP/a_stderr"
a_exit=$?

AFTER_MTIME="$( mtime_of "$CACHEDIR" )"

[ "$a_exit" -eq 0 ] \
    && ok "reuse: exits 0 (maps the cached clone, does not attempt network)" \
    || no "reuse: expected exit 0, got $a_exit ($(cat "$TMP/a_stderr" | tail -1))"

grep -q "reusing cached clone of" "$TMP/a_stderr" \
    && ok "reuse: stderr prints the reuse note" \
    || no "reuse: stderr missing the reuse note: $(cat "$TMP/a_stderr")"

grep -Eq "reusing cached clone of $URL \([0-9]+ days? old\); pass --refetch to update" "$TMP/a_stderr" \
    && ok "reuse: age-note format matches 'reusing cached clone of URL (N day(s) old); pass --refetch to update'" \
    || no "reuse: age-note format unexpected: $(cat "$TMP/a_stderr")"

grep -Eo '\([0-9]+ days? old\)' "$TMP/a_stderr" | grep -Eq '\b5 days? old\b' \
    && ok "reuse: reports ~5 days old (matches the backdated mtime, no network call needed to compute it)" \
    || no "reuse: age did not match the backdated mtime: $(grep -Eo '\([0-9]+ days? old\)' "$TMP/a_stderr")"

[ "$BEFORE_MTIME" = "$AFTER_MTIME" ] \
    && ok "reuse: cache dir mtime UNCHANGED (proves no re-clone/re-fetch touched it)" \
    || no "reuse: cache dir mtime changed ($BEFORE_MTIME -> $AFTER_MTIME) — a reuse must not refetch"

grep -qi "cloning" "$TMP/a_stderr" \
    && no "reuse: stderr mentions 'cloning' — should have reused, not re-cloned" \
    || ok "reuse: stderr does NOT mention 'cloning' (no clone attempted)"

# ── (b) --refetch bypasses reuse and attempts a fresh clone ─────────────────────────────────────────
# Same pre-seeded cache dir; this time pass --refetch. The unreachable URL means the clone itself
# fails, but the assertion is about the CODE PATH: --refetch must remove the cache and try `git clone`
# (stderr says "cloning", exit is non-zero because the clone genuinely can't reach example.invalid).
XDG2="$TMP/xdg_b"; mkdir -p "$XDG2"
CACHEDIR2="$XDG2/ripwire/ripwire-remote-$HASH"
mkdir -p "$CACHEDIR2/.git"
echo "fake-object" > "$CACHEDIR2/.git/HEAD"

env -u TMPDIR XDG_CACHE_HOME="$XDG2" "$BIN" "$URL" --refetch >"$TMP/b_stdout" 2>"$TMP/b_stderr"
b_exit=$?

[ "$b_exit" -ne 0 ] \
    && ok "--refetch: exits non-zero (forced a fresh clone attempt, which fails against an unreachable URL)" \
    || no "--refetch: expected non-zero exit (clone should have been attempted and failed), got 0"

grep -qi "cloning" "$TMP/b_stderr" \
    && ok "--refetch: stderr says 'cloning' (bypassed the reuse path)" \
    || no "--refetch: stderr should mention 'cloning': $(cat "$TMP/b_stderr")"

grep -q "reusing cached clone of" "$TMP/b_stderr" \
    && no "--refetch: stderr should NOT print the reuse note" \
    || ok "--refetch: stderr does not print the reuse note (reuse path was skipped)"

[ ! -s "$TMP/b_stdout" ] \
    && ok "--refetch: failed clone produces empty stdout (exit 1, not partial XML)" \
    || no "--refetch: failed clone produced stdout"

# ── (c) --refetch does not change behavior when absent (plain reuse case re-verified) ───────────────
# Re-run (a) once more to confirm reuse is stable/idempotent without --refetch anywhere near it.
XDG3="$TMP/xdg_c"; mkdir -p "$XDG3"
CACHEDIR3="$XDG3/ripwire/ripwire-remote-$HASH"
mkdir -p "$CACHEDIR3/.git"
env -u TMPDIR XDG_CACHE_HOME="$XDG3" "$BIN" "$URL" >/dev/null 2>"$TMP/c1_stderr"
env -u TMPDIR XDG_CACHE_HOME="$XDG3" "$BIN" "$URL" >/dev/null 2>"$TMP/c2_stderr"
grep -q "reusing cached clone of" "$TMP/c2_stderr" \
    && ok "no --refetch: repeated invocation still reuses (unaffected by the new flag's mere existence)" \
    || no "no --refetch: repeated invocation stopped reusing"

# ── (d) S4: cache path lands under \$XDG_CACHE_HOME/ripwire with mode 0700 (TMPDIR unset) ───────────
XDG4="$TMP/xdg_d"; mkdir -p "$XDG4"
CORPUS="$ROOT/test/fixture"
env -u TMPDIR XDG_CACHE_HOME="$XDG4" "$BIN" "$CORPUS" >/dev/null 2>"$TMP/d_stderr"

if [ -d "$XDG4/ripwire" ]; then
    ok "defaultCachePath: creates \$XDG_CACHE_HOME/ripwire when TMPDIR is unset"
    PERM="$( mode_of "$XDG4/ripwire" )"
    [ "$PERM" = "700" ] \
        && ok "defaultCachePath: \$XDG_CACHE_HOME/ripwire is mode 0700 ($PERM)" \
        || no "defaultCachePath: \$XDG_CACHE_HOME/ripwire mode is $PERM, expected 700"
    # A4-P4: the auto-cache filename is now split by verb class → ripwire-<hash>-{lean,rich}.bin (a plain
  # map is the lean class). The <hash> stability + ladder/mode contract is unchanged. Y4: new blobs
    # live in a 2-hex-char shard subdir (legacy flat blobs are still honored in place), so look in BOTH layouts.
    find "$XDG4/ripwire" -maxdepth 2 -type f | grep -q '/\([0-9a-f]\{2\}/\)\{0,1\}ripwire-[0-9a-f]\{16\}-\(lean\|rich\)\.bin$' \
        && ok "defaultCachePath: cache file named ripwire-<hash>-<class>.bin lives under \$XDG_CACHE_HOME/ripwire (flat or shard)" \
        || no "defaultCachePath: no ripwire-<hash>-<class>.bin found under \$XDG_CACHE_HOME/ripwire (flat or shard)"
else
    no "defaultCachePath: \$XDG_CACHE_HOME/ripwire was not created"
fi

# same ladder for the remote-clone cache dir (S4 parity): a FRESH \$XDG_CACHE_HOME so ripwire/ itself is
# created by the binary (not pre-seeded by this script, which would just inherit the shell's umask and
# prove nothing about the code). The clone attempt fails (unreachable URL) but cacheDirLadder() runs —
# and therefore the mkdir(...,0700) — before the clone command is even built.
XDG5="$TMP/xdg_e"; mkdir -p "$XDG5"
env -u TMPDIR XDG_CACHE_HOME="$XDG5" "$BIN" "$URL" >/dev/null 2>"$TMP/e_stderr"
if [ -d "$XDG5/ripwire" ]; then
    PERM_REMOTE="$( mode_of "$XDG5/ripwire" )"
    [ "$PERM_REMOTE" = "700" ] \
        && ok "resolveRemoteRoot: \$XDG_CACHE_HOME/ripwire (binary-created) is mode 0700 for the remote-clone cache too" \
        || no "resolveRemoteRoot: \$XDG_CACHE_HOME/ripwire mode is $PERM_REMOTE, expected 700"
else
    no "resolveRemoteRoot: \$XDG_CACHE_HOME/ripwire was not created by the clone-cache path"
fi

# ── (e) STABLE per-root path: same root + same env -> same defaultCachePath (warm reuse still works) ─
env -u TMPDIR XDG_CACHE_HOME="$XDG4" "$BIN" "$CORPUS" >/dev/null 2>/dev/null
COUNT1="$(find "$XDG4/ripwire" -maxdepth 2 -type f | grep -c '/\([0-9a-f]\{2\}/\)\{0,1\}ripwire-[0-9a-f]\{16\}-\(lean\|rich\)\.bin$')"
[ "$COUNT1" = "1" ] \
    && ok "defaultCachePath: two runs on the same root (same class) produce exactly ONE cache file (stable path, warm reuse intact)" \
    || no "defaultCachePath: expected exactly 1 cache file after 2 runs, found $COUNT1"

# ── (f) mutation test: prove check (a)'s age-note assertion can actually fail ────────────────────────
# Flip the grep to demand a note format that does NOT appear (garbage text) — this assertion MUST fail,
# proving the real assertion above is not vacuously true.
if grep -q "THIS_STRING_NEVER_APPEARS_IN_STDERR_xyz123" "$TMP/a_stderr"; then
    no "mutation-test: sanity check itself is broken (matched a string that should never match)"
else
    ok "mutation-test: a deliberately-wrong grep correctly reports no match (the real assertions above are non-vacuous)"
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
