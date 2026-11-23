#!/usr/bin/env bash
# bodypointercheck.sh — THE POINTER FORM of a `--for` answer's first page (src/forbodyptr.h; lane NB1, owner ruling 162): under
# --bodies=pointer every body page 1 would carry is the <skip p= n= l= e= bytes= next=> row that names it, and page 1 ends where it ended.
# The default (inline) is untouched until a pre-registered live check says otherwise.
# ARMS (every one NEW: red on a binary without the flag, which refuses --bodies= as unknown and leaves every pointer file empty)
#   (B0)  not vacuous: the inline twins hold fold bodies (<fold>), key bodies (<bodies of="key">) and a routed key body
#   (B1)  DEFAULT UNCHANGED: no flag == --bodies=inline, byte for byte, on page 1 of a fold and a key question, the whole answer, page 2,
#         the routed answer and every 6th test/*fix fixture; with RIPWIRE_PARENT_BIN set, the default is also the parent binary's answer
#         byte for byte on the same set (the lane runs it against the pre-flag build)
#   (B2)  pointer: no <b> element outside CDATA and comments on page 1 (default page, a spelled 9000 B page 1, the whole answer); the root says
#         body_form="pointer" and the form's legend clause is there exactly once (the inline twin has neither); a page with no <b> is
#         byte-identical to its inline twin
#   (B3)  each pointer replaces its body: the pointer rows stand where the twin's <b> and <skip> rows stood, in order, with the twin's
#         p= and n=; every pointer into a code file has e= (ER1 prints none for a doc or config file); the source lines l..e of p= ARE
#         the twin's body (first line compared without its indent, the form packBodies serves; the last may end before its line does),
#         and a twin skip row's l= stays or moves up to its declaration's first line
#   (B4)  NO REFILL: with every <b>/<skip> row and the root's est_tokens=/body_form= taken out, and the clause, the pointer page IS its
#         inline twin — the same rows, the same root (pages= withheld_bytes= next= continued=), page 1 ends at the same last row
#   (B5)  ROUTED: a routed answer (verbs_forroute.h) is byte-identical under --bodies=pointer and still carries its key body inline
#   (B6)  later pages unchanged: page 2 under --bodies=pointer is page 2 inline, byte for byte
#   (B7)  not applied: --expand and --pack-task are byte-identical with RIPWIRE_BODY_POINTERS=1 and without
#   (B8)  well formed (xmllint) and no newline outside CDATA (G4) on every pointer answer
#   (B9)  deterministic: two pointer runs byte-identical
#   (B10) FLAG OVER ENV, both directions: RIPWIRE_BODY_POINTERS=1 alone is --bodies=pointer; with it set, --bodies=inline is the default
#   (B11) refused in the house shape (exit 1, empty stdout, one stderr sentence): an unknown value, an empty value, no --for
#   (B12) est_tokens= re-priced: below the twin's, as the bytes are
#   (B13) MUTATION NEGATIVE CONTROLS: B3's check FAILS on a pointer whose e= is moved one line; B4's FAILS against the inline page 1 at
#         14000 B (a page with more rows: a refill); B2's detector FAILS on a pointer page with one body put back
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "bodypointercheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "bodypointercheck: xmllint required"; exit 2; }
PARENT="${RIPWIRE_PARENT_BIN:-}"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "bodypointercheck: BIN=$BIN${PARENT:+ PARENT=$PARENT}"
cd "$ROOT" || exit 2
unset RIPWIRE_BODY_POINTERS
FOLD="rank symbols by pagerank and serialize the map"
KEY='how does `pageEnds` cut the pages of an answer'
ROUTED='who calls `pageEnds`?'
rw(){ "$BIN" src --no-cache "$@" 2>/dev/null; }
# name, task, then argv: the default (.in), --bodies=inline (.il), --bodies=pointer (.pt)
trio(){ name="$1"; task="$2"; shift 2
    rw --for="$task" "$@" >"$WORK/$name.in"; rw --for="$task" "$@" --bodies=inline >"$WORK/$name.il"; rw --for="$task" "$@" --bodies=pointer >"$WORK/$name.pt"
    [ -n "$PARENT" ] && "$PARENT" src --no-cache --for="$task" "$@" >"$WORK/$name.pa" 2>/dev/null
    return 0; }
trio fold   "$FOLD"
trio key    "$KEY"
trio whole  "$FOLD" --page-bytes=0
trio p9000  "$FOLD" --page-bytes=9000
trio page2  "$FOLD" --page-bytes=12000:2
trio routed "$ROUTED"
rw --for="$FOLD" --page-bytes=14000 >"$WORK/fold14000.in"
rw --for="$FOLD" --bodies=pointer >"$WORK/fold.pt2"
RIPWIRE_BODY_POINTERS=1 rw --for="$FOLD" >"$WORK/env.pt"
RIPWIRE_BODY_POINTERS=1 rw --for="$FOLD" --bodies=inline >"$WORK/env.il"
rw --expand=pageEnds >"$WORK/expand.in"; RIPWIRE_BODY_POINTERS=1 rw --expand=pageEnds >"$WORK/expand.pt"
rw --pack-task="$FOLD" >"$WORK/pack.in"; RIPWIRE_BODY_POINTERS=1 rw --pack-task="$FOLD" >"$WORK/pack.pt"
n=0
for d in $( ls -d test/*fix | sort | awk 'NR % 6 == 1' ); do
    n=$(( n + 1 )); echo "$ROOT/$d" >"$WORK/t$n.root"
    "$BIN" "$d" --no-cache --for="main run init parse handle get set name value" >"$WORK/t$n.in" 2>/dev/null
    "$BIN" "$d" --no-cache --for="main run init parse handle get set name value" --bodies=inline >"$WORK/t$n.il" 2>/dev/null
    "$BIN" "$d" --no-cache --for="main run init parse handle get set name value" --bodies=pointer >"$WORK/t$n.pt" 2>/dev/null
    [ -n "$PARENT" ] && "$PARENT" "$d" --no-cache --for="main run init parse handle get set name value" >"$WORK/t$n.pa" 2>/dev/null
done
echo "$n" >"$WORK/trees.n"
for f in fold key whole p9000 page2 routed; do
    if [ -s "$WORK/$f.pt" ] && xmllint --noout "$WORK/$f.pt" 2>/dev/null; then ok "(B8) $f: well formed"; else no "(B8) $f: empty, or xmllint rejects it"; fi
done
if [ -s "$WORK/fold.pt" ] && cmp -s "$WORK/fold.pt" "$WORK/fold.pt2"; then ok "(B9) two pointer runs byte-identical"; else no "(B9) two pointer runs differ (or are empty)"; fi
same(){ [ -s "$1" ] && cmp -s "$1" "$2"; }
if same "$WORK/env.pt" "$WORK/fold.pt"; then ok "(B10) RIPWIRE_BODY_POINTERS=1 alone serves the pointer form"; else no "(B10) the variable alone did not serve --bodies=pointer's answer"; fi
if same "$WORK/env.il" "$WORK/fold.in"; then ok "(B10) with the variable set, --bodies=inline serves the default: the flag decides"; else no "(B10) --bodies=inline did not win over the variable"; fi
if same "$WORK/expand.in" "$WORK/expand.pt" && same "$WORK/pack.in" "$WORK/pack.pt"; then ok "(B7) --expand and --pack-task are byte-identical with RIPWIRE_BODY_POINTERS=1"
else no "(B7) --expand or --pack-task changed under RIPWIRE_BODY_POINTERS=1 (or is empty)"; fi
refused(){   # label, the stderr text required, then the argv
    label="$1"; want="$2"; shift 2
    "$BIN" src --no-cache "$@" >"$WORK/ref.out" 2>"$WORK/ref.err"; rc=$?
    if [ "$rc" -eq 1 ] && [ ! -s "$WORK/ref.out" ] && grep -qF -- "$want" "$WORK/ref.err" && [ "$( grep -c . "$WORK/ref.err" )" -eq 1 ]; then ok "(B11) $label: refused (exit 1, no answer, one sentence: $want)"
    else no "(B11) $label: rc=$rc, stdout $( wc -c <"$WORK/ref.out" | tr -d ' ' ) B, stderr: $( head -c 200 "$WORK/ref.err" )"; fi
}
refused "an unknown value"       "ripwire: --bodies needs inline or pointer — got 'none'" --for="$FOLD" --bodies=none
refused "an empty value"         "ripwire: --bodies= is empty — it needs inline or pointer" --for="$FOLD" --bodies=
refused "the flag without --for" "ripwire: --bodies shapes the bodies of a --for answer only" --bodies=pointer
python3 - "$WORK" "$ROOT/src" "${PARENT:+1}" <<'PY'
import os, re, sys
W, SRC, HAVE_PARENT = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
bad = 0
def rd(n):
    p = os.path.join(W, n)
    return open(p, "rb").read() if os.path.exists(p) else b""
def say(ok, msg):
    global bad
    print("  %s  %s" % ("PASS" if ok else "FAIL", msg)); bad |= not ok
CLAUSE_LEAD = b"<!-- body_form=pointer: "
TOK = re.compile(rb"<!\[CDATA\[.*?\]\]>|<!--.*?-->|<(b|skip)\b([^>]*?)(/?)>", re.S)
AT = re.compile(rb'([\w.:-]+)="([^"]*)"')
def rows(doc):
    """(start, end, kind, attrs, cdata) of every <b>…</b> and <skip/> outside CDATA and comments, in order"""
    out, i = [], 0
    while True:
        m = TOK.search(doc, i)
        if not m: return out
        if m.group(1) is None: i = m.end(); continue
        attrs = dict(AT.findall(m.group(2)))
        if m.group(1) == b"skip" or m.group(3) == b"/":
            out.append((m.start(), m.end(), m.group(1), attrs, None)); i = m.end(); continue
        j, cd = m.end(), []
        while True:
            c = doc.find(b"<![CDATA[", j); e = doc.find(b"</b>", j)
            if c != -1 and c < e:
                k = doc.find(b"]]>", c); cd.append(doc[c + 9:k]); j = k + 3; continue
            break
        out.append((m.start(), e + 4, b"b", attrs, b"".join(cd))); i = e + 4
def bodies(doc): return [r for r in rows(doc) if r[2] == b"b"]
def skeleton(doc):
    """the page with every <b>/<skip> row a placeholder, the root's est_tokens=/body_form= and the clause taken out"""
    out, last = [], 0
    for s, e, *_ in rows(doc):
        out.append(doc[last:s]); out.append(b"\0"); last = e
    t = b"".join(out) + doc[last:]
    t = re.sub(rb'<!-- body_form=pointer: .*? -->', b"", t, count=1, flags=re.S)
    end = t.index(b">")
    return re.sub(rb' (est_tokens|body_form)="[^"]*"', b"", t[:end]) + t[end:]
DOC_EXT = {b"md", b"markdown", b"rst", b"txt", b"adoc", b"html", b"htm", b"json", b"yaml", b"yml", b"toml", b"ini", b"cfg", b"xml"}
def src_lines(p, l, e, root=None):
    try: L = open(os.path.join(root or SRC, p.decode()), "rb").read().split(b"\n")
    except OSError: return None
    return L[l - 1:e]
def matches(ptr, twin, root=None):
    """the pointer's l..e are the body text of its twin row (a skip twin: same l=)"""
    a = ptr[3]
    if twin[3].get(b"p") != a.get(b"p") or twin[3].get(b"n") != a.get(b"n") or not a.get(b"l"): return False
    if not a.get(b"e"): return a[b"p"].rsplit(b".", 1)[-1].lower() in DOC_EXT   # e= absent only where ER1 prints none: not a code file
    l, e = int(a[b"l"]), int(a[b"e"])
    if twin[2] == b"skip": return l <= int(twin[3].get(b"l", b"0")) and e >= int(twin[3].get(b"l", b"0"))   # l= may move up to the declaration
    got = src_lines(a[b"p"], l, e, root)
    want = twin[4].split(b"\n")
    if len(want) > 1 and want[-1] == b"": want = want[:-1]   # a span whose last byte is its newline (a #define): e= is that line
    if got is None or not want or len(got) != len(want) or twin[3].get(b"truncated"): return False
    if twin[3].get(b"scrubbed"): return True   # the twin's text is lossy (invalid UTF-8 or C0 scrubbed): its line count is what can match
    if len(want) == 1:
        return want[0] in got[0]   # a one-line body: the definition's text within its line
    # the first line may be served without its indent, the last may end before the line does (a `;` or comment after the span)
    return (got[0] == want[0] or got[0].lstrip() == want[0]) and got[1:-1] == want[1:-1] and got[-1].startswith(want[-1])
def has_root_attr(doc, k): return (b" " + k + b'="') in doc[:doc.index(b">")] if doc.startswith(b"<ctx") else False
def est(doc):
    m = re.search(rb' est_tokens="(\d+)"', doc[:doc.index(b">")]) if doc.startswith(b"<ctx") else None
    return int(m.group(1)) if m else None

inl = {k: rd(k + ".in") for k in ("fold", "key", "whole", "p9000", "page2", "routed")}
ptr = {k: rd(k + ".pt") for k in inl}
# (B0)
fold_b = [r for r in bodies(inl["fold"])]
key_b = re.search(rb'<bodies of="key"[^>]*>.*?</bodies>', inl["key"], re.S)
rt_b = re.search(rb'<bodies of="key"[^>]*>.*?</bodies>', inl["routed"], re.S)
say(len(fold_b) >= 2 and b"<fold " in inl["fold"] and key_b is not None and bodies(key_b.group(0)) and rt_b is not None and bodies(rt_b.group(0))
    and b"<route " in inl["routed"],
    "(B0) the inline twins hold %d fold-page bodies, a key body, and a routed answer's key body" % len(fold_b))
# (B1)
T = int(rd("trees.n").strip() or b"0")
pairs = [(k + ".in", k + ".il") for k in inl] + [("t%d.in" % k, "t%d.il" % k) for k in range(1, T + 1)]
same_il = [a for a, b in pairs if rd(a) and rd(a) == rd(b)]
say(len(same_il) == len(pairs), "(B1) no flag == --bodies=inline byte for byte on %d of %d answers (6 questions + %d fixture trees)" % (len(same_il), len(pairs), T))
if HAVE_PARENT:
    pp = [(k + ".in", k + ".pa") for k in inl] + [("t%d.in" % k, "t%d.pa" % k) for k in range(1, T + 1)]
    same_pa = [a for a, b in pp if rd(a) == rd(b)]
    say(len(same_pa) == len(pp), "(B1) the default is the PARENT binary's answer byte for byte on %d of %d" % (len(same_pa), len(pp)))
else:
    print("  SKIP  (B1) parent byte-identity: set RIPWIRE_PARENT_BIN to the pre-flag build to run it")
# (B2)
for k in ("fold", "key", "whole", "p9000"):
    p, i = ptr[k], inl[k]
    say(bool(p) and not bodies(p) and has_root_attr(p, b"body_form") and p.count(CLAUSE_LEAD) == 1 and bodies(i)
        and not has_root_attr(i, b"body_form") and CLAUSE_LEAD not in i,
        "(B2) %s: no <b> outside CDATA (twin: %d), body_form=\"pointer\" on the root, the clause once" % (k, len(bodies(i))))
tree_pt = [k for k in range(1, T + 1) if rd("t%d.pt" % k).startswith(b"<ctx")]
say(len(tree_pt) > 0 and all(not bodies(rd("t%d.pt" % k)) for k in tree_pt)
    and all(rd("t%d.pt" % k) == rd("t%d.in" % k) for k in tree_pt if not bodies(rd("t%d.in" % k))),
    "(B2) %d fixture trees answered under --bodies=pointer: none holds a <b> outside CDATA; each with no body inline is byte-identical" % len(tree_pt))
# (B3)
def b3(p, i, root=None):
    pr, ir = rows(p), rows(i)
    return len(pr) == len(ir) and len(pr) > 0 and all(r[2] == b"skip" for r in pr) and all(matches(a, b, root) for a, b in zip(pr, ir))
for k in ("fold", "key", "whole", "p9000"):
    say(b3(ptr[k], inl[k]), "(B3) %s: %d pointer rows, each in its twin row's place with its p= n=, e= on every one, l..e the body it replaced" % (k, len(rows(ptr[k]))))
tree_ok = [k for k in tree_pt if b3(rd("t%d.pt" % k), rd("t%d.in" % k), rd("t%d.root" % k).decode().strip()) or (not rows(rd("t%d.in" % k)) and rd("t%d.pt" % k) == rd("t%d.in" % k))]
say(len(tree_ok) == len(tree_pt) and sum(1 for k in tree_pt if bodies(rd("t%d.in" % k))) >= 3,
    "(B3) fixture trees: %d of %d hold the rule (a tree with no body is byte-identical); %d had bodies inline"
    % (len(tree_ok), len(tree_pt), sum(1 for k in tree_pt if bodies(rd("t%d.in" % k)))))
# (B4)
for k in ("fold", "key", "whole", "p9000"):
    say(bool(ptr[k]) and skeleton(ptr[k]) == skeleton(inl[k]), "(B4) %s: with the body rows and est_tokens= aside, the pointer page IS its inline twin (no refill)" % k)
# (B5) (B6)
say(bool(ptr["routed"]) and ptr["routed"] == inl["routed"] and rt_b is not None, "(B5) the routed answer is byte-identical under --bodies=pointer, its key body inline")
say(bool(ptr["page2"]) and ptr["page2"] == inl["page2"] and b' page="2"' in inl["page2"][:inl["page2"].index(b">")], "(B6) page 2 under --bodies=pointer is page 2 inline, byte for byte")
# (B8) G4
def nl_outside(b): return b"\n" in re.sub(rb"<!\[CDATA\[.*?\]\]>", b"", b.rstrip(b"\n"), flags=re.S)
say(not any(nl_outside(b) for b in ptr.values()), "(B8) no newline outside CDATA in any pointer answer (G4)")
# (B12)
say(all(est(ptr[k]) is not None and est(inl[k]) is not None and est(ptr[k]) < est(inl[k]) and len(ptr[k]) < len(inl[k]) for k in ("fold", "key", "whole")),
    "(B12) est_tokens= re-priced below the twin's on fold/key/whole (%s)" % ", ".join("%s<%s" % (est(ptr[k]), est(inl[k])) for k in ("fold", "key", "whole")))
# (B13) mutation controls
m = re.search(rb'(<skip [^>]*? e=")(\d+)(")', ptr["fold"])
moved = ptr["fold"][:m.start(2)] + str(int(m.group(2)) + 1).encode() + ptr["fold"][m.end(2):] if m else b""
say(bool(moved) and not b3(moved, inl["fold"]), "(B13) [negative control] B3 fails on a pointer whose e= is moved one line")
say(rd("fold14000.in") != inl["fold"] and skeleton(ptr["fold"]) != skeleton(rd("fold14000.in")), "(B13) [negative control] B4 fails against the 14000 B inline page 1 (a refilled page)")
fb = fold_b[0] if fold_b else None
put_back = ptr["fold"].replace(b"</ctx>", inl["fold"][fb[0]:fb[1]] + b"</ctx>", 1) if fb else b""
say(bool(put_back) and len(bodies(put_back)) == 1, "(B13) [negative control] B2's detector finds a body put back into a pointer page")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1
[ "$fail" -eq 0 ] && echo "bodypointercheck: PASS" || echo "bodypointercheck: FAIL"
exit "$fail"
