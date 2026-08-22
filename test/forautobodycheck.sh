#!/usr/bin/env bash
# forautobodycheck.sh — T3 terminal-by-default --for (pre-registered: docs/EVALS.md §4, T3 round).
# The default --for bundle serves the top-ranked symbols' FULL bodies inline after the signatures,
# under the bundle budget, assembled by the SAME packBodies machinery --pack-task uses — rank-first,
# whole-body-or-not-at-all, disclosed on the container.
#
# Contract:
#   1) default --for emits an auto <bodies> section (CDATA bodies, the --expand shape) AFTER the
#      signatures, and the <ctx> root discloses it: bundle="auto" bodies="N" (N >= 1 when any fit).
#   2) the header legend explains the bundle=auto attributes (a reader never guesses).
#   3) a TIGHT explicit --token-budget drops the bodies (never cuts one mid-def), disclosed at ANY
#      tightness: while an allowance exists, bundle="auto" bodies="0" reason="budget" plus the
#      honest <bodies shown="0"> shell (W3-S: elements never vanish); at a ceiling the signature
#      bundle already EXHAUSTED, the attribute alone (legend + shell dropped — only the attribute
#      has reserved bytes there; the full path coverage is test/fordisclosurecheck.sh #2). The
#      <sigs> block is intact either way and the disclosure is never silently dropped.
#   4) --signatures-only opts out: no bundle= attribute, no <bodies> — the pre-T3 bundle shape.
#      It refuses loudly without --for, and refuses the contradictory --signatures-only --detail=N.
#   5) escalation is capped and disclosed: bodies= on the root equals the emitted <b> count and
#      never exceeds the pack-task body-candidate cap (6). Asserted on a CONCEPTUAL query, because
#      that is the route the rank-first walk still runs on — see (5b).
#   5b) on a route that NAMES an anchor, the allowance serves that anchor's own body or none at all;
#      a generous budget does not escalate past it, and a same-named symbol in another file is never
#      substituted for it. Mechanism + band: docs/EVALS.md, the anchor-only round; the dedicated
#      gate is test/anchorbodycheck.sh.
#   6) auto bodies take only genuine LEFTOVER budget: at the same explicit --token-budget, the
#      <sigs> block is byte-identical with and without --signatures-only.
#   7) the budget ledger accounts the bodies: est_tokens(default) > est_tokens(--signatures-only).
#   8) deterministic (x3 byte-identical); xmllint-clean (G4).
#   9) --detail=N supersedes auto (explicit shape: <bodies> present, no bundle="auto" attribute).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/forautobodycheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"
echo "forautobodycheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
TASK="pageRankDouble"                        # name-exact: rank-1 is a small, stable symbol

bodycount(){ grep -o '<b t=' "$1" | wc -l | tr -d ' '; }
rootattr(){ grep -o "$2" "$1" | head -1; }   # first match of an attr pattern in the file
# the <sigs>…</sigs> span, extracted byte-exactly (python3 is a suite prerequisite; sed's pattern-space
# handling of the very long minified line proved unreliable for a byte-identity assertion)
sigsblock(){ python3 -c 'import sys; s=open(sys.argv[1],"rb").read(); a=s.find(b"<sigs"); b=s.find(b"</sigs>"); sys.stdout.buffer.write(s[a:b+7] if a>=0 and b>=0 else b"")' "$1"; }

# ── presence guard: the fixture symbol must exist and rank (a gate that cannot observe is inert) ────────
grep -rq "pageRankDouble" src/pagerank.h src/pagerank.cpp 2>/dev/null \
    && ok "presence: pageRankDouble exists in the fixture corpus" \
    || no "presence: pageRankDouble missing from src/ — the arms below cannot observe what they assert"

# ── #1: default --for serves the rank-1 body inline, disclosed on the container ─────────────────────────
"$BIN" src --for="$TASK" --no-cache >"$TMP/auto" 2>/dev/null; rc=$?
[ "$rc" = 0 ] || no "default --for exited $rc"
NB=$( bodycount "$TMP/auto" )
{ grep -q '<bodies [^>]*>' "$TMP/auto" && [ "$NB" -ge 1 ]; } \
    && ok "default --for includes $NB full bod(ies) inline (auto <bodies> section)" \
    || no "default --for has no inline body (expected the rank-1 body under the default allowance)"
grep -q '<b [^>]*n="pageRankDouble"[^>]*><!\[CDATA\[' "$TMP/auto" \
    && ok "the rank-1 body is pageRankDouble, in CDATA (the --expand shape)" \
    || no "rank-1 body missing or not CDATA (expected <b ... n=\"pageRankDouble\"><![CDATA[...)"
ATTR=$( rootattr "$TMP/auto" 'bundle="auto" bodies="[0-9]*"' )
DN=${ATTR##*bodies=\"}; DN=${DN%\"}
{ [ -n "$ATTR" ] && [ "${DN:-x}" = "$NB" ]; } \
    && ok "container disclosure: <ctx ... $ATTR> matches the emitted body count" \
    || no "container disclosure wrong (attr='$ATTR' vs emitted $NB bodies)"

# ── #2: the legend explains the disclosure ──────────────────────────────────────────────────────────────
grep -q 'bundle="auto"' "$TMP/auto" && grep -qi 'bodies.*inline\|inline.*bod' "$TMP/auto" \
    && ok "header legend names the bundle=auto mechanism" \
    || no "header legend does not explain bundle=auto"

# ── #3a: an explicit --token-budget the signature bundle exhausts serves NO body and STILL discloses —
#         the bodies="0" reason="budget" attribute (attribute ONLY: legend and shell have no reserved
#         bytes at a spent ceiling — fordisclosurecheck #2 owns that half), per the registration's own
#         sentence ("when no body fits the remaining budget"). This arm used to assert the OPPOSITE
#         (surface silently off, byte-identical to --signatures-only) — the 2026-08-22 Lane-AA
#         transcript mine caught that silent shape on 5 of 26 real --for calls (bodyuse-memo §7), and
#         a disclosure that disappears exactly when the budget is tight is the opposite of a
#         disclosure. The <sigs> block still may not move a byte vs the opt-out run (bodies/disclosure
#         ride leftover only — the #6 contract, asserted here at the tight budget too). ────────────────
"$BIN" src --for="$TASK" --token-budget=400 --no-cache >"$TMP/tight" 2>/dev/null; rc=$?
[ "$rc" = 0 ] || no "tight-budget --for exited $rc (D10: --token-budget shapes, never gates, this bundle)"
"$BIN" src --for="$TASK" --token-budget=400 --signatures-only --no-cache >"$TMP/tightso" 2>/dev/null
grep -q 'bundle="auto" bodies="0" reason="budget"' "$TMP/tight" \
    && ok "ultra-tight budget: bodies=\"0\" reason=\"budget\" disclosed (never a silent surface)" \
    || no "ultra-tight budget: missing bodies=\"0\" reason=\"budget\" disclosure (the memo's silent shape)"
grep -q '<b [^>]*><!\[CDATA\[' "$TMP/tight" \
    && no "ultra-tight budget: emitted body bytes past an exhausted ceiling" \
    || ok "ultra-tight budget: no body bytes (whole-body-or-nothing holds)"
sigsblock "$TMP/tight" >"$TMP/tight_sigs"; sigsblock "$TMP/tightso" >"$TMP/tightso_sigs"
[ -s "$TMP/tight_sigs" ] || no "ultra-tight budget: could not extract a <sigs> block"
diff -q "$TMP/tight_sigs" "$TMP/tightso_sigs" >/dev/null \
    && ok "ultra-tight budget: <sigs> byte-identical to --signatures-only (disclosure rides leftover only)" \
    || no "ultra-tight budget: the disclosure changed the <sigs> bytes"
grep -q '<sigs' "$TMP/tight" && ok "ultra-tight budget: the <sigs> block is intact" \
    || no "ultra-tight budget: the <sigs> block vanished (signatures must survive)"

# ── #3b: candidates exist but none fits the body budget whole → shown="0", DISCLOSED, never truncated ────
#         (--pack-budget-bytes=64 forces the no-fit case corpus-robustly; the default budget is generous)
# R9 fix (W3-S, 2026-08-19): this used to assert <bodies> was WHOLLY ABSENT here — packBodies had already
# rendered the honest "<bodies shown="0" total="N" capped="1"></bodies>" shell (buildForAutoBodies called
# it just to find out nothing fit), and the caller threw that render away ("drop the empty section whole").
# "A zero means none found, never none exists" (CONTRIBUTING #3) applies to elements, not only counts, so
# the fixed behaviour KEEPS the element — this arm now asserts presence-with-shown="0", not absence.
"$BIN" src --for="$TASK" --pack-budget-bytes=64 --no-cache >"$TMP/nofit" 2>/dev/null
grep -q 'bundle="auto" bodies="0" reason="budget"' "$TMP/nofit" \
    && ok "no body fits whole: disclosed (bodies=\"0\" reason=\"budget\")" \
    || no "no-fit case: missing bodies=\"0\" reason=\"budget\" disclosure"
grep -qE '<bodies shown="0" total="[1-9][0-9]*" capped="1">' "$TMP/nofit" \
    && ok "no-fit case: <bodies shown=\"0\" total=\"N\" capped=\"1\"> is PRESENT (not absent — R9)" \
    || no "no-fit case: <bodies shown=\"0\"> missing or malformed (element must not vanish)"
grep -q '<b [^>]*><!\[CDATA\[' "$TMP/nofit" \
    && no "no-fit case emitted a truncated body (never cut mid-def)" \
    || ok "no-fit case: no body bytes at all (never a truncated one — whole-body-or-nothing still holds)"

# ── #4: --signatures-only opts out; guarded against misuse ──────────────────────────────────────────────
"$BIN" src --for="$TASK" --signatures-only --no-cache >"$TMP/sigonly" 2>/dev/null; rc=$?
{ [ "$rc" = 0 ] && ! grep -q 'bundle=' "$TMP/sigonly" && ! grep -q '<bodies [^>]*>' "$TMP/sigonly"; } \
    && ok "--signatures-only restores the signatures-only bundle (no bundle= attr, no <bodies>)" \
    || no "--signatures-only did not restore the pre-T3 shape (rc=$rc)"
"$BIN" src --signatures-only --no-cache >/dev/null 2>"$TMP/err1"; rc=$?
{ [ "$rc" != 0 ] && grep -qi 'signatures-only' "$TMP/err1"; } \
    && ok "--signatures-only without --for refuses loudly" \
    || no "--signatures-only without --for did not refuse (rc=$rc)"
"$BIN" src --for="$TASK" --signatures-only --detail=3 --no-cache >/dev/null 2>"$TMP/err2"; rc=$?
{ [ "$rc" != 0 ] && grep -qi 'signatures-only' "$TMP/err2"; } \
    && ok "--signatures-only + --detail refuses loudly (contradictory)" \
    || no "--signatures-only + --detail did not refuse (rc=$rc)"

# ── #5: escalation capped at the pack-task candidate cap (6) and disclosed ──────────────────────────────
# RE-ANCHORED (the anchor-only round, docs/EVALS.md): this arm used to escalate $TASK, a name-exact
# query. The allowance now serves the ANCHOR's own body or none on a route that names one, so a name-exact
# query has exactly ONE candidate by construction and "capped at 6" stopped being observable through it —
# green while inert, the failure mode CONTRIBUTING §2 names. A CONCEPTUAL query names no anchor, keeps the
# rank-first walk, and is where the cap is still a real bound. The presence guard is what keeps that true.
CONCEPTUAL="how are identifiers split into subtokens for ranking"
"$BIN" src --for="$CONCEPTUAL" --token-budget=20000 --no-cache >"$TMP/big" 2>/dev/null
grep -q 'anchors: ' "$TMP/big" \
    && no "#5 presence: the escalation query routed name-exact — re-author it, the cap is unobservable there" \
    || ok "#5 presence: the escalation query routed subtoken+body, where the candidate cap still binds"
BB=$( bodycount "$TMP/big" )
BATTR=$( rootattr "$TMP/big" 'bundle="auto" bodies="[0-9]*"' )
BN=${BATTR##*bodies=\"}; BN=${BN%\"}
{ [ -n "$BATTR" ] && [ "${BN:-x}" = "$BB" ] && [ "$BB" -gt 1 ] && [ "$BB" -le 6 ]; } \
    && ok "generous budget escalates to $BB bodies — capped at 6, disclosed ($BATTR)" \
    || no "escalation cap/disclosure wrong (attr='$BATTR', emitted $BB, expected 2..6)"

# ── #5b: …and on a route that NAMES an anchor, the allowance serves that anchor alone (never a namesake
#         substituted for it). The mechanism and its band: docs/EVALS.md, the anchor-only round; the
#         dedicated gate is test/anchorbodycheck.sh. Asserted here too so T3's own contract carries it.
"$BIN" src --for="$TASK" --token-budget=20000 --no-cache >"$TMP/bigname" 2>/dev/null
grep -q 'anchors: ' "$TMP/bigname" \
    && ok "#5b presence: the name-exact query does name an anchor" \
    || no "#5b presence: no anchors: clause on $TASK — this arm cannot observe the anchor-only rule"
NBB=$( bodycount "$TMP/bigname" )
{ [ "$NBB" = "1" ] && grep -q '<b [^>]*n="pageRankDouble"[^>]*><!\[CDATA\[' "$TMP/bigname"; } \
    && ok "#5b a generous budget does NOT escalate past the anchor on a name-exact route (1 body, the anchor's own)" \
    || no "#5b expected exactly the anchor's own body at a generous budget, got $NBB bod(ies)"

# ── #6: auto bodies ride only the LEFTOVER — <sigs> byte-identical with and without the opt-out ─────────
"$BIN" src --for="$TASK" --token-budget=6000 --no-cache >"$TMP/b6a" 2>/dev/null
"$BIN" src --for="$TASK" --token-budget=6000 --signatures-only --no-cache >"$TMP/b6s" 2>/dev/null
sigsblock "$TMP/b6a" >"$TMP/s_a"; sigsblock "$TMP/b6s" >"$TMP/s_s"
[ -s "$TMP/s_a" ] || no "#6 presence: could not extract a <sigs> block from the auto run"
diff -q "$TMP/s_a" "$TMP/s_s" >/dev/null \
    && ok "the <sigs> block is byte-identical with/without --signatures-only (bodies take leftover only)" \
    || no "auto mode changed the <sigs> bytes (bodies must never eat the signature budget)"

# ── #7: the budget ledger accounts the bodies' tokens ───────────────────────────────────────────────────
ETA=$( grep -o 'est_tokens="[0-9]*"' "$TMP/auto"    | head -1 | grep -o '[0-9]*' )
ETS=$( grep -o 'est_tokens="[0-9]*"' "$TMP/sigonly" | head -1 | grep -o '[0-9]*' )
{ [ -n "${ETA:-}" ] && [ -n "${ETS:-}" ] && [ "$ETA" -gt "$ETS" ]; } \
    && ok "est_tokens charges the bodies (auto $ETA > signatures-only $ETS)" \
    || no "est_tokens does not account the bodies (auto='$ETA' vs signatures-only='$ETS')"

# ── #8: determinism x3 — auto body inclusion is a pure function of (corpus, query, budget) ──────────────
"$BIN" src --for="$TASK" --no-cache >"$TMP/x1" 2>/dev/null
"$BIN" src --for="$TASK" --no-cache >"$TMP/x2" 2>/dev/null
"$BIN" src --for="$TASK" --no-cache >"$TMP/x3" 2>/dev/null
{ diff -q "$TMP/x1" "$TMP/x2" >/dev/null && diff -q "$TMP/x2" "$TMP/x3" >/dev/null; } \
    && ok "default --for deterministic (byte-identical x3)" \
    || no "default --for NON-deterministic across three runs"

# ── #9: --detail=N supersedes auto (explicit shape, no auto disclosure) ─────────────────────────────────
"$BIN" src --for="$TASK" --detail=2 --no-cache >"$TMP/det" 2>/dev/null
{ grep -q '<bodies [^>]*>' "$TMP/det" && ! grep -q 'bundle="auto"' "$TMP/det"; } \
    && ok "--detail=2 supersedes auto (explicit <bodies>, no bundle=\"auto\" attr)" \
    || no "--detail=2 did not supersede auto cleanly"

# ── #10: xmllint-clean (G4) ─────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    lint=1
    for F in "$TMP/auto" "$TMP/tight" "$TMP/sigonly" "$TMP/big" "$TMP/b6a" "$TMP/det"; do
        xmllint --noout "$F" 2>/dev/null || { echo "    malformed: $F"; lint=0; }
    done
    [ "$lint" = 1 ] && ok "all shapes well-formed XML (G4)" || no "malformed XML"
else
    printf '  SKIP  xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
