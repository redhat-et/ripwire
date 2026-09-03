#!/usr/bin/env bash
# cacheexclkeycheck.sh — gate for "the auto-cache key ignores --exclude" (EVALS, PRE-REGISTERED 2026-09-03).
#
# Background. `main.cpp::defaultCachePath` keyed the warm-by-default auto cache on realpath(root) + the
# lean/rich verb class ONLY. The exclude set and --max-file-size — both of which change WHICH FILES are
# extracted — were absent from the key, so `ripwire .` and `ripwire . --exclude=vendored` shared ONE blob.
# Two costs, both measured on this repo (EVALS §"The auto-cache key ignores --exclude"):
#   * the excluded run deserialises the UN-excluded superset it then discards — 536 ms of loadCache on a
#     686 MB blob against 31 ms of parsing, versus 8 ms under an explicit --cache=PATH;
#   * as soon as the excluded run is DIRTY (any file changed since it last ran, the ordinary case in a
#     working tree) it rewrites the shared blob with its SUBSET, and the next un-excluded run cold-parses
#     the whole excluded subtree (~15,000 files, 5.0 s on this repo).
# `quality.h::exclConfigHex` already folds exactly this material into the --quality-* cache families' keys;
# the ingest cache never adopted it. The fix folds the same material into the auto-cache filename, giving
# one blob per (root, exclude config, class).
#
# This gate exercises the AUTO path (defaultCachePath), never an explicit --cache=PATH: the key lives in
# the auto filename. XDG_CACHE_HOME is redirected (TMPDIR unset) so blobs land in a dir we own. The fixture
# is a small synthetic tree with an excludable `ext/` subdir, so the gate is fast — the wall-clock numbers
# behind band (2) are a bench/PROFILE.md ledger row on the real repo, never a red gate here.
#
# Checks:
#   (a) CONFIG SPLIT (structural): a plain run then an --exclude run leave TWO distinct auto-cache blobs.
#       Under the old single-key scheme only ONE blob could ever exist — the clean structural proof.
#   (b) BAND (1), literal registered sequence: `.` -> `. --exclude=ext` -> `.`  reparses 0 files on the
#       third run. (Held before the fix too, because a non-dirty excluded run never rewrites the blob —
#       it is the non-regression half of the band.)
#   (c) BAND (1), the DIRTY excluded run — the sequence that actually thrashes: `.` -> edit one kept file
#       -> `. --exclude=ext` (dirty: it rewrites the shared blob with its subset) -> `.`. The third run
#       must reparse ONLY the file that genuinely changed (1), never the excluded subtree (60 before the fix,
#       measured).
#   (d) --max-file-size is part of the same key: a third distinct blob, because it changes the extracted
#       file SET exactly as excludes do (the P0.2 argument, already settled for the quality families).
#   (e) BAND (3): warm output is byte-identical to --no-cache for BOTH configurations, and each warm run
#       is byte-identical to itself (determinism x2).
#   (f) EVICTION: the new-shaped blobs are inside the family `sweepStaleCacheBlobsOnce` evicts — a blob
#       back-dated past the 30-day cutoff is swept by the next run that saves, and that run's own blob
#       (keepPath) survives. Without this the per-root family would grow one blob per exclude config
#       forever.
#
# Usage:
#   bash test/cacheexclkeycheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/cacheexclkeycheck.sh
#   bash test/cacheexclkeycheck.sh path/to/ripwire
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/keep" "$REPO/ext"

echo "cacheexclkeycheck: BIN=$BIN  TMP=$TMP"

# ── fixture: 12 kept translation units + 60 in an excludable subtree ──────────────────────────────
i=1
while [ "$i" -le 12 ]; do
    printf 'int keep_%d( int a )\n{\n    return a + %d;\n}\n' "$i" "$i" > "$REPO/keep/k$i.cpp"
    i=$(( i + 1 ))
done
i=1
while [ "$i" -le 60 ]; do
    printf 'int vend_%d( int a )\n{\n    return a * %d;\n}\n' "$i" "$i" > "$REPO/ext/v$i.cpp"
    i=$(( i + 1 ))
done

# One phase = one private XDG_CACHE_HOME, so phases never inherit each other's blobs.
XDGN=0
newphase(){
    XDGN=$(( XDGN + 1 ))
    XDG="$TMP/xdg$XDGN"
    CACHEDIR="$XDG/ripwire"
    mkdir -p "$CACHEDIR"
}
# Y4: a blob may sit flat under $CACHEDIR or in a 2-hex-char shard subdir — look at both.
leanblobs(){ find "$CACHEDIR" -maxdepth 2 -type f -name 'ripwire-*-lean.bin' 2>/dev/null | sort; }
nleanblobs(){ leanblobs | wc -l | tr -d ' '; }

# run the tool against the fixture with the phase's private cache dir; stdout to $1, stderr to $TMP/err.
run(){ local out="$1"; shift; env -u TMPDIR XDG_CACHE_HOME="$XDG" RIPWIRE_CACHE_STATS=1 "$BIN" "$REPO" "$@" >"$out" 2>"$TMP/err"; }
# the reparsed= count of the LAST run (RIPWIRE_CACHE_STATS is the tool's own drift observable)
reparsed(){ sed -n 's/.*cache-stats reparsed=\([0-9][0-9]*\) .*/\1/p' "$TMP/err" | head -1; }

# ── (a) CONFIG SPLIT: two exclude configurations must not share one blob ──────────────────────────
newphase
run "$TMP/a1.xml"
run "$TMP/a2.xml" --exclude=ext
N="$( nleanblobs )"
[ "$N" = "2" ] && ok "plain + --exclude leave TWO distinct auto-cache blobs (exclude config is in the key)" \
    || no "expected 2 auto-cache blobs after plain + --exclude, found $N — the exclude set is NOT in the auto-cache key"

# (d) --max-file-size shares that key: a third configuration, a third blob.
run "$TMP/a3.xml" --max-file-size=2K
N3="$( nleanblobs )"
[ "$N3" = "3" ] && ok "--max-file-size=2K keys its OWN blob (the extracted file SET is part of the key)" \
    || no "expected 3 auto-cache blobs after adding a --max-file-size config, found $N3 — --max-file-size is NOT in the auto-cache key"

# ── (b) BAND (1), the registered sequence: . -> . --exclude=ext -> .  (third run reparses 0) ───────
newphase
run "$TMP/b1.xml"                                    # cold: parses the whole tree
R1="$( reparsed )"
[ "$R1" = "72" ] && ok "cold plain run parses the whole fixture (reparsed=$R1)" \
    || no "cold plain run reparsed=$R1, expected 72 — fixture or stat gate changed"
run "$TMP/b2.xml" --exclude=ext                      # excluded run
run "$TMP/b3.xml"                                    # plain again
R3="$( reparsed )"
[ "$R3" = "0" ] && ok "band (1): . -> . --exclude=ext -> . reparses 0 files on the third run" \
    || no "band (1) VIOLATED: third run reparsed=$R3, expected 0"

# ── (c) BAND (1) with a DIRTY excluded run — the sequence that actually thrashes ───────────────────
newphase
run "$TMP/c1.xml"                                    # cold plain: the un-excluded set is cached
printf 'int keep_1( int a )\n{\n    return a + 101;\n}\n' > "$REPO/keep/k1.cpp"   # one genuine edit
run "$TMP/c2.xml" --exclude=ext                      # dirty excluded run — it now rewrites its cache
RC2="$( reparsed )"
[ "$RC2" = "1" ] && ok "the excluded run reparses only the edited file (reparsed=$RC2) — it IS dirty, so it saves" \
    || no "excluded run reparsed=$RC2, expected 1 — the fixture edit did not make it dirty"
run "$TMP/c3.xml"                                    # plain again: must NOT have lost the ext/ records
RC3="$( reparsed )"
[ "$RC3" = "1" ] && ok "band (1): after a dirty excluded run, the next plain run reparses only the edited file (reparsed=$RC3)" \
    || no "band (1) VIOLATED: plain-after-dirty-excluded reparsed=$RC3, expected 1 — the excluded run truncated the shared blob to its subset"

# ── (e) BAND (3): warm == --no-cache for BOTH configurations, and determinism x2 ───────────────────
newphase
run "$TMP/e_plain_cold.xml"
run "$TMP/e_plain_warm1.xml"
run "$TMP/e_plain_warm2.xml"
run "$TMP/e_excl_cold.xml" --exclude=ext
run "$TMP/e_excl_warm1.xml" --exclude=ext
run "$TMP/e_excl_warm2.xml" --exclude=ext
env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO" --no-cache            > "$TMP/e_plain_nocache.xml" 2>/dev/null
env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO" --no-cache --exclude=ext > "$TMP/e_excl_nocache.xml" 2>/dev/null

cmp -s "$TMP/e_plain_warm1.xml" "$TMP/e_plain_nocache.xml" \
    && ok "band (3): warm plain output is byte-identical to --no-cache" \
    || no "band (3) VIOLATED: warm plain output differs from --no-cache"
cmp -s "$TMP/e_excl_warm1.xml" "$TMP/e_excl_nocache.xml" \
    && ok "band (3): warm --exclude output is byte-identical to --no-cache" \
    || no "band (3) VIOLATED: warm --exclude output differs from --no-cache"
cmp -s "$TMP/e_plain_warm1.xml" "$TMP/e_plain_warm2.xml" \
    && ok "band (3): plain warm run is deterministic (x2 byte-identical)" \
    || no "band (3) VIOLATED: two warm plain runs differ"
cmp -s "$TMP/e_excl_warm1.xml" "$TMP/e_excl_warm2.xml" \
    && ok "band (3): --exclude warm run is deterministic (x2 byte-identical)" \
    || no "band (3) VIOLATED: two warm --exclude runs differ"

# ── (f) EVICTION: the new blobs are inside the swept "ripwire-" family ─────────────────────────────
# Back-date the --exclude config's blob past the 30-day cutoff, then make a plain run that actually SAVES
# (sweepStaleCacheBlobsOnce lives inside saveCache and fires at most once per process). The stale blob must
# go; the running config's own blob (keepPath) must stay. Proves the per-root family stays bounded even
# though it now has one member per exclude configuration.
newphase
run "$TMP/f1.xml" --exclude=ext
STALE="$( leanblobs | head -1 )"
[ -n "$STALE" ] && ok "eviction setup: the --exclude run wrote an auto-cache blob ($( basename "$STALE" ))" \
    || no "eviction setup: no auto-cache blob written by the --exclude run"
touch -t 202001010000 "$STALE"
printf 'int keep_new( int a )\n{\n    return a - 1;\n}\n' > "$REPO/keep/knew.cpp"   # make the plain run dirty
run "$TMP/f2.xml"
KEEPN="$( nleanblobs )"
[ ! -e "$STALE" ] && ok "eviction: a >30-day-old auto-cache blob of ANOTHER exclude config is swept" \
    || no "eviction: the stale blob survived — the new blob shape is outside the swept ripwire-* family"
[ "$KEEPN" -ge 1 ] && ok "eviction: the running configuration's own blob survives the sweep (keepPath honored, $KEEPN left)" \
    || no "eviction: the running configuration's own blob was swept ($KEEPN left)"
rm -f "$REPO/keep/knew.cpp"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES above"; exit 1; }
