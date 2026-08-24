#!/usr/bin/env bash
# identitycheck.sh — FINDING IDENTITY SURVIVES A RENAME OR A MOVE, and NOT a real change.
#
# THE DEFECT: an ack's identity is
# `hash(path::scope::name)` (or pathQualifiedKey for short-horizon-churn) — PATH-QUALIFIED on every side.
# Rename the file, or move the symbol, and every ack recorded against it dies silently: the finding comes
# back as brand new, and the reason someone wrote for accepting it is stranded in the ledger forever. The
# measured evidence, replayed from this repo's own history before any of this was written: on commit
# 0eacce7 — ten leaf headers moved into src/infra/, not one byte of code changed — identity survival under
# today's keying is 0 of 59 canonId identities, 0 of 59 pathQualifiedKeys and 0 of 4 clone groups. The
# other three rename commits carrying indexed symbols measure the same 0%.
#
# THE CONTRACT THIS GATE PINS — three claims, none of which may be traded for either of the others:
#   (A) An ack SURVIVES a file rename, whether the rename is staged in the working tree or already
#       committed (the git-recorded rename map, pinned `-c diff.renames=true -M50%`).
#   (B) An ack SURVIVES a pure move that git records no rename for at all — a symbol relocated between two
#       files that both merely "changed" — via scrubbed-content-hash equality, INCLUDING when the move
#       re-indents the body (a namespace/class wrap). The re-indent arm is not decoration: raw-body-hash
#       equality measured 37.3% survival under a +4-space re-indent versus 100% on byte-identical moves,
#       which is what makes the whitespace scrub a requirement rather than a nicety.
#   (C) An ack does NOT survive a real change. Identity that follows a rename must not become identity that
#       follows a rewrite — that would turn the ratchet into the blank check its own contract forbids. Two
#       arms hold this edge: a WORSENED finding re-reports across a rename (magnitude ratchet intact), and a
#       moved-AND-rewritten body is NOT content-matched (the scrub is whitespace/name, never semantics).
#
# Runs on a synthetic git repo so it never depends on ripwire's own current debt or ack ledger.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }

echo "identitycheck: BIN=$BIN"

# attr VALUE of $1 from the <quality-delta …> root in file $2 ("" when absent)
attr(){ sed -n 's/.*<quality-delta [^>]*'"$1"'="\([^"]*\)".*/\1/p' "$2" | head -1; }

# ── the fixture: one SCOPED symbol, so its canonical id really is path::scope::name ────────────────────
# A scope-LESS free function degrades to a bare-name canonId (resolve.h::canonicalId) and would already
# survive a rename by accident — the wrong thing to measure. Widget::compute is path-qualified for real.
simple(){ cat <<'EOF'
#pragma once
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
# the SAME symbol, markedly more complex — the complexity finding this gate acks and then chases
complex(){ cat <<'EOF'
#pragma once
struct Widget
{
    int compute( int a )
    {
        int t = 0;
        for( int i = 0; i < a; ++i )
        {
            if( i % 2 == 0 )       { if( i % 3 == 0 ) { t += i * 2; } else { t += i; } }
            else if( i % 5 == 0 )  { if( i % 7 == 0 ) { t -= i * 2; } else { t -= i; } }
            else if( i % 11 == 0 ) { t += 1; }
            else                   { if( i > 100 ) { t -= 1; } else { t += 3; } }
        }
        return t;
    }
};
EOF
}
# worse still — used only to prove the magnitude ratchet still fires ACROSS a rename (claim C)
worse(){ cat <<'EOF'
#pragma once
struct Widget
{
    int compute( int a )
    {
        int t = 0;
        for( int i = 0; i < a; ++i )
        {
            if( i % 2 == 0 )       { if( i % 3 == 0 ) { t += i * 2; } else { t += i; } }
            else if( i % 5 == 0 )  { if( i % 7 == 0 ) { t -= i * 2; } else { t -= i; } }
            else if( i % 11 == 0 ) { if( i % 13 == 0 ) { t += 5; } else { t += 1; } }
            else if( i % 17 == 0 ) { if( i % 19 == 0 ) { t -= 5; } else { t -= 1; } }
            else if( i % 23 == 0 ) { if( i % 29 == 0 ) { t += 7; } else { t += 2; } }
            else                   { if( i > 100 ) { t -= 1; } else { t += 3; } }
        }
        return t;
    }
};
EOF
}

newrepo(){                                   # $1 = dir; leaves you cd'd into a fresh repo at commit "base"
    rm -rf "$1"; mkdir -p "$1/src"; cd "$1"
    git init -q .; git config user.email t@t; git config user.name t
    simple > src/lib.h
    git add -A; git commit -qm base
}

# ═══ arm 1 — CONTROL: the ratchet works at all, before any rename enters the picture ═══════════════════
newrepo "$TMP/r1"
complex > src/lib.h
"$BIN" . --quality-delta > "$TMP/d1" 2>/dev/null
grep -q 'kind="complexity"' "$TMP/d1" && ok "(1a) complexity finding fires on the worsened symbol" \
                                      || no "(1a) no complexity finding to ack — fixture broken"
"$BIN" . --quality-ack="fixture" >/dev/null 2>&1
"$BIN" . --quality-delta > "$TMP/d1b" 2>/dev/null
[ "$( attr acked "$TMP/d1b" )" = "1" ] && ok "(1b) the ack suppresses it (acked=1)" \
                                       || no "(1b) acked=$( attr acked "$TMP/d1b" ), expected 1"

# ═══ arm 2 — claim A, STAGED rename: git mv in the working tree, ack must follow the file ══════════════
mkdir -p src/core
git mv src/lib.h src/core/lib.h
"$BIN" . --quality-delta > "$TMP/d2" 2>/dev/null
[ "$( attr acked "$TMP/d2" )" = "1" ] && ok "(2a) ack survives a STAGED git mv (acked=1)" \
                                      || no "(2a) ack died on a staged rename: acked=$( attr acked "$TMP/d2" ) regressions=$( attr regressions "$TMP/d2" )"
[ "$( attr regressions "$TMP/d2" )" = "0" ] && ok "(2b) the finding does not come back as new" \
                                            || no "(2b) regressions=$( attr regressions "$TMP/d2" ), expected 0"
[ -n "$( attr renames "$TMP/d2" )" ] && ok "(2c) the rename map is DISCLOSED (renames= present)" \
                                     || no "(2c) no renames= on the root — an identity that follows renames must say so"
[ "$( attr acked_by_rename "$TMP/d2" )" = "1" ] && ok "(2d) the rescue ROUTE is disclosed (acked_by_rename=1)" \
                                                || no "(2d) acked_by_rename=$( attr acked_by_rename "$TMP/d2" ), expected 1"

# ═══ arm 3 — claim A, COMMITTED rename: the durable case (git log -M50%), not just the staged one ══════
newrepo "$TMP/r3"
complex > src/lib.h
"$BIN" . --quality-ack="fixture" >/dev/null 2>&1     # ack recorded against src/lib.h
git add -A; git commit -qm worsen                    # the finding is now HEAD; delta vs HEAD is empty
mkdir -p src/core; git mv src/lib.h src/core/lib.h; git commit -qm "pure rename"
simple > src/core/lib.h                              # rewind the body so the delta has something to say…
git add -A; git commit -qm simplify
complex > src/core/lib.h                             # …and re-introduce exactly the acked finding, at the NEW path
"$BIN" . --quality-delta > "$TMP/d3" 2>/dev/null
[ "$( attr acked "$TMP/d3" )" = "1" ] && ok "(3a) ack survives a COMMITTED rename (acked=1)" \
                                      || no "(3a) ack died on a committed rename: acked=$( attr acked "$TMP/d3" ) regressions=$( attr regressions "$TMP/d3" )"
[ "$( attr acked_by_rename "$TMP/d3" )" = "1" ] && ok "(3b) rescued by the rename map, disclosed" \
                                                || no "(3b) acked_by_rename=$( attr acked_by_rename "$TMP/d3" ), expected 1"

# ═══ arm 4 — claim C: a WORSENED finding re-reports across the rename (the ratchet is not a blank check) ═
worse > src/core/lib.h
"$BIN" . --quality-delta > "$TMP/d4" 2>/dev/null
grep -q 'kind="complexity"' "$TMP/d4" && ok "(4a) worsening past the acked magnitude RE-REPORTS across a rename" \
                                      || no "(4a) a worsened finding stayed suppressed — identity became a blank check"
[ "$( attr regressions "$TMP/d4" )" -ge 1 ] 2>/dev/null && ok "(4b) it is counted, not just printed" \
                                                        || no "(4b) regressions=$( attr regressions "$TMP/d4" ), expected >=1"

# ═══ arm 5 — claim B: a PURE MOVE git records no rename for (two files merely 'change') ════════════════
newrepo "$TMP/r5"
printf '#pragma once\nstruct Other { int keep( int a ) { return a + 41; } };\n' > src/other.h
git add -A; git commit -qm two-files
complex > src/lib.h
"$BIN" . --quality-ack="fixture" >/dev/null 2>&1
git add -A; git commit -qm worsen
# move Widget into src/other.h and leave src/lib.h behind with unrelated content: both files are MODIFIED,
# neither is added or deleted, so `git diff -M` has no rename to record. Only content can find it.
{ printf '#pragma once\nstruct Other { int keep( int a ) { return a + 41; } };\n'; complex | tail -n +2; } > src/other.h
printf '#pragma once\nstruct Leftover { int noop() { return 0; } };\n' > src/lib.h
"$BIN" . --quality-delta > "$TMP/d5" 2>/dev/null
[ "$( attr acked "$TMP/d5" )" = "1" ] && ok "(5a) ack survives a pure MOVE with no git rename record (acked=1)" \
                                      || no "(5a) ack died on a pure move: acked=$( attr acked "$TMP/d5" ) regressions=$( attr regressions "$TMP/d5" )"
[ "$( attr acked_by_content "$TMP/d5" )" = "1" ] && ok "(5b) rescued by content hash, disclosed (acked_by_content=1)" \
                                                 || no "(5b) acked_by_content=$( attr acked_by_content "$TMP/d5" ), expected 1"

# ═══ arm 6 — claim B, the RE-INDENT: a move that wraps the body in a namespace ═════════════════════════
# Measured on this repo's own 0eacce7: raw-body-hash equality falls 100% -> 37.3% under a +4-space
# re-indent. If this arm passes only because nothing was re-indented, the scrub is not doing its job.
newrepo "$TMP/r6"
printf '#pragma once\nstruct Other { int keep( int a ) { return a + 41; } };\n' > src/other.h
git add -A; git commit -qm two-files
complex > src/lib.h
"$BIN" . --quality-ack="fixture" >/dev/null 2>&1
git add -A; git commit -qm worsen
{ printf '#pragma once\nnamespace wrapped\n{\n'; complex | tail -n +2 | sed 's/^./    &/'; printf '}\n'; } > src/other.h
printf '#pragma once\nstruct Leftover { int noop() { return 0; } };\n' > src/lib.h
"$BIN" . --quality-delta > "$TMP/d6" 2>/dev/null
[ "$( attr acked "$TMP/d6" )" = "1" ] && ok "(6) ack survives a move that RE-INDENTS the body (acked=1)" \
                                      || no "(6) re-indented move lost the ack: acked=$( attr acked "$TMP/d6" ) — the content hash is not whitespace-scrubbed"

# ═══ arm 7 — claim C: moved AND REWRITTEN is a real change; content must NOT match ═════════════════════
newrepo "$TMP/r7"
printf '#pragma once\nstruct Other { int keep( int a ) { return a + 41; } };\n' > src/other.h
git add -A; git commit -qm two-files
complex > src/lib.h
"$BIN" . --quality-ack="fixture" >/dev/null 2>&1
git add -A; git commit -qm worsen
{ printf '#pragma once\nstruct Other { int keep( int a ) { return a + 41; } };\n'; worse | tail -n +2; } > src/other.h
printf '#pragma once\nstruct Leftover { int noop() { return 0; } };\n' > src/lib.h
"$BIN" . --quality-delta > "$TMP/d7" 2>/dev/null
[ "$( attr acked_by_content "$TMP/d7" )" = "0" ] || [ -z "$( attr acked_by_content "$TMP/d7" )" ] \
    && ok "(7) a moved-and-REWRITTEN body is not content-matched (the scrub is not semantic)" \
    || no "(7) acked_by_content=$( attr acked_by_content "$TMP/d7" ) — a rewritten body was treated as the same finding"

# ═══ arm 8 — the ledger's cid= field round-trips, and a v1 (cid-less) ledger still reads ═══════════════
newrepo "$TMP/r8"
complex > src/lib.h
"$BIN" . --quality-ack="fixture reason" >/dev/null 2>&1
grep -q 'cid=' .ripwire_quality_acks && ok "(8a) --quality-ack records the content id (cid=)" \
                                     || no "(8a) no cid= written — content rescue can never fire"
grep -q 'fixture reason' .ripwire_quality_acks && ok "(8b) the reason still runs to end of line" \
                                               || no "(8b) cid= ate the reason field"
cp .ripwire_quality_acks "$TMP/v2.acks"
"$BIN" . --quality-ack="fixture reason" >/dev/null 2>&1        # read -> write round trip
diff -q "$TMP/v2.acks" .ripwire_quality_acks >/dev/null && ok "(8c) ledger round-trips byte-identically" \
                                                        || no "(8c) a read->write round trip churned the ledger"
sed -E 's/ cid=[0-9a-f]+ / /' "$TMP/v2.acks" > .ripwire_quality_acks     # a v1 ledger, as an old binary wrote it
"$BIN" . --quality-delta > "$TMP/d8" 2>/dev/null
[ "$( attr acked "$TMP/d8" )" = "1" ] && ok "(8d) a v1 (cid-less) ledger still suppresses by key" \
                                      || no "(8d) dropping cid= broke the plain key path: acked=$( attr acked "$TMP/d8" )"

# ═══ arm 9 — determinism: identity resolution must not make the report timing-dependent ════════════════
newrepo "$TMP/r9"
complex > src/lib.h
"$BIN" . --quality-ack="fixture" >/dev/null 2>&1
mkdir -p src/core; git mv src/lib.h src/core/lib.h
"$BIN" . --quality-delta > "$TMP/d9a" 2>/dev/null
"$BIN" . --quality-delta > "$TMP/d9b" 2>/dev/null
diff -q "$TMP/d9a" "$TMP/d9b" >/dev/null && ok "(9) two runs over a renamed tree are byte-identical" \
                                         || no "(9) rename-aware identity made the report non-deterministic"

cd "$ROOT"
[ $fail -eq 0 ] && echo "identitycheck: ALL PASS" || echo "identitycheck: FAIL"
exit $fail
