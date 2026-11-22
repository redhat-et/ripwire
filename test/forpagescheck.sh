#!/usr/bin/env bash
# AF1 — the default `--for` answer is ANSWER-FIRST and served in PAGES (src/forpages.h). Pre-registered in
# results/AF1_ANSWERFIRST_1118/PREREG.md before the code it measures.
#
# A page is a WINDOW onto one deterministic answer, not a cut of it: the answer is rendered whole, permuted
# answer-first (foranswerfirst.h), and only then split at row boundaries into pages of about --page-bytes. Page 1
# carries the cut on its ROOT (page= pages= withheld_bytes= next=) and keeps the whole document legend after its rows;
# a continuation page re-sends no legend and ends with the ref posture's <about legend="ref" have="page1"/>.
#
# Arms:
#   (P1)  page 1: the disclosure rides the root, the legend + page clause sit after the rows and before </ctx>,
#         every disclosure attribute is defined inside the page, well-formed, no newline outside CDATA
#   (P2)  ROW IDENTITY: following next= to the last page, the pages' rows joined (envelopes removed) equal the
#         --page-bytes=0 answer's row stream byte for byte — at two page sizes
#   (P2n) negative control: dropping one row from one page must make (P2) fail
#   (P3)  a continuation page carries no document legend and ends <about legend="ref" have="page1" …/>; its
#         envelope bytes are printed (the measured per-page cost)
#   (P4)  the last page carries withheld_bytes="0" and no next=; every other page a next= naming page K+1
#   (P5)  --page-bytes=0 is the whole answer-first answer, byte-identical to --legend=last --page-bytes=0, unpaged
#   (P6)  --legend=first is the legend-first order, unpaged, and a permutation of the --page-bytes=0 answer
#   (P7)  determinism: page 1 and page 2, two runs each, byte-identical
#   (P8)  an answer that fits one page is served whole (no page attributes), byte-identical to --page-bytes=0
#   (P10) the flagless default is --page-bytes=12000's page 1 (one default constant)
#   (P11) PRESENT OR DISCLOSED-DEFERRED (AF1-fix): every page but the last names on its root the section its cut leaves open
#         (continued=) and every top-level element that starts on a later page (deferred=, each name once, in order) — exactly,
#         against the whole answer's own blocks — and page 1's legend defines both; (P11n) a page 1 with deferred= removed fails
#   (P9)  refusals: empty / malformed / page 0 / 0:K / without --for / with --legend=first / with a token budget /
#         a page past the last — each exits 1 with empty stdout and names --page-bytes
set -u
# FMT2 (ROWLINES + RANKSEQ, src/forrowlines.h): the default answer-first --for answer serves its <sigs>/<tail> rows as text lines in
# one CDATA (lossless; test/rowlinescheck.sh pins it: (L1) decodes the answer back to this element form byte for byte). This gate
# reads those rows as elements for another rule, so the line form is off here.
export RIPWIRE_NO_ROWLINES=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; fi
command -v python3 >/dev/null 2>&1 || { echo "forpagescheck: python3 required"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$1"; fail=1; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "forpagescheck: BIN=$BIN"
cd "$ROOT" || exit 2

TASK="legend posture answer first ordering of blocks"

# ---- (P9) refusals first: each must exit 1, print nothing on stdout, and name the flag ------------------------------
refuse(){  # refuse LABEL ARGS...
    local label="$1"; shift
    "$BIN" . "$@" >"$WORK/r.out" 2>"$WORK/r.err"; local rc=$?
    if [ "$rc" -eq 1 ] && [ ! -s "$WORK/r.out" ] && grep -q -- '--page-bytes' "$WORK/r.err"; then
        ok "(P9) $label refuses (exit 1, empty stdout, flag named)"
    else
        no "(P9) $label: rc=$rc stdout=$( wc -c <"$WORK/r.out" | tr -d ' ' ) B, stderr: $( head -c 200 "$WORK/r.err" )"
    fi
}
refuse "an empty value"        --for="$TASK" --page-bytes=
refuse "a malformed value"     --for="$TASK" --page-bytes=12k
refuse "page 0"                --for="$TASK" --page-bytes=6000:0
refuse "0:K"                   --for="$TASK" --page-bytes=0:2
refuse "no --for"              --callers=main --page-bytes=6000
refuse "--legend=first"        --for="$TASK" --legend=first --page-bytes=6000
refuse "a token budget"        --for="$TASK" --token-budget=3000 --page-bytes=6000
refuse "a page past the last"  --for="$TASK" --page-bytes=3000:999

# ---- capture: page chains at two sizes, the whole answer, the opt-outs -------------------------------------------------
chain(){  # chain SIZE -> $WORK/p<SIZE>_<k>.xml, following next=
    local size="$1" k=1
    "$BIN" . --for="$TASK" --page-bytes="$size" >"$WORK/p${size}_1.xml" 2>/dev/null || return 1
    while :; do
        local nx
        nx="$( python3 -c 'import re,sys,html; d=open(sys.argv[1],encoding="utf-8",errors="replace").read(); m=re.match(r"<ctx\b[^>]*?\snext=\"([^\"]*)\"",d); print(html.unescape(m.group(1)) if m else "")' "$WORK/p${size}_${k}.xml" )"
        [ -n "$nx" ] || break
        k=$(( k + 1 ))
        [ "$k" -le 60 ] || return 1
        # next= is pasteable shell: split it the way a shell would (shlex), never by hand
        python3 -c 'import shlex,sys,subprocess; a=shlex.split(sys.argv[3]); sys.exit(subprocess.run([sys.argv[1], "."]+a, stdout=open(sys.argv[2],"wb"), stderr=subprocess.DEVNULL).returncode)' \
            "$BIN" "$WORK/p${size}_${k}.xml" "$nx" || return 1
    done
    echo "$k" >"$WORK/p${size}.n"
}
chain 3000 || no "(P2) the 3000 B page chain could not be followed"
chain 6000 || no "(P2) the 6000 B page chain could not be followed"
"$BIN" . --for="$TASK" --page-bytes=0                    >"$WORK/whole.xml" 2>/dev/null
"$BIN" . --for="$TASK" --legend=last --page-bytes=0      >"$WORK/whole_last.xml" 2>/dev/null
"$BIN" . --for="$TASK" --legend=first                    >"$WORK/first.xml" 2>/dev/null
# SIGX (src/forsigx.h, TL1 M1) is LOSSLESS but not a permutation: it adds the <x r=R> envelopes, the <sigx> block and its legend after
# the rows. (P6) is about the PERMUTATION, so it compares --legend=first with the whole answer-first answer under RIPWIRE_NO_SIGX=1;
# test/forsigxcheck.sh (S1) proves the default whole answer rebuilds that twin byte for byte.
# TL1 M2 likewise adds its order clause to the legend when it reorders the tail (src/fortailorder.h): off for (P6) too.
RIPWIRE_NO_SIGX=1 RIPWIRE_NO_TAIL_SAMEDIR=1 "$BIN" . --for="$TASK" --page-bytes=0  >"$WORK/whole_nosigx.xml" 2>/dev/null
"$BIN" . --for="$TASK" --page-bytes=3000                 >"$WORK/again_1.xml" 2>/dev/null
"$BIN" . --for="$TASK" --page-bytes=3000:2               >"$WORK/again_2.xml" 2>/dev/null
"$BIN" . --for="$TASK" --page-bytes=100000000            >"$WORK/onepage.xml" 2>/dev/null

# (P10) the DEFAULT page size is the one constant: a flagless default answer is --page-bytes=12000's page 1, byte for byte (Config's
# literal and src/foranswerfirst.h kAnswerPageBytesDefault, which AF2's guard reads, cannot drift apart unseen)
"$BIN" . --for="$TASK"                       >"$WORK/dflt.xml" 2>/dev/null
"$BIN" . --for="$TASK" --page-bytes=12000    >"$WORK/p12k.xml" 2>/dev/null
cmp -s "$WORK/dflt.xml" "$WORK/p12k.xml" && grep -q ' page="1" pages="' "$WORK/dflt.xml" && ok "(P10) the flagless default is --page-bytes=12000's page 1, byte for byte" \
    || no "(P10) the flagless default differs from --page-bytes=12000 (or is unpaged on this task)"
cmp -s "$WORK/whole.xml" "$WORK/whole_last.xml" && ok "(P5) --page-bytes=0 is byte-identical to --legend=last --page-bytes=0" \
    || no "(P5) --page-bytes=0 differs from --legend=last --page-bytes=0"
cmp -s "$WORK/onepage.xml" "$WORK/whole.xml" && ok "(P8) an answer inside one page is served whole, byte-identical to --page-bytes=0" \
    || no "(P8) a one-page answer is not the whole answer"
if cmp -s "$WORK/p3000_1.xml" "$WORK/again_1.xml" && cmp -s "$WORK/p3000_2.xml" "$WORK/again_2.xml"; then
    ok "(P7) page 1 and page 2 are byte-identical across two runs"
else
    no "(P7) a page differs between two runs of the same call"
fi
for f in "$WORK"/p3000_*.xml "$WORK"/p6000_*.xml; do
    if ! xmllint --noout "$f" 2>"$WORK/x.err"; then no "(P1) $( basename "$f" ) is not well-formed: $( head -c 200 "$WORK/x.err" )"; fi
done

python3 - "$WORK" <<'PY'
import re, sys, glob, os
W = sys.argv[1]; bad = 0
def rd(p): return open(p, "rb").read().decode("latin-1")
def say(okay, msg):
    global bad
    print("  %s  %s" % ("PASS" if okay else "FAIL", msg))
    bad += 0 if okay else 1
MASK = re.compile(r"<!--.*?-->|<!\[CDATA\[.*?\]\]>", re.S)
def mask(d): return MASK.sub(lambda m: " " * len(m.group(0)), d)
def root_open(d):
    m = re.search(r"<ctx\b[^>]*>", mask(d)); return m
def trailing_comments_start(body):
    """start of the maximal suffix of top-level comments in `body` (comments hold no '-->' inside)"""
    i = len(body)
    while body[:i].endswith("-->"):
        j = body.rfind("<!--", 0, i)
        if j < 0: break
        i = j
    return i
def page_body(d):
    m = root_open(d); close = d.rfind("</ctx>"); body = d[m.end():close]
    a = body.rfind('<about legend="ref"')
    if a >= 0 and body.endswith("/>") and body.find("/>", a) == len(body) - 2: body = body[:a]
    return body[:trailing_comments_start(body)]
whole = rd(os.path.join(W, "whole.xml")); wm = root_open(whole)
wbody = whole[wm.end():whole.rfind("</ctx>")]
stream = wbody[:trailing_comments_start(wbody)]
opens = set(re.findall(r"<[A-Za-z_][\w-]*(?:\s[^<>]*[^/])?>", stream))  # candidate section open tags (SIGX: <sigx> has no attribute)
ENDS = []   # the stream offset each page of the last join() ended at
def join(pages):
    """rows of every page joined, envelopes removed against the whole stream. -> (joined_ok, detail)"""
    cur = 0; del ENDS[:]
    for k, d in enumerate(pages, 1):
        b = page_body(d)
        if not stream.startswith(b, cur):
            # a continuation page may open with a re-opened section tag; a page may end with a synthetic close
            if k > 1:
                m = re.match(r"<[A-Za-z_][\w-]*(?:\s[^<>]*[^/])?>", b)
                if m and m.group(0) in opens and not stream.startswith(b[:len(m.group(0))], cur): b = b[m.end():]
            if not stream.startswith(b, cur):
                m = re.search(r"</[A-Za-z_][\w-]*>$", b)
                if m: b = b[:m.start()]
        if not stream.startswith(b, cur):
            return False, "page %d's rows do not continue the stream at byte %d" % (k, cur)
        cur += len(b); ENDS.append(cur)
    return cur == len(stream), "joined %d of %d stream bytes" % (cur, len(stream))
for size in ("3000", "6000"):
    n = int(open(os.path.join(W, "p%s.n" % size)).read())
    pages = [rd(os.path.join(W, "p%s_%d.xml" % (size, k))) for k in range(1, n + 1)]
    say(n >= 2, "(P2) %s B pages: the answer spans %d pages (a single page would prove nothing)" % (size, n))
    okj, why = join(pages)
    say(okj, "(P2) %s B: every page's rows, joined, are the --page-bytes=0 row stream byte for byte (%s)" % (size, why))
    if n >= 2:   # (P2n) drop one row from page 2: the join MUST fail
        p2 = pages[1]; m = re.search(r"<t [^<>]*/>|<d [^<>]*/>|<y [^<>]*/>", p2[root_open(p2).end():])
        if m:
            at = root_open(p2).end() + m.start(); cut = p2[:at] + p2[at + len(m.group(0)):]
            okn, _ = join([pages[0], cut] + pages[2:])
            say(not okn, "(P2n) %s B: a row dropped from page 2 makes the join FAIL — (P2) can fail" % size)
        else:
            say(False, "(P2n) %s B: page 2 has no simple row to drop; the negative control did not run" % size)
    # (P1) page 1
    p1 = pages[0]; r = root_open(p1).group(0)
    attrs = dict(re.findall(r'\s([a-z_]+)="([^"]*)"', r))
    say(attrs.get("page") == "1" and attrs.get("pages") == str(n) and "withheld_bytes" in attrs and "next" in attrs,
        "(P1) %s B page 1: page=1 pages=%s withheld_bytes=%s next= on the ROOT" % (size, attrs.get("pages"), attrs.get("withheld_bytes")))
    tail = p1[root_open(p1).end():p1.rfind("</ctx>")]
    leg = tail[trailing_comments_start(tail):]
    say("<!-- page=K of pages=N:" in leg and leg.rstrip().endswith("-->") and len(leg) > 1000,
        "(P1) %s B page 1: the whole document legend (%d B) and the page clause sit after the rows, before </ctx>" % (size, len(leg)))
    undefined = [a for a in ("page", "pages", "withheld_bytes", "next") if not re.search(r"(?<![\w-])%s=" % a, leg)]
    say(not undefined, "(P1) %s B page 1: page= pages= withheld_bytes= next= are defined inside the page%s" % (size, (" (missing %s)" % undefined) if undefined else ""))
    say("\n" not in mask(p1).rstrip("\n"), "(P1) %s B page 1: no newline outside CDATA" % size)
    say(len(p1.encode("latin-1")) < len(whole.encode("latin-1")), "(P1) %s B page 1 (%d B) is smaller than the whole answer (%d B)" % (size, len(p1), len(whole)))
    # (P3)/(P4) continuations
    env = []
    for k, d in enumerate(pages[1:], 2):
        b = d[root_open(d).end():d.rfind("</ctx>")]
        say("<!-- page=K" not in d and "<!-- ripwire" not in d and "<!-- root=" not in d,
            "(P3) %s B page %d re-sends no document legend" % (size, k))
        say(re.search(r'<about legend="ref" have="page1" dict="[^"]*" dictv="[^"]*"/></ctx>$', d) is not None,
            "(P3) %s B page %d ends <about legend=\"ref\" have=\"page1\" …/>" % (size, k))
        env.append(len(d) - len(page_body(d)) + (len(page_body(d)) - 0) * 0)
    for k, d in enumerate(pages, 1):
        a = dict(re.findall(r'\s([a-z_]+)="([^"]*)"', root_open(d).group(0)))
        if k < n:
            say(a.get("page") == str(k) and ("--page-bytes=%s:%d" % (size, k + 1)) in a.get("next", ""), "(P4) %s B page %d's next= names page %d" % (size, k, k + 1))
        else:
            say(a.get("withheld_bytes") == "0" and "next" not in a, "(P4) %s B page %d (last): withheld_bytes=0, no next=" % (size, k))
    print("  INFO  %s B: continuation-page envelopes (page bytes minus its rows): %s" % (size, ", ".join(str(e - 0) for e in [len(d) - len(page_body(d)) for d in pages[1:]])))
# (P11) the section disclosure, judged against the whole stream's own top-level blocks (comments and CDATA masked)
def blocks(st):
    """[(begin, end, name)] of the stream's top-level elements"""
    m = mask(st); out = []; depth = 0; start = 0; name = ""
    for t in re.finditer(r"<(/?)([A-Za-z_][\w-]*)[^<>]*?(/?)>", m):
        if t.group(1):
            depth -= 1
            if depth == 0: out.append((start, t.end(), name))
        elif t.group(3):
            if depth == 0: out.append((t.start(), t.end(), t.group(2)))
        else:
            if depth == 0: start, name = t.start(), t.group(2)
            depth += 1
    return out
BL = blocks(stream)
def expect(end):
    later = []
    for b, e, n in BL:
        if b >= end and n not in later: later.append(n)
    cont = [n for b, e, n in BL if b < end < e]
    return (cont[0] if cont else None), later
def disclosed(d):
    a = dict(re.findall(r'\s([a-z_]+)="([^"]*)"', root_open(d).group(0)))
    return a.get("continued"), (a.get("deferred", "").split() if "deferred" in a else [])
def p11(pages):
    okj, _ = join(pages)
    if not okj: return False, "the join failed"
    for k, d in enumerate(pages, 1):
        want = expect(ENDS[k - 1]); got = disclosed(d)
        if want != got: return False, "page %d: continued=%s deferred=%s, the stream says continued=%s deferred=%s" % (k, got[0], got[1], want[0], want[1])
    return True, ""
for size in ("3000", "6000"):
    n = int(open(os.path.join(W, "p%s.n" % size)).read())
    pages = [rd(os.path.join(W, "p%s_%d.xml" % (size, k))) for k in range(1, n + 1)]
    okd, why = p11(pages)
    nd = sum(1 for d in pages if disclosed(d)[1])
    say(okd and nd >= 1, "(P11) %s B: every page's continued=/deferred= is exactly what starts or goes on past its cut (%d page(s) defer a section) %s" % (size, nd, why))
    leg = pages[0][pages[0].rfind("<!-- page=K"):]
    say(all(re.search(r"(?<![\w-])%s=" % a, leg) for a in ("continued", "deferred")), "(P11) %s B page 1's page clause defines continued= and deferred=" % size)
    cut = re.sub(r'\sdeferred="[^"]*"', "", pages[0], count=1)
    okn, _ = p11([cut] + pages[1:])
    say(not okn, "(P11n) %s B: page 1 with its deferred= removed FAILS (P11) — the arm can fail" % size)
# (P6) --legend=first: legend-first, unpaged, a permutation of the whole answer-first answer
first = rd(os.path.join(W, "first.xml")); fr = root_open(first).group(0)
say(" page=" not in fr and " next=" not in fr, "(P6) --legend=first carries no page disclosure")
say(first.find("<!--") < first.find("<sigs"), "(P6) --legend=first serves its legend BEFORE <sigs>")
wns = rd(os.path.join(W, "whole_nosigx.xml"))
say(len(first) == len(wns) and sorted(first) == sorted(wns), "(P6) --legend=first is a permutation of the --page-bytes=0 answer under RIPWIRE_NO_SIGX=1 RIPWIRE_NO_TAIL_SAMEDIR=1 (same bytes, other order)")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1

if [ "$fail" -ne 0 ]; then echo "forpagescheck: FAILURES"; exit 1; fi
echo "forpagescheck: ALL PASS"
