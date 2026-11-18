#!/usr/bin/env python3
"""importrowrecon.py — the reconstruction half of test/importrowshortcheck.sh.

An --impact importer row was printed `<f via="import" p="P" lazy="0|1"/>`. `via="import"` is a string literal on every such
row and `lazy="0"` is the default arm of a two-valued flag, so the row is now `<f p="P"/>`, with `lazy="1"` only when it is 1.
This file puts the dropped bytes back from the delivered answer ALONE and compares the result with a reference:

  xml NEW GOLD WANT      rebuild(NEW) == GOLD over the WHOLE <impact> element (LOSSLESS); no NEW row still carries the dropped
                         bytes (SHORT); at least WANT importer rows were read (FLOOR)
  json NEW JSON WANT     the same rows against the --json import_reach array, a different emitter in the same binary
  count NEW              rows=N lazy=K short=S  (the non-vacuity read)

The rule is context-free: it looks at one row and nothing else. Exit 0 = holds; 1 = a named failure, one per line.
"""
import json
import re
import sys

COMMENT = re.compile(r"<!--.*?-->", re.S)
ROW = re.compile(r"<f ([^<>]*?)/>")
SHORT_ROW = re.compile(r'^p="([^"]*)"( lazy="1")?$')


def body(path):
    with open(path, encoding="utf-8") as f:
        doc = COMMENT.sub("", f.read())
    i = doc.find("<impact ")
    return doc[i:] if i >= 0 else ""


def rebuild_row(attrs):
    """One delivered row -> the row the pre-change binary printed. A row not in the short form is returned unchanged."""
    m = SHORT_ROW.match(attrs)
    if not m:
        return "<f " + attrs + "/>"
    return '<f via="import" p="%s" lazy="%s"/>' % (m.group(1), "1" if m.group(2) else "0")


def rebuild(doc):
    """The whole document with every importer row rebuilt; the text between two rows is copied through untouched."""
    out, at = [], 0
    for m in ROW.finditer(doc):
        out.append(doc[at:m.start()])
        out.append(rebuild_row(m.group(1)))
        at = m.end()
    out.append(doc[at:])
    return "".join(out)


def rows(doc):
    return [m.group(1) for m in ROW.finditer(doc)]


def cmd_xml(new, gold, want):
    n, g = body(new), body(gold)
    bad = []
    got = rows(n)
    if len(got) < want:
        bad.append("FLOOR: %d importer row(s) read, want at least %d" % (len(got), want))
    for i, a in enumerate(got):
        if 'via="' in a or 'lazy="0"' in a:
            bad.append("SHORT ROW %d: still carries the dropped bytes: <f %s/>" % (i + 1, a))
        elif not SHORT_ROW.match(a):
            bad.append("SHAPE ROW %d: not <f p=\"…\"[ lazy=\"1\"]/>: <f %s/>" % (i + 1, a))
    gr = ["<f " + a + "/>" for a in rows(g)]
    rr = [rebuild_row(a) for a in got]
    if len(gr) != len(rr):
        bad.append("LOSSLESS COUNT: %d row(s) rebuilt, the reference holds %d" % (len(rr), len(gr)))
    for i, (a, b) in enumerate(zip(rr, gr)):
        if a != b:
            bad.append("LOSSLESS ROW %d: rebuilt %s, reference %s" % (i + 1, a, b))
    if rebuild(n) != g and not any(x.startswith("LOSSLESS") for x in bad):
        bad.append("LOSSLESS ELEMENT: the rows rebuild, but the rest of the <impact> element moved")
    if bad:
        print("\n".join(bad))
        return 1
    print("%d row(s) rebuilt byte for byte; the whole <impact> element (%d B) equals the reference; %d B shorter"
          % (len(got), len(g.encode()), len(g.encode()) - len(n.encode())))
    return 0


def cmd_json(new, jpath, want):
    got = rows(body(new))
    try:
        with open(jpath, encoding="utf-8") as f:
            ref = json.load(f)["import_reach"]
    except (OSError, ValueError, KeyError) as e:
        print("JSON: no import_reach array to read (%s)" % e)
        return 1
    bad = []
    if len(got) < want:
        bad.append("FLOOR: %d importer row(s) read, want at least %d" % (len(got), want))
    if len(got) != len(ref):
        bad.append("JSON COUNT: %d XML row(s), %d import_reach entr(ies)" % (len(got), len(ref)))
    for i, (a, r) in enumerate(zip(got, ref)):
        if r.get("via") != "import":
            bad.append("JSON ROW %d: the reference's via is %r, so the dropped literal is not a constant" % (i + 1, r.get("via")))
        want_row = '<f via="import" p="%s" lazy="%s"/>' % (r.get("p"), "1" if r.get("lazy") else "0")
        if rebuild_row(a) != want_row:
            bad.append("JSON ROW %d: rebuilt %s, --json says %s" % (i + 1, rebuild_row(a), want_row))
    if bad:
        print("\n".join(bad))
        return 1
    print("%d row(s) agree with --json import_reach (path, lazy, via)" % len(got))
    return 0


def cmd_count(new):
    got = rows(body(new))
    print("rows=%d lazy=%d short=%d" % (len(got), sum(1 for a in got if a.endswith(' lazy="1"')), sum(1 for a in got if SHORT_ROW.match(a))))
    return 0


def main(argv):
    if len(argv) >= 5 and argv[1] == "xml":
        return cmd_xml(argv[2], argv[3], int(argv[4]))
    if len(argv) >= 5 and argv[1] == "json":
        return cmd_json(argv[2], argv[3], int(argv[4]))
    if len(argv) >= 3 and argv[1] == "count":
        return cmd_count(argv[2])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
