#!/usr/bin/env bash
# qualityscopecheck.sh — --scope=GLOB partitions --quality-delta by OWNERSHIP, and refuses to let one
# session ack another session's rows.
#
# WHY THIS FLAG EXISTS. ~20 agent sessions share one working tree. --quality-delta compares the WORKING
# TREE against HEAD, so every concurrent writer's uncommitted rows appear in every agent's report. The
# noise is annoying; the DANGER is one bad ack — an agent that acks a sibling's row silently absorbs
# foreign debt into a committed ledger, with its own reason string attached, and the ratchet becomes a
# rubber stamp. The whole point of the flag is the refusal, so most of this gate is about the refusal.
#
# THE FIVE PROPERTIES, each an arm below:
#   (A) PARTITION      — findings split by their p= path; a clone group is in-scope iff ANY member matches.
#   (B) DISCLOSURE     — out-of-scope rows still PRINT, under <out-of-scope> with a do-not-ack banner, and
#                        never gate. Suppressing them would be a silent report, which the house forbids.
#   (C) GATING         — exit 2 fires on in-scope rows only; a sibling's gating row leaves this agent green.
#   (D) THE GUARD      — --quality-ack under --scope never writes an out-of-scope row, and REFUSES (exit 1,
#                        naming them, writing nothing) when the ack selection explicitly names one.
#   (E) PROVENANCE     — an ack written under --scope records by=<spec>; a later run flags an ack whose
#                        by= does not cover the path it is suppressing. Rows with no by= (every row written
#                        before this feature existed) keep working byte-for-byte.
#   (F) F-05 REGRESSION — the audit's own finding (2026-09-02): out-of-scope disclosure was ack-ratcheted,
#                        so a sibling's OWN ack — on a row that has nothing to do with you — made that row
#                        vanish from YOUR <out-of-scope> element instead of just yours suppressing it. And
#                        foreign-acks= tested provenance against the clone row's first-sorting member's path
#                        alone where inclusion already uses the whole member set, so a legitimate any-member
#                        ack (filed by the member that does NOT sort first) read as foreign every time. Arm
#                        13 below is the regression lock for both halves.
#
# A typo'd scope must never read as "you're clean": a --scope naming nothing indexed REFUSES (exit 1), the
# same ruling --dead-code=DIR already carries.
#
# The gate runs on a synthetic two-writer repo so it never depends on ripwire's own current debt.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }

echo "qualityscopecheck: BIN=$BIN"

R="$TMP/repo"; mkdir -p "$R/alpha" "$R/beta"
cd "$R"; git init -q .; git config user.email t@t; git config user.name t

# ── the shared tree at rest: two writers, two disjoint subtrees, nothing wrong with either ────────────
cat > alpha/lib.h <<'EOF'
#pragma once
inline int a_pub( int a ) { return a; }
inline int a_gamma( int a )
{
    int t = 0;
    for( int i = 0; i < a; ++i ) { if( i % 2 == 0 ) t += i; else t -= i; }
    return t;
}
EOF
cat > beta/lib.h <<'EOF'
#pragma once
inline int b_pub( int a ) { return a; }
inline int b_gamma( int a )
{
    int t = 0;
    for( int i = 0; i < a; ++i ) { if( i % 2 == 0 ) t += i; else t -= i; }
    return t;
}
EOF
git add alpha/lib.h beta/lib.h; git commit -qm base
"$BIN" . --quality-baseline >/dev/null 2>&1
[ -f .ripwire_quality_baseline ] && ok "baseline snapshot written" || { no "no baseline written"; echo "ALL FAIL"; exit 1; }

# ── both writers edit, at the same time, in their own subtree ─────────────────────────────────────────
# Each adds the SAME two gating shapes (an arity contract-change on a preexisting public symbol, and a
# complexity regression) plus one half of a clone group that STRADDLES the two subtrees — the case the
# any-member rule exists for.
cat > alpha/lib.h <<'EOF'
#pragma once
inline int a_pub( int a, int b ) { return a + b; }
inline int a_gamma( int a )
{
    int t = 0;
    for( int i = 0; i < a; ++i )
    {
        if( i % 2 == 0 )      { if( i % 3 == 0 ) t += i * 2; else t += i; }
        else if( i % 5 == 0 ) { if( i % 7 == 0 ) t -= i * 2; else t -= i; }
        else if( i % 11 == 0 ){ t += 1; }
        else                  { if( i > 100 ) t -= 1; else t += 3; }
    }
    return t;
}
inline int a_twin() { int x = 0; x += 1; x += 2; x += 3; x += 4; x += 5; return x * x + 1; }
EOF
cat > beta/lib.h <<'EOF'
#pragma once
inline int b_pub( int a, int b ) { return a + b; }
inline int b_gamma( int a )
{
    int t = 0;
    for( int i = 0; i < a; ++i )
    {
        if( i % 2 == 0 )      { if( i % 3 == 0 ) t += i * 2; else t += i; }
        else if( i % 5 == 0 ) { if( i % 7 == 0 ) t -= i * 2; else t -= i; }
        else if( i % 11 == 0 ){ t += 1; }
        else                  { if( i > 100 ) t -= 1; else t += 3; }
    }
    return t;
}
inline int b_twin() { int x = 0; x += 1; x += 2; x += 3; x += 4; x += 5; return x * x + 1; }
EOF

# `--scope`'s report is one document; split it at the <out-of-scope> boundary so an assertion about the
# GATING half can never be satisfied by a row sitting in the disclosed half (the exact confusion that
# would make this whole gate vacuous).
inscope_part(){ sed 's/<out-of-scope/\n<out-of-scope/' "$1" | head -1; }
oos_part(){     sed 's/<out-of-scope/\n<out-of-scope/' "$1" | tail -n +2; }
rowcount(){     tr '>' '\n' < "$1" | grep -c '<r ' || true; }
attr(){ grep -oE "$2=\"[0-9]+\"" "$1" | head -1 | grep -oE '[0-9]+'; }

# ── 0) fixture premise: the shared tree really does hold BOTH writers' gating debt ────────────────────
"$BIN" . --quality-delta >"$TMP/plain.xml" 2>/dev/null; plain_rc=$?
[ "$plain_rc" -eq 2 ] && ok "(0) plain --quality-delta gates on the shared tree (exit 2)" || no "(0) plain --quality-delta exited $plain_rc (expected 2)"
grep -q 'p="alpha/lib.h' "$TMP/plain.xml" && grep -q 'p="beta/lib.h' "$TMP/plain.xml" \
    && ok "(0) …and shows BOTH writers' rows — the friction this flag is about" \
    || { no "(0) fixture did not produce rows in both subtrees"; tr '>' '\n' <"$TMP/plain.xml" | grep '<r '; }
PLAIN_GATING="$( attr "$TMP/plain.xml" gating )"
[ "${PLAIN_GATING:-0}" -ge 2 ] && ok "(0) …with $PLAIN_GATING gating rows to partition" || no "(0) too few gating rows ($PLAIN_GATING) to tell the halves apart"

# ── 1) (A)+(B) PARTITION and DISCLOSURE ───────────────────────────────────────────────────────────────
"$BIN" . --quality-delta --scope=alpha >"$TMP/alpha.xml" 2>/dev/null; a_rc=$?
grep -q 'scope="alpha"' "$TMP/alpha.xml" && ok "(1) the report names the scope it was taken under" || no "(1) no scope= on the report root"
inscope_part "$TMP/alpha.xml" >"$TMP/alpha.in"
oos_part     "$TMP/alpha.xml" >"$TMP/alpha.out"
grep -q 'beta/lib.h' "$TMP/alpha.in" && no "(1) a beta row is in the GATING half of an alpha-scoped report" \
                                     || ok "(1) no out-of-scope row leaks into the gating half"
grep -q 'alpha/lib.h' "$TMP/alpha.in" && ok "(1) the agent's own rows are still there" || { no "(1) the scope dropped the agent's OWN rows"; cat "$TMP/alpha.in"; }
grep -q 'beta/lib.h' "$TMP/alpha.out" && ok "(1B) the sibling's rows are still PRINTED, under <out-of-scope>" \
                                      || { no "(1B) the sibling's rows were SUPPRESSED, not disclosed"; cat "$TMP/alpha.out"; }
grep -q 'do not ack' "$TMP/alpha.out" && ok "(1B) …behind a one-line do-not-ack banner" || { no "(1B) <out-of-scope> carries no banner"; head -c 400 "$TMP/alpha.out"; }
grep -qE 'scoped-out="[1-9]' "$TMP/alpha.xml" && ok "(1B) …and the header counts them (scoped-out)" || no "(1B) header does not count the disclosed rows"
grep -qE 'scoped-out-gating="[1-9]' "$TMP/alpha.xml" \
    && ok "(1B) …and says how many of them WOULD have gated — the number a reader must not mistake for green" \
    || no "(1B) header does not disclose how many out-of-scope rows would have gated"
grep -q 'gating="1"' "$TMP/alpha.out" && no "(1B) a disclosed out-of-scope row is marked gating" || ok "(1B) no disclosed row claims to gate"

# ── 2) (C) GATING is scope-local, in both directions ──────────────────────────────────────────────────
[ "$a_rc" -eq 2 ] && ok "(2) an agent with UNFIXED debt of its own still gates (exit 2)" || no "(2) alpha-scoped run exited $a_rc (expected 2)"
A_GATING="$( attr "$TMP/alpha.xml" gating )"
[ "${A_GATING:-0}" -lt "${PLAIN_GATING:-0}" ] && [ "${A_GATING:-0}" -gt 0 ] \
    && ok "(2) gating narrowed to this agent's share ($PLAIN_GATING -> $A_GATING)" \
    || no "(2) gating did not narrow ($PLAIN_GATING -> $A_GATING)"

# ── 3) well-formedness + determinism under the new element ────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/alpha.xml" 2>"$TMP/xml.err" && ok "(3) the scoped report is well-formed XML" \
        || { no "(3) the scoped report is not well-formed"; cat "$TMP/xml.err"; }
else
    ok "(3) xmllint unavailable — well-formedness arm skipped (regression.sh runs it separately)"
fi
"$BIN" . --quality-delta --scope=alpha >"$TMP/alpha2.xml" 2>/dev/null
cmp -s "$TMP/alpha.xml" "$TMP/alpha2.xml" && ok "(3) two scoped runs are byte-identical" || no "(3) the scoped report is not deterministic"

# ── 4) (A) the CLONE rule: a group is in-scope iff ANY member matches ─────────────────────────────────
"$BIN" . --quality-delta --scope=beta >"$TMP/beta.xml" 2>/dev/null; b_rc=$?
inscope_part "$TMP/beta.xml" >"$TMP/beta.in"
B_GATING_BEFORE="$( attr "$TMP/beta.xml" gating )"
if grep -q 'kind="duplication"' "$TMP/plain.xml"; then
    grep -q 'kind="duplication"' "$TMP/alpha.in" && grep -q 'kind="duplication"' "$TMP/beta.in" \
        && ok "(4) the straddling clone group is in-scope for BOTH members' owners" \
        || { no "(4) a clone group with a member in the scope was filed out-of-scope"; grep -o '<r kind="duplication"[^>]*>' "$TMP/alpha.xml" "$TMP/beta.xml"; }
else
    no "(4) fixture premise broken: the a_twin/b_twin pair did not clone-group, so the any-member rule is untested"
fi

# ── 5) a scope naming nothing indexed REFUSES — a typo must never read as "you're clean" ──────────────
"$BIN" . --quality-delta --scope=zzz-no-such-dir >"$TMP/typo.out" 2>"$TMP/typo.err"; rc=$?
[ $rc -eq 1 ] && ok "(5) a scope matching no indexed path exits 1" || no "(5) a typo'd scope exited $rc (expected 1)"
[ ! -s "$TMP/typo.out" ] && ok "(5) …and prints nothing to stdout (no exit-0-looking empty report)" || no "(5) …but printed $( wc -c <"$TMP/typo.out" ) bytes"
grep -q 'zzz-no-such-dir' "$TMP/typo.err" && ok "(5) …and names the offending pattern" || { no "(5) …without naming the pattern"; cat "$TMP/typo.err"; }

# ── 6) --scope outside the quality family is refused, not ignored ─────────────────────────────────────
"$BIN" . --scope=alpha >"$TMP/lone.out" 2>"$TMP/lone.err"; rc=$?
[ $rc -eq 1 ] && ok "(6) --scope without --quality-delta exits 1" || no "(6) lone --scope exited $rc (expected 1)"
[ ! -s "$TMP/lone.out" ] && ok "(6) …and prints no default map in its place" || no "(6) …but printed the ordinary map"
grep -q -- '--quality-delta' "$TMP/lone.err" && grep -q -- '--scope' "$TMP/lone.err" \
    && ok "(6) …and the message names both flags" || { no "(6) …without naming both flags"; cat "$TMP/lone.err"; }

# ── 7) (D) THE GUARD, part 1: a bare ack under --scope writes the agent's rows and NOT the sibling's ──
A_ROWS="$( rowcount "$TMP/alpha.in" )"
"$BIN" . --quality-delta --scope=alpha --quality-ack="alpha session" >/dev/null 2>"$TMP/ack.err"; rc=$?
[ $rc -eq 0 ] && ok "(7) the scoped ack succeeds (exit 0)" || { no "(7) the scoped ack exited $rc"; cat "$TMP/ack.err"; }
[ -f .ripwire_quality_acks ] && ok "(7) …and wrote the ledger" || no "(7) …but wrote no ledger"
ACK_LINES="$( grep -c '^ack ' .ripwire_quality_acks 2>/dev/null || echo 0 )"
[ "$ACK_LINES" = "$A_ROWS" ] && ok "(7) …with exactly the $A_ROWS in-scope finding(s), no more" \
    || no "(7) …with $ACK_LINES ack rows for $A_ROWS in-scope findings — the sibling's rows may have been absorbed"
grep -qi 'out of scope' "$TMP/ack.err" && ok "(7) …and says on stderr that it left the sibling's rows alone" \
    || { no "(7) …silently, with no word about the rows it refused to ack"; cat "$TMP/ack.err"; }

"$BIN" . --quality-delta --scope=alpha >"$TMP/alpha3.xml" 2>/dev/null; rc=$?
[ $rc -eq 0 ] && ok "(7C) the agent that acked ITS OWN rows is now green under its scope (exit 0)" \
    || { no "(7C) the acking agent still gates (exit $rc)"; tr '>' '\n' <"$TMP/alpha3.xml" | grep '<r '; }
"$BIN" . --quality-delta >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && ok "(7C) …while the UNSCOPED report still gates on the sibling's untouched debt (exit 2)" || no "(7C) the unscoped report exited $rc (expected 2)"
"$BIN" . --quality-delta --scope=beta >"$TMP/beta2.xml" 2>/dev/null; rc=$?
[ $rc -eq 2 ] && ok "(7C) …and so does the sibling's own scoped report (exit 2)" || no "(7C) the beta-scoped report exited $rc (expected 2)"
B_GATING_AFTER="$( attr "$TMP/beta2.xml" gating )"
[ "${B_GATING_AFTER:-0}" = "${B_GATING_BEFORE:-x}" ] \
    && ok "(7C) …with its gating count untouched ($B_GATING_BEFORE) — alpha absorbed none of beta's debt" \
    || no "(7C) beta's gating went $B_GATING_BEFORE -> $B_GATING_AFTER across alpha's ack — a sibling acked its rows"
# The ONE row alpha's ack legitimately suppresses for beta is the clone group that STRADDLES both subtrees:
# it is in scope for both owners by the any-member rule, so acking it once really does answer it for both.
# Pinned here rather than left as a surprise, because it is the only shared-fate case the partition has.
B_ACKED="$( attr "$TMP/beta2.xml" acked )"
STRADDLE="$( tr '>' '\n' <"$TMP/beta.in" | grep -c 'kind="duplication"' || true )"
[ "${B_ACKED:-0}" -le "$STRADDLE" ] \
    && ok "(7C) …and the only thing acked on beta's side is the $STRADDLE straddling clone group (acked=$B_ACKED)" \
    || no "(7C) beta reports ${B_ACKED} acked finding(s) but only $STRADDLE row straddles the two scopes"

# ── 8) (E) PROVENANCE: the rows the scoped session wrote carry by=<scope> ─────────────────────────────
grep -q 'by=alpha ' .ripwire_quality_acks && ok "(8) every scoped ack row records the scope that wrote it (by=)" \
    || { no "(8) no by= provenance on the scoped ack rows"; head -5 .ripwire_quality_acks; }
grep -q 'alpha session' .ripwire_quality_acks && ok "(8) …without displacing the human reason" || no "(8) the reason string was lost behind by="
cp .ripwire_quality_acks "$TMP/acks.scoped"

# ── 9) (D) THE GUARD, part 2 — THE MOST IMPORTANT ARM IN THIS FILE ───────────────────────────────────
# An ack selection that explicitly NAMES an out-of-scope row is refused outright: exit 1, the row named,
# the ledger untouched. This is the line between a ratchet and a rubber stamp.
"$BIN" . --quality-delta --scope=alpha --ack-only=b_gamma --quality-ack="not mine to accept" >"$TMP/steal.out" 2>"$TMP/steal.err"; rc=$?
[ $rc -eq 1 ] && ok "(9) acking an OUT-OF-SCOPE row is refused (exit 1)" || no "(9) the foreign ack exited $rc (expected 1)"
grep -q 'b_gamma' "$TMP/steal.err" && ok "(9) …and the refusal NAMES the row it would not accept" || { no "(9) …without naming the row"; cat "$TMP/steal.err"; }
cmp -s .ripwire_quality_acks "$TMP/acks.scoped" && ok "(9) …and the ledger is byte-unchanged" || no "(9) …but the ledger was MODIFIED by a refused ack"

# the composed, legitimate form must still work: 'gating' is scope-local, so it selects this agent's rows only
"$BIN" . --quality-delta --scope=beta --ack-only=gating --quality-ack="beta session" >/dev/null 2>"$TMP/backk.err"; rc=$?
[ $rc -eq 0 ] && ok "(9) --ack-only=gating under a scope still works — it selects the SCOPE's gating rows" \
    || { no "(9) --ack-only=gating under a scope exited $rc"; cat "$TMP/backk.err"; }
grep -q 'by=beta ' .ripwire_quality_acks && ok "(9) …and records its own provenance" || no "(9) …without by= provenance"

# ── 10) (E) BACKWARD COMPATIBILITY: rows with no by= (and no cid=) keep working, byte for byte ────────
"$BIN" . --quality-delta >"$TMP/bothacked.xml" 2>/dev/null; rc=$?
BOTH_ACKED="$( attr "$TMP/bothacked.xml" acked )"
[ "${BOTH_ACKED:-0}" -gt 0 ] && ok "(10) with both sessions acked, the unscoped report suppresses ${BOTH_ACKED} finding(s)" || no "(10) nothing suppressed after two scoped acks"
sed -E 's/ (cid|by)=[^ ]*//g' .ripwire_quality_acks > "$TMP/legacy.acks"
grep -q '^ack .*by=' "$TMP/legacy.acks" && no "(10) could not construct a pre-feature ledger to test against" || ok "(10) built a pre-feature ledger (no cid=, no by= on any ack row)"
cp "$TMP/legacy.acks" .ripwire_quality_acks
"$BIN" . --quality-delta >"$TMP/legacy.xml" 2>/dev/null
LEGACY_ACKED="$( attr "$TMP/legacy.xml" acked )"
[ "${LEGACY_ACKED:-0}" = "${BOTH_ACKED:-0}" ] \
    && ok "(10) a ledger with NO by= and NO cid= suppresses exactly the same $BOTH_ACKED finding(s)" \
    || no "(10) the pre-feature ledger suppressed ${LEGACY_ACKED} where the current one suppressed ${BOTH_ACKED}"

# ── 11) (E) the payoff: an ack whose by= does not cover the path it suppresses is FLAGGED ─────────────
# A hand-edited ledger is a supported input (the file is committed and reviewed by people), so this is
# also the honest way to build the state: rewrite one session's provenance to a scope it never owned.
sed 's/by=alpha /by=zzz-not-my-subtree /' "$TMP/acks.scoped" > .ripwire_quality_acks
"$BIN" . --quality-delta >"$TMP/foreign.xml" 2>/dev/null
grep -qE 'foreign-acks="[1-9]' "$TMP/foreign.xml" && ok "(11) the header counts acks whose provenance does not cover what they suppress" \
    || { no "(11) no foreign-acks= disclosure"; grep -o '<quality-delta[^>]*>' "$TMP/foreign.xml"; }
grep -q 'why="foreign-scope"' "$TMP/foreign.xml" && ok "(11) …with a per-row sa why=\"foreign-scope\"" || no "(11) no per-row foreign-scope detail"
grep -q 'by="zzz-not-my-subtree"' "$TMP/foreign.xml" && ok "(11) …naming the scope that wrote it" || { no "(11) …without naming the writing scope"; grep -o '<sa[^>]*/>' "$TMP/foreign.xml" | head -3; }
cp "$TMP/acks.scoped" .ripwire_quality_acks

# ── 12) P1.2 — the reserved `diff` token: the changed-files auto-scope ────────────────────────────────
# Sugar for the SINGLE-writer case, and the fixture is the case it is wrong for, which is the point: both
# writers edited, so diff covers both and partitions nothing. The arms pin the expansion, its disclosure,
# and the three refusals — never a silent widening.
"$BIN" . --quality-delta --scope=diff >"$TMP/diff.xml" 2>/dev/null; rc=$?
grep -q 'scope="diff"' "$TMP/diff.xml" && ok "(12) --scope=diff names itself on the report, unexpanded" || no "(12) no scope=\"diff\" on the report root"
grep -qE 'scope-diff-files="[1-9]' "$TMP/diff.xml" \
    && ok "(12) …and discloses how many indexed files it expanded to ($( grep -oE 'scope-diff-files="[0-9]+"' "$TMP/diff.xml" | head -1 ))" \
    || { no "(12) the auto-scope does not disclose its expansion size"; grep -o '<quality-delta[^>]*>' "$TMP/diff.xml"; }
"$BIN" . --quality-delta --scope=alpha,beta >"$TMP/both.xml" 2>/dev/null
inscope_part "$TMP/diff.xml" >"$TMP/diff.in"; inscope_part "$TMP/both.xml" >"$TMP/both.in"
[ "$( rowcount "$TMP/diff.in" )" = "$( rowcount "$TMP/both.in" )" ] \
    && ok "(12) …and covers the same rows as naming both subtrees by hand ($( rowcount "$TMP/diff.in" ))" \
    || no "(12) diff-scope covered $( rowcount "$TMP/diff.in" ) rows where the hand-named pair covered $( rowcount "$TMP/both.in" )"

# a CLEAN tree: the auto-scope owns nothing, and that must refuse rather than read as a green report
C="$TMP/clean"; mkdir -p "$C"; cd "$C"; git init -q .; git config user.email t@t; git config user.name t
printf '#pragma once\ninline int only( int a ) { return a; }\n' > only.h
git add only.h; git commit -qm base
"$BIN" . --quality-delta --scope=diff >"$TMP/cleandiff.out" 2>"$TMP/cleandiff.err"; rc=$?
[ $rc -eq 1 ] && ok "(12) --scope=diff on an UNCHANGED tree refuses (exit 1)" || no "(12) --scope=diff on a clean tree exited $rc (expected 1)"
[ ! -s "$TMP/cleandiff.out" ] && ok "(12) …printing nothing — an exit 0 there would say nothing about your change" || no "(12) …but printed a report anyway"
grep -q 'NO changed indexed file' "$TMP/cleandiff.err" && ok "(12) …and says exactly what was empty" || { no "(12) …without explaining"; cat "$TMP/cleandiff.err"; }

# the RANGE form compares two COMMITTED trees, so a working-tree auto-scope is the wrong question there
cd "$R"; git add -A; git commit -qm "both writers land"
"$BIN" . --quality-delta=HEAD~1..HEAD --scope=diff >"$TMP/rangediff.out" 2>"$TMP/rangediff.err"; rc=$?
[ $rc -eq 1 ] && ok "(12) --scope=diff under the A..B range form refuses (exit 1)" || no "(12) --scope=diff with a ref range exited $rc (expected 1)"
grep -q 'COMMITTED trees' "$TMP/rangediff.err" && ok "(12) …and says why the working tree is not the answer there" || { no "(12) …without saying why"; cat "$TMP/rangediff.err"; }
"$BIN" . --quality-delta=HEAD~1..HEAD --scope=alpha >/dev/null 2>&1; rc=$?
[ $rc -ne 1 ] && ok "(12) …while a PATH scope still works on the range form (exit $rc)" || no "(12) a path scope was refused on the range form too"

# ── 13) (F) F-05 REGRESSION LOCK: a sibling's ack must never hide a row from YOUR disclosure ─────────────
# A fresh two-owner repo: gamma writes four EXCLUSIVE findings (never delta's), plus a clone group that
# straddles gamma and delta (the any-member shared case). gamma acks two of its own exclusive rows —
# nothing shared — under --scope=gamma. delta's later --scope=delta report must still show ALL FOUR of
# gamma's rows under <out-of-scope> (acked or not): the legend promises the element is "not dropped …
# every one of them is printed", and an ack is a fact about gamma's OWN ledger, not about what delta gets
# told belongs to somebody else.
F13="$TMP/f13"; mkdir -p "$F13/gamma" "$F13/delta"
cd "$F13"; git init -q .; git config user.email t@t; git config user.name t
cat > gamma/lib.h <<'EOF'
#pragma once
inline int g_pub( int a ) { return a; }
EOF
cat > delta/lib.h <<'EOF'
#pragma once
inline int d_pub( int a ) { return a; }
EOF
git add -A; git commit -qm base
"$BIN" . --quality-baseline >/dev/null 2>&1
cat > gamma/lib.h <<'EOF'
#pragma once
inline int g_pub( int a, int b ) { return a + b; }
inline int gammaMess1( int a, int b ) { return a + b; }
inline int gammaMess2( int a, int b ) { return a + b; }
inline int g_twin() { int x = 0; x += 1; x += 2; x += 3; x += 4; x += 5; return x * x + 1; }
EOF
cat > delta/lib.h <<'EOF'
#pragma once
inline int d_pub( int a ) { return a; }
inline int d_twin() { int x = 0; x += 1; x += 2; x += 3; x += 4; x += 5; return x * x + 1; }
EOF
"$BIN" . --quality-delta --scope=gamma --ack-only=gammaMess --quality-ack="gamma session" --no-cache >/dev/null 2>"$TMP/f13ack.err"; rc=$?
[ $rc -eq 0 ] && ok "(13) gamma's own-row ack under its scope succeeds" || { no "(13) gamma's ack exited $rc"; cat "$TMP/f13ack.err"; }
"$BIN" . --quality-delta --scope=delta --no-cache >"$TMP/f13delta.xml" 2>/dev/null
grep -oE 'scoped-out="[0-9]+"' "$TMP/f13delta.xml" | grep -q 'scoped-out="4"' \
    && ok "(13B) delta's scoped-out= still counts all 4 of gamma's rows after gamma's own ack" \
    || { no "(13B) scoped-out= dropped after a sibling's ack — the F-05 bug"; grep -oE '<quality-delta[^>]*>' "$TMP/f13delta.xml"; }
for sym in g_pub g_twin gammaMess1 gammaMess2; do
    grep -q "sym=\"$sym\"" "$TMP/f13delta.xml" \
        && ok "(13B) …and '$sym' is still PRESENT in the disclosure, acked or not" \
        || { no "(13B) …but '$sym' vanished from <out-of-scope> — an acked row must still be disclosed"; }
done
oos_part2(){ sed 's/<out-of-scope/\n<out-of-scope/' "$1" | tail -n +2; }
oos_part2 "$TMP/f13delta.xml" > "$TMP/f13delta.oos"
grep -q 'gating="1"' "$TMP/f13delta.oos" && no "(13B) a disclosed row claims to gate" || ok "(13B) no disclosed row claims to gate, ack or not"

# ── 13C) foreign-acks= any-member symmetry: the group's r.path is its FIRST-SORTING member, and
# "delta" < "gamma" ASCII-sorts first — so gamma is the member that does NOT sort first. gamma legitimately
# acks the straddling group (gamma owns g_twin, a real member) and that must NOT read as foreign just
# because the row's own locator names delta's file instead.
cd "$F13"; rm -f .ripwire_quality_acks
"$BIN" . --quality-delta --scope=gamma --ack-only=duplication --quality-ack="gamma acks the shared group" --no-cache >/dev/null 2>&1
"$BIN" . --quality-delta --no-cache >"$TMP/f13unscoped.xml" 2>/dev/null
grep -q 'foreign-acks=' "$TMP/f13unscoped.xml" \
    && { no "(13C) gamma's legitimate any-member ack (non-first-sorting member) reads as foreign"; grep -oE '<quality-delta[^>]*>|<sa[^>]*/>' "$TMP/f13unscoped.xml"; } \
    || ok "(13C) gamma's legitimate any-member ack does not false-positive as foreign-scope"
# negative control: hand-corrupt the SAME ack's by= to a scope that owns NEITHER member — must still fire.
sed -i.bak 's/by=gamma /by=zzz-nobody /' .ripwire_quality_acks
"$BIN" . --quality-delta --no-cache >"$TMP/f13corrupt.xml" 2>/dev/null
grep -qE 'foreign-acks="[1-9]' "$TMP/f13corrupt.xml" \
    && ok "(13C) …while a GENUINELY foreign by= (owns no member) is still caught (negative control holds)" \
    || { no "(13C) a genuinely foreign ack was not caught — the any-member fix over-corrected"; grep -oE '<quality-delta[^>]*>' "$TMP/f13corrupt.xml"; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
