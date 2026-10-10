#!/usr/bin/env bash
# localitycheck.sh — the S6-C locality tie-break gate (adversarial HIGH-1 regression + the receiver-type credit).
#
#   test/localitycheck.sh                       # uses build/ripwire on test/localityfix
#   RIPWIRE_BIN=asan/ripwire test/localitycheck.sh
#
# Arms 1-4 — HIGH-1. The fixture test/localityfix/loc.cpp has two UNRELATED classes Xtra and Bravo that BOTH
# define go(). The class template Xenon<Base> calls `this->go()` — a method of its template-parameter base, which
# the index cannot see. The caller scope "Xenon" shares only a leading LETTER with "Xtra" — NOT a real structural
# prefix. The old raw-byte locality tie-break scored `Xenon`↔`Xtra` higher than `Xenon`↔`Bravo` and resolved the
# call CONFIDENTLY to the WRONG Xtra::go (ambiguous=0). The fix makes locality SEGMENT-aware (`/`/`::`), so the
# partial in-segment overlap counts as ZERO: Xtra and Bravo tie on path-only locality and the call stays HONESTLY
# ambiguous. This gate asserts:
#   * the call NEVER resolves to a lone confident pick of the unrelated Xtra::go
#   * it either stays split (count=2) or resolves to Bravo::go — never a wrong one
#   * the call REACHED the tie-break with both candidates (census pre=2): the arm is live, not vacuously split
#   * `ambiguous` > 0 on the fixture (the resolver is HONEST, not falsely certain)
#   * determinism (run twice → byte-identical) and no symbol loss / well-formed XML
#
# Arms 5-9 — THE SCOPE-SEGMENT CREDIT IS EVIDENCE ONLY FOR `this`/bare calls (2026-09-16). The tie-break prefers
# the candidate sharing the longest segment prefix with the caller — same file, then same CLASS. For an explicit
# receiver whose type no receiver rule (2, 2b, 2c) established, the caller's own class winning that credit is
# anti-evidence: `auto other = make(); other->pick( 1 )` inside Decoy::untypedLocal pinned Decoy::pick — one precise
# edge, no amb=. Measured with --pin-census on real corpora, the dominant shape is delegation through a member whose
# type Rule 2b cannot read (`rep_->Name()` inside `Wrapper::Name`, `tree_.upper_bound( key )` inside
# `btree_container::upper_bound`): 14 of 14 sampled pins wrong on rocksdb, 14 of 16 on a private C++ corpus. Such a
# receiver now keeps the file and directory credit and loses the scope segments, so the call splits and says so.
#   5  an untyped local receiver splits (RED on the unfixed binary: locality pin to Decoy::pick)
#   6  a member receiver of a type Rule 2b cannot read (`ns::Handle<Target> rep_`) splits (RED: Wrapper::pick)
#  6b  control — a `std::unique_ptr<Target>` member, which Rule 2b reads since test/fieldnarrowcheck.sh arm p, narrows
#      `owned_->pick()` to Target::pick alone (receiver-rule). Arm 6 held that member until then, as the unreadable type.
#   7  a TYPED receiver whose type defines no such method (`Shape& other`) splits (RED: Decoy::pick)
#   8  control — {the caller itself, Target::peek} answers Target::peek; since FE-B the call is name-only, so the
#      disclosure is via="name" on the row (census mech=unique), no longer the locality pin. Skipping the tie-break for these receivers moved no target on seven
#      corpora either, but relabelled every such site `unique` and dropped its lpin= disclosure.
#   9  control — a typed receiver Rule 2 narrows is untouched (receiver-rule, Target::pick alone)
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/localityfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "localitycheck: BIN=$BIN  CORPUS=$CORPUS"

# the two candidate definitions' lines, read from the fixture (presence guard: both must be found)
XTRA_LINE="$( grep -n '^int Xtra::go()' "$CORPUS/loc.cpp" | cut -d: -f1 )"
BRAVO_LINE="$( grep -n '^int Bravo::go()' "$CORPUS/loc.cpp" | cut -d: -f1 )"
if [ -n "$XTRA_LINE" ] && [ -n "$BRAVO_LINE" ]; then ok "presence: Xtra::go at loc.cpp:$XTRA_LINE, Bravo::go at loc.cpp:$BRAVO_LINE"
else no "presence: the fixture's Xtra::go / Bravo::go definitions were not found (xtra=${XTRA_LINE:-?} bravo=${BRAVO_LINE:-?})"; fi

# 1) determinism — same input, byte-identical output run-to-run (the tie-break must stay deterministic)
"$BIN" "$CORPUS" --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --no-cache >"$TMP/b" 2>/dev/null
if diff -q "$TMP/a" "$TMP/b" >/dev/null; then ok "determinism (byte-identical, $(wc -c <"$TMP/a" | tr -d ' ') B)"; else no "determinism (non-deterministic output)"; fi

# 2) the spurious-prefix call (`this->go()` in Xenon::call) must NOT be a lone confident pick of the WRONG class.
CALLEES="$( "$BIN" "$CORPUS" --callees=call --no-cache 2>/dev/null )"
NEDGE="$( printf '%s' "$CALLEES" | grep -o 'count="[0-9]*"' | grep -o '[0-9]*' )"
HAS_XTRA="$( printf '%s' "$CALLEES" | grep -c "loc.cpp:${XTRA_LINE:-none}\"" )"     # Xtra::go (the WRONG class)
HAS_BRAVO="$( printf '%s' "$CALLEES" | grep -c "loc.cpp:${BRAVO_LINE:-none}\"" )"   # Bravo::go

# the core regression assertion: a lone confident edge to ONLY the unrelated Xtra::go is the bug.
if [ "$NEDGE" = "1" ] && [ "$HAS_XTRA" -ge 1 ] && [ "$HAS_BRAVO" -eq 0 ]; then
    no "REGRESSION: call resolves CONFIDENTLY to the WRONG unrelated class Xtra::go (loc.cpp:$XTRA_LINE) — the HIGH-1 bug"
    printf '    %s\n' "$CALLEES"
else
    ok "no false-confident pick of the unrelated Xtra::go (count=${NEDGE:-?})"
fi

# acceptable outcomes: stay split (count=2, both go() present) OR resolve to Bravo::go only.
if { [ "$NEDGE" = "2" ] && [ "$HAS_XTRA" -ge 1 ] && [ "$HAS_BRAVO" -ge 1 ]; } || { [ "$NEDGE" = "1" ] && [ "$HAS_BRAVO" -ge 1 ] && [ "$HAS_XTRA" -eq 0 ]; }; then
    ok "call is honestly ambiguous (split 2) or narrowed to Bravo::go — never a wrong confident pick"
else
    no "unexpected resolution shape (count=${NEDGE:-?}, xtra=$HAS_XTRA, bravo=$HAS_BRAVO)"
    printf '    %s\n' "$CALLEES"
fi

# liveness: the call must REACH the tie-break holding both candidates — a call some earlier rule settled (or one that
# never reached S6-C) would pass the two arms above without exercising segment-awareness at all.
"$BIN" "$CORPUS" --no-cache --pin-census="$TMP/loc.tsv" >/dev/null 2>&1
PRE="$( awk -F '\t' '$1 == "C" && $6 ~ /::Xenon::call#/ && $7 == "go" { print $3 }' "$TMP/loc.tsv" 2>/dev/null | head -1 )"
[ "$PRE" = "2" ] && ok "liveness: Xenon::call's go site reached the tie-break with both candidates (census pre=2)" \
                 || no "liveness: Xenon::call's go site pre=[${PRE:-NO-CENSUS-ROW}], want 2 — the arm no longer exercises the tie-break"

# 3) ambiguous= header count is > 0 — the resolver is HONEST about the unresolved same-name call, not falsely
#    certain (ambiguous=0 was the bug's false-confidence signature). This count RISING is the fix working.
AMB="$( "$BIN" "$CORPUS" --no-cache 2>/dev/null | grep -o 'ambiguous=[0-9]*' | grep -o '[0-9]*' )"
if [ "${AMB:-0}" -gt 0 ]; then ok "ambiguous=$AMB on the fixture (>0 — honest, was falsely 0 with the byte-prefix bug)"; else no "ambiguous=${AMB:-?} on the fixture (expected >0 — the resolver is falsely confident)"; fi

# 4) no symbol loss + well-formed XML (the corrected tie-break must not corrupt the map or drop symbols).
MAP="$( "$BIN" "$CORPUS" --no-cache 2>/dev/null )"
if printf '%s' "$MAP" | grep -q 'n="call"'; then ok "call symbol still present (no symbol loss)"; else no "call symbol vanished"; fi
if printf '%s' "$MAP" | grep -q 'n="go"'; then ok "go symbols still present (no symbol loss)"; else no "go symbols vanished"; fi
command -v xmllint >/dev/null 2>&1 && { if printf '%s' "$MAP" | xmllint --noout - 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi; } || ok "xml well-formed (xmllint absent — skipped)"

# ── Arms 5-9: explicit receivers (see the header). LINE NUMBERS ARE ASSERTED BELOW — edit with care.
#   Target::pick/peek r.cpp:1   Decoy::pick r.cpp:6   Wrapper::pick r.cpp:15
RFIX="$TMP/recvfix"
mkdir -p "$RFIX"
cat >"$RFIX/r.cpp" <<'EOF'
struct Target { int pick( int n ) { return n; } int peek( int n ) { return n; } };
Target* make();
struct Shape { int area() { return 0; } };
struct Decoy
{
    int pick( int n ) { return n; }
    int peek( int n ) { auto other = make(); return other->peek( n ); }
    int untypedLocal() { auto other = make(); return other->pick( 1 ); }
    int typedNoMethod( Shape& other ) { return other.pick( 1 ); }
    int typedLocal() { Target other; return other.pick( 1 ); }
};
struct Wrapper
{
    ns::Handle<Target> rep_; std::unique_ptr<Target> owned_;
    int pick( int n ) { return n; }
    int forward( int n ) { return rep_->pick( n ); }
    int forwardOwned( int n ) { return owned_->pick( n ); }
};
EOF
"$BIN" "$RFIX" --no-cache --pin-census="$TMP/recv.tsv" >/dev/null 2>&1

# one caller's callee rows (selector `Class::method`) as sorted `name@line` words for one method name; a probe that did
# not run — or matched more than one definition — prints a marker no assertion accepts
rowsOf(){
    local out
    out="$( "$BIN" "$RFIX" "--callees=$1" --no-cache 2>/dev/null )"
    printf '%s' "$out" | grep -q "<callees [^>]*of=\"$1\" defs=\"1\"" || { printf 'NO-CALLEES-ANSWER'; return; }
    printf '%s' "$out" | grep -o '<s [^>]*>' | sed -n 's/.* n="\([^"]*\)".* p="r\.cpp:\([0-9]*\)".*/\1@\2/p' \
        | grep "^$2@" | sort -u | tr '\n' ' ' | sed 's/ $//'
}
# the census mechanism for one (Class::caller, callee) site
mechOf(){ awk -F '\t' -v c="::$1#" -v n="$2" '$1 == "C" && index( $6, c ) > 0 && $7 == n { print $2 }' "$TMP/recv.tsv" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//'; }
expectSite(){   # arm label, Class::caller, callee, the exact expected row set, the expected census mechanism
    local got mech
    got="$( rowsOf "$2" "$3" )"
    mech="$( mechOf "$2" "$3" )"
    if [ "$got" = "$4" ] && [ "$mech" = "$5" ]; then ok "$1 $2(): $3 -> [$got] mech=$mech"
    else no "$1 $2(): $3 -> [$got] mech=[${mech:-NO-CENSUS-ROW}], want [$4] mech=$5"; fi
}

# presence guard: every probed caller and every candidate def is indexed, or the arms below prove nothing
RMAP="$( "$BIN" "$RFIX" --no-cache 2>/dev/null | tr '>' '\n' )"
rmiss=0
for want in 'n="pick" sc="Target"' 'n="peek" sc="Target"' 'n="pick" sc="Decoy"' 'n="peek" sc="Decoy"' 'n="pick" sc="Wrapper"' \
            'n="untypedLocal" sc="Decoy"' 'n="typedNoMethod" sc="Decoy"' 'n="typedLocal" sc="Decoy"' 'n="forward" sc="Wrapper"' 'n="forwardOwned" sc="Wrapper"'; do
    printf '%s\n' "$RMAP" | grep -qF "$want" || { no "presence guard: recvfix symbol $want not indexed"; rmiss=1; }
done
[ "$rmiss" = 0 ] && ok "presence: all recvfix symbols indexed"

# ── 5) an UNTYPED local receiver: no scope credit, so Decoy::pick no longer wins — the three same-file picks split.
expectSite "(5)" Decoy::untypedLocal pick "pick@1 pick@15 pick@6" split
# ── 6) delegation through a member whose type Rule 2b cannot read (the measured dominant shape).
expectSite "(6)" Wrapper::forward pick "pick@1 pick@15 pick@6" split
# ── 6b) control: the member Rule 2b CAN read — a std smart pointer's pointee through `->` — is a narrow, not a split.
expectSite "(6b)" Wrapper::forwardOwned pick "pick@1" receiver-rule
# ── 7) a TYPED receiver whose type defines no `pick`: Rule 2 declines, CHA-lite's cone keeps nothing and degrades.
expectSite "(7)" Decoy::typedNoMethod pick "pick@1 pick@15 pick@6" split
# ── 8) control — the target stays: the tier is {Decoy::peek itself, Target::peek}; the caller is never its own answer, so
#       Target::peek is the one row. Since FE-B (test/receiverevidencecheck.sh) an untyped receiver's call is NAME-ONLY and
#       never reaches the tie-break, so the disclosure moved from the census's `locality` pin to the row itself: via="name"
#       (the census labels a lone name-only target `unique`, as it labels a lone global).
expectSite "(8)" Decoy::peek peek "peek@1" unique
"$BIN" "$RFIX" --callees=Decoy::peek --no-cache 2>/dev/null | grep -q '<s t="method" n="peek" p="r.cpp:1" via="name"/>' \
    && ok "(8) Decoy::peek(): the Target::peek row says via=\"name\" — the pick is disclosed on the row" \
    || no "(8) Decoy::peek(): the Target::peek row is not marked via=\"name\""
# ── 9) control — Rule 2 narrows a typed local before the tie-break: one precise edge, untouched.
expectSite "(9)" Decoy::typedLocal pick "pick@1" receiver-rule

# ── 10) (cli-perf-068) the per-(name, language) candidate memo answers every call as the plain walk did. One name, `ok`,
#       is defined in 18 shell scripts AND 18 Python files (36 definitions, past the memo's 16-candidate floor), and each
#       file calls its own `ok` at module scope. The same-file tier must pick the caller's OWN file in the caller's OWN
#       language for every file, whichever language filled the memo first: a memo keyed without the language, or a
#       same-file run found in the wrong place, binds some file's call elsewhere (or nowhere) and turns these red.
#       One directory per file (train 26c, 2026-10-09): since #383 a bare module-scope call whose same-named definitions
#       sit in the SAME directory is hedged over that directory (the name-only tier: same file, same directory, each row
#       via="name"), so 36 files in one directory answered 18 hedged callers per Python def and the arm read the resolver's
#       hedge, not the memo. A directory per file keeps exactly the claim: the caller's own file, in its own language.
MF="$( mktemp -d )"
for i in $( seq 1 18 ); do
    mkdir -p "$MF/d$i"
    printf 'ok() { echo "$1"; }\nok "bash %s"\nok "again"\n' "$i" > "$MF/d$i/s$i.sh"
    printf 'def ok(x):\n    return x\nok("py %s")\n' "$i" > "$MF/d$i/p$i.py"
done
memoBad=0
for i in 1 2 9 17 18; do
    for f in "d$i/s$i.sh" "d$i/p$i.py"; do
        out="$( "$BIN" "$MF" --no-cache --callers="$f:ok" 2>/dev/null )"
        if printf '%s' "$out" | grep -q 'count="1"' && printf '%s' "$out" | grep -q "p=\"$f:1\""; then :; else
            memoBad=1; no "(10) $f:ok should have exactly its own file's module scope as caller: $( printf '%s' "$out" | grep -o '<callers [^>]*>' | head -1 )"
        fi
    done
done
rm -rf "$MF"
if [ "$memoBad" -eq 0 ]; then ok "(10) 36 same-named defs over two languages: every file's module-scope call binds its own file's ok (10 files sampled)"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
