#!/usr/bin/env bash
# staleackcheck.sh — L2 gate for STALE-ACK disclosure on --quality-delta.
#
# WHY. `.ripwire_quality_acks` has acquisition (--quality-ack) and a worsen-past-acked-magnitude ratchet
# (quality::applyAckRatchet) but no retirement surface: an ack whose target symbol was deleted, or whose
# finding kind no longer fires on a symbol that survived, sits in the ledger forever, invisibly. A past
# round hand-retired 109 dead rows out of this repo's own 188-line ledger — a whole session of manual
# audit for a question the tool should answer in one pass. The in-repo precedent for exactly this shape
# is --notes: a note whose target no longer resolves is flagged dangling="1" against the LIVE symbol/file
# set. This gate pins the mirror of that pattern for acks: quality::computeStaleAcks (src/quality.h),
# surfaced on --quality-delta's report root as stale="N" plus a per-row <sa kind= key= why=/> detail —
# report, never gate: exit code must be unchanged whether or not any ack is stale.
#
# FIXTURE MECHANICS. computeStaleAcks reads ONLY the CURRENT working-tree snapshot — never the git
# baseline computeDelta compares against — so once a finding is acked, staleness is decided purely by
# rewriting the file on disk (no further git commits needed): delete the symbol entirely for target-gone,
# or shrink its body back under the bar (same canonId, same file/scope/name) for finding-gone.
#
# Checks:
#   (1) a clean, freshly-acked tree reports stale="0" and emits no <sa> rows.
#   (2) TARGET-GONE — the acked symbol is deleted outright: stale="1", why="target-gone", exit code
#       unchanged from (1).
#   (3) FINDING-GONE — the acked symbol survives (same canonId) but its complexity is refactored back
#       under the bar: stale="1", why="finding-gone", exit code unchanged from (1).
#   (4) a second, independent clean fixture also reports stale="0" (not a one-off on the first tree).
#
# Own temp repo, own private cache dir. Needs git.
# Usage:  test/staleackcheck.sh   |   test/staleackcheck.sh asan/ripwire   |   RIPWIRE_BIN=asan/ripwire test/staleackcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

REPO="$( mktemp -d )"; REPO2="$( mktemp -d )"; TMP="$( mktemp -d )"
trap 'rm -rf "$REPO" "$REPO2" "$TMP"' EXIT
XDG="$TMP/xdg"; mkdir -p "$XDG"
run(){ env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO" "$@"; }
run2(){ env -u TMPDIR XDG_CACHE_HOME="$XDG" "$BIN" "$REPO2" "$@"; }
ACKS="$REPO/.ripwire_quality_acks"

echo "staleackcheck: BIN=$BIN"

# `knotty` breaches kCcxBar (15) reliably — the same fixture shape test/qackorigincheck.sh uses to pin a
# real complexity finding, reused here so this gate does not have to re-derive a bar-breaching shape.
# Committed WITHOUT knotty first, so appending it makes an UNCOMMITTED (ackable) new-symbol finding —
# exactly test/qackorigincheck.sh's own setup.
mkdir -p "$REPO/src"
cat > "$REPO/src/lib.cpp" <<'EOF'
int stable( int a ) { return a + 1; }
EOF
git -C "$REPO" init -q; git -C "$REPO" config user.email x@y; git -C "$REPO" config user.name x
git -C "$REPO" add -A; git -C "$REPO" commit -qm init >/dev/null

cat > "$REPO/src/lib.cpp" <<'EOF'
int stable( int a ) { return a + 1; }
int knotty( int a, int b, int c ) {
    int r = 0;
    for( int i = 0; i < a; ++i ) {
        if( i % 2 == 0 ) { if( i > b ) { r += i; } else { r -= 1; } }
        else { for( int j = 0; j < b; ++j ) { if( j > c ) { r += j; } else { r--; } } }
        while( r > c && r > b ) { r = r - 1; if( r % 3 == 0 ) { r += 2; } }
    }
    return r;
}
EOF

# ── setup: ack the complexity finding on knotty() ──────────────────────────────────────────────────────
run --quality-delta --quality-ack="fixture: accepted complexity" >/dev/null 2>&1
grep -q '^ack complexity ' "$ACKS" 2>/dev/null \
    && ok "setup: complexity finding on knotty() acked" \
    || { no "setup: no complexity ack recorded — fixture vacuous, later checks are meaningless"; cat "$ACKS" 2>/dev/null; }

# ── (1) clean re-run: the acked symbol is untouched and still breaches its bar → stale="0", no <sa> rows ─
run --quality-delta >"$TMP/clean" 2>/dev/null; rcClean=$?
if grep -q 'stale="0"' "$TMP/clean" && ! grep -q '<sa ' "$TMP/clean"; then
    ok "(1) a clean, freshly-acked tree reports stale=\"0\" with no <sa> rows"
else
    no "(1) unexpected stale reporting on a clean tree"
    grep -o '<quality-delta[^>]*>\|<sa[^>]*/>' "$TMP/clean"
fi

# ── (2) TARGET-GONE: delete knotty() outright — the acked canonId no longer exists at all. knotty() is
#     uncalled, so it was ALSO a dead-code candidate at ack time (--quality-ack sweeps every CURRENT
#     finding, not just complexity) — deleting it therefore goes stale on BOTH acked kinds sharing its
#     canonId, so this checks stale=\"N\" is non-zero rather than pinning the exact count.
cat > "$REPO/src/lib.cpp" <<'EOF'
int stable( int a ) { return a + 1; }
EOF
run --quality-delta >"$TMP/targetgone" 2>/dev/null; rcTG=$?
if grep -q 'stale="[1-9]' "$TMP/targetgone" && grep -q '<sa kind="complexity"[^>]*why="target-gone"' "$TMP/targetgone"; then
    ok "(2) a deleted acked symbol is reported stale>0 including why=\"target-gone\" for its complexity ack"
else
    no "(2) target-gone case not reported correctly"
    grep -o '<quality-delta[^>]*>\|<sa[^>]*/>' "$TMP/targetgone"
fi
if [ "$rcTG" -eq "$rcClean" ]; then
    ok "(2) stale-ack disclosure does not change the exit code ($rcTG, same as the no-stale run)"
else
    no "(2) exit code changed from the no-stale run ($rcClean -> $rcTG) — disclosure must never gate"
fi

# ── (3) FINDING-GONE: knotty() survives (same canonId) but is simplified back under the complexity bar ──
cat > "$REPO/src/lib.cpp" <<'EOF'
int stable( int a ) { return a + 1; }
int knotty( int a, int b, int c ) { return a + b + c; }
EOF
run --quality-delta >"$TMP/findinggone" 2>/dev/null; rcFG=$?
if grep -q 'stale="[1-9]' "$TMP/findinggone" && grep -q '<sa kind="complexity"[^>]*why="finding-gone"' "$TMP/findinggone"; then
    ok "(3) a simplified (still-existing) symbol is reported stale>0 including why=\"finding-gone\" for its complexity ack"
else
    no "(3) finding-gone case not reported correctly"
    grep -o '<quality-delta[^>]*>\|<sa[^>]*/>' "$TMP/findinggone"
fi
if [ "$rcFG" -eq "$rcClean" ]; then
    ok "(3) stale-ack disclosure does not change the exit code ($rcFG, same as the no-stale run)"
else
    no "(3) exit code changed from the no-stale run ($rcClean -> $rcFG) — disclosure must never gate"
fi

# ── (5) M21(a): a <sa> row NAMES the ack that went stale, wherever the tree can still name it ──────────
# capture-audit 2026-09-04 (lens 0 M0-2). `<sa kind="complexity" key="4b309450f25c2b44" why="finding-gone"/>`
# is a 16-hex hash of an identity the reader does not have: to act on it — retire the ack, or look at why
# the finding stopped firing — the agent had to open .ripwire_quality_acks and then reverse a hash it
# cannot reverse. On this repo's own ledger that was 10 rows and 10 dead ends.
#
# THE RULE, and it is exactly derivable rather than best-effort: why="finding-gone" means the oracle found
# the key IN the current snapshot (that is how it told finding-gone from target-gone), so the symbol EXISTS
# and must be named. why="target-gone" means it is not there, so there is nothing to name and the why=
# already says so. The two CLONE kinds key on a member-SET hash that no live symbol carries, so they are
# never nameable — a floor, stated in the legend rather than papered over with a guess. Asserted in all
# three directions below, on the documents arms (2) and (3) already produced.
FG_ROWS="$( grep -o '<sa [^>]*why="finding-gone"[^>]*/>' "$TMP/findinggone" | grep -vE 'kind="(duplication|new-clone-of-reused-helper)' )"
if [ -z "$FG_ROWS" ]; then
    no "(5) no non-clone finding-gone row in the fixture — the arm cannot bite"
else
    FG_BAD="$( printf '%s\n' "$FG_ROWS" | grep -v ' sym="' )"
    [ -z "$FG_BAD" ] \
        && ok "(5) every non-clone why=\"finding-gone\" row names its symbol ($( printf '%s\n' "$FG_ROWS" | grep -c . ) rows)" \
        || { no "(5) a finding-gone <sa> row carries only a key hash — the reader cannot tell WHICH ack is stale"; printf '%s\n' "$FG_BAD"; }
    # and the name must be the RIGHT one, not just present: the fixture's stale complexity ack is knotty().
    printf '%s\n' "$FG_ROWS" | grep -q 'kind="complexity"[^>]*sym="[^"]*knotty"' \
        && ok "(5) the stale complexity ack is named as knotty(), the symbol it was written for" \
        || { no "(5) the finding-gone complexity row names the wrong symbol"; printf '%s\n' "$FG_ROWS"; }
    # …and it carries the LOCATOR every other row family in this document carries, so it is one paste from
    # --expand (the gating <r> rows' own p="path:line" shape).
    printf '%s\n' "$FG_ROWS" | grep -q 'kind="complexity"[^>]*p="[^"]*src/lib\.cpp:[0-9]*"' \
        && ok "(5) the named row carries p=\"path:line\", the locator the gating rows use" \
        || { no "(5) the named row carries no p= locator"; printf '%s\n' "$FG_ROWS"; }
fi
# the counterpart: target-gone is unnameable BY CONSTRUCTION, so it must not fabricate a name.
grep -o '<sa [^>]*why="target-gone"[^>]*/>' "$TMP/targetgone" | grep -q ' sym="' \
    && { no "(5) a target-gone row names a symbol the current tree does not have"; grep -o '<sa [^>]*/>' "$TMP/targetgone"; } \
    || ok "(5) target-gone rows name nothing — the tree cannot name what it no longer holds"
# and the rule itself is stated where the attribute is emitted (legendcoveragecheck's rule, pinned here too).
# the rule itself is stated where the attribute is emitted (legendcoveragecheck's rule, pinned here too).
# The legend is everything BEFORE the root start tag — a greedy <!--…--> regex over a one-line document
# would capture only the last comment.
if grep -q '<sa [^>]*sym="' "$TMP/findinggone"; then
    sed 's/<quality-delta.*//' "$TMP/findinggone" | grep -q 'sym=' \
        && ok "(5) the sa sym= rule is defined in the document's own legend" \
        || no "(5) sa sym= is emitted with no legend definition"
else
    no "(5) no sa row carried sym= — the legend arm cannot bite"
fi

# ── (4) a second, independent clean fixture also reports stale="0" — not a one-off on the first tree ────
mkdir -p "$REPO2/src"
cat > "$REPO2/src/other.cpp" <<'EOF'
int stable2( int a ) { return a + 1; }
EOF
git -C "$REPO2" init -q; git -C "$REPO2" config user.email x@y; git -C "$REPO2" config user.name x
git -C "$REPO2" add -A; git -C "$REPO2" commit -qm init >/dev/null
cat > "$REPO2/src/other.cpp" <<'EOF'
int stable2( int a ) { return a + 1; }
int knotty2( int a, int b, int c ) {
    int r = 0;
    for( int i = 0; i < a; ++i ) {
        if( i % 2 == 0 ) { if( i > b ) { r += i; } else { r -= 1; } }
        else { for( int j = 0; j < b; ++j ) { if( j > c ) { r += j; } else { r--; } } }
        while( r > c && r > b ) { r = r - 1; if( r % 3 == 0 ) { r += 2; } }
    }
    return r;
}
EOF
run2 --quality-delta --quality-ack="fixture 2: accepted complexity" >/dev/null 2>&1
run2 --quality-delta >"$TMP/clean2" 2>/dev/null
if grep -q 'stale="0"' "$TMP/clean2" && ! grep -q '<sa ' "$TMP/clean2"; then
    ok "(4) a second, independent clean fixture also reports stale=\"0\""
else
    no "(4) unexpected stale reporting on the second clean fixture"
    grep -o '<quality-delta[^>]*>\|<sa[^>]*/>' "$TMP/clean2"
fi

[ "$fail" -eq 0 ] && echo "staleackcheck: ALL PASS" || { echo "staleackcheck: SOME CHECKS FAILED"; exit 1; }
