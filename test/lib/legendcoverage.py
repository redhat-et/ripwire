#!/usr/bin/env python3
"""legendcoverage.py — the bounded head-comment scan, and the python twin of legendcoverage.sh.

Why a shared implementation rather than a regex at each site: see the header of legendcoverage.sh. The
short version is that `<!--.*-->` is greedy, ripwire's output is minified onto one line, and `--expand`
and `--for` answers carry ripwire's own C++ in CDATA — which contains comment-shaped text. A
document-wide scan therefore reads payload as legend. This walks only the two runs where a legend can
live, exactly as src/legenddict.h's headComments() does, and stops at the first byte that is neither a
comment nor whitespace.

Used two ways:
    python3 legendcoverage.py --head-comments DOC      one comment per line, for the bash helper
    from legendcoverage import head_comments, defines   for the python gates
"""
import argparse
import re
import sys

_ROOT = re.compile(r"<([A-Za-z_][A-Za-z0-9_-]*)\b[^>]*>")
_WS = " \n\r\t"


def _run(doc: str, lo: int, hi: int) -> list[str]:
    """Comments in the contiguous comment/whitespace run starting at `lo`, stopping before `hi`."""
    out: list[str] = []
    i = lo
    while i < hi:
        if doc.startswith("<!--", i):
            j = doc.find("-->", i)
            if j < 0 or j + 3 > hi:
                break
            out.append(doc[i:j + 3])
            i = j + 3
        elif doc[i] in _WS:
            i += 1
        else:
            break
    return out


def root_span(doc: str):
    """(start, end) of the root element's open tag, stepping over any leading comments or XML decl.

    The root is NOT at offset 0: compactlegend.h's families emit their legend and data comments BEFORE
    the root, while --for and --expand put theirs just inside it. A scan anchored at offset 0 reads
    every compactlegend.h verb as "not XML" and skips it, which is how an earlier instrument silently
    measured 2 of 13 legend families and reported a pass.
    """
    i, n = 0, len(doc)
    while i < n:
        while i < n and doc[i] in _WS:
            i += 1
        if doc.startswith("<!--", i):
            j = doc.find("-->", i)
            if j < 0:
                return None
            i = j + 3
            continue
        if doc.startswith("<?", i):
            j = doc.find("?>", i)
            if j < 0:
                return None
            i = j + 2
            continue
        break
    m = _ROOT.match(doc, i)
    return (m.start(), m.end()) if m else None


def head_comments(doc: str) -> list[str]:
    """Every comment in the two head runs: before the root's open tag, and immediately after it."""
    span = root_span(doc)
    if span is None:
        # Not one XML document (a refusal, JSON, prose). Returning [] rather than guessing is the honest
        # answer; a caller that needs to distinguish "no legend" from "not XML" should call root_span.
        return []
    start, end = span
    close = doc.rfind("</")
    limit = close if close > end else len(doc)
    return _run(doc, 0, start) + _run(doc, end, limit)


def defines(doc: str, attr: str, dictionary: str) -> str:
    """Where `attr` is documented for this answer: "legend", "dict" or "nowhere"."""
    needle = attr + "="
    if any(needle in c for c in head_comments(doc)):
        return "legend"
    if needle in dictionary:
        return "dict"
    return "nowhere"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--head-comments", metavar="DOC")
    a = ap.parse_args()
    if not a.head_comments:
        ap.error("nothing to do: pass --head-comments DOC")
    with open(a.head_comments, encoding="utf-8", errors="replace") as fh:
        for c in head_comments(fh.read()):
            print(c)
    return 0


if __name__ == "__main__":
    sys.exit(main())
