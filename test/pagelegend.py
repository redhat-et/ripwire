#!/usr/bin/env python3
"""pagelegend.py — the PAGE-SCOPED legend reader of a paged `--for` answer (lane LD1, test/pagelegendcheck.sh). Zero deps.

THE RULE IT HOLDS (src/forpages.h, "WHERE THE LEGEND SITS"): a reader of page N holds page N and page 1 — page 1 because every
continuation page names it (<about legend="ref" have="page1"/>), and nothing else, because a page may be asked directly
(--page-bytes=P:N) without the pages between. So every attribute and element page N carries must be defined in PAGE N'S OWN
comments or in PAGE 1'S. Page 1 therefore must not define, in advance, what only a later page uses (that is the bytes lane LD1
moves), and a later page must carry what it uses that page 1 no longer does.

It reads ELEMENT-form pages (RIPWIRE_NO_ROWLINES=1, or a default page through rowlines.decode). Comments and CDATA are masked
before any element or attribute is read, so a served body that quotes markup defines and carries nothing.

Predicates — the generous/definitional split legendcoveragecheck.sh's header explains, used the same way:
  spelled(legend)     the names spelled `a=` with no name character before them — the house convention for an attribute's definition.
  CLAUSES             the document-legend clauses that travel with their page, each with the elements and attributes it
                      defines (its TRIGGERS). Written here independently of src/forpagelegend.h's table; the gate asserts the two
                      agree where it matters (a clause the product moves is one this table knows).
LIMIT, stated: `defined` is ELEMENT-BLIND (legendcoveragecheck.sh, "ELEMENT-BLINDNESS"): `l=` defined for <d> credits `l=` on <h>.
The element-aware arm is clause_cover(), and it covers only the clauses in CLAUSES.
"""
import re

MASK = re.compile(rb"<!--.*?-->|<!\[CDATA\[.*?\]\]>", re.S)
COMMENT = re.compile(rb"<!--.*?-->|<!\[CDATA\[.*?\]\]>", re.S)
TAG = re.compile(rb"<([A-Za-z_][\w-]*)((?:\s+[\w:-]+=\"[^\"]*\")*)\s*/?>")
ATTR = re.compile(rb"\s([\w:-]+)=\"")

# lead (the clause's opening bytes, as the dictionary spells it) -> triggers: "<name" an element, "name=" an attribute.
# A clause is NEEDED on a page whose rows carry any trigger. Short attributes (l= p= n= …, on every row kind) are never triggers:
# such a clause is needed by its ELEMENT.
CLAUSES = [
    (b"; h l= p= n=, c n= l= p=",                [b"<hops", b"<h", b"<c", b"noedge="]),
    (b"; h calls capped=1 next=",                [b"<h", b"<calls"]),
    (b"; h qword=",                              [b"qword=", b"qword_cut="]),
    (b"; fold kind=bodies:",                     [b"<fold", b"<slice", b"<skip"]),
    (b"slice members= of=:",                     [b"<fold", b"<slice", b"<skip", b"members="]),
    (b"skip bytes= next=;",                      [b"<fold", b"<slice", b"<skip", b"sigs_next="]),
    (b"; b follow_of=W:",                        [b"follow_of=", b"<follow_cut"]),
    (b"; d mem= ",                               [b"mem=", b"mem_more="]),
    (b"; c via=name:",                           [b"via="]),
    (b"; c prov=split:",                         [b"prov="]),
    (b" h value_refs=N:",                        [b"value_refs="]),
    (b"; d same_as=N:",                          [b"same_as="]),
    (b"; t tsym=",                               [b"tsym="]),
    (b"; d layer=:",                             [b"layer="]),
    (b"; iface implementors=N:",                 [b"<iface", b"implementors="]),
    (b"; field name= type= owner= rel=:",        [b"<field", b"<compose"]),
    (b"; lego/compose collapse to a counted stub", [b"<lego", b"<compose"]),
    (b"; d ctor_l= ctor_calls=",                 [b"ctor_l=", b"ctor_calls=", b"ctor_calls_more="]),
    (b"; d slot_by= functions that MAY call",    [b"slot_by=", b"slot_fields=", b"slot_by_more=", b"slot_fields_more="]),
    (b"; d slot_by= ~C,",                        [b"slot_by=", b"slot_fields="]),
    (b"; d slots= ",                             [b"slots=", b"slots_more="]),
]


def rows_of(p): return p[0] if isinstance(p, tuple) else p
def raw_of(p): return p[1] if isinstance(p, tuple) else p
# A page is its bytes, or (element-form rows, served bytes) for a row-line page: rowlines.decode gives the rows, and the comments
# are read from the page as served (the decoder removes the row-line clauses, which DEFINE <d>'s p= l= e= n= on that page).


def comments(d):
    """every comment outside CDATA, joined: what the page defines"""
    return b"\n".join(m.group(0) for m in COMMENT.finditer(raw_of(d)) if m.group(0).startswith(b"<!--"))


def carried(d):
    """(elements, attributes) the page carries, comments and CDATA masked; <about> (the ref pointer, defined by the dictionary
    it names) is not a row"""
    els, attrs = set(), set()
    for m in TAG.finditer(MASK.sub(lambda m: b" " * len(m.group(0)), rows_of(d))):
        name = m.group(1)
        if name == b"about": continue
        els.add(name)
        for a in ATTR.findall(m.group(2)): attrs.add(a)
    return els, attrs


def needs(triggers, els, attrs):
    for t in triggers:
        if t.startswith(b"<"):
            if t[1:] in els: return True
        elif t[:-1] in attrs: return True
    return False


def holds(lead, legend): return lead in legend


def attr_gaps(pages):
    """(page, attribute) pairs page N carries that neither page N's comments nor page 1's spell `a=`"""
    l1 = comments(pages[0]); out = []
    for k, d in enumerate(pages, 1):
        leg = l1 + b"\n" + comments(d) if k > 1 else l1
        _, attrs = carried(d)
        out += [(k, a.decode()) for a in sorted(attrs) if a not in spelled(leg)]
    return out


def clause_cover(pages, universe):
    """(page, lead) pairs: page N carries a trigger of a clause the answer defines somewhere (`universe`, the whole answer's
    comments), and neither page N nor page 1 holds that clause"""
    l1 = comments(pages[0]); out = []
    for k, d in enumerate(pages, 1):
        leg = l1 + b"\n" + comments(d) if k > 1 else l1
        els, attrs = carried(d)
        for lead, trig in CLAUSES:
            if holds(lead, universe) and needs(trig, els, attrs) and not holds(lead, leg):
                out.append((k, lead.decode()))
    return out


def spelled(body): return set(re.findall(rb"(?<![\w-])([\w-]+)=", body))


def document_legend(d):
    """page 1's DOCUMENT legend, the run of comments its rows end with, less the two row-line clauses (src/forrowlines.h writes them
    after paging, and the product does not count them: rowlinescheck (L1) pins both row forms to shed the same clauses)"""
    raw = raw_of(d); body = raw[:raw.rfind(b"</ctx>")]; i = len(body)
    while body[:i].endswith(b"-->"):
        j = body.rfind(b"<!--", 0, i)
        if j < 0: break
        i = j
    return b"\n".join(c for c in re.findall(rb"<!--.*?-->", body[i:], re.S) if not c.startswith((b"<!-- sigs/tail rows are lines", b"<!-- sigs rseq=1")))


def last_definer(lead, body, pages):
    """THE BACKSTOP (src/forpagelegend.h shed): page 1 keeps a clause, needed only later, while it is the one page-1 text that spells
    `a=` in its DOCUMENT legend for an attribute a page carries without needing the clause (none of its triggers) —
    element-blind, as `spelled` is. `body` is the clause's whole
    text (the dictionary's), `pages` the answer."""
    l1 = document_legend(pages[0]); trig = dict(CLAUSES)[lead]
    body = next((x for x in body if x in l1), None) if isinstance(body, list) else body   # the dialect's spelling page 1 carries
    if body is None: return False
    rest = l1.replace(body, b"", 1)
    for a in spelled(body):
        for k, d in enumerate(pages):
            el, at = carried(d)
            # a page that NEEDS the clause (one of its triggers) is owed the clause itself, not a page-1 definer
            if a in at and (k == 0 or not needs(trig, el, at)) and a not in spelled(rest): return True
    return False


def ahead_of_need(pages, bodies=None):
    """leads page 1 holds although page 1's rows need none of the clause's triggers and a later page's do: definitions sent
    IN ADVANCE (what lane LD1 moves) — less a clause that is the last definer of a name a page carries (last_definer; `bodies`:
    lead -> the clause's whole texts, from the binary's --legend-dict). [] on a one-page answer."""
    l1 = comments(pages[0]); e1, a1 = carried(pages[0]); out = []
    later = [carried(d) for d in pages[1:]]
    for lead, trig in CLAUSES:
        if holds(lead, l1) and not needs(trig, e1, a1) and any(needs(trig, e, a) for e, a in later):
            if bodies and lead in bodies and last_definer(lead, bodies[lead], pages): continue
            out.append(lead.decode())
    return out


def dictionary_bodies(dict_text):
    """lead -> the clause's whole texts (one per dialect), from `ripwire --legend-dict` (a `for` clause's line is `for: ` + the clause less its
    leading punctuation)"""
    out = {}
    for lead, _ in CLAUSES:
        key = b"for: " + lead.lstrip(b"; ")
        for line in dict_text.splitlines():   # every dialect's spelling (the MCP `for` clause and the CLI one may share a lead)
            if line.startswith(key):
                out.setdefault(lead, []).append(lead[:len(lead) - len(lead.lstrip(b"; "))] + line[len(b"for: "):])
    return out


def resent(pages):
    """(page, lead) pairs: a continuation page re-sends a clause page 1 already holds"""
    l1 = comments(pages[0]); out = []
    for k, d in enumerate(pages[1:], 2):
        own = comments(d)
        out += [(k, lead.decode()) for lead, _ in CLAUSES if holds(lead, own) and holds(lead, l1)]
    return out


# ── (LD8) a travelling clause held: priced against src/legendseen.h's never-larger rule ─────────────────────────────────────────
# "An answer the reduction would not shorten is served unchanged." So holding a page's travelling clauses leaves them out exactly
# when that shortens the page: saved = the clauses' dictionary text; cost = the in-place " [legend-seen: K held]" the reduced
# comment gains plus the answer's ONE marker (`<!-- legend-seen: K definitions … -->`, its length read off a served reduction, so a
# reworded marker re-prices itself). SEEN_BAND absorbs the page re-pricing its own est_tokens= (a digit or two); inside it either
# outcome is right, outside it exactly one is.
SEEN_BAND = 8
MARKER = re.compile(rb"<!-- legend-seen: (\d+) definitions.*?-->", re.S)
EST = re.compile(rb' est_tokens="\d+"')


def travelling_bodies(travel, bodies):
    """(lead, dictionary text) of each clause the travelling comment carries — the longest of the lead's spellings found in it"""
    out = []
    for lead, _ in CLAUSES:
        found = [b for b in bodies.get(lead, []) if b in travel]
        if found:
            out.append((lead, max(found, key=len)))
    return out


def seen_margin(travel, bodies, marker):
    """saved - cost, in bytes, of leaving `travel`'s clauses out (positive: the omission shortens the page)"""
    cl = travelling_bodies(travel, bodies)
    k = len(cl)
    m = MARKER.match(marker)
    mlen = len(marker) - len(m.group(1)) + len(str(k))
    return sum(len(b) for _, b in cl) - mlen - len(b" [legend-seen: %d held]" % k)


def seen_verdict(page, served, travel, bodies, marker):
    """(ok, why, margin): `served` is `page` asked again with its travelling clauses held"""
    margin, band = seen_margin(travel, bodies, marker), SEEN_BAND
    cl = travelling_bodies(travel, bodies)
    if served == page:
        return (margin <= band, ("served whole, as it must: omitting would cost %d B more than it saves" % -margin) if margin < -band else
                ("served whole inside the band (margin %+d B)" % margin) if margin <= band else
                ("served WHOLE though leaving the clauses out saves %d B — the omission was not made" % margin), margin)
    left = [lead.decode() for lead, _ in cl if holds(lead, comments(served))]
    whys = []
    if len(served) >= len(page):
        whys.append("the reduced page is not shorter (%d B against %d B)" % (len(served), len(page)))
    if left:
        whys.append("still carries %s" % left)
    if (b"[legend-seen: %d held]" % len(cl)) not in served:
        whys.append("its travelling comment does not refer to the %d held" % len(cl))
    if EST.sub(b"", MASK.sub(b"", served)) != EST.sub(b"", MASK.sub(b"", page)):
        whys.append("rows differ from the page served whole")
    if margin < -band:
        whys.append("reduced though omitting costs %d B more than it saves" % -margin)
    return (not whys, ("left out (%d B saved net, priced at %+d B)" % (len(page) - len(served), margin)) if not whys else "; ".join(whys), margin)


def seen_grown(page, travel, bodies, marker):
    """(LD8m) the reduction a never-larger rule must refuse, built by hand: the clauses cut, the in-place reference and the marker
    added — what a product without the rule would serve"""
    cl = travelling_bodies(travel, bodies)
    t = travel
    for _, b in cl:
        t = t.replace(b, b"", 1)
    t = t[:-len(b" -->")] + b" [legend-seen: %d held] -->" % len(cl)
    m = MARKER.match(marker)
    mk = marker[:m.start(1)] + str(len(cl)).encode() + marker[m.end(1):]
    return page.replace(travel, mk + t, 1)


# ── (LD10) a re-opened section carries its block-local legend ──────────────────────────────────────────────────────────────────
# A cut never falls right after a comment, so a section's block-local legend (the comments glued before its open tag, <!-- syms: … -->
# before <syms>) sits on the page the section starts on. A page that RE-OPENS a section the page before left open (that page's root
# says continued="NAME") carries the section's open tag and rows, so it needs that legend too: held already when it is on page 1,
# carried by the continuation page, verbatim, otherwise (src/forpages.h reopenedLegend). Element-form pages, raw bytes.
CONTINUED = re.compile(rb"<ctx\b[^>]* continued=\"([^\"]+)\"")
def glued_legend(whole, open_tag):
    """the comments immediately before `open_tag` in the whole answer, or b"" """
    at = whole.find(open_tag); start = at
    while at > 0 and whole[:start].endswith(b"-->"):
        c = whole.rfind(b"<!--", 0, start)
        if c < 0: break
        start = c
    return whole[start:at] if at > 0 else b""

def reopened_gaps(pages, whole):
    """(premise, gaps): the (page, section) re-opens whose glued legend page 1 does not hold, and those whose page lacks it too"""
    premise, gaps = [], []
    for k in range(1, len(pages)):
        m = CONTINUED.search(pages[k - 1][:pages[k - 1].find(b">") + 1])
        if not m: continue
        page = pages[k]; body = MASK.sub(lambda x: b" " * len(x.group(0)), page[page.find(b">") + 1:])
        t = re.search(rb"<" + re.escape(m.group(1)) + rb"\b[^>]*>", body)
        if not t: continue
        leg = glued_legend(whole, t.group(0))
        if not leg or leg in pages[0]: continue
        premise.append((k + 1, m.group(1).decode()))
        if leg not in page: gaps.append((k + 1, m.group(1).decode()))
    return premise, gaps
