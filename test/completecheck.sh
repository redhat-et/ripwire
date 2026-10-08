#!/usr/bin/env bash
# completecheck.sh — T1 COMPLETENESS CLAIMS: the mirror of the floor vocabulary.
#
# The honesty vocabulary discloses UNCERTAINTY (counts_floor=, hits_capped=, shown=/capped=, <more/>).
# This gate pins the mirror: when an answer IS exhaustive, the tool says so machine-readably —
# `complete="1"` on the container element — so a consumer need not re-derive (re-grep, re-scan branches)
# an answer that already listed everything. A FALSE completeness claim is the worst bug this tool can
# ship, so most arms here are MUTATION arms: force each partiality condition and assert the attribute
# VANISHES.
#
# WHO MAY CLAIM (the probe's verdict, pinned by arms 10a/10b):
#   --grep     literal scans (and regex with the prefilter disabled): a full end-to-end read of every
#              indexed file, no collection ceiling reached, no unreadable file, every hit printed.
#              R-H (2026-08-19) adds the FIFTH condition: nothing was SPAN-TIER suppressed. The default
#              --grep serves the tightest non-empty tier, so an answer that held comment/string rows back
#              did not print every hit it found and may not claim exhaustiveness; grep-in=any (the
#              un-tiered listing) is where the claim lives now, and arm 4b is its mutation twin.
#              A prefiltered regex answer NEVER claims (the claim would rest on the analyzer, not on
#              a full read). The claim is complete-WITHIN-THE-INDEX: files the ingest skipped (the
#              skipped verb) were never scanned, and the legend must say so wherever the claim appears.
#   --whereis  every occurrence in every TEXT blob of every scanned ref's full tree printed; no blob
#              oversized/missing/short-read, no cap or page cut the listing.
#   NEVER: the five graph-count verbs (--uses/--callers/--callees/--impact/--edit-check). Their counts
#   are FLOORS of an unmodelable reality (src/graphlegend.h: dynamic dispatch, escaped fn-pointers,
#   unindexed macros contribute no edge) — §H4 retired exactly this absolutism from --uses' legend,
#   and a complete= there would resurrect it. counts_floor= and complete= are mutually exclusive.
#
# Usage:  test/completecheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/completecheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # §18 builds throwaway git repos: no inherited GIT_DIR / GIT_WORK_TREE may steer them
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "completecheck: BIN=$BIN"

CORPUS=test/fixture

# the root START-TAG only — the legend COMMENT also spells complete= (it defines it), so every
# presence/absence assertion must parse the element, never grep the stream.
root_of(){ grep -o "<$1 [^>]*>" | head -1; }

# ── 1) a small literal scan claims: every hit printed, no ceiling, no cap ──────────────────────────────
# L1 (2026-09-19): the CLI default legend is compact; arm 2 reads the FULL legend's complete= definition, so g1
# (and its determinism twin g1b) ask for it.
"$BIN" "$CORPUS" --grep=distance --grep-in=any --legend=full >"$TMP/g1.xml" 2>/dev/null; rc=$?
G1ROOT="$( root_of grep <"$TMP/g1.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$G1ROOT" | grep -q 'complete="1"'; } \
    && ok 'grep: small literal scan carries complete="1" on the root' \
    || { no "grep: literal scan lost complete= (rc=$rc)"; printf '%s\n' "$G1ROOT"; }

# ── 2) the claim never appears without its legend: definition + the within-the-index caveat ────────────
{ grep -q 'complete= ' "$TMP/g1.xml" || grep -q 'complete=(' "$TMP/g1.xml" || grep -q 'COMPLETENESS: complete=' "$TMP/g1.xml"; } \
    && ok 'grep: the legend defines complete= where the claim appears' \
    || no 'grep: complete= claimed but the legend never defines it'
grep -q 'complete-within-the-index' "$TMP/g1.xml" \
    && ok 'grep: the legend scopes the claim to the INDEX (skipped files are outside it)' \
    || no 'grep: the within-the-index caveat is missing from the legend'
grep -q 'skipped' "$TMP/g1.xml" \
    && ok 'grep: the legend names the skipped verb as the list of what is outside the claim' \
    || no 'grep: the legend does not point at the skipped surface'

# ── 3) the ZERO-hit claim — the strongest answer this verb can give ────────────────────────────────────
# With complete= present, hits="0" means "no occurrence exists in any indexed file", the exact claim
# the floor vocabulary forbids WITHOUT the attribute. This is the verify-a-claim terminator.
"$BIN" "$CORPUS" --grep=zqzq_no_such_token_zqzq >"$TMP/g0.xml" 2>/dev/null
G0ROOT="$( root_of grep <"$TMP/g0.xml" )"
{ printf '%s' "$G0ROOT" | grep -q 'hits="0"' && printf '%s' "$G0ROOT" | grep -q 'complete="1"'; } \
    && ok 'grep: an exhaustive zero-hit scan claims complete= (none exists in the index)' \
    || { no 'grep: zero-hit exhaustive scan does not claim'; printf '%s\n' "$G0ROOT"; }

# ── 4) MUTATION: a --limit cap must drop the claim ─────────────────────────────────────────────────────
# H4 (capture-audit 2026-09-04): the root now also states unindexed_hits= (the second, out-of-index
# population), so an unanchored hits=" match returns TWO numbers and every arithmetic below reads garbage.
# Anchored on the leading space, which is what makes it the root's OWN hits= attribute.
HITS="$( printf '%s' "$G1ROOT" | grep -oE ' hits="[0-9]*"' | head -1 | grep -o '[0-9]*' )"
if [ "${HITS:-0}" -ge 2 ]; then
    "$BIN" "$CORPUS" --grep=distance --limit=1 >"$TMP/g2.xml" 2>/dev/null
    G2ROOT="$( root_of grep <"$TMP/g2.xml" )"
    { printf '%s' "$G2ROOT" | grep -q 'capped="1"' && ! printf '%s' "$G2ROOT" | grep -q 'complete='; } \
        && ok 'grep MUTATION: forcing a row cap (limit=1) makes complete= vanish' \
        || { no 'grep MUTATION: complete= survived a row cap'; printf '%s\n' "$G2ROOT"; }
else
    no "grep: fixture yields fewer than 2 'distance' hits ($HITS) — the cap mutation has no room"
fi

# ── 5) MUTATION: an --offset that skips row 0 must drop the claim ──────────────────────────────────────
"$BIN" "$CORPUS" --grep=distance --offset=1 >"$TMP/g3.xml" 2>/dev/null
G3ROOT="$( root_of grep <"$TMP/g3.xml" )"
{ [ -n "$G3ROOT" ] && ! printf '%s' "$G3ROOT" | grep -q 'complete='; } \
    && ok 'grep MUTATION: a page that skips rows (offset=1) never claims' \
    || { no 'grep MUTATION: complete= survived offset=1'; printf '%s\n' "$G3ROOT"; }

# ── 5b) MUTATION (R-H): a SPAN-TIER-FILTERED listing never claims ──────────────────────────────────────
# The default --grep on this corpus holds `distance`'s comment mentions back (geometry.cpp's trailing
# `// edge: perimeter -> distance`), so the printed set is not every hit found — exactly the shape
# complete= must refuse. This is the fifth partiality condition, and its mutation arm.
"$BIN" "$CORPUS" --grep=distance >"$TMP/g3b.xml" 2>/dev/null
G3BROOT="$( root_of grep <"$TMP/g3b.xml" )"
printf '%s' "$G3BROOT" | grep -q 'suppressed_comment="' \
    && ok 'grep: the default answer on this corpus DOES suppress a comment row (the arm is live)' \
    || { no 'grep: nothing was tier-suppressed, so the next assertion proves nothing'; printf '%s\n' "$G3BROOT"; }
printf '%s' "$G3BROOT" | grep -q 'complete="1"' \
    && { no 'grep MUTATION: complete= survived a tier-filtered listing'; printf '%s\n' "$G3BROOT"; } \
    || ok 'grep MUTATION: a tier-filtered listing never claims'

# ── 6) an explicit page that COVERS the whole listing still claims ─────────────────────────────────────
"$BIN" "$CORPUS" --grep=distance --grep-in=any --limit=100000 >"$TMP/g4.xml" 2>/dev/null
G4ROOT="$( root_of grep <"$TMP/g4.xml" )"
printf '%s' "$G4ROOT" | grep -q 'complete="1"' \
    && ok 'grep: an explicit limit wide enough to show everything keeps the claim' \
    || { no 'grep: a whole-listing page lost the claim'; printf '%s\n' "$G4ROOT"; }

# ── 7) regex NEVER claims — in either prefilter mode ───────────────────────────────────────────────────
# Prefiltered, the claim would rest on the analyzer, not on a full read. And no-prefilter may not claim
# what prefiltered does not: the two modes are contractually BYTE-IDENTICAL (test/regexcheck.sh's
# soundness oracle diffs them — the prefilter is a performance switch, never an answer switch), so a
# mode-dependent attribute would break the oracle. complete= is a literal-scan claim only.
"$BIN" "$CORPUS" --regex='dist[a-z]+' >"$TMP/g5.xml" 2>/dev/null
G5ROOT="$( root_of grep <"$TMP/g5.xml" )"
{ [ -n "$G5ROOT" ] && ! printf '%s' "$G5ROOT" | grep -q 'complete='; } \
    && ok 'grep: a prefiltered regex answer never claims (the claim would rest on the analyzer)' \
    || { no 'grep: prefiltered regex claimed complete='; printf '%s\n' "$G5ROOT"; }
"$BIN" "$CORPUS" --regex='dist[a-z]+' --no-prefilter >"$TMP/g6.xml" 2>/dev/null
G6ROOT="$( root_of grep <"$TMP/g6.xml" )"
{ [ -n "$G6ROOT" ] && ! printf '%s' "$G6ROOT" | grep -q 'complete='; } \
    && ok 'grep: a no-prefilter regex answer never claims either (mode parity — the soundness oracle diffs the modes)' \
    || { no 'grep: no-prefilter regex claimed complete= (mode-dependent answer breaks the oracle)'; printf '%s\n' "$G6ROOT"; }

# ── 8) MUTATION: the collection ceiling (hits_capped) must drop the claim ──────────────────────────────
# kGrepCollectionBudget is 4,000,000 raw hits. Build a scratch corpus whose one pattern exceeds it:
# 11 markdown files x 400k occurrences (multiple hits per line — a hit is an occurrence, not a line).
# Each file stays under kDefaultMaxFileBytes (4 MB) or the ingest would SKIP it and grep would scan
# nothing: 4,000 x 9 bytes = 36 KB per line, x100 lines = 3.6 MB per file.
BUDGETDIR="$TMP/budget"; mkdir -p "$BUDGETDIR"
python3 - "$BUDGETDIR" <<'PYEOF'
import sys, os
d = sys.argv[1]
line = ("zqbudget " * 4000).rstrip() + "\n"          # 4,000 occurrences per line
for i in range(11):
    with open(os.path.join(d, f"bulk{i}.md"), "w") as f:
        for _ in range(100):                          # 400,000 per file; 4.4M total
            f.write(line)
PYEOF
"$BIN" "$BUDGETDIR" --grep=zqbudget --no-cache >"$TMP/g7.xml" 2>/dev/null
G7ROOT="$( root_of grep <"$TMP/g7.xml" )"
{ printf '%s' "$G7ROOT" | grep -q 'hits_capped="1"' && ! printf '%s' "$G7ROOT" | grep -q 'complete='; } \
    && ok 'grep MUTATION: reaching the collection ceiling (hits_capped) makes complete= vanish' \
    || { no 'grep MUTATION: complete= beside a floored total, or the ceiling never fired'; printf '%s\n' "$G7ROOT"; }

# ── 9) MUTATION: a file the scan cannot READ must drop the claim ───────────────────────────────────────
UNREADDIR="$TMP/unread"
cp -R "$CORPUS" "$UNREADDIR"
chmod 000 "$UNREADDIR/related.md" 2>/dev/null
if [ -r "$UNREADDIR/related.md" ]; then
    printf '  SKIP  grep MUTATION unreadable file (running as root — chmod 000 is not a barrier)\n'
else
    "$BIN" "$UNREADDIR" --grep=distance --no-cache >"$TMP/g8.xml" 2>/dev/null
    G8ROOT="$( root_of grep <"$TMP/g8.xml" )"
    { [ -n "$G8ROOT" ] && ! printf '%s' "$G8ROOT" | grep -q 'complete='; } \
        && ok 'grep MUTATION: an unreadable indexed file makes complete= vanish' \
        || { no 'grep MUTATION: complete= survived an unreadable file'; printf '%s\n' "$G8ROOT"; }
    chmod 644 "$UNREADDIR/related.md" 2>/dev/null
fi

# ── 10) the graph verbs NEVER claim — counts_floor= and complete= are mutually exclusive ───────────────
"$BIN" "$CORPUS" --uses=distance >"$TMP/u1.xml" 2>/dev/null
U1ROOT="$( root_of uses <"$TMP/u1.xml" )"
{ printf '%s' "$U1ROOT" | grep -q 'counts_floor="1"' && ! printf '%s' "$U1ROOT" | grep -q 'complete='; } \
    && ok 'uses: still a floor (counts_floor=), never complete= — the §H4 absolutism stays retired' \
    || { no 'uses: complete= appeared beside a floored count, or the floor marker is gone'; printf '%s\n' "$U1ROOT"; }
"$BIN" "$CORPUS" --callers=distance >"$TMP/c1.xml" 2>/dev/null
C1ROOT="$( root_of callers <"$TMP/c1.xml" )"
{ printf '%s' "$C1ROOT" | grep -q 'counts_floor="1"' && ! printf '%s' "$C1ROOT" | grep -q 'complete='; } \
    && ok 'callers: still a floor (counts_floor=), never complete=' \
    || { no 'callers: complete= appeared beside a floored count, or the floor marker is gone'; printf '%s\n' "$C1ROOT"; }

# ── 11) determinism + well-formedness of a claiming document ───────────────────────────────────────────
"$BIN" "$CORPUS" --grep=distance --grep-in=any --legend=full >"$TMP/g1b.xml" 2>/dev/null
diff -q "$TMP/g1.xml" "$TMP/g1b.xml" >/dev/null \
    && ok 'grep: a claiming answer is byte-deterministic across runs' \
    || no 'grep: claiming answer differs across two runs'
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/g1.xml" 2>/dev/null; then ok 'grep: claiming document is well-formed XML'; else no 'grep: claiming document is malformed'; fi
else
    printf '  SKIP  xmllint (not installed)\n'
fi

# ── 12) the MCP grep twin claims and un-claims with the CLI ────────────────────────────────────────────
mcp_call(){ printf '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":"%s","pattern":"distance"%s}}}\n' "$1" "$2"; }
mcp_call "$CORPUS" ',"in":"any"' | "$BIN" --mcp >"$TMP/m1.json" 2>/dev/null
mcp_call "$CORPUS" ',"limit":1'  | "$BIN" --mcp >"$TMP/m2.json" 2>/dev/null
# inside the JSON-RPC wrapper the payload's quotes are ESCAPED: \"complete\":true
grep -q '\\"complete\\":true' "$TMP/m1.json" \
    && ok 'mcp grep: un-paged literal answer carries complete true' \
    || { no 'mcp grep: complete missing from an exhaustive answer'; grep -o '\\"hits_capped\\":[a-z]*' "$TMP/m1.json" | head -2; }
# the mutation only has power if the same file DOES carry the escaped hits_capped key (wrapper sanity)
grep -q '\\"hits_capped\\":' "$TMP/m2.json" && ! grep -q '\\"complete\\":true' "$TMP/m2.json" \
    && ok 'mcp grep MUTATION: limit=1 makes the claim vanish' \
    || no 'mcp grep MUTATION: complete true survived a row cap (or the wrapper shape changed)'

# ── whereis: the cross-branch claim ────────────────────────────────────────────────────────────────────
if command -v git >/dev/null 2>&1; then
    R="$TMP/repo"; mkdir -p "$R"
    export GIT_AUTHOR_NAME=ripwire GIT_AUTHOR_EMAIL=ripwire@example.invalid
    export GIT_COMMITTER_NAME=ripwire GIT_COMMITTER_EMAIL=ripwire@example.invalid
    export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
    g(){ git -C "$R" "$@" >/dev/null 2>&1; }
    g init -q -b main
    g config commit.gpgsign false
    printf 'int zqWhereToken( int x )\n{\n    return x + 1;\n}\n' > "$R/alpha.cpp"
    g add alpha.cpp; g commit -qm base
    g checkout -qb side
    printf '// zqWhereToken is used here too\nint other() { return zqWhereToken( 2 ); }\n' > "$R/beta.cpp"
    g add beta.cpp; g commit -qm side
    g checkout -q main

    # ── 13) an uncut tree scan claims ──────────────────────────────────────────────────────────────────
    "$BIN" "$R" --whereis=zqWhereToken --no-cache --legend=full >"$TMP/w1.xml" 2>/dev/null; rc=$?
    W1ROOT="$( root_of whereis <"$TMP/w1.xml" )"
    { [ $rc -eq 0 ] && printf '%s' "$W1ROOT" | grep -q 'complete="1"'; } \
        && ok 'whereis: an uncut full-tree scan carries complete="1"' \
        || { no "whereis: exhaustive scan lost complete= (rc=$rc)"; printf '%s\n' "$W1ROOT"; }
    grep -q 'complete=' "$TMP/w1.xml" && grep -q 'TEXT blob' "$TMP/w1.xml" \
        && ok 'whereis: the legend defines complete= and scopes it to text blobs' \
        || no 'whereis: the claim appears without its legend definition'

    # ── 14) MUTATION: a --limit cap must drop the claim ────────────────────────────────────────────────
    WHITS="$( printf '%s' "$W1ROOT" | grep -o 'hits="[0-9]*"' | grep -o '[0-9]*' )"
    if [ "${WHITS:-0}" -ge 2 ]; then
        "$BIN" "$R" --whereis=zqWhereToken --limit=1 --no-cache >"$TMP/w2.xml" 2>/dev/null
        W2ROOT="$( root_of whereis <"$TMP/w2.xml" )"
        { [ -n "$W2ROOT" ] && ! printf '%s' "$W2ROOT" | grep -q 'complete='; } \
            && ok 'whereis MUTATION: forcing a row cap (limit=1) makes complete= vanish' \
            || { no 'whereis MUTATION: complete= survived a row cap'; printf '%s\n' "$W2ROOT"; }
    else
        no "whereis: fixture yields fewer than 2 hits ($WHITS) — the cap mutation has no room"
    fi

    # ── 14b) MUTATION: a ref DROPPED at enumeration must drop the claim — in every build flavour ───────────
    # enumerateRefs skips a for-each-ref row whose tip is not an object name. It used to do so with a one-argument
    # DISCLOSE (a debug trace, nothing at all in Release) and no counter, so --whereis still claimed complete="1"
    # over a sweep that never searched that ref. The DISCLOSE( sink, why ) now counts it and the claim is withheld.
    # The fault is planted with a PATH shim around the real git that appends one malformed row to for-each-ref's
    # output — a seam that reaches the Release binary too, unlike the non-NDEBUG fault switches. Control: the same
    # shim passing everything through keeps the claim, so the arm cannot pass by breaking git.
    REALGIT="$( command -v git )"; SHIM="$TMP/gitshim"; mkdir -p "$SHIM"
    cat >"$SHIM/git" <<SHEOF
#!/usr/bin/env bash
case " \$* " in
    *" for-each-ref "*) "$REALGIT" "\$@"; rc=\$?; [ -n "\${RW_SHIM_MANGLE:-}" ] && printf 'zz-dropped|not-an-object-name|2026-01-01\n'; exit \$rc ;;
    *) exec "$REALGIT" "\$@" ;;
esac
SHEOF
    chmod +x "$SHIM/git"
    PATH="$SHIM:$PATH" "$BIN" "$R" --whereis=zqWhereToken --no-cache >"$TMP/w14c.xml" 2>/dev/null
    PATH="$SHIM:$PATH" RW_SHIM_MANGLE=1 "$BIN" "$R" --whereis=zqWhereToken --no-cache >"$TMP/w14m.xml" 2>/dev/null
    W14C="$( root_of whereis <"$TMP/w14c.xml" )"; W14M="$( root_of whereis <"$TMP/w14m.xml" )"
    if printf '%s' "$W14C" | grep -q 'complete="1"'; then
        ok 'whereis (14b control): the pass-through git shim keeps complete="1"'
        { [ -n "$W14M" ] && ! printf '%s' "$W14M" | grep -q 'complete='; } \
            && ok 'whereis MUTATION: a ref dropped at enumeration (tip not an object name) makes complete= vanish' \
            || { no 'whereis MUTATION: complete= survived a ref the sweep never searched'; printf '%s\n' "$W14M"; }
    else
        no "whereis (14b control): the pass-through shim lost complete= — the shim is broken and the mutation is void: $W14C"
    fi

    # ── 14c) MUTATION: the same dropped ref must be DISCLOSED by --stray-content and its --plan ──────────────
    # --stray-content called enumerateRefs with no sink, so the ref dropped above vanished from refs= and every
    # bucket with nothing on the root saying a branch was skipped (CodeRabbit on #295). The sweep now carries the
    # count to the root as refs_dropped=, on --plan as well. Same shim, same control discipline as 14b.
    for V in "--stray-content" "--stray-content --plan"; do
        TAG="$( [ "$V" = "--stray-content" ] && echo stray-content || echo landing-plan )"
        # shellcheck disable=SC2086
        PATH="$SHIM:$PATH" "$BIN" "$R" $V --no-cache >"$TMP/s14c.xml" 2>/dev/null; rcC=$?
        # shellcheck disable=SC2086
        PATH="$SHIM:$PATH" RW_SHIM_MANGLE=1 "$BIN" "$R" $V --no-cache >"$TMP/s14m.xml" 2>/dev/null; rcM=$?
        S14C="$( root_of "$TAG" <"$TMP/s14c.xml" )"; S14M="$( root_of "$TAG" <"$TMP/s14m.xml" )"
        if [ "$rcC" = 0 ] && [ -n "$S14C" ] && ! printf '%s' "$S14C" | grep -q 'refs_dropped='; then
            ok "$V (14c control): the pass-through shim answers (exit 0) with no refs_dropped="
            { [ "$rcM" = 0 ] && printf '%s' "$S14M" | grep -q 'refs_dropped="1"'; } \
                && ok "$V MUTATION: a ref dropped at enumeration is disclosed on the root (refs_dropped=\"1\")" \
                || { no "$V MUTATION: a ref the sweep never read left no refs_dropped= on <$TAG> (exit $rcM)"; printf '%s\n' "$S14M"; }
        else
            no "$V (14c control): the pass-through run did not answer cleanly (exit $rcC) — the mutation is void: $S14C"
        fi
    done

    # ── 15) MUTATION: an OVERSIZED text blob (silently unscannable) must drop the claim ────────────────
    # kMaxBlobBytes is 2 MB; a symbol inside a larger blob is invisible to the scan, so the scan may
    # not claim exhaustiveness over a tree that contains one.
    g checkout -qb bigblob
    python3 - "$R/huge.txt" <<'PYEOF'
import sys
with open(sys.argv[1], "w") as f:
    f.write("filler line of ordinary text\n" * 80000)     # ~2.3 MB
    f.write("zqWhereToken hides in an oversized blob\n")
PYEOF
    g add huge.txt; g commit -qm bigblob
    g checkout -q main
    "$BIN" "$R" --whereis=zqWhereToken --no-cache >"$TMP/w3.xml" 2>/dev/null
    W3ROOT="$( root_of whereis <"$TMP/w3.xml" )"
    { [ -n "$W3ROOT" ] && ! printf '%s' "$W3ROOT" | grep -q 'complete='; } \
        && ok 'whereis MUTATION: an oversized blob in any scanned tree makes complete= vanish' \
        || { no 'whereis MUTATION: complete= survived an oversized (unscanned) blob'; printf '%s\n' "$W3ROOT"; }

    # ── 16) determinism + well-formedness of the claiming whereis ──────────────────────────────────────
    # Two FRESH runs at the same repo state (w1 predates the bigblob branch, so it is not comparable).
    "$BIN" "$R" --whereis=zqWhereToken --no-cache >"$TMP/w4a.xml" 2>/dev/null
    "$BIN" "$R" --whereis=zqWhereToken --no-cache >"$TMP/w4b.xml" 2>/dev/null
    diff -q "$TMP/w4a.xml" "$TMP/w4b.xml" >/dev/null \
        && ok 'whereis: a claiming answer is byte-deterministic across runs' \
        || no 'whereis: claiming answer differs across two runs'
    if command -v xmllint >/dev/null 2>&1; then
        if xmllint --noout "$TMP/w1.xml" 2>/dev/null; then ok 'whereis: claiming document is well-formed XML'; else no 'whereis: claiming document is malformed'; fi
    fi
else
    printf '  SKIP  whereis arms (git unavailable)\n'
fi

# ── 17) an indexed file the scan cannot READ floors grep's count — in every build flavour ──────────────────
# Indexed from a warm cache, then made unreadable: the scan skips it. complete= was already withheld, but hits=
# carried no floor and read as a total. The root now names the shortfall (unread_files=) and carries
# counts_floor="1", with the SHORT SCAN clause defining both — and the compact dialect defines them too.
UG="$TMP/unreadgrep"; mkdir -p "$UG/tree" "$UG/xdg"
printf 'int zqUnreadTok( void ) { return 1; }\n' >"$UG/tree/a.c"
printf 'int zqOther( void ) { return zqUnreadTok(); }\n' >"$UG/tree/b.c"
XDG_CACHE_HOME="$UG/xdg" "$BIN" "$UG/tree" --grep=zqUnreadTok >"$UG/warm.xml" 2>/dev/null
if grep -o '<grep [^>]*>' "$UG/warm.xml" | grep -q ' hits="2".* complete="1"'; then
    ok 'grep (17 control): both files readable → hits="2" complete="1", no floor'
    chmod 000 "$UG/tree/b.c"
    if cat "$UG/tree/b.c" >/dev/null 2>&1; then
        printf '  SKIP  17: chmod 000 does not stop this user reading the file (root?) — the arm cannot plant its fault\n'
    else
        # L1: the CLI default is compact; the FULL-legend arm below asks for that posture by name (the compact arm has its own run)
        XDG_CACHE_HOME="$UG/xdg" "$BIN" "$UG/tree" --grep=zqUnreadTok --legend=full >"$UG/cold.xml" 2>/dev/null
        XDG_CACHE_HOME="$UG/xdg" "$BIN" "$UG/tree" --grep=zqUnreadTok --legend=compact >"$UG/coldc.xml" 2>/dev/null
        G17="$( grep -o '<grep [^>]*>' "$UG/cold.xml" )"
        { printf '%s' "$G17" | grep -q ' unread_files="1"' && printf '%s' "$G17" | grep -q ' counts_floor="1"' \
          && ! printf '%s' "$G17" | grep -q 'complete='; } \
            && ok 'grep: an unreadable indexed file is named on the root (unread_files="1") and floors hits= (counts_floor="1")' \
            || no "grep: an unreadable indexed file left hits= reading as a total: $G17"
        grep -q 'SHORT SCAN: unread_files= ' "$UG/cold.xml" \
            && ok 'grep: unread_files= is defined in the full legend' || no 'grep: unread_files= rides with no full-legend definition'
        grep -q 'unread_files=N: ' "$UG/coldc.xml" \
            && ok 'grep: unread_files= is defined in the compact legend' || no 'grep: unread_files= rides with no compact-legend definition'
        command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$UG/cold.xml" 2>/dev/null \
            && ok 'grep: the short-scan document is well-formed' || no 'grep: the short-scan document fails xmllint'; }
    fi
    chmod 644 "$UG/tree/b.c"
else
    no "grep (17 control): the readable fixture did not claim complete over 2 hits — the arm is void: $( grep -o '<grep [^>]*>' "$UG/warm.xml" )"
fi

# ── 18) whereis on a DIRTY checkout: the working tree is read, or the claim is withheld ───────────────
# The comparison-table repros (2026-10-01): --whereis scanned committed trees only, so on a dirty checkout it
# answered hits="0" complete="1" for a function the edit had just added, and listed a renamed or deleted
# function at its old HEAD lines, also complete="1", with a bare at= (no +dirty). --callers on the same tree
# saw the edit. Now every path under the root that differs from HEAD (modified, staged, deleted or untracked)
# is read from disk: its rows say ref="worktree" and replace HEAD's rows for that path, at= gains +dirty and
# the root says worktree="read". A changed path that cannot be read keeps its HEAD rows, says
# worktree="partial" and withholds complete=. A clean checkout answers byte-for-byte as before.
WT="$TMP/wtrepo"; mkdir -p "$WT/src"
cat >"$WT/src/main.c" <<'EOF'
int zqKeep( int x ) { return x + 1; }
int zqOldName( int x ) { return x * 2; }
int zqDoomed( void ) { return 3; }
int zqUser( void ) { return zqKeep( 1 ) + zqOldName( 2 ) + zqDoomed(); }
EOF
cat >"$WT/src/other.c" <<'EOF'
int zqOther( void ) { return 4; }
EOF
cat >"$WT/src/gone.c" <<'EOF'
int zqGone( void ) { return 5; }
EOF
( cd "$WT" && git init -q -b main . && git add -A \
    && git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false commit -qm seed ) >/dev/null 2>&1
WSHA="$( git -C "$WT" rev-parse --short=9 HEAD 2>/dev/null )"
wroot(){ grep -o '<whereis [^>]*>' | head -1; }
wwhere(){ "$BIN" "$WT" --whereis="$1" --no-cache "${@:2}" 2>/dev/null; }

# 18a) control: the clean checkout claims, with a bare at= and no worktree= — the pre-fix shape, unchanged
W0="$( wwhere zqOldName | wroot )"
{ printf '%s' "$W0" | grep -q " at=\"$WSHA\" complete=\"1\"" && ! printf '%s' "$W0" | grep -q 'worktree='; } \
    && ok 'whereis (18a control): a clean checkout claims complete="1" with a bare at= and no worktree=' \
    || no "whereis (18a control): the clean shape changed: $W0"

# the edit: add a function, rename one, delete one, delete a whole tracked file, add an untracked file
cat >"$WT/src/main.c" <<'EOF'
int zqKeep( int x ) { return x + 1; }
int zqNewName( int x ) { return x * 2; }
int zqFresh( void ) { return 6; }
int zqUser( void ) { return zqKeep( 1 ) + zqNewName( 2 ) + zqFresh(); }
EOF
rm -f "$WT/src/gone.c"
printf 'int zqUntracked( void ) { return 7; }\n' >"$WT/src/new.c"

# 18b) a function the edit ADDED is found, as a worktree definition, and the stamp says the tree is dirty
W1="$( wwhere zqFresh )"; W1R="$( printf '%s' "$W1" | wroot )"
{ printf '%s' "$W1" | grep -q '<hit ref="worktree" [^>]*p="src/main.c" l="3" kind="def"' \
  && printf '%s' "$W1R" | grep -q " at=\"$WSHA+dirty\" worktree=\"read\"" && printf '%s' "$W1R" | grep -q ' on-head="1"'; } \
    && ok 'whereis (18b): a function added in the working tree is found (ref="worktree" kind="def"), at= says +dirty, worktree="read"' \
    || { no 'whereis (18b): a function the working tree added is still invisible (the stale-and-silent answer)'; printf '%s\n' "$W1R"; }

# 18c) a RENAMED-away name no longer lists its old HEAD line; the new name is found
W2R="$( wwhere zqOldName | wroot )"; W2="$( wwhere zqOldName )"
{ printf '%s' "$W2R" | grep -q ' hits="0"' && ! printf '%s' "$W2" | grep -q '<hit ref="HEAD"'; } \
    && ok 'whereis (18c): a name the working tree renamed away lists no stale HEAD row (hits="0")' \
    || { no 'whereis (18c): the renamed-away name still lists its old HEAD lines'; printf '%s\n' "$W2R"; }
wwhere zqNewName | grep -q '<hit ref="worktree" [^>]*p="src/main.c" l="2" kind="def"' \
    && ok 'whereis (18c): the rename target is found in the working tree' \
    || no 'whereis (18c): the rename target is not found'

# 18d) a DELETED definition, and a whole deleted tracked file, drop out
for s in zqDoomed zqGone; do
    W3R="$( wwhere "$s" | wroot )"
    printf '%s' "$W3R" | grep -q ' hits="0"' \
        && ok "whereis (18d): $s, deleted in the working tree, has no rows" \
        || { no "whereis (18d): $s, deleted in the working tree, still has rows"; printf '%s\n' "$W3R"; }
done

# 18e) an UNTRACKED file is part of the checkout; an untouched path keeps its HEAD row
wwhere zqUntracked | grep -q '<hit ref="worktree" [^>]*p="src/new.c" l="1" kind="def"' \
    && ok 'whereis (18e): a definition in an untracked file is found' \
    || no 'whereis (18e): a definition in an untracked file is invisible'
wwhere zqOther | grep -q '<hit ref="HEAD" [^>]*p="src/other.c" l="1" kind="def"' \
    && ok 'whereis (18e): a path the edit did not touch still answers from HEAD (ref="HEAD")' \
    || no 'whereis (18e): an untouched path lost its HEAD row'

# 18f) the INVARIANT: no complete="1" answer carries a HEAD row for a path that differs from HEAD
CHANGED="$( git -C "$WT" diff --name-only HEAD; git -C "$WT" ls-files --others --exclude-standard )"
bad=0
# lean-answers lane: the invariant reads BOTH listings — the default (def rows) and the whole list (every row), so the
# default's shorter row set never makes it pass vacuously.
for s in zqKeep zqFresh zqOldName zqNewName zqDoomed zqGone zqUntracked zqOther zqUser; do
  for lst in defs all; do
    out="$( wwhere "$s" --whereis-listing=$lst )"
    printf '%s' "$out" | wroot | grep -q 'complete="1"' || continue
    for p in $CHANGED; do
        printf '%s' "$out" | grep -q "<hit ref=\"HEAD\" [^>]*p=\"$p\"" && { bad=1; no "whereis (18f): $s ($lst) claims complete=\"1\" beside a stale HEAD row for changed $p"; }
    done
  done
done
[ $bad -eq 0 ] && ok 'whereis (18f): no complete="1" answer carries a HEAD row for a path the working tree changed'

# 18g) the twin: MCP whereis reads the same working tree, row for row
if command -v python3 >/dev/null 2>&1; then
    M1="$( python3 - "$BIN" "$WT" <<'PY'
import json, subprocess, sys
msgs = [ { "jsonrpc": "2.0", "id": 1, "method": "initialize" },
         { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": "whereis", "arguments": { "path": sys.argv[2], "symbol": "zqFresh" } } } ]
p = subprocess.run( [ sys.argv[1], "--mcp" ], input = "".join( json.dumps( m ) + "\n" for m in msgs ), capture_output = True, text = True, timeout = 300 )
d = json.loads( [ l for l in p.stdout.splitlines() if l.strip() ][ -1 ] )
print( d.get( "result", {} ).get( "content", [ {} ] )[ 0 ].get( "text", "" ) )
PY
)"
    C1H="$( printf '%s' "$W1" | grep -o '<hit [^>]*/>' )"; M1H="$( printf '%s' "$M1" | grep -o '<hit [^>]*/>' )"
    { [ -n "$C1H" ] && [ "$C1H" = "$M1H" ] && printf '%s' "$M1" | wroot | grep -q " at=\"$WSHA+dirty\" worktree=\"read\""; } \
        && ok 'whereis (18g): the MCP twin serves the same worktree rows, +dirty stamp and worktree="read"' \
        || { no 'whereis (18g): the MCP twin disagrees with the CLI on a dirty checkout'; printf '%s\n' "$M1" | wroot; }
fi

# 18h) the legend defines worktree= wherever it rides, in both dialects
grep -q 'worktree=read|partial|unlisted' <<<"$W1" \
    && ok 'whereis (18h): the compact legend defines worktree=' || no 'whereis (18h): worktree= rides with no compact definition'
wwhere zqFresh --legend=full | grep -q 'WORKTREE: worktree=' \
    && ok 'whereis (18h): the full legend defines worktree=' || no 'whereis (18h): worktree= rides with no full-legend definition'

# 18i) MUTATION: a changed path that cannot be READ keeps its HEAD rows, says partial, and never claims
chmod 000 "$WT/src/main.c"
if cat "$WT/src/main.c" >/dev/null 2>&1; then
    printf '  SKIP  18i: chmod 000 does not stop this user reading the file (root?) — the arm cannot plant its fault\n'
else
    W4R="$( wwhere zqKeep | wroot )"
    { printf '%s' "$W4R" | grep -q ' worktree="partial"' && ! printf '%s' "$W4R" | grep -q 'complete='; } \
        && ok 'whereis (18i): an unreadable changed path says worktree="partial" and withholds complete=' \
        || { no 'whereis (18i): an unreadable changed path still claims a complete answer'; printf '%s\n' "$W4R"; }
fi
chmod 644 "$WT/src/main.c"

# 18j) "none found" is an ANSWER on whereis (rc 0, a document) and stays the documented REFUSAL on callers
# (README §6.2: 1 = refused; docs/COMMANDS.md --callers "Unknown-symbol REFUSAL shape (exit 1)").
"$BIN" "$WT" --whereis=zqDoomed --no-cache >"$TMP/wt0.xml" 2>/dev/null; rc=$?
{ [ $rc -eq 0 ] && wroot <"$TMP/wt0.xml" | grep -q ' hits="0"'; } \
    && ok 'whereis (18j): a name the working tree deleted answers rc 0 with a hits="0" document' \
    || no "whereis (18j): the deleted name did not answer as a document (rc=$rc)"
"$BIN" "$WT" --callers=zqDoomed --no-cache >"$TMP/wt0c.xml" 2>"$TMP/wt0c.err"; rc=$?
{ [ $rc -eq 1 ] && grep -q 'not found' "$TMP/wt0c.err"; } \
    && ok 'callers (18j): the same name is still the documented refusal (exit 1, stderr names it)' \
    || no "callers (18j): the unknown-symbol contract moved (rc=$rc)"

# 18l) ...and the refusal now ALSO answers on stdout (fix list #2): the verb's own root, the selector echoed, found="0",
# the legend defining it — so an agent reading stdout gets an answer, not nothing. Exit 1 is unchanged.
for v in callers callees uses impact; do
    "$BIN" "$WT" --$v=zqDoomed --no-cache >"$TMP/nf.xml" 2>/dev/null; rc=$?
    { [ $rc -eq 1 ] && grep -q "<$v [^>]*of=\"zqDoomed\" found=\"0\"" "$TMP/nf.xml" && grep -q 'found=0: ' "$TMP/nf.xml" \
      && { ! command -v xmllint >/dev/null 2>&1 || xmllint --noout "$TMP/nf.xml" 2>/dev/null; }; } \
        && ok "$v (18l): not found answers on stdout (<$v of= found=\"0\">, legend-defined, well-formed) and still exits 1" \
        || { no "$v (18l): not found printed no answer document (rc=$rc)"; head -c 300 "$TMP/nf.xml"; echo; }
done
"$BIN" "$WT" --path=zqUser,zqDoomed --no-cache >"$TMP/nf.xml" 2>/dev/null; rc=$?
{ [ $rc -eq 1 ] && grep -q '<path [^>]*from="zqUser" to="zqDoomed" found="0" missing="to"' "$TMP/nf.xml"; } \
    && ok 'path (18l): an endpoint that matched nothing answers <path from= to= found="0" missing="to"> and exits 1' \
    || { no "path (18l): no answer document (rc=$rc)"; head -c 300 "$TMP/nf.xml"; echo; }
"$BIN" "$WT" --callers=zqDoomed --json --no-cache 2>/dev/null \
    | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d.get("of")=="zqDoomed" and d.get("found")==0 else 1)' 2>/dev/null \
    && ok 'callers (18l): under --json the not-found answer is one JSON object with found:0' \
    || no 'callers (18l): --json not-found printed no JSON answer'

# 18m) the near-miss ranks a WORKING-TREE RENAME first: zqOldName became zqNewName in the working tree, so the answer
# offers zqNewName (near_renamed="1"), and stderr names the rename before any spelling near-miss.
"$BIN" "$WT" --callers=zqOldName --no-cache >"$TMP/rn.xml" 2>"$TMP/rn.err"; rc=$?
{ [ $rc -eq 1 ] && grep -q 'near="zqNewName" near_renamed="1"' "$TMP/rn.xml" \
  && grep -q "symbol not found: zqOldName (renamed in the working tree: did you mean 'zqNewName'?)" "$TMP/rn.err"; } \
    && ok 'callers (18m): a name the working tree renamed offers the new name first (near_renamed="1", stderr says renamed)' \
    || { no 'callers (18m): the rename is not offered first'; cat "$TMP/rn.err"; head -c 400 "$TMP/rn.xml"; echo; }
"$BIN" "$WT" --callers=zqNoSuchNameAtAll --no-cache >"$TMP/rn0.xml" 2>/dev/null
grep -q 'near_renamed' "$TMP/rn0.xml" \
    && no 'callers (18m): a name no file ever had was offered as a rename' \
    || ok 'callers (18m): a name no file ever had gets no rename claim'

# 18n) fix list #9: a TEST-LOCAL definition (a test file's own `def helper`, hono-05's `const serveStatic =`) is
# ordered after the production definition when both exist, and marked test_local="1"; nothing is dropped. An answer
# with only one kind keeps its bytes.
TL="$TMP/testlocal"; mkdir -p "$TL/pkg" "$TL/tests"
printf 'def helper( x ):\n    return x\n' >"$TL/pkg/lib.py"
printf 'from pkg.lib import helper as real\n\ndef helper( x ):\n    return real( x )\n\ndef only_in_test():\n    return helper( 1 )\n' >"$TL/tests/test_lib.py"
( cd "$TL" && git init -q -b main . && git add -A \
    && git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false commit -qm seed ) >/dev/null 2>&1
# lean-answers lane: the "every hit printed" half reads the WHOLE list, so it asks for it (--whereis-listing=all, the
# pre-listing answer); the twin below holds the same facts on the default listing, where the refs are counted.
TLO="$( "$BIN" "$TL" --whereis=helper --no-cache --whereis-listing=all 2>/dev/null )"
FIRSTDEF="$( printf '%s' "$TLO" | grep -o '<hit [^>]*kind="def"[^>]*>' | head -1 )"
TESTDEF="$( printf '%s' "$TLO" | grep -o '<hit [^>]*p="tests/test_lib.py" l="3" kind="def"[^>]*>' )"
{ printf '%s' "$FIRSTDEF" | grep -q 'p="pkg/lib.py" l="1" kind="def" t=' && printf '%s' "$TESTDEF" | grep -q 'kind="def" test_local="1"' \
  && [ "$( printf '%s' "$TLO" | sed 's/<!--.*-->//' | grep -o '<hit ' | wc -l | tr -d ' ' )" = "$( printf '%s' "$TLO" | grep -o ' hits="[0-9]*"' | grep -o '[0-9]*' )" ]; } \
    && ok 'whereis (18n): the production def leads; the test-local def is marked test_local="1" and kept (every hit printed)' \
    || { no 'whereis (18n): a test-local definition is not demoted beside the production one'; printf '%s\n' "$TLO" | sed 's/<!--.*-->//' | head -c 900; echo; }
# TWIN on the default listing (lean-answers lane): the same order and mark on the def rows, and every hit accounted for —
# printed (the def rows) or counted (<refs count=>), the two summing to hits=.
TLD="$( "$BIN" "$TL" --whereis=helper --no-cache 2>/dev/null )"
{ printf '%s' "$TLD" | grep -o '<hit [^>]*kind="def"[^>]*>' | head -1 | grep -q 'p="pkg/lib.py" l="1" kind="def" t=' \
  && printf '%s' "$TLD" | grep -o '<hit [^>]*p="tests/test_lib.py" l="3" kind="def"[^>]*>' | grep -q 'kind="def" test_local="1"' \
  && [ "$(( $( printf '%s' "$TLD" | sed 's/<!--.*-->//' | grep -o '<hit ' | wc -l | tr -d ' ' ) + $( printf '%s' "$TLD" | grep -oE '<refs count="[0-9]+"' | grep -oE '[0-9]+' || echo 0 ) ))" \
       = "$( printf '%s' "$TLD" | grep -o ' hits="[0-9]*"' | grep -o '[0-9]*' )" ]; } \
    && ok 'whereis (18n twin, default listing): the production def leads, the test-local def is marked; printed + refs count= = hits=' \
    || { no 'whereis (18n twin): the default listing lost the test-local order or an unaccounted hit'; printf '%s\n' "$TLD" | sed 's/<!--.*-->//' | head -c 900; echo; }
printf '%s' "$TLO" | grep -q 'TEST-LOCAL: \|test_local=1: ' \
    && ok 'whereis (18n): test_local= is defined in the legend where it rides' || no 'whereis (18n): test_local= rides undefined'
"$BIN" "$TL" --whereis=only_in_test --no-cache 2>/dev/null | grep -q 'test_local' \
    && no 'whereis (18n): an answer with only test definitions grew test_local=' \
    || ok 'whereis (18n): an answer with one kind of definition carries no test_local= (bytes unchanged)'

# 18n, the ORDER half: a test-scope def in a source file whose path sorts first (src/a.rs) used to lead the answer;
# the production def (src/z.rs) now does.
TR="$TMP/testscope"; mkdir -p "$TR/src"
printf '#[cfg(test)]\nmod tests {\n    fn helper() -> i32 { 2 }\n    #[test]\n    fn t() { assert_eq!(helper(), 2); }\n}\n' >"$TR/src/a.rs"
printf 'pub fn helper() -> i32 { 1 }\n' >"$TR/src/z.rs"
( cd "$TR" && git init -q -b main . && git add -A \
    && git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false commit -qm seed ) >/dev/null 2>&1
TRF="$( "$BIN" "$TR" --whereis=helper --no-cache 2>/dev/null | sed 's/<!--.*-->//' | grep -o '<hit [^>]*kind="def"[^>]*>' )"
{ printf '%s\n' "$TRF" | head -1 | grep -q 'p="src/z.rs" l="1" kind="def" t=' && printf '%s\n' "$TRF" | sed -n 2p | grep -q 'p="src/a.rs" l="3" kind="def" test_local="1"'; } \
    && ok 'whereis (18n): a test-scope def in a source file sorts after the production def (test_local="1")' \
    || { no 'whereis (18n): a test-scope def still leads the production def'; printf '%s\n' "$TRF"; }

# 18o) the MCP twins keep their -32602 refusal and carry the same answer document in error.data.answer
if command -v python3 >/dev/null 2>&1; then
    python3 - "$BIN" "$WT" <<'PY' && ok 'MCP (18o): all five twins (find_referencing_symbols, find_symbol, uses, impact, path_between) refuse -32602 AND carry the answer; batch names the rename' \
                               || no 'MCP (18o): the twins do not carry the not-found answer'
import json, subprocess, sys
BIN, WT = sys.argv[1], sys.argv[2]
calls = [ ( "find_referencing_symbols", { "path": WT, "symbol": "zqOldName" }, '"found":0', '"near":"zqNewName"' ),
          ( "find_symbol", { "path": WT, "symbol": "zqOldName" }, '"found":0', '"near":"zqNewName"' ),
          ( "uses", { "path": WT, "symbol": "zqOldName" }, 'found="0"', 'near="zqNewName" near_renamed="1"' ),
          ( "impact", { "path": WT, "symbol": "zqDoomed" }, 'found="0"', 'of="zqDoomed"' ),
          ( "path_between", { "path": WT, "from": "zqUser", "to": "zqDoomed" }, 'found="0"', 'missing="to"' ),
          ( "path_between", { "path": WT, "from": "zqNope1", "to": "zqNope2" }, 'found="0"', 'missing="both"' ) ]
msgs = [ { "jsonrpc": "2.0", "id": 1, "method": "initialize" } ] + [
    { "jsonrpc": "2.0", "id": 10 + i, "method": "tools/call", "params": { "name": n, "arguments": a } } for i, ( n, a, _, _ ) in enumerate( calls ) ]
p = subprocess.run( [ BIN, "--mcp" ], input = "".join( json.dumps( m ) + "\n" for m in msgs ), capture_output = True, text = True, timeout = 300 )
byId = {}
for line in p.stdout.splitlines():
    try:
        d = json.loads( line )
    except ValueError:
        continue
    byId[ d.get( "id" ) ] = d
bad = 0
for i, ( n, a, want1, want2 ) in enumerate( calls ):
    d = byId.get( 10 + i, {} )
    e = d.get( "error", {} )
    ans = e.get( "data", {} ).get( "answer", "" )
    if e.get( "code" ) != -32602 or want1 not in ans or want2 not in ans:
        print( "  MCP %s: %s" % ( n, json.dumps( d )[ :300 ] ) ); bad = 1
for k in ( 10, 11, 12 ):
    rn = byId.get( k, {} ).get( "error", {} ).get( "message", "" )
    if "renamed in the working tree: did you mean 'zqNewName'" not in rn:
        print( "  MCP rename clause missing (id %d): %s" % ( k, rn ) ); bad = 1
# the batch arm (review M6): each answering sub-verb's err= names the rename first
bq = [ { "verb": v, "symbol": "zqOldName" } for v in ( "callers", "callees", "impact", "uses" ) ]
pb = subprocess.run( [ BIN, "--mcp" ], input = json.dumps( msgs[ 0 ] ) + "\n" + json.dumps(
    { "jsonrpc": "2.0", "id": 99, "method": "tools/call", "params": { "name": "batch", "arguments": { "path": WT, "queries": bq } } } ) + "\n",
    capture_output = True, text = True, timeout = 300 )
bt = ""
for line in pb.stdout.splitlines():
    try:
        d = json.loads( line )
    except ValueError:
        continue
    if d.get( "id" ) == 99:
        bt = d.get( "result", {} ).get( "content", [ {} ] )[ 0 ].get( "text", "" )
if bt.count( "renamed in the working tree: did you mean &apos;zqNewName&apos;" ) != 4:
    print( "  MCP batch: not every not-found item names the rename: " + bt[ :400 ] ); bad = 1
sys.exit( bad )
PY
fi
# ── review round (rv-fresh-067) ────────────────────────────────────────────────────────────────────────────────
# 18p) M1: near_renamed needs a DEFINITION of the name to have LEFT a changed file. Two negatives that the first cut
# called renames: an external name still imported and called beside an unrelated new def, and a name only a HEAD
# comment ever mentioned. Both must fall back to the spelling near-miss with no near_renamed.
RF="$TMP/renamefp"; mkdir -p "$RF/a" "$RF/b"
printf 'from lib import parse_config\n\ndef run():\n    return parse_config("x")\n' >"$RF/a/app.py"
printf '# TODO: retire old_fetch_user once the cache lands\ndef get_user():\n    return 1\n' >"$RF/b/svc.py"
for d in a b; do ( cd "$RF/$d" && git init -q -b main . && git add -A \
    && git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false commit -qm seed ) >/dev/null 2>&1; done
printf 'from lib import parse_config\n\ndef run():\n    return parse_config("x")\n\ndef config_parse_v2():\n    return 2\n' >"$RF/a/app.py"
printf '# TODO: retire old_fetch_user once the cache lands\ndef get_user():\n    return 1\n\ndef fetch_user_old():\n    return 0\n' >"$RF/b/svc.py"
for c in 'a parse_config' 'b old_fetch_user'; do
    set -- $c
    "$BIN" "$RF/$1" --callers="$2" --no-cache >"$TMP/rf.out" 2>"$TMP/rf.err"
    { ! grep -q 'near_renamed' "$TMP/rf.out" && ! grep -q 'renamed in the working tree' "$TMP/rf.err"; } \
        && ok "callers (18p): $2 — still mentioned, never a definition that left — is not offered as a rename" \
        || { no "callers (18p): $2 was offered as a working-tree rename"; cat "$TMP/rf.err"; }
done

# 18q) M7: --whereis's own zero names the working tree's rename first (r="renamed"), not the spelling neighbour.
WR="$( wwhere zqOldName | sed 's/<!--.*-->//' )"
{ printf '%s' "$WR" | grep -q '<selector-note r="renamed" spec="zqOldName" retry="zqNewName"/>' && ! printf '%s' "$WR" | grep -q 'r="near-miss"'; } \
    && ok 'whereis (18q): a renamed-away name offers the rename (r="renamed" retry="zqNewName"), not a spelling near-miss' \
    || { no 'whereis (18q): the renamed-away zero does not name the rename'; printf '%s\n' "$WR"; }
wwhere zqOldName --legend=full | grep -q 'renamed (the scan found nothing and the working tree' \
    && ok 'whereis (18q): the full legend defines r="renamed"' || no 'whereis (18q): r="renamed" rides undefined'

# 18r) M8: --with-history on a name only the WORKING TREE removed (HEAD's commit still holds it) is not "never".
FA="$( "$BIN" "$WT" --whereis=zqDoomed --with-history --no-cache 2>/dev/null | sed 's/<!--.*-->//' )"
{ printf '%s' "$FA" | grep -q '<fate sym="zqDoomed" v="uncommitted"' && ! printf '%s' "$FA" | grep -q 'v="never"'; } \
    && ok 'whereis (18r): a name the working tree removed (HEAD still holds it) gets fate v="uncommitted", never "never"' \
    || { no 'whereis (18r): the fate lane still reads a working-tree removal as a name this repo never had'; printf '%s\n' "$FA" | grep -o '<fate [^>]*>'; }
"$BIN" "$WT" --whereis=zqNoSuchNameAtAll --with-history --no-cache 2>/dev/null | grep -q 'v="uncommitted"' \
    && no 'whereis (18r): a name HEAD never held was called an uncommitted removal' \
    || ok 'whereis (18r): a name HEAD never held keeps the history verdict (no v="uncommitted")'

# 18s) M2: an untracked NESTED repository is a directory the overlay does not read — worktree="partial", no complete=.
NR="$TMP/nested"; mkdir -p "$NR"; printf 'int outer_fn( void ) { return 0; }\n' >"$NR/a.c"
( cd "$NR" && git init -q -b main . && git add -A && git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false commit -qm seed \
  && mkdir inner && cd inner && git init -q -b main . && printf 'int nested_fn( void ) { return 1; }\n' >n.c && git add -A \
  && git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false commit -qm seed ) >/dev/null 2>&1
NRR="$( "$BIN" "$NR" --whereis=nested_fn --no-cache 2>/dev/null | wroot )"
{ printf '%s' "$NRR" | grep -q ' worktree="partial"' && ! printf '%s' "$NRR" | grep -q 'complete='; } \
    && ok 'whereis (18s): an untracked nested repository is not read, so worktree="partial" and no complete=' \
    || { no 'whereis (18s): an unread nested repository still claims a complete answer'; printf '%s\n' "$NRR"; }

# 18t) S1: a changed path BEYOND a symlinked directory is not in the checkout (git: deleted); it is never read through
# the link, so a file outside the root never answers.
SL="$TMP/symparent"; mkdir -p "$SL/a" "$TMP/symout/a"; printf 'int inside_fn( void ) { return 1; }\n' >"$SL/a/b.c"
( cd "$SL" && git init -q -b main . && git add -A && git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false commit -qm seed ) >/dev/null 2>&1
printf 'int outside_fn( void ) { return 2; }\n' >"$TMP/symout/a/b.c"; rm -rf "$SL/a"; ln -s "$TMP/symout/a" "$SL/a"
SLR="$( "$BIN" "$SL" --whereis=outside_fn --no-cache 2>/dev/null )"
{ printf '%s' "$SLR" | wroot | grep -q ' hits="0"' && ! printf '%s' "$SLR" | grep -q 'p="a/b.c"'; } \
    && ok 'whereis (18t): a path beyond a symlinked directory is never read through the link (no row from outside the root)' \
    || { no 'whereis (18t): the overlay read a file outside the root through a symlinked parent'; printf '%s\n' "$SLR" | sed 's/<!--.*-->//'; }

# 18v) M4: both --path endpoints missing says missing="both", on the CLI and (18o) over MCP.
"$BIN" "$WT" --path=zqNope1,zqNope2 --no-cache 2>/dev/null | grep -q '<path [^>]*from="zqNope1" to="zqNope2" found="0" missing="both"' \
    && ok 'path (18v): both endpoints missing answers missing="both"' || no 'path (18v): both endpoints missing names only one'

# 18w) S2: the test_local= legend names the path tiers the code uses (test, bench, fixture), and a bench/ def is marked.
TB="$TMP/benchtl"; mkdir -p "$TB/src" "$TB/bench"
printf 'int bench_helper( void ) { return 1; }\n' >"$TB/src/b.c"; printf 'int bench_helper( void ) { return 2; }\n' >"$TB/bench/b.c"
( cd "$TB" && git init -q -b main . && git add -A && git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false commit -qm seed ) >/dev/null 2>&1
TBF="$( "$BIN" "$TB" --whereis=bench_helper --no-cache --legend=full 2>/dev/null )"
{ printf '%s' "$TBF" | grep -q 'p="bench/b.c" l="1" kind="def" test_local="1"' && printf '%s' "$TBF" | grep -q 'under a test, bench or fixture path'; } \
    && ok 'whereis (18w): a bench/ def is test_local="1" and the legend says test, bench or fixture path' \
    || no 'whereis (18w): the test_local legend and the code disagree on bench/ and fixture paths'
TBC="$( "$BIN" "$TB" --whereis=bench_helper --no-cache 2>/dev/null )"
printf '%s' "$TBC" | grep -q 'test_local=1: a definition in a test scope or under a test/bench/fixture path' \
    && ok 'whereis (18w): the compact legend says the same' || no 'whereis (18w): the compact test_local reading disagrees with the code'
# 18k) a Class.method / Class#method selector is searched as a LITERAL, and no tree spells a method's definition
# that way. It used to answer hits="0" on-head="0" complete="1" with no note — a zero shaped exactly like a name this
# repo never had (the edit-check lane's finding). The zero now carries a selector-note r="dotted-selector" whose
# retry= is the bare method name, and complete= is withheld: the scan did not answer the question the selector asked.
mkdir -p "$TMP/dotted" && printf 'class Shape:\n    def area( self ):\n        return 1\n' >"$TMP/dotted/shape.py"
( cd "$TMP/dotted" && git init -q -b main . && git add -A \
    && git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false commit -qm seed ) >/dev/null 2>&1
for sel in 'Shape.area' 'Shape#area'; do
    D="$( "$BIN" "$TMP/dotted" --whereis="$sel" --no-cache 2>/dev/null )"; DR="$( printf '%s' "$D" | wroot )"
    { printf '%s' "$D" | grep -q "<selector-note r=\"dotted-selector\" spec=\"$sel\" retry=\"area\"/>" \
      && ! printf '%s' "$DR" | grep -q 'complete='; } \
        && ok "whereis (18k): $sel says the dotted selector was searched literally (retry=\"area\") and claims no complete=" \
        || { no "whereis (18k): $sel claims a measured zero for a selector it never resolved"; printf '%s\n' "$DR"; }
done
"$BIN" "$TMP/dotted" --whereis=area --no-cache 2>/dev/null | grep -q '<hit ref="HEAD" [^>]*p="shape.py" l="2" kind="def"' \
    && ok 'whereis (18k): the offered retry (the bare name) finds the method definition' \
    || no 'whereis (18k): the offered retry does not find the definition'
"$BIN" "$TMP/dotted" --whereis=area --no-cache 2>/dev/null | grep -q 'dotted-selector' \
    && no 'whereis (18k): a bare name grew a dotted-selector note' || ok 'whereis (18k): a bare name carries no dotted-selector note'

# 18u) M3: a dotted LITERAL whose last segment the index does not define (a file name, a module path) is an ordinary
# literal search: no dotted note, and its complete= stands. The method spelling (18k) keeps the note.
printf 'Run setup.py first; see os.path docs.\n' >"$TMP/dotted/README.txt"
( cd "$TMP/dotted" && git add -A && git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false commit -qm readme ) >/dev/null 2>&1
for sel in setup.py os.path; do
    LD="$( "$BIN" "$TMP/dotted" --whereis="$sel" --no-cache 2>/dev/null )"
    { printf '%s' "$LD" | wroot | grep -q ' hits="1".* complete="1"' && ! printf '%s' "$LD" | grep -q 'dotted-selector"'; } \
        && ok "whereis (18u): the literal $sel keeps hits=\"1\" complete=\"1\" and carries no dotted note" \
        || { no "whereis (18u): the literal $sel was treated as a Class.method selector"; printf '%s' "$LD" | wroot; }
done

command -v xmllint >/dev/null 2>&1 && { printf '%s' "$W1" | xmllint --noout - 2>/dev/null \
    && ok 'whereis (18): the dirty-checkout document is well-formed' || no 'whereis (18): the dirty-checkout document fails xmllint'; }

[ $fail -eq 0 ] && printf 'completecheck: ALL PASS\n' || printf 'completecheck: FAILURES ABOVE\n'
exit $fail
