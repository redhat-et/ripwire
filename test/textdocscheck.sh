#!/usr/bin/env bash
# textdocscheck.sh — THE PLAIN-TEXT DOCUMENT TIER: which prose extensions the crawl admits, which it
# deliberately refuses, and that `--recall` can actually answer from the admitted ones.
#
# THE DEFECT THIS GATE PINS (measured 2026-09-09, before the fix). Eight files holding the SAME ADR text
# and differing only in extension produced `unindexed="adoc:1,log:1,mdx:1,org:1,rst:1,txt:1"` — so a
# repository whose decision history lives in `docs/adr/*.rst` got "0 relevant of 0 document files" from
# `--recall`. reStructuredText, AsciiDoc, Org-mode and MDX are SINGLE-PURPOSE PROSE formats: an extension
# that exists for nothing but documents was being dropped by the one verb whose whole job is documents.
#
# WHAT IS ADMITTED, AND WHY THOSE FOUR. `.rst` / `.adoc` / `.org` / `.mdx` ride Lang::Markdown and the
# markdown BLOCK grammar (ingest_crawl.h's kLangTable), so they reach the section tier, `--recall`'s
# section-granular serving and the doc→code mention machinery with no new extractor and no docText copy.
# Heading tiling is honest rather than uniform: reStructuredText's `====` / `----` title underlines ARE
# setext headings, so `.rst` tiles by section; AsciiDoc's `== Section` and Org's `* Heading` are not
# markdown headings, so those files serve as ONE whole-file unit. Both shapes are pinned below.
#
# WHAT IS REFUSED, AND WHY — the arm that keeps this tier from becoming the thing it replaces:
#   .txt   REFUTED BY CENSUS, not by taste. `.txt` is the universal "arbitrary bytes" extension. In this
#          repository 69 of 69 crawled `.txt` files are build manifests, gate fixtures or captured output
#          (571,706 B; the largest is 69,729 B = 7.5x the corpus median document) and NONE is prose. Across
#          three checkouts on the development machine the commonest `.txt` basenames are requirements.txt
#          (111), meson_options.txt (67) and CMakeLists.txt (50) against README.txt (71) and index.txt
#          (32). Admitting it would hand BM25 half a megabyte of gate dumps that the generated-document
#          demotion does NOT catch (no marker, no ``` fences — docparse.h states that limit itself).
#   .log   machine output, unbounded, written for a tail -f and not for a reader.
#   .lock  a resolver's output — a pinned dependency graph, not prose.
#   .out   captured stdout by convention, the same class as .log.
# All four stay in the `unindexed=` roll-up, so their absence stays DISCLOSED rather than silent.
#
# Usage:
#   test/textdocscheck.sh
#   RIPWIRE_BIN=asan/ripwire test/textdocscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL (and one uid-gated SKIP) per check, ALL PASS on success.
# Does NOT edit regression.sh. Builds its fixture under mktemp — nothing is written into the checkout.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "textdocscheck: BIN=$BIN"

# ═══════════════════════════════════════════════════════════════════════════
# the fixture — one ADR-shaped decision per prose format, plus the refused classes and one code file
# ═══════════════════════════════════════════════════════════════════════════
FIX="$TMP/fixture"
mkdir -p "$FIX/docs/adr" "$FIX/docs/notes" "$FIX/src" "$FIX/logs"

cat > "$FIX/docs/adr/0007-isolation.rst" <<'RST'
ADR 0007: Isolate the settlement worker
=======================================

Status
------

Accepted

Context
-------

The settlement worker shares a thread pool with the refund poller. A slow
upstream in the refund path starved settlement for forty minutes.

Decision
--------

We adopt bulkhead isolation: settlement and refunds each get a separate,
bounded thread pool, and the gateway rejects rather than queues past the bound.

Consequences
------------

Peak throughput drops about eight percent. A refund stall can no longer stop
settlement. Operators must size two pools instead of one.
RST

cat > "$FIX/docs/adr/0008-retry.adoc" <<'ADOC'
= ADR 0008: Retry budget for the refund poller

== Decision

The refund poller carries a retry budget of three attempts per settlement
window, after which it sheds load instead of retrying.
ADOC

cat > "$FIX/docs/notes/roadmap.org" <<'ORG'
* Roadmap for the payment gateway

The gateway migrates to a bounded queue in the next quarter.
ORG

cat > "$FIX/docs/guide.mdx" <<'MDX'
# Operator guide

<Note>Size the settlement pool from the observed peak.</Note>
MDX

cat > "$FIX/docs/reference.md" <<'MD'
# Reference

The gateway exposes one endpoint per settlement window.
MD

printf 'INFO 12:00:01 settlement worker started\nINFO 12:00:02 refund poller started\n' > "$FIX/logs/output.log"
printf 'requests==2.31.0\nurllib3==2.0.7\n'                                            > "$FIX/requirements.txt"
printf 'lockfileVersion: 6\nsettings:\n  autoInstallPeers: true\n'                     > "$FIX/pnpm.lock"
printf 'settlement worker: ok\nrefund poller: ok\n'                                    > "$FIX/run.out"

cat > "$FIX/src/gateway.py" <<'PY'
def settle_payment( amount ):
    """Settle one payment through the gateway."""
    return amount
PY

QUERY='which isolation scheme did we choose for the settlement worker and why'

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== presence guards: the fixture really spells what the arms below assert ==="
# ═══════════════════════════════════════════════════════════════════════════
guard(){ if grep -qF -- "$2" "$1"; then ok "fixture spells $3"; else no "fixture LOST $3 — its arm below would pass by finding nothing"; fi; }
guard "$FIX/docs/adr/0007-isolation.rst" 'bulkhead isolation'    'the .rst decision phrase "bulkhead isolation"'
guard "$FIX/docs/adr/0007-isolation.rst" '======================' 'the .rst setext-shaped title underline'
guard "$FIX/docs/adr/0008-retry.adoc"    '== Decision'           'the .adoc section marker'
guard "$FIX/docs/notes/roadmap.org"      '* Roadmap'             'the .org heading marker'
guard "$FIX/docs/guide.mdx"              '# Operator guide'      'the .mdx ATX heading'
guard "$FIX/requirements.txt"            'requests=='            'the refused .txt manifest line'
guard "$FIX/logs/output.log"             'settlement worker'     'the refused .log line'
case "$QUERY" in *bulkhead*) no "the query echoes the probe token — arm F could never contrast";; *) ok "the query does NOT contain the probe token (so the echoed header cannot satisfy arm B/F)";; esac

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== A: the crawl admits the four prose formats and still refuses the four noise classes ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --no-cache >"$TMP/map.xml" 2>"$TMP/map.err"
"$BIN" "$FIX" --skipped --no-cache >"$TMP/skipped.xml" 2>"$TMP/skipped.err"
# `--skipped`'s <e x=".ext" files=N/> rows are the UNCAPPED form of the same roll-up the map header prints
# as unindexed=. The header list is a TOP-6 (serialize.h kUnindexedHeaderExts), so an absence there can mean
# "cut", not "admitted" — this arm reads the uncapped rows and would otherwise be CONTRIBUTING §2 shape 2,
# a correct check aimed at the wrong artifact. The header is asserted separately, below, once it is short.
extRows="$( tr '>' '\n' < "$TMP/skipped.xml" | sed -n 's/.*<e x="\.\([a-z0-9]*\)" files="\([0-9]*\)".*/\1:\2/p' | tr '\n' ',' )"
echo "  unsupported-ext rows: $extRows"

for e in rst adoc org mdx; do
    case ",$extRows" in
        *",$e:"*) no "A: .$e is still refused as unsupported-ext — the crawl did not admit it" ;;
        *)        ok "A: .$e is admitted (no unsupported-ext row)" ;;
    esac
done
# The refusal half. This is also what keeps arm A from being "empty equals agreement": the roll-up is
# demonstrably LIVE on this same run, so an admitted extension's absence means admitted, not silent.
for e in txt log lock out; do
    case ",$extRows" in
        *",$e:"*) ok "A: .$e stays unindexed on purpose, and says so in the roll-up" ;;
        *)        no "A: .$e vanished from the roll-up — a refused class must stay DISCLOSED, not silent" ;;
    esac
done

# the map header's own list, which after this lane holds exactly the four refused classes and is therefore
# under the top-6 cut: what an agent reading the DEFAULT map sees.
unindexed="$( sed -n 's/.*unindexed="\([^"]*\)".*/\1/p' "$TMP/map.xml" | head -1 )"
echo "  unindexed= $unindexed"
case "$unindexed" in
    *rst:*|*adoc:*|*org:*|*mdx:*) no "A: the map header still names a prose format as unindexed: $unindexed" ;;
    *) ok "A: the map header's unindexed= names no admitted prose format" ;;
esac

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== B: --recall counts and serves the admitted documents ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --recall="$QUERY" --no-cache >"$TMP/recall.txt" 2>"$TMP/recall.err"
docTotal="$( sed -n 's/.* of \([0-9][0-9]*\) document files.*/\1/p' "$TMP/recall.txt" | head -1 )"
[ -n "$docTotal" ] || docTotal=0
echo "  document files = $docTotal"
[ "$docTotal" -eq 5 ] && ok "B: the document total is 5 (.md .mdx .rst .adoc .org)" \
                      || no "B: the document total is $docTotal, expected 5 (.md .mdx .rst .adoc .org)"

grep -q '0007-isolation\.rst' "$TMP/recall.txt" \
    && ok "B: --recall names the .rst ADR for a query about its decision" \
    || no "B: --recall does NOT name 0007-isolation.rst — the ADR is unreachable"
# the SERVED BODY, not the echoed query line (the guard above proved the query cannot supply this token)
tail -n +2 "$TMP/recall.txt" | grep -q 'bulkhead isolation' \
    && ok "B: the served body carries the decision sentence" \
    || no "B: the served body does NOT carry the decision sentence"
grep -q 'roadmap\.org\|0008-retry\.adoc\|guide\.mdx' "$TMP/recall.txt" \
    && ok "B: at least one of .org/.adoc/.mdx is reachable by --recall too" \
    || no "B: none of .org/.adoc/.mdx reached --recall"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== C: tiling — .rst tiles by section, .adoc/.org serve as one whole-file unit ==="
# ═══════════════════════════════════════════════════════════════════════════
# reStructuredText title underlines ARE setext headings, so the markdown section tier reaches them and
# --recall serves SECTIONS. AsciiDoc/Org headings are not markdown headings and serve whole — the tier is
# honest about which formats it can tile rather than claiming uniform section granularity.
rstLine="$( grep -F '0007-isolation.rst' "$TMP/recall.txt" | head -1 )"
case "$rstLine" in
    *section-granular*) ok "C: the .rst is served SECTION-GRANULAR (its underlines tile)" ;;
    *)                  no "C: the .rst was not served section-granular: $rstLine" ;;
esac
"$BIN" "$FIX" --recall='retry budget for the refund poller' --no-cache >"$TMP/recall_adoc.txt" 2>&1
adocLine="$( grep -F '0008-retry.adoc' "$TMP/recall_adoc.txt" | head -1 )"
if [ -n "$adocLine" ]; then ok "C: the .adoc is reachable by its own query"; else no "C: the .adoc is unreachable"; fi
case "$adocLine" in
    *section-granular*) no "C: the .adoc claims section-granular serving — markdown cannot read '== Section'" ;;
    *)                  ok "C: the .adoc serves as one whole-file unit (no false granularity claim)" ;;
esac

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== D: determinism — a warm run reproduces the cold run byte-for-byte ==="
# ═══════════════════════════════════════════════════════════════════════════
# WHERE A MISSED CACHE-KEY BUMP SHOWS. ingest's blob header carries kCacheVersion + kParserVer and its
# per-file records key on them; a tier that admits new files without moving the key can serve a warm run
# from a blob that never knew those files. LIMIT, named rather than implied (CONTRIBUTING §2 shape 7):
# this arm has ONE binary, so it proves cold==warm for THIS extraction identity — it cannot prove the
# identity moved relative to a PREVIOUS binary's blobs. test/qextractionkeycheck.sh owns that half.
CACHE="$TMP/cachehome"; mkdir -p "$CACHE"
TMPDIR="$CACHE" "$BIN" "$FIX" >"$TMP/cold.xml" 2>"$TMP/cold.err"
TMPDIR="$CACHE" "$BIN" "$FIX" >"$TMP/warm.xml" 2>"$TMP/warm.err"
if cmp -s "$TMP/cold.xml" "$TMP/warm.xml"; then
    ok "D: cold and warm runs are byte-identical"
else
    no "D: cold and warm runs DIFFER — the cache key does not cover the new document tier"
    diff "$TMP/cold.xml" "$TMP/warm.xml" | head -5
fi
grep -q '0007-isolation\.rst' "$TMP/cold.xml" \
    && ok "D: the cached run really contains the .rst (the comparison is not two empty corpora)" \
    || no "D: the .rst is absent from the cached run — arm D compared nothing"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== D2: an admitted document that cannot be READ is disclosed, never a silent zero ==="
# ═══════════════════════════════════════════════════════════════════════════
# A file this tier ADMITS and then fails to read must not vanish quietly: it stays in indexed= and is
# counted by unmeasured= (the --skipped header's "indexed files this run never parsed" class). Root can
# read a mode-000 file, so the arm SKIPS rather than passing there — a skipped arm leaves the conjunction
# honestly, a green one on an unenforceable permission does not.
if [ "$( id -u )" = "0" ]; then
    printf '  SKIP  D2: running as uid 0 — a mode-000 file is still readable, so this arm cannot be posed
'
else
    UNREAD="$TMP/unread"; cp -R "$FIX" "$UNREAD"
    chmod 000 "$UNREAD/docs/adr/0007-isolation.rst"
    if [ -r "$UNREAD/docs/adr/0007-isolation.rst" ]; then
        no "D2: the mode-000 mutation did not take — the file is still readable, so the arm proves nothing"
    else
        ok "D2: the mode-000 mutation took (the .rst is unreadable on a real copy)"
        "$BIN" "$UNREAD" --skipped --no-cache >"$TMP/unread_skipped.xml" 2>/dev/null
        unmeasured="$( sed -n 's/.*unmeasured="\([0-9]*\)".*/\1/p' "$TMP/unread_skipped.xml" | head -1 )"
        [ "${unmeasured:-0}" -ge 1 ] \
            && ok "D2: the unreadable document is disclosed as unmeasured=${unmeasured}, not silently zero" \
            || no "D2: unmeasured= is ${unmeasured:-absent} — an unreadable admitted document vanished silently"
    fi
    chmod 644 "$UNREAD/docs/adr/0007-isolation.rst" 2>/dev/null
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== E: CONTROL 1 — mutate the ADMISSION input (the extension) and re-run the identical check ==="
# ═══════════════════════════════════════════════════════════════════════════
MUT1="$TMP/mut_ext"; cp -R "$FIX" "$MUT1"
mv "$MUT1/docs/adr/0007-isolation.rst" "$MUT1/docs/adr/0007-isolation.rstx"
if [ -f "$MUT1/docs/adr/0007-isolation.rst" ] || [ ! -f "$MUT1/docs/adr/0007-isolation.rstx" ]; then
    no "E: the extension mutation did not take — the control proves nothing"
else
    ok "E: the extension mutation took (.rst -> .rstx on a real copy)"
    "$BIN" "$MUT1" --skipped --no-cache >"$TMP/mut1_skipped.xml" 2>&1
    "$BIN" "$MUT1" --recall="$QUERY" --no-cache >"$TMP/mut1_recall.txt" 2>&1
    mut1Rows="$( tr '>' '\n' < "$TMP/mut1_skipped.xml" | sed -n 's/.*<e x="\.\([a-z0-9]*\)" files="\([0-9]*\)".*/\1:\2/p' | tr '\n' ',' )"
    case ",$mut1Rows" in
        *',rstx:'*) ok "E: .rstx (not in the admission table) is refused as unsupported-ext — the table is what decides" ;;
        *)          no "E: .rstx did not reach the roll-up (saw: $mut1Rows) — arm A cannot fail" ;;
    esac
    if tail -n +2 "$TMP/mut1_recall.txt" | grep -q 'bulkhead isolation'; then
        no "E: --recall still serves the decision after the file left the admission table — arm B cannot fail"
    else
        ok "E: --recall loses the decision once the extension leaves the table — arm B has a failing state"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== F: CONTROL 2 — mutate the ADR's CONTENT and re-run the identical --recall ==="
# ═══════════════════════════════════════════════════════════════════════════
MUT2="$TMP/mut_body"; cp -R "$FIX" "$MUT2"
sed 's/bulkhead/zzmutatedscheme/g' "$FIX/docs/adr/0007-isolation.rst" > "$MUT2/docs/adr/0007-isolation.rst"
if cmp -s "$FIX/docs/adr/0007-isolation.rst" "$MUT2/docs/adr/0007-isolation.rst"; then
    no "F: the content mutation did not take — the copy is unchanged, so it proves nothing"
else
    ok "F: the content mutation took (bulkhead -> zzmutatedscheme in a real copy)"
    "$BIN" "$MUT2" --recall="$QUERY" --no-cache >"$TMP/mut2_recall.txt" 2>&1
    if tail -n +2 "$TMP/mut2_recall.txt" | grep -q 'zzmutatedscheme'; then
        ok "F: --recall serves the MUTATED bytes — the arm reads the file, not merely its path"
    else
        no "F: --recall did not serve the mutated token — it is not reading the .rst body"
    fi
    if tail -n +2 "$TMP/mut2_recall.txt" | grep -q 'bulkhead'; then
        no "F: --recall still serves the pre-mutation token — arm B is reading something stale"
    else
        ok "F: the pre-mutation token is gone from the served body"
    fi
fi

echo
if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES PRESENT"
fi
exit "$fail"
