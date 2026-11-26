#!/usr/bin/env bash
# pagelegendcheck.sh — LD1 (lane LD1, 2026-11-21; lane LG2's lever d1): THE LEGEND IS PAGE-SCOPED. A document-legend clause that
# only a LATER page's rows use travels with that page instead of riding page 1 (src/forpagelegend.h, src/forpages.h).
#
# THE RULE (test/pagelegend.py says it at length): a reader of page N holds page N and page 1 — page 1 because every continuation
# page names it (<about legend="ref" have="page1"/>), nothing else because a page may be asked directly (--page-bytes=P:N). So:
#   every attribute and element page N carries is defined in page N's own comments or in page 1's,
#   and page 1 defines nothing in advance that only a later page carries.
# Reading the pages in element form (RIPWIRE_NO_ROWLINES=1: the row-line form is a lossless re-spelling, rowlinescheck (L1)).
#
# Arms:
#   (LD0) PREMISE: the fixture answer spans >= 3 pages, and some clause of the answer is needed by a later page's rows and not by
#         page 1's — without one, (LD1) would pass on any binary (a prohibition is vacuous by default)
#   (LD1) NOT IN ADVANCE: page 1 holds no clause that only a later page's rows need, unless it is the LAST DEFINER — the one
#         page-1 text spelling `a=` for a name a page carries without receiving the clause (element-blind, as (LD3); the
#         hops clause's n= is the only n= an element-form <d n=> meets)                       (RED before LD1's change)
#   (LD2) ELEMENT-AWARE COVERAGE: a page carrying a clause's element or attribute holds that clause on itself or on page 1
#   (LD3) ATTRIBUTE COVERAGE: every attribute any page carries is spelled `a=` in that page's comments or page 1's — absolutely on
#         this fixture, and on any answer no gap the old layout (every moved clause back on page 1) did not have
#   (LD4) NO RE-SEND: a continuation page carries no clause page 1 already holds
#   (LD5) LOSSLESS: every clause the whole answer (--page-bytes=0) defines whose rows some page carries is held by some page
#   (LD6) both row forms carry the same travelling comments, byte for byte (each arm also runs on the row-line form: rows
#         decoded by test/rowlines.py, comments as served)
#   (LD7) page 1's page clause states the rule (a later page defines what only its rows carry)
#   (LD8) DICTIONARY: the travelling clauses are dictionary entries — --legend-dict=seen reads one hash per clause off page N, and
#         a --legend-seen FILE holding them leaves them out of page N WHENEVER THAT SHORTENS IT (src/legendseen.h: "an answer the
#         reduction would not shorten is served unchanged"). The arm prices the omission itself — saved = the held clauses' dictionary
#         text, cost = the in-place " [legend-seen: K held]" plus the answer's one marker (its length read off the fixture's page 1 reduced) —
#         and demands: saved beats cost by > 8 B (pagelegend.SEEN_BAND) -> left out (page shorter, rows unchanged); cost beats saved by > 8 B -> served
#         byte-identical (a reduction there would GROW the page); inside the band either, each one whole.
#         ITS PREMISE LIVES ON A FROZEN FIXTURE THE GATE WRITES ITSELF ($WORK/fx). Run on this repo alone the arm went red on a
#         changelog.d-only edit: the repo's last travelling page changed from one carrying 4 dictionary entries to one carrying a
#         single 90 B clause, which the never-larger rule correctly serves whole (holding it alone left the OLD tree's page whole too).
#         The fixture serves BOTH shapes — a travelling page whose held clauses must be left out and one that must be served whole —
#         and (LD8) fails if either shape is missing, so a corpus edit can neither redden it nor make it vacuous. This repo's pages
#         are still checked under the same priced rule (no premise demanded of them).
#   (LD8m) the (LD8) predicate FAILS a must-omit page served whole and a must-keep page served reduced (it can fail both ways)
#   (LD9) every page is well-formed XML, and page N is byte-identical across two runs
#   (LD10) A RE-OPENED SECTION CARRIES ITS BLOCK-LOCAL LEGEND: a page that re-opens a section the page before left open (continued=)
#         carries the comments glued before that section's open tag, unless page 1 holds them (src/forpages.h reopenedLegend). On
#         #742's CI merge this repo's 3000 B page 9 re-opened a <syms> that began on page 8 without its legend: name_total=
#         callee_total= files_total= by= undefined (LD3). PREMISE on the frozen fixture at 600 B (its <syms> starts on a later page
#         and is cut); this repo's pages are checked with no premise. (LD10m) the re-opened page with that legend stripped FAILS
#   (LDm) MUTATION CONTROLS: page N with its travelling comment stripped fails (LD2); a moved clause put back on page 1 fails (LD1);
#         a clause on both fails (LD4) — each arm can fail
set -u
# θ5 (src/forpages.h): this gate pins the FULL page-1 legend (every attribute defined in its own answer); the default's core legend
# is pinned by test/corelegendcheck.sh, so the full legend is switched back on here.
export RIPWIRE_NO_CORE_LEGEND=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; fi
command -v python3 >/dev/null 2>&1 || { echo "pagelegendcheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "pagelegendcheck: xmllint required"; exit 2; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "pagelegendcheck: BIN=$BIN"
cd "$ROOT" || exit 2
TASK="legend posture answer first ordering of blocks"
fail=0
: >"$WORK/ld8.list"
# (LD8) ld8_hold PAGE PREFIX DIR TASK SIZE:K — hold exactly PAGE's travelling clauses (their hashes, as --legend-dict=seen reads them
# off the travelling comment alone) and serve the same page again: PREFIX.travel / .thash / .phash (every hash on PAGE) / .served
ld8_hold() {
    python3 -c 'import re,sys; m=re.search(rb"<!-- defined for this page.*?-->", open(sys.argv[1],"rb").read(), re.S); sys.stdout.buffer.write(m.group(0) if m else b"")' \
        "$1" >"$2.travel"
    "$BIN" --legend-dict=seen <"$2.travel" >"$2.thash" 2>/dev/null
    "$BIN" --legend-dict=seen <"$1" >"$2.phash" 2>/dev/null
    ( cd "$3" && RIPWIRE_NO_ROWLINES=1 "$BIN" . --for="$4" --page-bytes="$5" --legend-seen="$2.thash" ) >"$2.served" 2>/dev/null
}

for SIZE in 6000 3000; do
    RIPWIRE_NO_ROWLINES=1 "$BIN" . --for="$TASK" --page-bytes=0 >"$WORK/whole.$SIZE.xml" 2>/dev/null
    k=1; n=1
    while :; do
        RIPWIRE_NO_ROWLINES=1 "$BIN" . --for="$TASK" --page-bytes=$SIZE:$k >"$WORK/e.$SIZE.$k.xml" 2>"$WORK/err" || { echo "  FAIL  page $k at $SIZE B: $( head -c 200 "$WORK/err" )"; fail=1; break; }
        "$BIN" . --for="$TASK" --page-bytes=$SIZE:$k >"$WORK/l.$SIZE.$k.xml" 2>/dev/null
        xmllint --noout "$WORK/e.$SIZE.$k.xml" 2>/dev/null && xmllint --noout "$WORK/l.$SIZE.$k.xml" 2>/dev/null \
            || { echo "  FAIL  (LD9) $SIZE B page $k is not well-formed XML"; fail=1; }
        n="$( grep -o ' pages="[0-9]*"' "$WORK/e.$SIZE.$k.xml" | head -1 | tr -dc 0-9 )"; n="${n:-1}"
        [ "$k" -ge "$n" ] && break
        k=$(( k + 1 ))
    done
    echo "$n" >"$WORK/n.$SIZE"
    # (LD8) the travelling clauses of the last page that has one, held: priced against the never-larger rule (no premise here)
    for (( j = n; j >= 2; j-- )); do
        if grep -q '<!-- defined for this page' "$WORK/e.$SIZE.$j.xml"; then
            ld8_hold "$WORK/e.$SIZE.$j.xml" "$WORK/ld8.repo.$SIZE.$j" . "$TASK" $SIZE:$j
            echo "repo $SIZE B page $j|$WORK/e.$SIZE.$j.xml|$WORK/ld8.repo.$SIZE.$j" >>"$WORK/ld8.list"
            echo "$j" >"$WORK/seenpage.$SIZE"; break
        fi
    done
    # (LD9) determinism: the last page, twice
    RIPWIRE_NO_ROWLINES=1 "$BIN" . --for="$TASK" --page-bytes=$SIZE:$n >"$WORK/again.$SIZE.xml" 2>/dev/null
    cmp -s "$WORK/again.$SIZE.xml" "$WORK/e.$SIZE.$n.xml" && echo "  PASS  (LD9) $SIZE B page $n is byte-identical across two runs" \
        || { echo "  FAIL  (LD9) $SIZE B page $n differs between two runs"; fail=1; }
done

# (LD8) THE FROZEN FIXTURE: 6 modules x 8 flush_/ledger_ pairs, a cross-module ledger_ call and two names defined in every module
# (encode/render: name-only edges). Paged at these sizes its later pages carry 1, 2 or 3 travelling clauses (the via=name clause
# alone, or with the fold legend's pieces), so both (LD8) shapes are served: a lone ~100 B clause holding which would GROW the page,
# and a 3-clause comment holding which shortens it. Written here, never read from the repo: no repo edit moves it.
FX="$WORK/fx"; FXTASK="legend ledger posture flush ordering"
mkdir -p "$FX/src"
python3 - "$FX/src" <<'PY'
import sys
for m in range(6):
    rows = []
    for k in range(8):
        rows.append(f"def flush_{m}_{k}(buf):\n    \"\"\"write the legend ledger buffer to the ledger file, posture {k}\"\"\"\n"
                    f"    return encode(buf) + render(buf) + ledger_{(m + 1) % 6}_{k}(buf)\n")
        rows.append(f"def ledger_{m}_{k}(buf):\n    \"\"\"legend ledger posture block ordering for page {k}\"\"\"\n    return encode(buf)\n")
    rows += ["def encode(buf):\n    return buf\n", "def render(buf):\n    return buf\n"]
    open(f"{sys.argv[1]}/mod{m}.py", "w").write("\n".join(rows))
PY
for FXSIZE in 1500 2000 2500 3000; do
    k=1; n=1
    while :; do
        ( cd "$FX" && RIPWIRE_NO_ROWLINES=1 "$BIN" . --for="$FXTASK" --page-bytes=$FXSIZE:$k ) >"$WORK/fx.$FXSIZE.$k.xml" 2>/dev/null
        n="$( grep -o ' pages="[0-9]*"' "$WORK/fx.$FXSIZE.$k.xml" | head -1 | tr -dc 0-9 )"; n="${n:-1}"
        if [ "$k" -eq 1 ] && [ "$FXSIZE" -eq 3000 ]; then
            # the marker's length, priced off a reduction no travelling clause takes part in: page 1 with all it defines held
            "$BIN" --legend-dict=seen <"$WORK/fx.$FXSIZE.1.xml" >"$WORK/ld8.p1hash" 2>/dev/null
            ( cd "$FX" && RIPWIRE_NO_ROWLINES=1 "$BIN" . --for="$FXTASK" --page-bytes=$FXSIZE:1 --legend-seen="$WORK/ld8.p1hash" ) >"$WORK/ld8.marker.xml" 2>/dev/null
        fi
        if [ "$k" -ge 2 ] && grep -q '<!-- defined for this page' "$WORK/fx.$FXSIZE.$k.xml"; then
            ld8_hold "$WORK/fx.$FXSIZE.$k.xml" "$WORK/ld8.fx.$FXSIZE.$k" "$FX" "$FXTASK" $FXSIZE:$k
            echo "fixture $FXSIZE B page $k|$WORK/fx.$FXSIZE.$k.xml|$WORK/ld8.fx.$FXSIZE.$k" >>"$WORK/ld8.list"
        fi
        [ "$k" -ge "$n" ] && break
        k=$(( k + 1 ))
    done
done

# (LD10) the frozen fixture at 600 B: its <syms> block starts on a page >= 2 and is cut, so a later page re-opens it
( cd "$FX" && RIPWIRE_NO_ROWLINES=1 "$BIN" . --for="$FXTASK" --page-bytes=0 ) >"$WORK/fxr.whole.xml" 2>/dev/null
k=1; n=1
while :; do
    ( cd "$FX" && RIPWIRE_NO_ROWLINES=1 "$BIN" . --for="$FXTASK" --page-bytes=600:$k ) >"$WORK/fxr.$k.xml" 2>/dev/null
    n="$( grep -o ' pages="[0-9]*"' "$WORK/fxr.$k.xml" | head -1 | tr -dc 0-9 )"; n="${n:-1}"
    [ "$k" -ge "$n" ] && break
    k=$(( k + 1 ))
done
echo "$n" >"$WORK/fxr.n"

"$BIN" --legend-dict >"$WORK/dict.txt" 2>/dev/null
python3 - "$WORK" "$ROOT/test" <<'PY'
import os, re, sys
W, T = sys.argv[1], sys.argv[2]
sys.path.insert(0, T)
import pagelegend as P
from rowlines import decode
bad = 0
def say(ok, msg):
    global bad
    print("  %s  %s" % ("PASS" if ok else "FAIL", msg)); bad += 0 if ok else 1
def rd(p): return open(p, "rb").read()
BODIES = P.dictionary_bodies(rd(os.path.join(W, "dict.txt")))
say(len(BODIES) == len(P.CLAUSES), "(LD0) every travelling clause's lead starts a line of --legend-dict (%d of %d)%s" % (
    len(BODIES), len(P.CLAUSES), "" if len(BODIES) == len(P.CLAUSES) else " — missing %s" % [l for l, _ in P.CLAUSES if l not in BODIES]))
LEAD = b"<!-- defined for this page, the rest on page 1"
TRAVEL = re.compile(re.escape(LEAD) + rb".*?-->", re.S)
def raw(p): return P.raw_of(p)
def swap(p, b): return (P.rows_of(p), b) if isinstance(p, tuple) else b
def unmove(pages):
    """the old layout: every travelling comment's clauses back on page 1 (before its page clause), off page N"""
    moved = b"".join(m.group(0)[len(LEAD):-4] for d in pages[1:] for m in TRAVEL.finditer(raw(d)))
    p1 = raw(pages[0]); at = p1.rfind(b"<!-- page=K")
    return [swap(pages[0], p1[:at] + (b"<!--" + moved + b" -->" if moved else b"") + p1[at:])] + [swap(d, TRAVEL.sub(b"", raw(d))) for d in pages[1:]]
for size in ("6000", "3000"):
    n = int(open(os.path.join(W, "n." + size)).read())
    whole = rd(os.path.join(W, "whole.%s.xml" % size))
    E = [rd(os.path.join(W, "e.%s.%d.xml" % (size, k))) for k in range(1, n + 1)]
    Lraw = [rd(os.path.join(W, "l.%s.%d.xml" % (size, k))) for k in range(1, n + 1)]
    L = [(decode(b), b) for b in Lraw]
    for form, pages in (("elements", E), ("lines", L)):
        tag = "%s B %s" % (size, form)
        uni = b"".join(P.comments(d) for d in pages)
        e1, a1 = P.carried(pages[0]); later = [P.carried(d) for d in pages[1:]]
        pending = [lead.decode() for lead, trig in P.CLAUSES if P.holds(lead, uni) and not P.needs(trig, e1, a1) and any(P.needs(trig, e, a) for e, a in later)]
        say(n >= 3 and len(pending) >= 1, "(LD0) %s: %d pages; %d clause(s) needed by a later page and not by page 1: %s" % (tag, n, len(pending), pending))
        ahead = P.ahead_of_need(pages, BODIES)
        say(not ahead, "(LD1) %s: page 1 holds no clause only a later page needs, but the last definer of a name a page carries%s" % (tag, (" — it holds %s" % ahead) if ahead else ""))
        cov = P.clause_cover(pages, uni + P.comments(whole))
        say(not cov, "(LD2) %s: every page carrying a clause's element/attribute holds the clause or page 1 does%s" % (tag, (" — missing %s" % cov) if cov else ""))
        gaps = P.attr_gaps(pages); old = P.attr_gaps(unmove(pages))
        say(not gaps, "(LD3) %s: every attribute on every page is defined on that page or page 1%s" % (tag, (" — undefined %s" % gaps) if gaps else ""))
        say(set(gaps) <= set(old), "(LD3) %s: no gap the old layout lacked (%d now, %d with every clause on page 1)" % (tag, len(gaps), len(old)))
        rs = P.resent(pages)
        say(not rs, "(LD4) %s: no continuation page re-sends a clause page 1 holds%s" % (tag, (" — %s" % rs) if rs else ""))
        allel, allat = set(), set()
        for d in pages:
            e, a = P.carried(d); allel |= e; allat |= a
        lost = [lead.decode() for lead, trig in P.CLAUSES if P.holds(lead, P.comments(whole)) and P.needs(trig, allel, allat) and not P.holds(lead, uni)]
        say(not lost, "(LD5) %s: every clause the whole answer defines for rows some page carries is on some page%s" % (tag, (" — lost %s" % lost) if lost else ""))
        # (LDm) mutation controls
        k = next((i for i, d in enumerate(pages[1:], 1) if TRAVEL.search(raw(d))), None)
        if k is not None:
            stripped = pages[:k] + [swap(pages[k], TRAVEL.sub(b"", raw(pages[k])))] + pages[k + 1:]
            say(bool(P.clause_cover(stripped, uni)), "(LDm) %s: page %d with its travelling comment stripped FAILS (LD2)" % (tag, k + 1))
            back = unmove(pages)
            say(bool(P.ahead_of_need(back, BODIES)), "(LDm) %s: the moved clauses put back on page 1 FAIL (LD1)" % tag)
            say(bool(P.resent([back[0]] + pages[1:])), "(LDm) %s: a clause on page 1 AND a later page FAILS (LD4)" % tag)
        else:
            say(False, "(LDm) %s: no travelling comment to mutate — the controls did not run" % tag)
    # (LD6) both row forms shed the same clauses: rowlinescheck (L1) pins the row-line answer decoded as the element form byte for byte
    te = [TRAVEL.findall(d) for d in E[1:]]; tl = [TRAVEL.findall(d) for d in Lraw[1:]]
    say(te == tl and any(tl), "(LD6) %s B: the row-line pages carry the element pages' travelling comments byte for byte (%d page(s) carry one)" % (size, sum(1 for x in tl if x)))
    clause = re.search(rb"<!-- page=K of pages=N:.*?-->", E[0], re.S)
    say(clause is not None and b"no legend but what only its rows use (this one defines the rest)" in clause.group(0),
        "(LD7) %s B: page 1's page clause says a later page defines what only its rows carry" % size)
    if not os.path.exists(os.path.join(W, "seenpage." + size)):
        say(False, "(LD8) %s B: no page carries a travelling comment, so the dictionary arm did not run on this repo" % size)
# (LD8) every held page — this repo's last travelling page per size, and every travelling page of the frozen fixture
HELD = [l.split("|") for l in open(os.path.join(W, "ld8.list")).read().splitlines() if l]
m = P.MARKER.search(rd(os.path.join(W, "ld8.marker.xml")))
marker = m.group(0) if m else None
say(marker is not None, "(LD8) the fixture's page 1, all it defines held, carries the answer's one legend-seen marker (%s B: it prices every omission)" % (
    len(marker) if marker else "none"))
omit, keep = [], []
for tag, pg, pre in HELD:
    page, served, travel = rd(pg), rd(pre + ".served"), rd(pre + ".travel")
    th, ph = rd(pre + ".thash").split(), set(rd(pre + ".phash").split())
    cl = P.travelling_bodies(travel, BODIES)
    say(len(cl) >= 1 and len(th) == len(cl) and set(th) <= ph,
        "(LD8) %s: its %d travelling clause(s) are %d dictionary entries, --legend-dict=seen reads each off the page" % (tag, len(cl), len(th)))
    if marker is None:
        continue
    ok, why, margin = P.seen_verdict(page, served, travel, BODIES, marker)
    say(ok, "(LD8) %s: %d clause(s) held — %s" % (tag, len(cl), why))
    if tag.startswith("fixture") and ok:
        if margin > P.SEEN_BAND:
            omit.append((tag, page, travel))
        elif margin < -P.SEEN_BAND:
            keep.append((tag, page, travel))
say(len(omit) >= 1 and len(keep) >= 1,
    "(LD8) PREMISE (frozen fixture): %d page(s) whose held clauses must be left out and were, %d that must be served whole and were" % (len(omit), len(keep)))
# (LD8m) the predicate can fail both ways
if omit:
    tag, page, travel = omit[0]
    say(not P.seen_verdict(page, page, travel, BODIES, marker)[0], "(LD8m) %s served whole (the omission not made) FAILS (LD8)" % tag)
if keep:
    tag, page, travel = keep[0]
    grown = P.seen_grown(page, travel, BODIES, marker)
    say(len(grown) > len(page) and not P.seen_verdict(page, grown, travel, BODIES, marker)[0],
        "(LD8m) %s reduced anyway (%d B against %d B: the never-larger rule broken) FAILS (LD8)" % (tag, len(grown), len(page)))
# (LD10) a re-opened section carries its block-local legend when page 1 does not: this repo's pages (no premise), then the fixture's
for size in ("6000", "3000"):
    n = int(open(os.path.join(W, "n." + size)).read())
    E = [rd(os.path.join(W, "e.%s.%d.xml" % (size, k))) for k in range(1, n + 1)]
    seen, gaps = P.reopened_gaps(E, rd(os.path.join(W, "whole.%s.xml" % size)))
    say(not gaps, "(LD10) repo %s B: every re-opened section whose legend page 1 lacks carries it (%d re-open(s))%s" % (
        size, len(seen), (" — missing on %s" % gaps) if gaps else ""))
n = int(open(os.path.join(W, "fxr.n")).read())
FXR = [rd(os.path.join(W, "fxr.%d.xml" % k)) for k in range(1, n + 1)]
FXW = rd(os.path.join(W, "fxr.whole.xml"))
seen, gaps = P.reopened_gaps(FXR, FXW)
say(len(seen) >= 1 and not gaps, "(LD10) fixture 600 B: PREMISE %d re-opened section(s) whose legend page 1 lacks (%s); each carries it%s" % (
    len(seen), seen, (" — missing on %s" % gaps) if gaps else ""))
if seen:
    k, name = seen[0]
    tag = re.search(rb"<" + re.escape(name.encode()) + rb"\b[^>]*>", P.MASK.sub(lambda x: b" " * len(x.group(0)), FXR[k - 1][FXR[k - 1].find(b">") + 1:]))
    leg = P.glued_legend(FXW, tag.group(0))
    cut = FXR[:k - 1] + [FXR[k - 1].replace(leg, b"", 1)] + FXR[k:]
    say(bool(P.reopened_gaps(cut, FXW)[1]), "(LD10m) fixture 600 B page %d with the re-opened <%s>'s legend stripped FAILS (LD10)" % (k, name))
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1
if [ "$fail" -ne 0 ]; then echo "pagelegendcheck: FAILURES"; exit 1; fi
echo "pagelegendcheck: ALL PASS"
