#!/usr/bin/env bash
# qualitykeycheck.sh — THE QUALITY KEY SPACE IS PATH-QUALIFIED, INCLUDING FOR SCOPE-LESS SYMBOLS.
#
# THE DEFECT (filed as a residual by the 2026-08-24 identity round, 6cd5ba5, and fixed here):
# quality.h's computeSnapshot and computeDelta both key on `fnv1a64( baselineCanonId(...) )`, and
# resolve.h::canonicalId DEGRADES TO THE BARE NAME when a symbol has no scope. The key for a scope-less
# symbol is therefore `fnv1a64(name)` — completely PATH-INDEPENDENT — so every scope-less `helper()` in
# the tree collapses into ONE identity, and perSymbolKind aggregates that fold with max().
#
# This is not a cosmetic id problem. The fold SILENTLY HIDES REAL REGRESSIONS, which is what arm (A)
# pins: two files each define a scope-less `helper`. b.cpp's is complex (ccx 23) and never changes.
# a.cpp's goes from ccx 1 to ccx 18 — a genuine complexity regression, well over the kCcxBar of 15.
# Under the fold the baseline max is max(1,23)=23 and the current max is max(18,23)=23, so `now > was`
# is false and NOTHING is reported: regressions="0", exit 0, a clean bill of health for a function that
# just tripled in complexity. Measured on the pre-fix binary, which is why this arm is the red one.
#
# THE FIX, and what it deliberately is NOT: canonicalId is NOT touched. Path-qualifying canonicalId
# itself was measured and rejected — it inflates the default map +26.4% (id= is currently omitted for
# every scope-less row, so qualifying them makes 6,418 rows grow an attribute), a G4 breach, and it would
# SPLIT 21 CORRECT folds in src/ alone (the `extern "C" tree_sitter_X` grammar entry points are declared
# in BOTH ingest.cpp and main.cpp; they are ONE C function and the bare-name fold is what correctly
# unifies them). Instead the seven canonId-keyed quality kinds move onto the pathQualifiedKey that
# ALREADY EXISTS (quality.h, `relPath \0 scope \0 name`) — the same key d593de3 gave short-horizon-churn
# for exactly this reason. canonicalId answers "which ENTITY is this?"; the quality key must answer
# "which piece of SOURCE is this?". Arm (F) pins that canonicalId did not move.
#
# THE CONTRACT THIS GATE PINS:
#   (A) FOLD ELIMINATED — a regression on one scope-less symbol is reported even when a same-named
#       scope-less symbol in ANOTHER file is larger. RED before the fix.
#   (B) SCOPED IDENTITY UNMOVED — a scoped symbol still keys the same under an absolute and a relative
#       root spelling (the S2 root-spelling-portability rule survives the key change).
#   (C) REPLAY — an ack written under the OLD key scheme still suppresses its finding after the change.
#       This is the migration: ~270 committed acks must not die because the key rule improved.
#   (D) AMBIGUITY REFUSED, NEVER GUESSED — an old-scheme ack on a name that FOLDED across files cannot
#       be attributed to one of them, so it is refused and disclosed, not silently applied to all.
#   (E) STALE DISCLOSED — an ack naming nothing is reported through stale=, never silently dropped.
#   (F) G4 / canonicalId UNTOUCHED — a scope-less symbol still emits NO id= attribute on the default map.
#   (G) DETERMINISM — two identical runs are byte-identical.
#
# Runs on synthetic git repos so it never depends on ripwire's own debt or ack ledger.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "qualitykeycheck: SKIP — python3 needed to compute old-scheme keys"; exit 0; }

echo "qualitykeycheck: BIN=$BIN"

# FNV-1a-64 of a literal string, as 16 lowercase hex — the same hash quality.h keys with. Used to forge
# an OLD-SCHEME ack key (fnv1a64 of the canonical id) so the replay can be tested without shipping a
# second binary.
fnv(){ python3 -c '
import sys
h=14695981039346656037
for b in sys.argv[1].encode():
    h=((h^b)*1099511628211)&((1<<64)-1)
print("%016x"%h)' "$1"; }

attr(){ sed -n 's/.*<quality-delta [^>]*'"$1"'="\([^"]*\)".*/\1/p' "$2" | head -1; }

# ── fixture bodies ─────────────────────────────────────────────────────────────────────────────────
simpleA(){ cat <<'EOF'
int helper( int a )
{
    int t = 0;
    for( int i = 0; i < a; ++i ) { t += i; }
    return t;
}
EOF
}
# ccx 18 — over kCcxBar(15), and deliberately UNDER b.cpp's 23 so the fold's max() cannot move.
complexA(){ cat <<'EOF'
int helper( int a )
{
    int t = 0;
    for( int i = 0; i < a; ++i )
    {
        if( i % 2 == 0 )
        {
            if( i % 3 == 0 ) { t += i; } else { t -= i; }
        }
        else if( i % 5 == 0 )
        {
            if( i % 7 == 0 ) { t ^= i; } else { t |= i; }
        }
        else if( i % 11 == 0 )
        {
            if( i % 13 == 0 ) { t &= i; } else { t += 2; }
        }
        else
        {
            t = t * 2 + 1;
        }
    }
    return t;
}
EOF
}
# ccx 23, a DIFFERENT body shape so the duplication kind never fires and only complexity is under test.
bigB(){ cat <<'EOF'
int helper( int q )
{
    int r = 1;
    while( q > 0 )
    {
        if( q % 2 ) { if( q % 3 ) { r *= 2; } else if( q % 5 ) { r += 7; } else { r -= 1; } }
        else if( q % 7 )  { if( q % 11 ) { r ^= 3; } else { r |= 4; } }
        else if( q % 13 ) { if( q % 17 ) { r &= 9; } else { r += 5; } }
        else if( q % 19 ) { r <<= 1; }
        else if( q % 23 ) { r >>= 1; }
        else if( q % 29 ) { r += 11; }
        else if( q % 31 ) { r -= 13; }
        else { r = r * 3 + 1; }
        --q;
    }
    return r;
}
EOF
}
# a SCOPED symbol — its canonical id really is path::scope::name
scopedSimple(){ cat <<'EOF'
struct Widget
{
    int compute( int a )
    {
        int t = 0;
        for( int i = 0; i < a; ++i ) { t += i; }
        return t;
    }
};
EOF
}
scopedComplex(){ cat <<'EOF'
struct Widget
{
    int compute( int a )
    {
        int t = 0;
        for( int i = 0; i < a; ++i )
        {
            if( i % 2 == 0 )
            {
                if( i % 3 == 0 ) { t += i; } else { t -= i; }
            }
            else if( i % 5 == 0 )
            {
                if( i % 7 == 0 ) { t ^= i; } else { t |= i; }
            }
            else if( i % 11 == 0 )
            {
                if( i % 13 == 0 ) { t &= i; } else { t += 2; }
            }
            else
            {
                t = t * 2 + 1;
            }
        }
        return t;
    }
};
EOF
}

newrepo(){ local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"; ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t ); echo "$d"; }

# ── (A) THE FOLD IS ELIMINATED — the red-first arm ──────────────────────────────────────────────────
D="$( newrepo fold )"
( cd "$D" && simpleA > a.cpp && bigB > b.cpp && git add -A && git commit -qm base )
( cd "$D" && complexA > a.cpp )
"$BIN" "$D" --quality-delta > "$TMP/fold.xml" 2>/dev/null
if grep -q 'kind="complexity"' "$TMP/fold.xml"; then
    ok "(A) the complexity regression on a.cpp::helper is REPORTED (fold eliminated)"
else
    no "(A) a.cpp::helper went ccx 1 -> 18 and NOTHING was reported — the bare-name fold hid it behind b.cpp::helper's 23"
fi
# and it must be attributed to the RIGHT file
if grep -q 'kind="complexity"[^>]*p="a\.cpp' "$TMP/fold.xml"; then
    ok "(A2) the finding is located at a.cpp, the file that actually regressed"
else
    no "(A2) complexity finding not located at a.cpp: $( grep -o 'kind="complexity"[^>]*' "$TMP/fold.xml" | head -1 )"
fi
# b.cpp did NOT change, so it must NOT be reported
if grep -o 'kind="complexity"[^>]*' "$TMP/fold.xml" | grep -q 'p="b\.cpp'; then
    no "(A3) b.cpp::helper is unchanged but was reported — the split over-reports"
else
    ok "(A3) b.cpp::helper, unchanged, is NOT reported"
fi

# ── (B) a SCOPED symbol keys the same under absolute and relative root spellings ────────────────────
D="$( newrepo scoped )"
( cd "$D" && scopedSimple > w.cpp && git add -A && git commit -qm base )
( cd "$D" && scopedComplex > w.cpp )
"$BIN" "$D" --quality-delta > "$TMP/abs.xml" 2>/dev/null
( cd "$D" && "$BIN" . --quality-delta > "$TMP/rel.xml" 2>/dev/null )
a_reg="$( attr regressions "$TMP/abs.xml" )"; r_reg="$( attr regressions "$TMP/rel.xml" )"
if [ -n "$a_reg" ] && [ "$a_reg" = "$r_reg" ] && grep -q 'kind="complexity"' "$TMP/abs.xml"; then
    ok "(B) scoped identity is root-spelling-portable (abs=$a_reg rel=$r_reg)"
else
    no "(B) scoped symbol keyed differently by root spelling: abs=$a_reg rel=$r_reg"
fi

# ── (C) REPLAY — an ack written under the OLD key scheme still suppresses ───────────────────────────
# The old scheme hashed the canonical id text. For Widget::compute in w.cpp under root ".", that text is
# exactly the id= the map emits, so read it from the binary rather than hard-coding a path spelling.
D="$( newrepo replay )"
( cd "$D" && scopedSimple > w.cpp && git add -A && git commit -qm base )
( cd "$D" && scopedComplex > w.cpp )
CANON="$( cd "$D" && "$BIN" . --top-k=50 2>/dev/null | tr '>' '>\n' | sed -n 's/.*n="compute" id="\([^"]*\)".*/\1/p' | head -1 )"
if [ -z "$CANON" ]; then
    no "(C) could not read the emitted canonical id for Widget::compute"
else
    OLDKEY="$( fnv "$CANON" )"
    printf '# ripwire quality acks v1\nack complexity %s 18 forged old-scheme ack for the replay arm\n' "$OLDKEY" > "$D/.ripwire_quality_acks"
    ( cd "$D" && "$BIN" . --quality-delta > "$TMP/replay.xml" 2>/dev/null )
    acked="$( attr acked "$TMP/replay.xml" )"
    if [ "${acked:-0}" -ge 1 ] 2>/dev/null; then
        ok "(C) an OLD-scheme ack (key=$OLDKEY for $CANON) still suppresses after the key change (acked=$acked)"
    else
        no "(C) old-scheme ack was NOT replayed forward — acked=$acked; ~270 committed acks would die"
    fi
fi

# ── (D) AMBIGUITY IS REFUSED, NEVER GUESSED ────────────────────────────────────────────────────────
# `helper` folds across a.cpp and b.cpp. An old-scheme ack keyed on the bare name cannot name which one,
# so it must NOT silently suppress a finding on either.
D="$( newrepo ambig )"
( cd "$D" && simpleA > a.cpp && bigB > b.cpp && git add -A && git commit -qm base )
( cd "$D" && complexA > a.cpp )
OLDBARE="$( fnv "helper" )"
printf '# ripwire quality acks v1\nack complexity %s 18 forged ambiguous bare-name ack\n' "$OLDBARE" > "$D/.ripwire_quality_acks"
( cd "$D" && "$BIN" . --quality-delta > "$TMP/ambig.xml" 2>/dev/null )
if grep -q 'kind="complexity"' "$TMP/ambig.xml"; then
    ok "(D) a bare-name ack over a FOLDED name did not suppress — ambiguity refused, not guessed"
else
    no "(D) an ambiguous bare-name ack suppressed a finding it cannot be shown to cover: $( attr acked "$TMP/ambig.xml" ) acked"
fi

# ── (E) a STALE ack is DISCLOSED, not silently dropped ─────────────────────────────────────────────
D="$( newrepo stale )"
( cd "$D" && scopedSimple > w.cpp && git add -A && git commit -qm base )
( cd "$D" && scopedComplex > w.cpp )
printf '# ripwire quality acks v1\nack complexity %s 99 an ack naming nothing at all\n' "$( fnv "no/such/file.cpp::Nobody::nothing" )" > "$D/.ripwire_quality_acks"
( cd "$D" && "$BIN" . --quality-delta > "$TMP/stale.xml" 2>/dev/null )
st="$( attr stale "$TMP/stale.xml" )"
if [ "${st:-0}" -ge 1 ] 2>/dev/null; then
    ok "(E) an ack naming nothing is disclosed through stale= (stale=$st)"
else
    no "(E) a stale ack vanished silently instead of being disclosed (stale=$st)"
fi

# ── (F) G4 — canonicalId was NOT touched: a scope-less symbol still emits NO id= ────────────────────
D="$( newrepo g4 )"
( cd "$D" && simpleA > a.cpp )
row="$( "$BIN" "$D" --top-k=50 2>/dev/null | tr '>' '>\n' | grep -o '<s [^>]*n="helper"[^>]*' | head -1 )"
case "$row" in
    *' id="'*) no "(F) a scope-less symbol grew an id= attribute — canonicalId moved, and that is the +26.4% G4 breach: $row" ;;
    '')        no "(F) could not find the helper row on the default map" ;;
    *)         ok "(F) scope-less symbols still emit no id= — canonicalId untouched, map density preserved" ;;
esac

# ── (G) DETERMINISM ────────────────────────────────────────────────────────────────────────────────
D="$( newrepo det )"
( cd "$D" && simpleA > a.cpp && bigB > b.cpp && git add -A && git commit -qm base )
( cd "$D" && complexA > a.cpp )
"$BIN" "$D" --quality-delta > "$TMP/d1.xml" 2>/dev/null
"$BIN" "$D" --quality-delta > "$TMP/d2.xml" 2>/dev/null
if cmp -s "$TMP/d1.xml" "$TMP/d2.xml"; then
    ok "(G) two --quality-delta runs are byte-identical"
else
    no "(G) --quality-delta is not deterministic across two runs"
fi

[ "$fail" -eq 0 ] && echo "qualitykeycheck: ALL PASS" || echo "qualitykeycheck: FAILURES"
exit "$fail"
