#!/usr/bin/env python3
"""rowlines.py — the DECODER of the row-line form of a `--for` answer (src/forrowlines.h: ROWLINES + RANKSEQ). Zero deps.

    decode(answer bytes) -> the element-form answer, byte for byte what RIPWIRE_NO_ROWLINES=1 serves (test/rowlinescheck.sh (L1)).

It keys on the DATA, never on the legend, so a continuation page or a --legend-seen answer (no legend) decodes too:
  * a <sigs>/<tail> whose only child is one CDATA is in line form: each line is a row (parse_line);
  * a <sigs> whose last attribute is rseq="1" elides sequential ranks: a <d>/<t> row with no r= has the previous row's + 1;
  * the two legend clauses, where the encoder writes them (last before </ctx>), are removed.
An element-form answer is returned unchanged, so a gate may decode unconditionally.

A gate that reads rows as ELEMENTS pipes the answer through this first and then asserts exactly what it asserted before:
    "$BIN" src --for=TASK | python3 test/rowlines.py            (stdin -> stdout)
    python3 test/rowlines.py FILE...                            (each FILE decoded in place)
    from rowlines import decode                                 (inline python: sys.path.insert(0, "<repo>/test"))
"""
import re, sys

RSEQ_CLAUSE = b"<!-- sigs rseq=1: a row with no r= has the previous row's r= plus 1 -->"
ROWS_CLAUSE = (b"<!-- sigs/tail rows are lines: 'P SYMS' is <t p=P sym=SYMS/> (a space between), then tab-separated k=v are its other attributes; "
               b"'P:L-E N k=v.. | SIG' is <d p=P l=L e=E n=N k=v..>SIG</d>; values are unescaped; a line starting with &lt; is the row verbatim; "
               b"est_tokens= may price the element form: an upper bound -->")
NAME = re.compile(rb"[A-Za-z_][A-Za-z0-9_.:-]*")
D_HEAD = re.compile(rb"(.+?):([0-9]+)(?:-([0-9]+))? (\S+)")
D_ATTR = re.compile(rb" ([A-Za-z_][A-Za-z0-9_.:-]*)=(?:\"([^\"]*)\"|([^\s\"]\S*|))(?= |$)")


def esc_text(v): return v.replace(b"&", b"&amp;").replace(b"<", b"&lt;").replace(b">", b"&gt;")
def esc_attr(v): return esc_text(v).replace(b'"', b"&quot;")
def tag(name, attrs, selfclose): return b"<" + name + b"".join(b" " + a + b'="' + v + b'"' for a, v in attrs) + (b"/>" if selfclose else b">")


def parse_pointer(line):
    f = line.split(b"\t"); p, sp, sym = f[0].partition(b" ")
    attrs = [(b"p", esc_attr(p))] + ([(b"sym", esc_attr(sym))] if sp else [])
    for x in f[1:]:
        a, _, v = x.partition(b"="); attrs.append((a, esc_attr(v)))
    return tag(b"t", attrs, True)


def parse_definition(line):
    m = D_HEAD.match(line)
    if not m: return None
    p, l, e, n = m.groups(); pos = m.end(); rest = []
    while True:
        a = D_ATTR.match(line, pos)
        if not a: break
        rest.append((a.group(1), esc_attr(a.group(2) if a.group(2) is not None else a.group(3)))); pos = a.end()
    sig = line[pos:]
    if sig and not sig.startswith(b" | "): return None
    k = 1 if rest and rest[0][0] == b"sc" else 0
    attrs = [(b"l", l)] + ([(b"e", e)] if e is not None else []) + [(b"n", esc_attr(n))] + rest[:k] + [(b"p", esc_attr(p))] + rest[k:]
    return tag(b"d", attrs, False) + esc_text(sig[3:]) + b"</d>" if sig else tag(b"d", attrs, True)


def parse_line(line):
    """verbatim XML, else a definition, else a pointer: the order the legend clause gives a reader."""
    if line.startswith(b"<"): return line
    d = parse_definition(line)
    return d if d is not None else parse_pointer(line)


def open_tag(b, i):
    """the open tag at b[i] == '<' : (name, [(attr, raw value)], selfclose, end) — strict ` name="value"` attributes."""
    m = NAME.match(b, i + 1); j = m.end(); attrs = []
    while b[j:j + 1] == b" ":
        a = NAME.match(b, j + 1); assert a and b[a.end():a.end() + 2] == b'="', b[i:i + 80]
        k = b.index(b'"', a.end() + 2); attrs.append((a.group(), b[a.end() + 2:k])); j = k + 1
    sc = b[j:j + 2] == b"/>"; assert sc or b[j:j + 1] == b">", b[i:i + 80]
    return m.group(), attrs, sc, j + (2 if sc else 1)


def top_sections(b):
    """(name, open tag start, open tag end, close tag start) of each <sigs>/<tail> that is a direct child of a <ctx> (the root, or the
    page a routed answer carries as its last child); comments and CDATA skipped."""
    out = []; i = 0; stack = []
    while i < len(b):
        if b.startswith(b"<!--", i): i = b.index(b"-->", i) + 3
        elif b.startswith(b"<![CDATA[", i): i = b.index(b"]]>", i) + 3
        elif b.startswith(b"</", i):
            name, s, e = stack.pop()
            if name in (b"sigs", b"tail") and stack and stack[-1][0] == b"ctx": out.append((name, s, e, i))
            i = b.index(b">", i) + 1
        elif b[i:i + 1] == b"<":
            name, _, sc, j = open_tag(b, i)
            if not sc: stack.append((name, i, j))
            i = j
        else: i += 1
    return out


def rows_of(body):
    """the direct children of a section body as (start, end, name|None): elements, with comments as (.., None)."""
    out = []; i = 0; depth = 0; start = 0; name = None
    while i < len(body):
        if body.startswith(b"<!--", i):
            j = body.index(b"-->", i) + 3
            if depth == 0: out.append((i, j, None))
            i = j
        elif body.startswith(b"<![CDATA[", i): i = body.index(b"]]>", i) + 3
        elif body.startswith(b"</", i):
            depth -= 1; i = body.index(b">", i) + 1
            if depth == 0: out.append((start, i, name))
        elif body[i:i + 1] == b"<":
            n, _, sc, j = open_tag(body, i)
            if depth == 0: start, name = i, n
            if sc and depth == 0: out.append((i, j, n))
            depth += 0 if sc else 1; i = j
        else: i += 1
    return out


def unrank(body):
    """RANKSEQ undone on a section body in element form."""
    out = []; at = 0; prev = 0
    for s, e, name in rows_of(body):
        if name not in (b"d", b"t"): continue
        n, attrs, sc, j = open_tag(body, s); r = dict(attrs).get(b"r")
        if r is not None: prev = int(r); continue
        prev += 1; out.append(body[at:s] + tag(n, attrs + [(b"r", str(prev).encode())], sc)); at = s + j - s
    return b"".join(out) + body[at:]


def decode(b):
    k = b.rfind(b"</ctx>")
    if k >= 0:
        head = b[:k]
        for c in (ROWS_CLAUSE, RSEQ_CLAUSE):
            if head.endswith(c): head = head[:-len(c)]
        b = head + b[k:]
    for name, s, e, c in reversed(top_sections(b)):
        otag = b[s:e]; body = b[e:c]
        if body.startswith(b"<![CDATA[") and body.endswith(b"]]>") and body.find(b"]]>") == len(body) - 3:
            body = b"".join(parse_line(l) for l in body[9:-3].split(b"\n"))
        if name == b"sigs" and otag.endswith(b' rseq="1">'):
            otag = otag[:-len(b' rseq="1">')] + b">"; body = unrank(body)
        b = b[:s] + otag + body + b[c:]
    return b


if __name__ == "__main__":
    if len(sys.argv) > 1:
        for p in sys.argv[1:]:
            d = decode(open(p, "rb").read()); open(p, "wb").write(d)
    else:
        sys.stdout.buffer.write(decode(sys.stdin.buffer.read()))
