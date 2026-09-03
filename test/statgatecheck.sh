#!/usr/bin/env bash
# statgatecheck.sh — A4-P7: warm-run (size,mtime) STAT-GATE + racy-git rule.
#
# ingest()'s incremental --cache stores (sizeBytes, mtimeNs, ctimeNs) per file plus the blob's own write
# timestamp. On a warm run each file is stat'd ONCE; if all three still match the cache AND the cached
# mtime is strictly older than the blob write time (not "racy"), the cached parse is trusted WITHOUT
# reading/hashing the file. On ANY mismatch (or a racy entry, or an unstatable file) the file is read +
# content-hashed exactly as before — the content hash stays the sole authority for what actually changed.
# This gate proves the shortcut never returns a stale or wrong answer.
#
# WHY THREE TIMESTAMPS AND NOT TWO. (size, mtime) alone leaves the adversarial corner (b2) stages: an
# unprivileged process can restore mtime with utimes() and can keep the byte length, and the gate then
# trusts a file whose content changed. It CANNOT restore st_ctime — POSIX exposes no interface for it, and
# the utimes() that restores mtime is itself an inode change that moves ctime forward. So the third
# discriminator comes out of the ::stat the gate already performs: no extra syscall, no file read, and (b2)
# becomes a HARD assertion instead of the informational note it used to be.
#
# WHAT THAT STILL DOES NOT COVER, and why (b3) stays: a caller who can move the system clock backward, raw
# block-device manipulation, and a filesystem that maintains no distinct ctime (FAT/exFAT, some SMB mounts)
# — there the gate degrades to exactly the pre-ctime behaviour, so the racy rule is KEPT, not replaced.
#
# Cases:
#   (a) warm re-run, no changes            → output byte-identical to the cold run
#   (b1) NORMAL edit, mtime ADVANCES       → change ALWAYS detected (the common case)
#   (b2) content edit, mtime forced EQUAL  → the adversarial backdated-mtime + same-size attack. HARD:
#        the restore moved st_ctime, so the gate re-hashes and the edit is detected. This was an
#        informational note until the ctime discriminator landed (docs/EVALS.md, card A3 follow-up).
#   (b3) RACY entry (mtime == blob write)  → forced re-hash → edit detected even with mtime unchanged
#   (c) touch only, no content change      → output still correct (trusted shortcut, no false change)
#   (d) file added / removed               → correct output
#   (e) metadata-only chmod to UNREADABLE   → cached parse kept, output unchanged (the ctime cost side)
#
# Usage:
#   bash test/statgatecheck.sh
#   RIPWIRE_BIN=build_r2a3/ripwire bash test/statgatecheck.sh
#
# Exits non-zero on any failure — every case above is HARD. Prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
note(){ printf '  NOTE  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "statgatecheck: BIN=$BIN  TMP=$TMP"

# L3 (Linux probe): portable stat reader(s). GNU coreutils and BSD/macOS disagree on both the flag and the
# format directives, and the `stat -f FMT ... || stat -c FMT ...` fallback this gate used is a TRAP. On GNU,
# `-f` means FILESYSTEM status and takes NO format argument, so FMT is parsed as a second FILE: measured on
# coreutils 9.11, `stat -f %i FILE` PRINTS a six-line filesystem block for FILE on stdout and exits 1. The
# `||` arm then appends the right number under six lines of junk -- so a string compare fails, a numeric
# compare dies with "integer expression expected", and a `|| echo MISSING` variant reports MISSING forever
# (a gate that then passes by comparing nothing to nothing). Detect the flavour ONCE, use one form.
# (ns precision where the FS/stat supports it: BSD %Fm, GNU %.9Y)
if stat --version >/dev/null 2>&1; then mtime_ns(){ stat -c '%.9Y' "$1" 2>/dev/null; }   # GNU coreutils
else                                    mtime_ns(){ stat -f '%Fm'  "$1" 2>/dev/null; }   # BSD / macOS
fi

# ── case (a): warm no-change run is byte-identical ────────────────────────────────────────────────
WA="$TMP/a"; mkdir -p "$WA"; CA="$TMP/a.bin"
printf 'int alpha( void )\n{\n    return 1;\n}\n' > "$WA/f.cpp"
printf 'int beta( int x )\n{\n    return x + 1;\n}\n' > "$WA/g.cpp"
"$BIN" "$WA" --cache="$CA" --no-stable >"$TMP/a.cold" 2>/dev/null
"$BIN" "$WA" --cache="$CA" --no-stable >"$TMP/a.warm" 2>/dev/null   # this run engages the stat-gate (no file changed)
if diff -q "$TMP/a.cold" "$TMP/a.warm" >/dev/null 2>&1; then
    ok "(a) warm no-change run is byte-identical to cold (stat-gate output-neutral)"
else
    no "(a) warm run diverged from cold — stat-gate changed the answer (REGRESSION)"
fi
grep -q 'n="alpha"' "$TMP/a.warm" && grep -q 'n="beta"' "$TMP/a.warm" \
    && ok "(a) both symbols present on the warm run" \
    || no "(a) a symbol vanished on the warm run"

# ── case (b1): a NORMAL edit whose mtime advances is always detected ──────────────────────────────
WB="$TMP/b"; mkdir -p "$WB"; CB="$TMP/b.bin"
printf 'int oldOne( void )\n{\n    return 1;\n}\n' > "$WB/f.cpp"
"$BIN" "$WB" --cache="$CB" --no-stable >/dev/null 2>&1
sleep 1                                                            # push the edit into a later mtime granule
printf 'int newOne( void )\n{\n    return 2;\n}\n' > "$WB/f.cpp"   # different size + later mtime
"$BIN" "$WB" --cache="$CB" --no-stable >"$TMP/b.warm" 2>/dev/null
if grep -q 'n="newOne"' "$TMP/b.warm" && ! grep -q 'n="oldOne"' "$TMP/b.warm"; then
    ok "(b1) normal edit (mtime advances) detected — newOne in, oldOne out"
else
    no "(b1) normal edit NOT detected — stat-gate masked a real change (REGRESSION)"
fi

# ── case (b2): backdated mtime + IDENTICAL size — closed by the recorded ctime (HARD) ─────────────
WB2="$TMP/b2"; mkdir -p "$WB2"; CB2="$TMP/b2.bin"
printf 'int sameSizeA( void )\n{\n    return 1;\n}\n' > "$WB2/f.cpp"
cp -p "$WB2/f.cpp" "$TMP/b2.ref"                                   # -p: ref keeps the EXACT pre-edit mtime (true backdate)
"$BIN" "$WB2" --cache="$CB2" --no-stable >/dev/null 2>&1
sleep 1
printf 'int sameSizeB( void )\n{\n    return 2;\n}\n' > "$WB2/f.cpp"   # SAME byte length as sameSizeA
touch -r "$TMP/b2.ref" "$WB2/f.cpp"                               # restore mtime EXACTLY to the cached value
"$BIN" "$WB2" --cache="$CB2" --no-stable >"$TMP/b2.warm" 2>/dev/null
if grep -q 'n="sameSizeB"' "$TMP/b2.warm" && ! grep -q 'n="sameSizeA"' "$TMP/b2.warm"; then
    ok "(b2) backdated same-size edit DETECTED — the touch -r moved st_ctime, so the gate re-hashed"
else
    no "(b2) backdated same-size edit was TRUSTED — the ctime discriminator is not holding (or this filesystem maintains no distinct st_ctime: $( df -T 2>/dev/null || mount | grep -E " on / " ))"
fi

# ── case (b3): the RACY rule — an entry whose mtime is >= the blob write time is force-re-hashed ──
# Construct a racy entry: give the file a FUTURE mtime BEFORE caching, so its stored mtime lands after
# the blob's own write time. On the warm run the racy rule must re-hash it even though (size,mtime) are
# unchanged and the edit is size-preserving — exactly the same-granule hole the rule exists to close.
WB3="$TMP/b3"; mkdir -p "$WB3"; CB3="$TMP/b3.bin"
printf 'int racyA( void )\n{\n    return 1;\n}\n' > "$WB3/f.cpp"
# future-date the file (portable: GNU date vs BSD touch). Falls back to a plain touch far ahead.
if touch -d '2037-01-01 00:00:00' "$WB3/f.cpp" 2>/dev/null; then :; \
elif touch -t 203701010000 "$WB3/f.cpp" 2>/dev/null; then :; \
else note "(b3) could not future-date file — racy construction may be weak on this platform"; fi
cp -p "$WB3/f.cpp" "$TMP/b3.ref"                                  # capture the future mtime
"$BIN" "$WB3" --cache="$CB3" --no-stable >/dev/null 2>&1          # cache stores mtime(future) >= blobWriteNs(now) → racy
printf 'int racyB( void )\n{\n    return 2;\n}\n' > "$WB3/f.cpp"   # size-preserving edit
touch -r "$TMP/b3.ref" "$WB3/f.cpp"                              # keep the same (future) mtime
"$BIN" "$WB3" --cache="$CB3" --no-stable >"$TMP/b3.warm" 2>/dev/null
if grep -q 'n="racyB"' "$TMP/b3.warm" && ! grep -q 'n="racyA"' "$TMP/b3.warm"; then
    ok "(b3) racy entry (mtime >= blob write) force-re-hashed — size-preserving edit still detected"
else
    no "(b3) racy rule FAILED — a same-granule-class edit was trusted (REGRESSION)"
fi

# ── case (c): touch-only (no content change) → correct output, no phantom change ──────────────────
WC="$TMP/c"; mkdir -p "$WC"; CC="$TMP/c.bin"
printf 'int gamma( void )\n{\n    return 7;\n}\n' > "$WC/f.cpp"
"$BIN" "$WC" --cache="$CC" --no-stable >"$TMP/c.cold" 2>/dev/null
sleep 1
touch "$WC/f.cpp"                                                 # bump mtime, content identical → stat mismatch → re-hash → same facts
"$BIN" "$WC" --cache="$CC" --no-stable >"$TMP/c.warm" 2>/dev/null
if diff -q "$TMP/c.cold" "$TMP/c.warm" >/dev/null 2>&1 && grep -q 'n="gamma"' "$TMP/c.warm"; then
    ok "(c) touch-only (mtime bumped, content same) → output unchanged & correct"
else
    no "(c) touch-only changed the output — a false change slipped through"
fi

# ── case (d): file added, then removed → correct output each time ──────────────────────────────────
WD="$TMP/d"; mkdir -p "$WD"; CD="$TMP/d.bin"
printf 'int keep( void )\n{\n    return 1;\n}\n' > "$WD/keep.cpp"
"$BIN" "$WD" --cache="$CD" --no-stable >/dev/null 2>&1
sleep 1
printf 'int added( void )\n{\n    return 2;\n}\n' > "$WD/added.cpp"   # NEW file (absent from cache)
"$BIN" "$WD" --cache="$CD" --no-stable >"$TMP/d.add" 2>/dev/null
grep -q 'n="added"' "$TMP/d.add" && grep -q 'n="keep"' "$TMP/d.add" \
    && ok "(d) added file picked up on warm run" \
    || no "(d) added file NOT picked up"
rm -f "$WD/added.cpp"                                             # REMOVE it
"$BIN" "$WD" --cache="$CD" --no-stable >"$TMP/d.rm" 2>/dev/null
if grep -q 'n="keep"' "$TMP/d.rm" && ! grep -q 'n="added"' "$TMP/d.rm"; then
    ok "(d) removed file gone on next warm run; survivor intact"
else
    no "(d) removed file still present (or survivor lost)"
fi

# ── case (e): a METADATA-only change must not COST the file — the ctime discriminator's own cost side ─
# The third discriminator is deliberately conservative: st_ctime moves on chmod/chown/xattr/rename too, not
# only on a write. Every one of those falls out of the stat gate and into the read+hash path, which is
# correct and cheap — EXCEPT when the metadata change is what made the file unreadable. Then the re-hash's
# read FAILS, and the naive implementation drops every symbol the file had, turning a `chmod 000` into a
# silent partial index. (postingscheck (d) is the gate that caught it: it makes every source unreadable on
# purpose, to prove the warm scorer does not re-read per query.)
#
# The rule this arm pins: when a file cannot be READ but its (size, mtime) still match the record and the
# entry is not racy, the cached parse is KEPT. A ctime that moved on its own is a metadata change, not
# evidence of a content change, and dropping a file we were unable to look at is a worse answer than
# serving its last-known parse. The exposure is stated where the code is: a same-(mtime,size) edit hidden
# behind a chmod-to-unreadable is served stale — but no cache-free run can do better (--no-cache cannot
# read it either), and the MCP edit verbs re-read + byte-hash their target regardless.
WE="$TMP/e"; mkdir -p "$WE"; CE="$TMP/e.bin"
printf 'int deltaSym( void )\n{\n    return 3;\n}\n' > "$WE/f.cpp"
"$BIN" "$WE" --cache="$CE" --no-stable >"$TMP/e.cold" 2>/dev/null
chmod 000 "$WE/f.cpp"                                             # metadata only: size and mtime unchanged, ctime moves
"$BIN" "$WE" --cache="$CE" --no-stable >"$TMP/e.warm" 2>/dev/null
chmod 644 "$WE/f.cpp"
if diff -q "$TMP/e.cold" "$TMP/e.warm" >/dev/null 2>&1 && grep -q 'n="deltaSym"' "$TMP/e.warm"; then
    ok "(e) chmod-to-unreadable (ctime moves, size+mtime hold) → cached parse kept, output unchanged"
else
    no "(e) a metadata-only chmod DROPPED the file's symbols — the ctime discriminator is costing an answer"
fi

# ── well-formed XML on the representative outputs ─────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    allok=1
    for f in "$TMP/a.warm" "$TMP/b.warm" "$TMP/b3.warm" "$TMP/c.warm" "$TMP/d.rm"; do
        xmllint --noout "$f" 2>/dev/null || allok=0
    done
    [ "$allok" = 1 ] && ok "all warm outputs well-formed XML" || no "some warm output malformed"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
