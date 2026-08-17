#!/usr/bin/env bash
# prconvergecheck.sh — a ranked document DISCLOSES the PageRank power iteration that ordered it.
#
# WHY THIS GATE EXISTS. PageRank here stops on one of two conditions: the L1 residual falls below tolerance
# (the fixed point), or the iteration ceiling is reached with the residual still above it (a TRUNCATION of
# the computation). Before this item the two produced byte-identical documents. `pageRankDouble` fired
# DEGRADED_PATH_ALERT on the truncating exit and returned its iteration count; `rankGraphTeleport` discarded
# that return, and DEGRADED_PATH_ALERT is `#ifndef NDEBUG`, so on every shipped Release binary it is not code
# at all. A release build emitted a ranking from an unfinished iteration with no alert, no attribute, exit 0.
# `pr_iters=` / `pr_converged=` put the fact in the document, where a release build cannot delete it.
#
# THE GATE WAS RED BEFORE THE FEATURE, and this is what it looked like — recorded because a disclosure gate
# that was never observed failing is a gate nobody has evidence for:
#
#     RIPWIRE_BIN=<pre-feature binary> bash test/prconvergecheck.sh     ->  exit 1, 16 FAIL / 19 PASS
#       FAIL  (A) default map root carries pr_iters= with a plausible count (root: <r est_tokens="691">)
#       FAIL  (B) plain build: lowered ceiling must emit pr_iters="2" pr_converged="0" — got: <r est_tokens="691">
#       FAIL  (E) --tree / --seams / --communities / --zoom / --impact / --graph-query carry no pr_iters=
#       FAIL  (E) the MCP impact verb drops pr_iters= that its CLI sibling emits
#       FAIL  (F) the JSON map header is missing "pr_iters" the XML header carries
#       FAIL  (I) the default map emits pr_iters= with no definition on the first screen
#
# The 19 that PASSED on the pre-feature binary are the ABSENCE arms — (C), (D), (G), (H) — and their passing
# is not a defect in them: "no pr_iters= on a HITS map" is trivially true of a binary that has no pr_iters=
# anywhere. That asymmetry is why arm (A) leads. The presence arms carry the ratchet; the absence arms exist
# only so the presence arms cannot be satisfied by stamping the attribute onto everything.
#
# ARM 2 IS THE HARD ONE, AND IT NEEDED A HOOK. The obvious design is a fixture graph that genuinely fails to
# converge. It is provably impossible at the shipped configuration, so the effort was spent on the arithmetic
# instead of on the fixture: the iteration is an alpha-contraction in L1 (the operator is column-stochastic —
# wOutDeg is the exact per-source out-edge weight sum, and dangling mass is redistributed through the
# teleport prior), two probability vectors differ by at most 2 in L1, so residual_k <= 2 * alpha^k and
#
#     2 * 0.85^k < 1e-6   =>   k > ln(2e6)/ln(1/0.85) = 89.3
#
# No graph of any shape survives ~90 iterations against maxIterationCount = 100. E2 measured 28-52 across
# four real corpora (ripwire 33, memgraph 52, LightRAG 28, ugrep 28), which is the same fact from the other
# side. So the branch cannot be armed by an INPUT; it has to be armed by the ceiling, and
# `RIPWIRE_TEST_PR_MAXITERS=N` (src/pagerank.cpp) lowers it. The hook can only LOWER the configured ceiling —
# arm (C) proves it, so the arming mechanism cannot become a way to change shipped behaviour — it is not a
# flag and appears in no --help (arm (G) asserts that), and unlike serialize.h's RIPWIRE_FAULT_CHARGE_BUFFER
# it is honoured in EVERY build flavour, which is the whole point: the question this gate asks is whether an
# NDEBUG build still discloses after DEGRADED_PATH_ALERT has been compiled out of it.
#
# Arms:
#   (A) presence   — the default map root carries pr_iters="N" with 1 <= N <= 100, and NO pr_converged=
#   (B) truncation — under the lowered ceiling the plain build emits pr_iters="2" pr_converged="0", the
#                    prose clause, and still pipes clean through xmllint
#   (B2) RELEASE   — the same, from an NDEBUG binary. SKIPs with a banner when RIPWIRE_RELEASE_BIN is unset
#                    (the argvdiffcheck pattern: a gate that cannot run must say so, never pretend to pass)
#   (C) the hook can only LOWER — a ceiling at/above the configured one, and every malformed value, leave
#                    the output byte-identical to an unset run. This is the mutation control on the arming
#                    mechanism itself: without it the hook could silently be a behaviour switch
#   (D) absence    — a document NOT ordered by a power iteration (lexical query, HITS hub/authority) carries
#                    no pr_iters= at all, so the attribute never describes a ranking it did not shape
#   (E) surfaces   — every ranked verb root discloses, and the MCP twin agrees with its CLI sibling
#   (F) dialects   — the JSON header carries the same keyset (pr_iters, and pr_converged only when short)
#   (G) not a flag — RIPWIRE_TEST_PR_MAXITERS appears in no --help text (G5: flags are additive and parsed)
#   (H) determinism under the hook — two truncated runs are byte-identical
#   (I) legend     — where the attribute appears, the first screen DEFINES it (legendcoveragecheck's own
#                    stricter predicate, asserted here at the source so a legend edit reds this gate too)
#
# Usage:  bash test/prconvergecheck.sh   [RIPWIRE_BIN=path/to/binary] [RIPWIRE_RELEASE_BIN=path/to/ndebug/binary]
# Exit:   0 = clean · 1 = at least one arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
REL="${RIPWIRE_RELEASE_BIN:-}"
[ -n "$REL" ] && [ "${REL#/}" = "$REL" ] && REL="$ROOT/$REL"
[ -x "$BIN" ] || { printf 'prconvergecheck: no ripwire binary at %s — build first\n' "$BIN"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
CORPUS="test/fixture"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# The root open tag of an XML document, which is where every one of these attributes lives.
rootTag(){ grep -o '<r [^>]*>' "$1" | head -1; }

# ── (A) presence on the default map ───────────────────────────────────────────────────────────────
# The number is asserted as a RANGE, not a value: pinning 13 would red on any corpus edit and teach the
# next agent to update the expectation instead of reading it. What must hold is that it is a real
# iteration count — at least one iteration ran, and it is inside the ceiling the kernel ships with.
"$BIN" "$CORPUS" --no-cache >"$TMP/a.xml" 2>/dev/null
aRoot="$( rootTag "$TMP/a.xml" )"
aIters="$( printf '%s' "$aRoot" | sed -n 's/.* pr_iters="\([0-9]*\)".*/\1/p' )"
if [ -n "$aIters" ] && [ "$aIters" -ge 1 ] 2>/dev/null && [ "$aIters" -le 100 ]; then
    ok "(A) default map root carries pr_iters=\"$aIters\" (1..100, the shipped maxIterationCount)"
else
    no "(A) default map root carries pr_iters= with a plausible count (root: $aRoot)"
fi
case "$aRoot" in
    *pr_converged*) no "(A) a converged run must emit NO pr_converged= (absence means converged) — got: $aRoot" ;;
    *)              ok "(A) converged run emits no pr_converged= (zero-cost converged path)" ;;
esac

# ── (B) the truncating exit, plain build ──────────────────────────────────────────────────────────
RIPWIRE_TEST_PR_MAXITERS=2 "$BIN" "$CORPUS" --no-cache >"$TMP/b.xml" 2>/dev/null
bRoot="$( rootTag "$TMP/b.xml" )"
case "$bRoot" in
    *' pr_iters="2"'*' pr_converged="0"'*) ok "(B) plain build discloses the truncation: $bRoot" ;;
    *) no "(B) plain build: lowered ceiling must emit pr_iters=\"2\" pr_converged=\"0\" — got: $bRoot" ;;
esac
grep -q 'STOPPED SHORT of tolerance' "$TMP/b.xml" \
    && ok "(B) the truncated map carries the prose clause that says what to do about it" \
    || no "(B) the truncated map is missing the pr_converged=\"0\" prose clause"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/b.xml" 2>"$TMP/b.lint" \
        && ok "(B) the truncated map is still well-formed XML (G4)" \
        || { no "(B) the truncated map fails xmllint (G4)"; sed 's/^/          /' "$TMP/b.lint" | head -5; }
else
    printf '  SKIP  (B) xmllint not installed — well-formedness of the truncated map unchecked\n'
fi

# ── (B2) the truncating exit under NDEBUG — the reason this whole item exists ──────────────────────
# A Release build has no DEGRADED_PATH_ALERT. If the disclosure were still carried by the alert, this arm
# is where that would show. Build the reference with:
#     cmake -S . -B build_rel -DCMAKE_BUILD_TYPE=Release && cmake --build build_rel -j
#     RIPWIRE_RELEASE_BIN=build_rel/ripwire bash test/prconvergecheck.sh
if [ -z "$REL" ] || [ ! -x "$REL" ]; then
    echo "prconvergecheck: SKIP (B2) — no RIPWIRE_RELEASE_BIN reference binary"
    echo "  (cmake -S . -B build_rel -DCMAKE_BUILD_TYPE=Release && cmake --build build_rel -j, then"
    echo "   RIPWIRE_RELEASE_BIN=build_rel/ripwire bash test/prconvergecheck.sh — CI arms this arm)"
else
    RIPWIRE_TEST_PR_MAXITERS=2 "$REL" "$CORPUS" --no-cache >"$TMP/b2.xml" 2>"$TMP/b2.err"
    b2Root="$( rootTag "$TMP/b2.xml" )"
    case "$b2Root" in
        *' pr_iters="2"'*' pr_converged="0"'*) ok "(B2) NDEBUG build discloses the truncation: $b2Root" ;;
        *) no "(B2) NDEBUG build must emit pr_iters=\"2\" pr_converged=\"0\" — got: $b2Root" ;;
    esac
    # The counterpart fact, asserted so the arm's PREMISE is visible rather than assumed: the alert really
    # is gone from this flavour, so the attribute above is the only disclosure the release binary has.
    grep -q 'math degraded' "$TMP/b2.err" \
        && no "(B2) the NDEBUG binary still logs the degrade alert — is RIPWIRE_RELEASE_BIN really an NDEBUG build?" \
        || ok "(B2) the NDEBUG binary emits no degrade alert — the attribute is its only disclosure"
    "$REL" "$CORPUS" --no-cache >"$TMP/b2c.xml" 2>/dev/null
    case "$( rootTag "$TMP/b2c.xml" )" in
        *pr_converged*) no "(B2) the NDEBUG build's unhooked run must converge (no pr_converged=)" ;;
        *pr_iters=*)    ok "(B2) the NDEBUG build's unhooked run converges and says so by saying nothing" ;;
        *)              no "(B2) the NDEBUG build emits no pr_iters= at all" ;;
    esac
fi

# ── (C) the hook can only LOWER — mutation control on the arming mechanism ────────────────────────
# Each of these must produce a document byte-identical to the unset run. If any of them differed, the
# hook would be a behaviour switch rather than a test ceiling, and every arm above would be measuring a
# binary nobody ships.
for v in 100 100000 0 "" "2x" "x2" " 2" "-2"; do
    RIPWIRE_TEST_PR_MAXITERS="$v" "$BIN" "$CORPUS" --no-cache >"$TMP/c.xml" 2>/dev/null
    if cmp -s "$TMP/a.xml" "$TMP/c.xml"; then
        ok "(C) RIPWIRE_TEST_PR_MAXITERS='$v' leaves the document byte-identical (cannot raise, cannot corrupt)"
    else
        no "(C) RIPWIRE_TEST_PR_MAXITERS='$v' CHANGED the document — the hook is not lower-only/strict-parse"
        diff <( rootTag "$TMP/a.xml" ) <( rootTag "$TMP/c.xml" ) | sed 's/^/          /' | head -4
    fi
done

# ── (D) absence — the attribute never describes a ranking it did not shape ────────────────────────
# --query is a lexical BM25 score and --rank-by=hub/authority are HITS vectors that REPLACE the PageRank
# one. A pr_iters= on any of those would attach a power iteration's numbers to an ordering it does not
# explain, which is the §B2.1 defect this disclosure must not reintroduce.
for args in "--query=serialize" "--rank-by=hub" "--rank-by=authority"; do
    # shellcheck disable=SC2086
    "$BIN" "$CORPUS" $args --no-cache >"$TMP/d.xml" 2>/dev/null
    case "$( rootTag "$TMP/d.xml" )" in
        *pr_iters*) no "(D) $args is not PageRank-ordered but carries pr_iters=" ;;
        *)          ok "(D) $args carries no pr_iters= (its order did not come from a power iteration)" ;;
    esac
    grep -q 'pr_iters=pagerank-power-iterations' "$TMP/d.xml" \
        && no "(D) $args carries the pr legend clause it has no attribute for" \
        || ok "(D) $args pays no legend bytes for an attribute it does not emit"
done
# rrf FUSES pagerank with the two HITS vectors, so the run did shape the order and must be disclosed.
"$BIN" "$CORPUS" --rank-by=rrf --no-cache >"$TMP/d-rrf.xml" 2>/dev/null
case "$( rootTag "$TMP/d-rrf.xml" )" in
    *pr_iters=*) ok "(D) rank-by=rrf DOES disclose — pagerank is one of the vectors it fuses" ;;
    *)           no "(D) rank-by=rrf fuses pagerank but drops the disclosure" ;;
esac

# ── (E) every ranked verb root discloses, and the MCP twin agrees with its CLI sibling ────────────
for args in "--tree" "--seams" "--communities" "--zoom" "--impact=distance" "--graph-query=kind(all,fn)"; do
    # shellcheck disable=SC2086
    if "$BIN" "$CORPUS" $args --no-cache 2>/dev/null | grep -q 'pr_iters="[0-9]\+"'; then
        ok "(E) $args discloses pr_iters="
    else
        no "(E) $args is PageRank-ordered but its root carries no pr_iters="
    fi
done
# CLI ≡ MCP: the impact verb has two front doors and one wording. (mcpclidiffcheck owns the general rule;
# this arm pins THIS attribute at THIS seam, because "the clause landed at 3 of its 5 echo sites" is the
# failure family the shared-constant headers in src/ exist to stop.)
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"impact","arguments":{"path":"%s","symbol":"distance"}}}\n' "$CORPUS" \
    | "$BIN" --mcp >"$TMP/e.mcp" 2>/dev/null
if grep -q 'pr_iters=' "$TMP/e.mcp"; then
    ok "(E) the MCP impact verb discloses pr_iters= exactly as the CLI one does"
else
    no "(E) the MCP impact verb drops pr_iters= that its CLI sibling emits"
fi

# ── (F) dialect parity — one keyset, two spellings ────────────────────────────────────────────────
"$BIN" "$CORPUS" --json --no-cache >"$TMP/f.json" 2>/dev/null
grep -q '"pr_iters":[0-9]' "$TMP/f.json" \
    && ok "(F) the JSON map header carries \"pr_iters\"" \
    || no "(F) the JSON map header is missing \"pr_iters\" the XML header carries"
grep -q '"pr_converged"' "$TMP/f.json" \
    && no "(F) a converged JSON run must carry no \"pr_converged\" key" \
    || ok "(F) converged JSON run omits \"pr_converged\" (same absence rule as the XML dialect)"
RIPWIRE_TEST_PR_MAXITERS=2 "$BIN" "$CORPUS" --json --no-cache >"$TMP/f2.json" 2>/dev/null
grep -q '"pr_iters":2,"pr_converged":false' "$TMP/f2.json" \
    && ok "(F) the truncated JSON run carries \"pr_converged\":false beside \"pr_iters\":2" \
    || no "(F) the truncated JSON run does not carry \"pr_iters\":2,\"pr_converged\":false"

# ── (G) the hook is not a flag (G5) ───────────────────────────────────────────────────────────────
if "$BIN" --help 2>&1 | grep -q 'RIPWIRE_TEST_PR_MAXITERS'; then
    no "(G) RIPWIRE_TEST_PR_MAXITERS is advertised in --help — it is a gate's arming hook, not a user surface"
else
    ok "(G) RIPWIRE_TEST_PR_MAXITERS appears in no --help text (G5)"
fi

# ── (H) determinism under the hook ────────────────────────────────────────────────────────────────
RIPWIRE_TEST_PR_MAXITERS=2 "$BIN" "$CORPUS" --no-cache >"$TMP/h1.xml" 2>/dev/null
RIPWIRE_TEST_PR_MAXITERS=2 "$BIN" "$CORPUS" --no-cache >"$TMP/h2.xml" 2>/dev/null
cmp -s "$TMP/h1.xml" "$TMP/h2.xml" \
    && ok "(H) two truncated runs are byte-identical (the hook reads once per process)" \
    || no "(H) two truncated runs differ — the hook or the truncated path is not deterministic"

# ── (I) the legend DEFINES what the root emits ────────────────────────────────────────────────────
# legendcoveragecheck's stricter predicate is `name=` in the leading comment block. Asserted here as well
# as there, so an edit that trims the clause reds the gate that OWNS the attribute, not just the ratchet.
for n in pr_iters pr_converged; do
    if head -c 4000 "$TMP/a.xml" | grep -q "$n="; then
        ok "(I) the default map's first screen defines $n="
    else
        no "(I) the default map emits pr_iters= with no $n= definition on the first screen"
    fi
done

[ "$fail" = 0 ] && echo "prconvergecheck: ALL PASS" || echo "prconvergecheck: FAILURES ABOVE"
exit $fail
