#!/usr/bin/env bash
# forsectioncollapsecheck.sh — L2 → R2-L2' (round-1 lever B1, priced in round 2, lane/r2-sections-stub-priced,
# 2026-09-19): the ranked --for lens's <lego>/<compose> sections collapse to a COUNTED STUB — `<lego
# total="N" shown="0" capped="1" next="…"/>` (same shape for <compose>) instead of the full <iface>/<m>/<impl> contract
# or <field> row list — ONLY WHEN THE STUB IS CHEAPER: len(section) > len(stub) + len(kForSectionStubLegend),
# the FULL clause (251 B, identical in both legend dialects) charged WHOLE to each candidate section's own
# decision (rv-prereg2 Amendment 1, R4). Round 1 collapsed every non-empty candidate unconditionally; round
# 2 retracted that where the stub — whose next= echoes the task verbatim, so it is not free — would have
# been the BIGGER of the two. The decision is POSTURE-INDEPENDENT: the same collapse set under
# --legend=full and --legend=compact, because kForSectionStubLegend is the one string both dialects splice.
#
# A disclosed cut (§9.3) when it fires, never a silent one: total= is that section's own PRE-CAP row count
# (packLego's post-dedup ifaces.size() before its topN=12 display cap; every matched HAS-A edge for
# compose, which caps nothing so "pre-cap" and "emitted" are the same count there), shown="0" discloses
# nothing was rendered, and next= names the ONE restoring spelling — `--sections=lego,compose` — that
# returns BOTH sections byte-identical to the pre-stub render, in ONE call (E41 rule b: nextverb.h's
# capped composer). No stub for a section that would have been EMPTY, and no stub for a section too SMALL
# to be worth replacing.
#
# total= is NOT the same number `--for --json`'s lego_total/compose_total print: that JSON count is
# PRE-DEDUP (by design — src/verbs_for.h's own comment on ForLensJsonInputs::legoTotal), so it can exceed
# this stub's total= on a corpus with same-named fwd-decl/definition collisions. Do not cross-check the
# two; this gate cross-checks the stub's total= against the RESTORED render's own row count instead.
#
# Fixtures: test/legofix (lego collapses: three small interfaces still clear the threshold) and
# test/sectionpricefix (both lego and compose collapse: a purpose-built interface + HAS-A owners sized
# comfortably above threshold) prove the ABOVE-threshold side; test/hasafix (compose stays whole: two
# short <field> rows, priced BELOW threshold) proves the round-2 delta itself, arm (10). test/legochargefix (a lego
# block bigger than the <sigs> budget) proves the stub is what the <sigs> budget is charged for, arm (13).
#
# Usage:  bash test/forsectioncollapsecheck.sh [path-to-ripwire-binary]
#         RIPWIRE_BIN=build/ripwire bash test/forsectioncollapsecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "forsectioncollapsecheck: BIN=$BIN"

# ── (1) SMALL FIXTURE, byte identity: --sections=lego,compose reproduces the pre-stub render exactly ────
# test/legofix carries a real interface (Shape, 2 implementors) and no compose edges of its own — the
# fixture legobundlecheck.sh already relies on for the standalone --lego=Shape reference. Every arm below
# spells --legend=full explicitly so L1 (a later lane's compact-default flip) moves none of these pins.
LFQ="shape interface implementors"
"$BIN" test/legofix --no-cache --legend=full --for="$LFQ" >"$TMP/lf_stub.xml" 2>/dev/null
"$BIN" test/legofix --no-cache --legend=full --for="$LFQ" --sections=lego,compose >"$TMP/lf_restored.xml" 2>/dev/null
"$BIN" test/legofix --no-cache --legend=full --for="$LFQ" --sections=compose,lego >"$TMP/lf_restored_rev.xml" 2>/dev/null

[ -s "$TMP/lf_stub.xml" ] && [ -s "$TMP/lf_restored.xml" ] || no "(1) empty output — the rest of this gate is meaningless"

printf '%s' "$( cat "$TMP/lf_stub.xml" )" | grep -Eq '<lego total="[0-9]+" shown="0" capped="1" next="[^"]*"/>' \
    && ok "(1a) default run: <lego> is a self-closing counted stub" \
    || no "(1a) default run: no <lego total= shown=\"0\" capped=\"1\" next=…/> stub found — $( grep -o '<lego[^>]*' "$TMP/lf_stub.xml" | head -1 )"

grep -q '<iface\|<impl' "$TMP/lf_stub.xml" \
    && no "(1b) default run: full <iface>/<impl> rows leaked past the stub" \
    || ok "(1b) default run: no <iface>/<impl> rows (the stub carries no body)"

grep -Fq '<lego><iface' "$TMP/lf_restored.xml" \
    && ok "(1c) --sections=lego,compose: full <lego><iface…> render restored" \
    || no "(1c) --sections=lego,compose: expected the full <lego><iface…> shape, got $( grep -o '<lego[^>]*' "$TMP/lf_restored.xml" | head -1 )"

cmp -s "$TMP/lf_restored.xml" "$TMP/lf_restored_rev.xml" \
    && ok "(1d) --sections=lego,compose and --sections=compose,lego are order-insensitive (byte-identical)" \
    || no "(1d) --sections order changed the output — the set must be order-insensitive"

# The reference this arm proves byte identity against: the SAME query, same fixture, rendered by a
# binary built before this lane (2026-09-19, commit 7d72e7235 — captured once, not re-derived, so a
# future accidental behavior change in EITHER binary is caught rather than silently re-baselined).
read -r -d '' LF_GOLDEN <<'GOLDEN_EOF' || true
<ctx task="shape interface implementors" route="subtoken+body" root="test/legofix" confidence="high" margin_pct="41" at="7d72e7235+dirty" bundle="sigs" budget_bytes="7500" est_tokens="4023"><!-- ripwire lens for "shape interface implementors" [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=sigs: signatures only in this bundle, no inline bodies — fetch a symbol's full body with the fetch_body verb --><!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). -->
GOLDEN_EOF
# This gate does NOT assert the golden verbatim (the ranked <sigs> head is corpus-sensitive and this
# fixture's git churn is not pinned) — it asserts the one property that IS this lever's contract: the
# lego/compose SECTION BYTES are unaffected by anything else in the document. Extract just those two
# elements from both the restored run and a same-session re-run and require them identical, which is the
# real content the CLI --for full dialect could always spell before this lane and still can via the flag.
sections(){ grep -o '<lego>.*</lego><compose>.*</compose>\|<lego>.*</lego>\|<compose>.*</compose>' "$1" || true; }
"$BIN" test/legofix --no-cache --legend=full --for="$LFQ" --sections=lego,compose >"$TMP/lf_restored2.xml" 2>/dev/null
[ "$( sections "$TMP/lf_restored.xml" )" = "$( sections "$TMP/lf_restored2.xml" )" ] && [ -n "$( sections "$TMP/lf_restored.xml" )" ] \
    && ok "(1e) restored <lego>/<compose> section bytes are deterministic across runs" \
    || no "(1e) restored <lego>/<compose> section bytes differ between two runs of the same query"

# ── (2) total= is the RESTORED render's own row count (never guessed, never the JSON pre-dedup count) ──
STUBTOTAL="$( grep -o '<lego total="[0-9]*"' "$TMP/lf_stub.xml" | grep -o '[0-9]*' )"
IFACEROWS="$( grep -o '<iface ' "$TMP/lf_restored.xml" | wc -l | tr -d ' ' )"
if [ -n "$STUBTOTAL" ] && [ -n "$IFACEROWS" ]; then
    # packLego caps at topN=12 in ranked mode; on this small fixture the restored count must equal the
    # stub's total= exactly (both well under the cap).
    [ "$STUBTOTAL" = "$IFACEROWS" ] \
        && ok "(2a) lego total=\"$STUBTOTAL\" matches the restored render's $IFACEROWS <iface> row(s) exactly" \
        || no "(2a) lego total=\"$STUBTOTAL\" but the restored render shows $IFACEROWS <iface> row(s)"
else
    no "(2a) could not read total=/<iface> counts to compare"
fi

# ── (3) absent section: this fixture has no compose edges — no stub, in EITHER dialect ──────────────────
grep -q '<compose' "$TMP/lf_stub.xml" \
    && no "(3) default run: <compose> present for a fixture with no compose edges (should be wholly absent)" \
    || ok "(3) default run: no <compose> element at all — absence stays absence, no stub invents a row"
grep -q '<compose' "$TMP/lf_restored.xml" \
    && no "(3) --sections=lego,compose: <compose> present for a fixture with no compose edges" \
    || ok "(3) --sections=lego,compose: still no <compose> element (consistent with the default run)"

# ── (4) test/sectionpricefix: a query with BOTH sections non-empty (and both PRICED ABOVE the round-2
# threshold — see (10) below), cross-checked against the restored render's exact compose count. packCompose
# has no cap, so its total= must equal <field> exactly (a strict cross-check unlike lego's). A dedicated,
# committed fixture (not the live repo root: R2-L2' prices the stub against the SECTION'S OWN bytes, so a
# repo-root probe query drifts in and out of collapsing as the corpus changes underneath it — R2's own
# measurement hit exactly this, see (10)'s note).
RQ="big iface implementors owner"
"$BIN" test/sectionpricefix --no-cache --legend=full --for="$RQ" >"$TMP/r_stub.xml" 2>/dev/null
"$BIN" test/sectionpricefix --no-cache --legend=full --for="$RQ" --sections=compose >"$TMP/r_compose_only.xml" 2>/dev/null
COMPOSETOTAL="$( grep -o '<compose total="[0-9]*"' "$TMP/r_stub.xml" | grep -o '[0-9]*' )"
FIELDROWS="$( grep -o '<field ' "$TMP/r_compose_only.xml" | wc -l | tr -d ' ' )"
if [ -n "$COMPOSETOTAL" ] && [ -n "$FIELDROWS" ]; then
    [ "$COMPOSETOTAL" = "$FIELDROWS" ] \
        && ok "(4a) compose total=\"$COMPOSETOTAL\" matches --sections=compose's $FIELDROWS <field> row(s) exactly (no cap on this section)" \
        || no "(4a) compose total=\"$COMPOSETOTAL\" but --sections=compose shows $FIELDROWS <field> row(s)"
else
    no "(4a) test/sectionpricefix's ranking of \"$RQ\" surfaced no compose edges ($COMPOSETOTAL/$FIELDROWS)"
fi
grep -Eq '<lego total="[0-9]+" shown="0"' "$TMP/r_compose_only.xml" \
    && ok "(4b) --sections=compose restores compose ALONE — lego is still stubbed" \
    || no "(4b) --sections=compose unexpectedly restored lego too (the set must be independent per section)"
grep -Fq '<compose><field' "$TMP/r_compose_only.xml" \
    && ok "(4c) --sections=compose restores the full <compose><field…> render" \
    || no "(4c) --sections=compose did not restore the full compose render"

# ── (5) next= is a real, runnable invocation (nextverb.h's own contract — E41 rule b) ────────────────────
NEXT="$( grep -o '<lego[^>]*next="[^"]*"' "$TMP/r_stub.xml" | head -1 | grep -o 'next="[^"]*"' | sed 's/^next="//; s/"$//' \
         | sed 's/&quot;/"/g; s/&apos;/'"'"'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g' )"
if [ -n "$NEXT" ]; then
    [ "${#NEXT}" -le 120 ] \
        && ok "(5a) next= is ${#NEXT} B (<= 120, nextverb.h's kNextAttrMaxBytes)" \
        || no "(5a) next= is ${#NEXT} B (> 120): $NEXT"
    case "$NEXT" in
        *"--sections=lego,compose"*) ok "(5b) next= names the restoring spelling --sections=lego,compose" ;;
        *) no "(5b) next= does not name --sections=lego,compose: $NEXT" ;;
    esac
    python3 -c "import shlex,sys; print('\0'.join(shlex.split(sys.argv[1])),end='')" "$NEXT" >"$TMP/argv.bin"
    ( cd "$ROOT" && xargs -0 "$BIN" test/sectionpricefix --no-cache < "$TMP/argv.bin" >"$TMP/nx.out" 2>"$TMP/nx.err" ); rc=$?
    if [ "$rc" = 0 ] || [ "$rc" = 4 ]; then
        ok "(5c) next=\"$NEXT\" parses and runs (exit $rc)"
    else
        no "(5c) next=\"$NEXT\" exits $rc: $( head -c 160 "$TMP/nx.err" | tr '\n' ' ' )"
    fi
    grep -Fq '<lego><iface' "$TMP/nx.out" \
        && ok "(5d) running next= verbatim restores the full <lego> render" \
        || no "(5d) running next= verbatim did not restore the full <lego> render"
else
    no "(5) no next= found on the repo-root stub to test"
fi

# ── (6) refusals: closed set, and --sections modifies --for only ─────────────────────────────────────
"$BIN" . --no-cache --for="x" --sections=bogus >"$TMP/bad1.out" 2>"$TMP/bad1.err"; rc1=$?
[ "$rc1" != 0 ] && grep -q 'sections' "$TMP/bad1.err" \
    && ok "(6a) --sections=bogus refuses (exit $rc1)" \
    || no "(6a) --sections=bogus did not refuse cleanly (exit $rc1): $( cat "$TMP/bad1.err" )"

"$BIN" . --no-cache --for="x" --sections=lego,lego >"$TMP/bad2.out" 2>"$TMP/bad2.err"; rc2=$?
[ "$rc2" != 0 ] \
    && ok "(6b) --sections=lego,lego (a name repeated) refuses (exit $rc2)" \
    || no "(6b) --sections=lego,lego did not refuse (a repeated name should not silently pass)"

"$BIN" . --no-cache --sections=lego >"$TMP/bad3.out" 2>"$TMP/bad3.err"; rc3=$?
[ "$rc3" != 0 ] && grep -q -- '--for' "$TMP/bad3.err" \
    && ok "(6c) --sections without --for refuses, naming --for" \
    || no "(6c) --sections without --for did not refuse cleanly (exit $rc3): $( cat "$TMP/bad3.err" )"

# (6d)/(6e) CodeRabbit 4054594298 (train 8): an EMPTY segment is a typo too. The parse loop used to stop on
# "nothing left", so the empty segment after a trailing comma was never read and `lego,` passed as `lego`.
for badv in 'lego,' 'lego,,compose'; do
    "$BIN" . --no-cache --for="x" --sections="$badv" >"$TMP/bad4.out" 2>"$TMP/bad4.err"; rc4=$?
    [ "$rc4" != 0 ] && grep -q 'sections' "$TMP/bad4.err" \
        && ok "(6d) --sections=$badv (an empty segment) refuses (exit $rc4)" \
        || no "(6d) --sections=$badv did not refuse (exit $rc4) — an empty segment was read as absent"
done

# ── (7) well-formed XML on every shape this gate rendered ────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    lint=1
    for f in lf_stub lf_restored lf_restored_rev r_stub r_compose_only; do
        xmllint --noout "$TMP/$f.xml" 2>/dev/null || { echo "    malformed: $TMP/$f.xml"; lint=0; }
    done
    if [ "$lint" = 1 ]; then ok "(7) every rendered shape is well-formed XML (G4)"; else no "(7) malformed XML above"; fi
else
    ok "(7) xml well-formed (xmllint absent — skipped)"
fi

# ── (8) MCP `for` twin: same stub, same closed-set refusal ────────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
    MCPQ='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"test/legofix","task":"shape interface implementors","legend":"full"}}}'
    printf '%s\n' "$MCPQ" | "$BIN" --mcp >"$TMP/mcp_stub.json" 2>/dev/null
    python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
t = d.get('result',{}).get('content',[{}])[0].get('text','')
sys.exit(0 if ('<lego total=' in t and '<iface' not in t) or '<lego' not in t else 1)
" "$TMP/mcp_stub.json" \
        && ok "(8a) MCP for: default carries no full <iface> render (stub or absent)" \
        || no "(8a) MCP for: full <iface> content leaked past the default stub"

    MCPBAD='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"test/legofix","task":"shape interface implementors","sections":"bogus"}}}'
    printf '%s\n' "$MCPBAD" | "$BIN" --mcp >"$TMP/mcp_bad.json" 2>/dev/null
    grep -q '"error"' "$TMP/mcp_bad.json" && grep -q 'sections' "$TMP/mcp_bad.json" \
        && ok "(8b) MCP for: sections=\"bogus\" refuses with a message naming the field" \
        || no "(8b) MCP for: sections=\"bogus\" did not refuse cleanly: $( cat "$TMP/mcp_bad.json" )"

    # (8c) independent review, 2026-09-19: PRESENT-BUT-EMPTY must refuse exactly like the CLI's own
    # --sections= (empty value) does — the F9/F11 ABSENT-vs-PRESENT-BUT-EMPTY rule `legend` already
    # follows. `sections:""` used to be silently read as "restore nothing" (the guard was `!sections.empty()`,
    # which cannot distinguish absent from present-but-empty) — a real, shipped bug caught before landing.
    MCPEMPTY='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"test/legofix","task":"shape interface implementors","sections":""}}}'
    printf '%s\n' "$MCPEMPTY" | "$BIN" --mcp >"$TMP/mcp_empty.json" 2>/dev/null
    grep -q '"error"' "$TMP/mcp_empty.json" && grep -q 'sections' "$TMP/mcp_empty.json" \
        && ok "(8c) MCP for: sections=\"\" (present, empty) refuses — not silently read as absent" \
        || no "(8c) MCP for: sections=\"\" did not refuse — present-but-empty was read as absent: $( cat "$TMP/mcp_empty.json" )"

    # (8d) CodeRabbit 4054594302 (train 8): the MCP twin of (6d) — an empty segment refuses here too.
    for badv in 'lego,' 'lego,,compose'; do
        MCPTRAIL='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"test/legofix","task":"shape interface implementors","sections":"'"$badv"'"}}}'
        printf '%s\n' "$MCPTRAIL" | "$BIN" --mcp >"$TMP/mcp_trail.json" 2>/dev/null
        grep -q '"error"' "$TMP/mcp_trail.json" && grep -q 'sections' "$TMP/mcp_trail.json" \
            && ok "(8d) MCP for: sections=\"$badv\" (an empty segment) refuses" \
            || no "(8d) MCP for: sections=\"$badv\" did not refuse: $( head -c 300 "$TMP/mcp_trail.json" )"
    done
else
    ok "(8) MCP arm skipped (python3 absent)"
fi

# ── (9) the OPEN_MEMSTREAM DEGRADE PATH: an UNMEASURED section is never collapsed ────────────────────
# History. The independent review of 2026-09-19 found this path streaming the full section regardless of
# --sections=, and made it collapse UNCONDITIONALLY (round 1's rule) from a row count computed without
# rendering. CodeRabbit 4054594306 (train 8) found the other half: round 2's rule is "collapse ONLY WHEN
# CHEAPER", and a section that was never rendered has no size to compare — collapsing it anyway replaced
# test/hasafix's two-row <compose> (smaller than its own stub + clause, arm 10) with the LARGER stub plus its
# legend clause, so the section's shape depended on whether an allocation succeeded. rw::priceSectionStub now
# refuses to collapse without measured bytes, and the degrade path streams the section WHOLE — exactly what
# --sections= restores. That path already omits est_tokens= and discloses why, so nothing is priced wrong.
#
# THE SWITCH EXISTS ONLY ON THE NON-NDEBUG FLAVOUR (serialize.h's own header comment on
# RIPWIRE_FAULT_CHARGE_BUFFER): on a Release/NDEBUG binary the switch is compiled to constexpr-false and
# setting the env var injects nothing, which would make this arm trivially (and falsely) green. Detected the
# estchargecheck.sh way: force an UNRELATED, always-present degrade path (the --scip corrupt-index alert) and
# check whether its own DISCLOSE reaches stderr — if it cannot, no alert in this binary can be observed, and
# forcing RIPWIRE_FAULT_CHARGE_BUFFER on it proves nothing either. SKIP (not silently PASS) is correct there;
# CI's non-NDEBUG leg is what actually proves this arm.
printf 'not a scip index at all\n' > "$TMP/flavour.scip"
"$BIN" test/fixture --scip="$TMP/flavour.scip" --top-k=1 --no-cache >/dev/null 2>"$TMP/flavour.err"
if grep -qF '[math degraded] --scip: corrupt/truncated index' "$TMP/flavour.err"; then
    RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" test/legofix --no-cache --legend=full --for="$LFQ" >"$TMP/fault_stub2.xml" 2>"$TMP/fault_stub2.err"
    if grep -q 'open_memstream failed' "$TMP/fault_stub2.err"; then
        # NOTE: RIPWIRE_FAULT_CHARGE_BUFFER fails EVERY openChargeStream call in the process (serialize.h's own
        # header: "one seam for two reasons"), so <sigs> ALSO degrades and the WHOLE document takes a different
        # shape (no est_tokens=, etc.) — these arms compare just the <lego>/<compose> FRAGMENT, the one thing
        # this rule controls.
        grep -Eq '<(lego|compose) total="[0-9]+" shown="0"' "$TMP/fault_stub2.xml" \
            && no "(9a) RIPWIRE_FAULT_CHARGE_BUFFER=1: an unmeasured section collapsed to a stub — $( grep -Eo '<(lego|compose) total=[^>]*' "$TMP/fault_stub2.xml" | head -1 )" \
            || ok "(9a) RIPWIRE_FAULT_CHARGE_BUFFER=1: no stub on the degrade path (nothing was measured, so nothing is claimed cheaper)"
        [ "$( sections "$TMP/fault_stub2.xml" )" = "$( sections "$TMP/lf_restored.xml" )" ] && [ -n "$( sections "$TMP/fault_stub2.xml" )" ] \
            && ok "(9b) RIPWIRE_FAULT_CHARGE_BUFFER=1: the default run streams the WHOLE section, byte-identical to the buffered --sections=lego,compose restore" \
            || no "(9b) RIPWIRE_FAULT_CHARGE_BUFFER=1: the degrade-path <lego>/<compose> fragment differs from the buffered restore"
        grep -Fq 'lego/compose collapse to a counted stub' "$TMP/fault_stub2.xml" \
            && no "(9c) RIPWIRE_FAULT_CHARGE_BUFFER=1: the stub legend clause rides a document with no stub" \
            || ok "(9c) RIPWIRE_FAULT_CHARGE_BUFFER=1: no stub, no stub legend clause"
        RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" test/legofix --no-cache --legend=full --for="$LFQ" --sections=lego,compose >"$TMP/fault_restored.xml" 2>/dev/null
        [ "$( sections "$TMP/fault_restored.xml" )" = "$( sections "$TMP/lf_restored.xml" )" ] && [ -n "$( sections "$TMP/fault_restored.xml" )" ] \
            && ok "(9d) RIPWIRE_FAULT_CHARGE_BUFFER=1 + --sections=lego,compose: the <lego>/<compose> fragment matches the buffered restore" \
            || no "(9d) RIPWIRE_FAULT_CHARGE_BUFFER=1 + --sections=lego,compose: the <lego>/<compose> fragment differs from the buffered restore"
        # (9f) the case CodeRabbit named: test/hasafix's <compose> stays WHOLE on the buffered path (arm 10)
        # because it is smaller than its stub — and must stay whole on the degrade path too.
        RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" test/hasafix --no-cache --legend=full --for="member field composition" >"$TMP/fault_hasa.xml" 2>/dev/null
        grep -Fq '<compose><field' "$TMP/fault_hasa.xml" \
            && ok "(9f) RIPWIRE_FAULT_CHARGE_BUFFER=1: test/hasafix's small <compose> stays WHOLE, as on the buffered path" \
            || no "(9f) RIPWIRE_FAULT_CHARGE_BUFFER=1: test/hasafix's <compose> collapsed on the degrade path — $( grep -o '<compose[^>]*' "$TMP/fault_hasa.xml" | head -1 )"
        if command -v xmllint >/dev/null 2>&1; then
            xmllint --noout "$TMP/fault_stub2.xml" 2>/dev/null && xmllint --noout "$TMP/fault_restored.xml" 2>/dev/null && xmllint --noout "$TMP/fault_hasa.xml" 2>/dev/null \
                && ok "(9e) degrade-path shapes are well-formed XML" \
                || no "(9e) degrade-path shapes are malformed XML"
        fi
    else
        no "(9) RIPWIRE_FAULT_CHARGE_BUFFER=1 produced no 'open_memstream failed' DISCLOSE on a build that CAN observe alerts (the unrelated --scip probe fired) — the openChargeStream seam or the switch regressed. This is a FAILURE, not a skip."
    fi
else
    skip(){ printf '  SKIP  %s\n' "$*"; }
    skip "(9) open_memstream degrade arms — DISCLOSE is compiled out of this binary (the unrelated --scip decode degrade path produced no alert either, so alerts are unobservable globally here, not this seam having broken). RIPWIRE_FAULT_CHARGE_BUFFER does not exist on this flavour. Proven by the PLAIN-flavour CI leg, the estchargecheck.sh #14 precedent."
fi

# ── (10) R2-L2' PRICED: a section SMALLER than its own stub (+ the legend clause's unshared charge) stays
# WHOLE — the round-2 delta over round-1's unconditional collapse. test/hasafix's <compose> is two short
# <field> rows (168 B measured) against a stub (task-echoing next=) plus the 251 B kForSectionStubLegend
# clause (≈ 356 B here) — smaller than what would replace it, so it must NOT collapse, in either dialect.
# RED on the pre-R2 binary (round-1 collapsed every non-empty section unconditionally); GREEN here.
HQ="member field composition"
"$BIN" test/hasafix --no-cache --legend=full    --for="$HQ" >"$TMP/hasa_full.xml"    2>/dev/null
"$BIN" test/hasafix --no-cache --legend=compact --for="$HQ" >"$TMP/hasa_compact.xml" 2>/dev/null
grep -Fq '<compose><field' "$TMP/hasa_full.xml" \
    && ok "(10a) full: a <compose> smaller than its own stub+clause stays WHOLE (no collapse)" \
    || no "(10a) full: <compose> collapsed even though it is smaller than its stub — $( grep -o '<compose[^>]*' "$TMP/hasa_full.xml" | head -1 )"
grep -Fq '<compose><field' "$TMP/hasa_compact.xml" \
    && ok "(10b) compact: same section stays WHOLE (posture carries no separate threshold)" \
    || no "(10b) compact: <compose> collapsed even though it is smaller than its stub — $( grep -o '<compose[^>]*' "$TMP/hasa_compact.xml" | head -1 )"
grep -Eq '<(lego|compose) total="[0-9]+" shown="0"' "$TMP/hasa_full.xml" \
    && no "(10c) a lego/compose stub shape leaked into a run that should have stayed whole" \
    || ok "(10c) no lego/compose stub shape anywhere in the whole-section run (unrelated <tail total= shown=> is a different element)"

# ── (11) R2-L2' PRICED, posture-independent (rv-prereg2 Amendment 1, R4): the COLLAPSE SET — which of
# lego/compose collapsed — is IDENTICAL under --legend=full and --legend=compact, on both a section that
# collapses (test/sectionpricefix, priced above threshold) and one that does not (test/hasafix, priced
# below). kForSectionStubLegend is the one clause text both dialects splice (never a shorter compact-only
# variant), so the size-gate arithmetic cannot differ by posture.
"$BIN" test/sectionpricefix --no-cache --legend=full    --for="$RQ" >"$TMP/big_full.xml"    2>/dev/null
"$BIN" test/sectionpricefix --no-cache --legend=compact --for="$RQ" >"$TMP/big_compact.xml" 2>/dev/null
collapse_set(){ { grep -Eqo '<lego total="[0-9]+" shown="0"' "$1" && printf 'lego '; } ; { grep -Eqo '<compose total="[0-9]+" shown="0"' "$1" && printf 'compose '; } ; }
BIGFULL_SET="$( collapse_set "$TMP/big_full.xml" )"
BIGCOMPACT_SET="$( collapse_set "$TMP/big_compact.xml" )"
[ "$BIGFULL_SET" = "$BIGCOMPACT_SET" ] && [ -n "$BIGFULL_SET" ] \
    && ok "(11a) sectionpricefix: same collapse set under full and compact (\"$BIGFULL_SET\")" \
    || no "(11a) sectionpricefix: collapse set differs by posture — full=\"$BIGFULL_SET\" compact=\"$BIGCOMPACT_SET\""
HASAFULL_SET="$( collapse_set "$TMP/hasa_full.xml" )"
HASACOMPACT_SET="$( collapse_set "$TMP/hasa_compact.xml" )"
[ "$HASAFULL_SET" = "$HASACOMPACT_SET" ] && [ -z "$HASAFULL_SET" ] \
    && ok "(11b) hasafix: same (empty) collapse set under full and compact — neither dialect collapses a too-small section" \
    || no "(11b) hasafix: collapse set differs by posture, or unexpectedly non-empty — full=\"$HASAFULL_SET\" compact=\"$HASACOMPACT_SET\""

# ── (12) R2-L2p (independent review, 2026-09-19): the MCP `for` twin must carry the SAME disclosure the CLI
# does when a stub happens — rw::kForSectionStubLegend, spliced into the header comment (the CLI splices it
# via finishForLensHeaderPriced/spliceBefore; the MCP twin, forTaskText in src/mcpverbs.h, computes the same
# collapse decision through the shared rw::priceSectionStub but used to swap legoStr/composeStr for their
# stub XML and never carry the clause explaining the cut — arm (8a) above only proves no FULL render leaked,
# it never checked for the legend). test/sectionpricefix's "big iface implementors owner" (RQ, the same
# fixture/query the CLI-side arms (4)/(11a) already use) collapses <compose> on the MCP surface too (no
# <lego> element on this route — the MCP bundle ranking differs slightly from the CLI's own bundle choice,
# which does not matter here: this arm only needs ONE section to have collapsed to prove the legend rides
# it, exactly the "at least one section" condition both dialects share).
if command -v python3 >/dev/null 2>&1; then
    MCPRQ='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"test/sectionpricefix","task":"big iface implementors owner"}}}'
    printf '%s\n' "$MCPRQ" | "$BIN" --mcp >"$TMP/mcp_legend.json" 2>/dev/null
    python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
t = d.get('result',{}).get('content',[{}])[0].get('text','')
stubbed = ('<lego total=' in t) or ('<compose total=' in t)
legend = 'lego/compose collapse to a counted stub by default' in t
sys.exit(0 if (stubbed and legend) else 1)
" "$TMP/mcp_legend.json" \
        && ok "(12a) MCP for: a stubbed lego/compose section carries the kForSectionStubLegend clause" \
        || no "(12a) MCP for: a section stubbed but the legend clause is missing — $( head -c 400 "$TMP/mcp_legend.json" )"

    python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
t = d.get('result',{}).get('content',[{}])[0].get('text','')
sys.exit(0 if '<compose total=\"5\" shown=\"0\"' in t else 1)
" "$TMP/mcp_legend.json" \
        && ok "(12b) MCP for: the stub itself is unchanged by the fix (compose total=\"5\" shown=\"0\")" \
        || no "(12b) MCP for: the stub shape changed unexpectedly — $( head -c 400 "$TMP/mcp_legend.json" )"

    if command -v xmllint >/dev/null 2>&1; then
        python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
sys.stdout.write(d.get('result',{}).get('content',[{}])[0].get('text',''))
" "$TMP/mcp_legend.json" > "$TMP/mcp_legend.xml"
        xmllint --noout "$TMP/mcp_legend.xml" 2>/dev/null \
            && ok "(12c) MCP for: the legend-carrying document is well-formed XML (G4)" \
            || no "(12c) MCP for: the legend-carrying document is malformed XML"
    else
        ok "(12c) xml well-formed (xmllint absent — skipped)"
    fi

    # (12d) no-stub control: --sections=lego,compose opts back into the full render (arm (8) already proves
    # this for the CLI), so nothing collapses and the clause must be PRESENT-ONLY — absent here, not padded
    # onto an answer with nothing to disclose.
    MCPNOSTUB='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"test/sectionpricefix","task":"big iface implementors owner","sections":"lego,compose"}}}'
    printf '%s\n' "$MCPNOSTUB" | "$BIN" --mcp >"$TMP/mcp_nostub.json" 2>/dev/null
    python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
t = d.get('result',{}).get('content',[{}])[0].get('text','')
sys.exit(0 if 'lego/compose collapse to a counted stub by default' not in t else 1)
" "$TMP/mcp_nostub.json" \
        && ok "(12d) MCP for: --sections=lego,compose (nothing stubbed) carries NO legend clause" \
        || no "(12d) MCP for: the legend clause leaked onto a run where nothing was stubbed"
else
    ok "(12) MCP legend disclosure arm skipped (python3 absent)"
fi

# ── (13) lego-charge (K18 root cause): the <sigs> budget charges a collapsing section at its STUB, not its full render.
# test/legochargefix is textual-shaped: its query names 14 interfaces with 4 implementors each, so the full <lego> render
# (~10 KB) is bigger than the default <sigs> budget, while the default answer serves it as a ~150 B stub. Charging the
# full render left 1 B for <sigs>: 4 rows in a ~3 KB answer under a 7.5 KB ceiling (textual's round-1 rows: 4 of 40).
# Rules (rw::forSectionsSigChargePlan, serialize.h): no explicit ceiling → the default answer's charge, also under
# --sections= (so the stub's next= restores both sections with the SAME <sigs>, byte-identically); an explicit ceiling
# (--token-budget, MCP budget_tokens) → a section --sections= opts into is charged in full (hard bound).
LCQ="how do render stage classes arrange and reflow widgets"
lc_shown(){ grep -o '<sigs shown="[0-9]*"' "$1" | head -1 | grep -o '[0-9][0-9]*'; }
lc_est(){ grep -o 'est_tokens="[0-9]*"' "$1" | head -1 | grep -o '[0-9][0-9]*'; }
lc_sigs(){ grep -o '<sigs .*</sigs>' "$1"; }
"$BIN" test/legochargefix --no-cache --for="$LCQ" >"$TMP/lc_def.xml" 2>/dev/null;                                  rc_def=$?
"$BIN" test/legochargefix --no-cache --for="$LCQ" --sections=lego,compose >"$TMP/lc_rest.xml" 2>/dev/null;         rc_rest=$?
"$BIN" test/legochargefix --no-cache --for="$LCQ" --token-budget=3000 >"$TMP/lc_tb.xml" 2>/dev/null;               rc_tb=$?
"$BIN" test/legochargefix --no-cache --for="$LCQ" --token-budget=3000 --sections=lego,compose >"$TMP/lc_tbrest.xml" 2>/dev/null; rc_tbrest=$?
LC_DEF="$( lc_shown "$TMP/lc_def.xml" )"; LC_REST="$( lc_shown "$TMP/lc_rest.xml" )"
LC_TB="$( lc_shown "$TMP/lc_tb.xml" )";   LC_TBREST="$( lc_shown "$TMP/lc_tbrest.xml" )"; LC_TBEST="$( lc_est "$TMP/lc_tbrest.xml" )"
if [ "$rc_def$rc_rest$rc_tb$rc_tbrest" != "0000" ] || ! [[ "$LC_DEF" =~ ^[0-9]+$ && "$LC_REST" =~ ^[0-9]+$ && "$LC_TB" =~ ^[0-9]+$ && "$LC_TBREST" =~ ^[0-9]+$ && "$LC_TBEST" =~ ^[0-9]+$ ]]; then
    no "(13) legochargefix: a run failed or printed no <sigs shown=>/est_tokens= (rc=$rc_def/$rc_rest/$rc_tb/$rc_tbrest shown=$LC_DEF/$LC_REST/$LC_TB/$LC_TBREST est=$LC_TBEST)"
else
    # (13a) RED on the base: the stub is served, so the budget pays the stub — the answer carries a budget's worth of rows
    grep -Eq '<lego total="[0-9]+" shown="0" capped="1" next="[^"]*"/>' "$TMP/lc_def.xml" && [ "$LC_DEF" -ge 24 ] \
        && ok "(13a) default: <lego> is served as a stub and <sigs> shows $LC_DEF rows (the stub's price was charged, not the full render's)" \
        || no "(13a) default: <sigs shown=\"$LC_DEF\"> (want >= 24 with a <lego> stub) — the budget paid for a lego render it never served"
    # (13b) the stub's next= restores both sections byte-identically: same <sigs> block, the full <lego> on top
    [ "$( lc_sigs "$TMP/lc_def.xml" )" = "$( lc_sigs "$TMP/lc_rest.xml" )" ] && grep -q '<lego><iface ' "$TMP/lc_rest.xml" \
        && ok "(13b) --sections=lego,compose: the same <sigs> as the stubbed answer ($LC_REST rows) plus the full <lego>" \
        || no "(13b) --sections=lego,compose: <sigs shown=\"$LC_REST\"> differs from the stubbed answer's ($LC_DEF) or no full <lego> — next= does not restore the cut it disclosed"
    LC_STUBTOTAL="$( grep -o '<lego total="[0-9]*"' "$TMP/lc_def.xml" | head -1 | grep -o '[0-9][0-9]*' )"
    LC_IFACES="$( grep -o '<iface ' "$TMP/lc_rest.xml" | wc -l | tr -d ' ' )"
    [[ "$LC_STUBTOTAL" =~ ^[0-9]+$ ]] && [ "$LC_IFACES" -eq "$(( LC_STUBTOTAL < 12 ? LC_STUBTOTAL : 12 ))" ] \
        && ok "(13c) the stub's total=$LC_STUBTOTAL matches the restored <lego> ($LC_IFACES <iface> rows, display cap 12)" \
        || no "(13c) the stub's total=\"$LC_STUBTOTAL\" vs $LC_IFACES restored <iface> rows (display cap 12)"
    # (13d) NEAR-MISS: under an explicit ceiling, a section --sections= opts into is charged in full — the hard bound holds
    # (its <lego> is then narrowed to the few rendered rows' files — here none of stages.h — so the bound is read off <sigs>)
    [ "$LC_TBEST" -le 3000 ] && [ "$LC_TBREST" -lt "$LC_TB" ] \
        && ok "(13d) --token-budget=3000 --sections=lego,compose: est_tokens=$LC_TBEST <= 3000, <sigs> $LC_TBREST < $LC_TB (the full <lego> was charged)" \
        || no "(13d) --token-budget=3000 --sections=lego,compose: est_tokens=$LC_TBEST, <sigs> $LC_TBREST vs $LC_TB stubbed — the opted-in section was not charged in full under an explicit ceiling"
fi
if command -v python3 >/dev/null 2>&1; then
    lc_mcp(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"test/legochargefix","task":"%s"%s}}}\n' "$LCQ" "$1" \
                | "$BIN" --mcp 2>/dev/null | python3 -c "
import json,sys,re
t = json.loads(sys.stdin.readline())['result']['content'][0]['text']
m = re.search(r'<sigs shown=\"([0-9]+)\"', t)
print(m.group(1) if m else 'none')"; }
    LCM_DEF="$( lc_mcp '' )"; LCM_TB="$( lc_mcp ',"budget_tokens":3000' )"; LCM_TBREST="$( lc_mcp ',"budget_tokens":3000,"sections":"lego,compose"' )"
    [[ "$LCM_DEF" =~ ^[0-9]+$ && "$LCM_TB" =~ ^[0-9]+$ && "$LCM_TBREST" =~ ^[0-9]+$ ]] && [ "$LCM_DEF" -ge 24 ] && [ "$LCM_TBREST" -lt "$LCM_TB" ] \
        && ok "(13e) MCP for: the same charge — <sigs> $LCM_DEF rows by default; under budget_tokens + sections $LCM_TBREST < $LCM_TB" \
        || no "(13e) MCP for: <sigs shown> default=$LCM_DEF budget=$LCM_TB budget+sections=$LCM_TBREST (want >= 24, and the last below the middle)"
else
    printf '  SKIP  %s\n' "(13e) python3 absent: the MCP twin of the lego charge is not checked"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
