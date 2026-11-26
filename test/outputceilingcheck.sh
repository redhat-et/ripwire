#!/usr/bin/env bash
# outputceilingcheck.sh — CL1: no DEFAULT call prints more than the output ceiling, and what does not fit is one pasteable
# call away and LOSSLESS.
#
#   test/outputceilingcheck.sh [BIN]     # BIN defaults to $RIPWIRE_BIN, then build/ripwire; BASE_BIN= adds the (N*) arms
#
# WHY. Claude Code's Bash tool shows a result inline "up to roughly 30,000 characters by default; past that, the path of a
# file ... plus a preview of up to the first 2,000 characters" (code.claude.com/docs tools-reference, Output limits). MEASURED
# (results/RL1_ROUTED_PAGING_1121 §6, base 36a95d732 re-measured by CL1): on GA1 DEV 9 of 11 default `--lint` answers and 2 of
# 11 `--expand=<hub>` answers printed over 30,000 characters (max 83,162 and 51,406) — answers that never reached the agent.
# src/outputceiling.h: kOutputCeilingChars = 24,000, the inline limit less 20 %.
#
# THE RULE. A default call prints <= 24,000 characters; a cut is disclosed on the root and continued by its own unit:
#   --lint     findings: shown= total= has_more= next_offset= and next="--lint … --offset=K"; the pages chain to the whole set
#   --expand   bodies: unserved_next= names the definitions that did not fit; a cut body says lines="lo-hi/T" and next= the slice
#   --for --page-bytes=0   the whole answer BY REQUEST: printed whole, plus one stderr line naming its size when over the ceiling
#   --grep     matches (PG1): shown= has_more= next_offset= and next="--grep=… --offset=K"; the pages chain to both lists whole
#   --clones   clone groups (PG1): the same window and next="--clones --offset=K"; the pages chain to every group once
#   --expand=<many definitions> (PG1): unserved_next= (selectors, or past 16 of them --offset=K) serves each definition once
#   MCP memory_recall   an explicit budget_tokens is served whole (the --page-bytes=0 rule), its visible notes saying _over_ceiling;
#              with offset it pages by body bytes (audit 2026-11-26): offset= shown_bytes= of_bytes= has_more= next_offset= on the
#              header line, and the pages' bodies rebuild the CLI --recall's whole answer
#   MCP batch  whole <q> sub-answers: offset= shown= has_more= next_offset= on the root; every <q> exactly once
#   the map   file groups (and, inside a large inventory, its ls rows): page= pages= withheld_bytes= has_more= and
#              next="--page-bytes=24000:K" (page_next= when the root already has a next=); the pages rebuild --page-bytes=0's map
#
# Arm classes (LANE_CONSTRAINTS §17): [P] a NEW bar — RED on the parent 36a95d732, its control; [C] holds on every binary;
# [N] must NOT change (needs BASE_BIN); [M] a mutation control: the same check FAILS on a doctored chain.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASE="${BASE_BIN:-}"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "outputceilingcheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "outputceilingcheck: xmllint required"; exit 2; }
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
echo "outputceilingcheck: BIN=$BIN${BASE:+ BASE_BIN=$BASE}"

BIN="$BIN" BASE="$BASE" DIR="$DIR" REPO="$ROOT" python3 - <<'PY'
import html, os, re, shlex, subprocess, sys
BIN, BASE, W, REPO = os.environ["BIN"], os.environ["BASE"], os.environ["DIR"], os.environ["REPO"]
CEILING = 24000        # src/outputceiling.h kOutputCeilingChars
bad = 0


def say(okay, msg):
    global bad
    print("  %s  %s" % ("PASS" if okay else "FAIL", msg))
    bad += 0 if okay else 1


# ── the corpus, written here ─────────────────────────────────────────────────────────────────────────────────────────
# big/    60 C++ modules x 8 functions (c-style casts and a goto each: ~2,400 --lint findings, 60 KB unpaged on 36a95d732);
#         giant.cpp: giant_body() is 1,400 lines (47 KB on 36a95d732); rows/: 40 definitions of render_row() (54 KB).
# small/  one module: every answer fits whole, so it must be byte-identical to the parent.
def w(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(s)


for m in range(60):
    fns = ["int mod%02d_fn%d(double v) {\n  int a = (int)v;\n  long b = (long)a + (long)v;\n  if (b > 7) goto out;\n"
           "  a += hub_total(a, (int)b);\nout:\n  return a;\n}\n" % (m, f) for f in range(8)]
    w(os.path.join(W, "big", "src", "mod%02d.cpp" % m), "int hub_total(int a, int b);\n" + "\n".join(fns))
body = "".join("  acc += step_value(i, %d) * %d;\n" % (k, k % 9 + 1) for k in range(1400))
w(os.path.join(W, "big", "src", "giant.cpp"), "int step_value(int i, int k);\nint giant_body(int i) {\n  int acc = 0;\n" + body + "  return acc;\n}\n")
w(os.path.join(W, "big", "src", "hub.cpp"), "int hub_total(int a, int b) { return a + b; }\nint step_value(int i, int k) { return i * k; }\n")
for r in range(40):
    rows = "".join("  out += cell_%d_%d;\n" % (r, k) for k in range(60))
    w(os.path.join(W, "big", "rows", "row%02d.cpp" % r), "int render_row(int out) {\n" + rows + "  return out;\n}\n")
# wide/   30 directories x 25 files, two functions each: a 40,655 B flagless map on 36a95d732 (rows plus a large <inv>).
for dd in range(30):
    for f in range(25):
        nxt = "process_record_%02d_%02d" % (dd, (f + 1) % 25)
        w(os.path.join(W, "wide", "pkg_component_%02d" % dd, "module_handler_%02d_%02d.c" % (dd, f)),
          "int %s(int x);\nint process_record_%02d_%02d(int x) { return x > 3 ? %s(x - 1) : x; }\n"
          "int validate_entry_%02d_%02d(int y) { return process_record_%02d_%02d(y) + 1; }\n" % (nxt, dd, f, nxt, dd, f, dd, f))
w(os.path.join(W, "small", "a.cpp"), "int helper(int x) { return (int)(x * 2.0); }\nint small_fn(int x) { return helper(x) + 1; }\n")
BIG, SMALL, WIDE = os.path.join(W, "big"), os.path.join(W, "small"), os.path.join(W, "wide")


def run(binary, root, args):
    r = subprocess.run([binary, root] + args, capture_output=True, stdin=subprocess.DEVNULL)
    return r.returncode, r.stdout.decode("utf8", "replace"), r.stderr.decode("utf8", "replace")


def rows_of(doc):
    """The document with its legend comments removed: a legend QUOTES row shapes (<f rule= p= in=>), never rows."""
    return re.sub(r"<!--.*?-->", "", doc, flags=re.S)


def well_formed(doc):
    return subprocess.run(["xmllint", "--noout", "-"], input=doc.encode(), capture_output=True).returncode == 0


def root_attr(doc, tag, name):
    m = re.search(r"<%s\b[^>]*>" % tag, doc)
    a = m and re.search(r'\s%s="([^"]*)"' % name, m.group(0))
    return html.unescape(a.group(1)) if a else None


FROW = re.compile(r"<f rule=.*?</f>", re.S)


def lint_chain(binary, root, first_args):
    """Follow next= from the default page; returns (pages, rows)."""
    pages, rows, args = [], [], first_args
    for _ in range(200):
        rc, out, _ = run(binary, root, args)
        pages.append(out)
        rows += FROW.findall(rows_of(out))
        nxt = root_attr(out, "lint", "next")
        if not nxt:
            break
        args = shlex.split(nxt)
    return pages, rows


def ceiling_ok(pages):
    return all(len(p) <= CEILING for p in pages)


def lossless(chain_rows, whole_rows):
    return chain_rows == whole_rows


# ── (L) --lint ───────────────────────────────────────────────────────────────────────────────────────────────────────
rc, whole, _ = run(BIN, BIG, ["--lint", "--limit=100000"])
whole_rows = FROW.findall(rows_of(whole))
total = int(root_attr(whole, "lint", "findings") or 0)
say(len(whole_rows) == total and total > 1000, "(L0) [C] the fixture's whole --lint set is %d rows (findings=%d; > 1,000 so the default must page)" % (len(whole_rows), total))
pages, rows = lint_chain(BIN, BIG, ["--lint"])
say(len(pages[0]) <= CEILING, "(L1) [P] a default --lint answer prints %d chars <= %d" % (len(pages[0]), CEILING))
say(len(pages) > 1 and ceiling_ok(pages), "(L2) [P] every page of the next= chain is <= %d chars (%d pages, max %d)" % (CEILING, len(pages), max(map(len, pages))))
say(lossless(rows, whole_rows), "(L3) [P] the chain's rows reproduce the whole set in order, no gap, no repeat (%d vs %d rows)" % (len(rows), len(whole_rows)))
say(root_attr(pages[-1], "lint", "has_more") == "0" and root_attr(pages[-1], "lint", "next") is None,
    "(L4) [P] the chain ends: the last page says has_more=\"0\" and names no next=")
say(all(well_formed(p) for p in pages), "(L5) [C] every page is well-formed XML (xmllint)")
say(all("\n" not in p.rstrip("\n") for p in pages), "(L6) [C] no newline inside a page (G4)")
mut_rows = rows[:5] + rows[6:]
say(not lossless(mut_rows, whole_rows), "(L7) [M] mutation: the lossless check FAILS when one row of the chain is dropped")
say(not ceiling_ok(pages[:1] + [pages[0] + "x" * CEILING]), "(L8) [M] mutation: the ceiling check FAILS on a page inflated past the ceiling")
rc2, again, _ = run(BIN, BIG, ["--lint"])
say(again == pages[0], "(L9) [C] determinism: the default page is byte-identical across two runs")

# ── (E) --expand ─────────────────────────────────────────────────────────────────────────────────────────────────────
CDATA = re.compile(r"<!\[CDATA\[(.*?)\]\]>", re.S)
rc, giant, _ = run(BIN, BIG, ["--expand=giant_body"])
say(len(giant) <= CEILING, "(E1) [P] --expand=<a 1,400-line body> prints %d chars <= %d" % (len(giant), CEILING))
# a range slice turns off the whole-FILE serving (it would add the file's other lines), so this is the whole BODY
rc, giant_whole, _ = run(BIN, BIG, ["--expand=giant_body:1-100000", "--pack-budget-bytes=10000000"])
whole_body = "".join(CDATA.findall(rows_of(giant_whole)))
got, doc, hops = "", giant, 0
while hops < 40:
    got += "".join(CDATA.findall(rows_of(doc)))
    b = re.search(r"<b\b[^>]*\struncated=\"1\"[^>]*>", rows_of(doc))
    nx = b and re.search(r'\snext="([^"]*)"', b.group(0))
    if not nx:
        break
    hops += 1
    rc, doc, _ = run(BIN, BIG, shlex.split(html.unescape(nx.group(1))))
    say(len(doc) <= CEILING, "(E2.%d) [P] the body's continuation slice prints %d chars <= %d" % (hops, len(doc), CEILING))
say(hops > 0 and got.replace("\n", "") == whole_body.replace("\n", ""),
    "(E3) [P] the cut body plus its next= slices reproduce the whole body (%d hops, %d of %d body chars)" % (hops, len(got), len(whole_body)))
rc, many, _ = run(BIN, BIG, ["--expand=render_row"])
say(len(many) <= CEILING, "(E4) [P] --expand=<a name with 40 definitions> prints %d chars <= %d" % (len(many), CEILING))
served = len(re.findall(r"<b\s", rows_of(many)))
unserved = int(root_attr(many, "ctx", "unserved_total") or 0)
say(served + unserved == 40 and unserved > 0 and root_attr(many, "ctx", "unserved_next"),
    "(E5) [P] nothing silently dropped: %d served + unserved_total=%d == 40, and unserved_next= names the rest" % (served, unserved))
say(well_formed(giant) and well_formed(many), "(E6) [C] both --expand answers are well-formed XML")

# ── (W) --for --page-bytes=0: the whole answer, by request ───────────────────────────────────────────────────────────
# The fixture's --for answers are small (its own budget bounds them), so the over-ceiling case runs on this repository's own
# source: 25,430 B on 36a95d732. If the repo's answer ever drops under the ceiling the arm still checks the "no line" half.
WQ = ["--for=paging continuation next_offset has_more truncation", "--page-bytes=0"]
rc, out, err = run(BIN, REPO, WQ)
over = len(out.encode()) > CEILING
warned = "ripwire: --page-bytes=0" in err and str(len(out.encode())) in err
say(rc == 0 and warned == over, "(W1) [P] --page-bytes=0 printed %d B; a size line on stderr iff over the ceiling (over=%s warned=%s)" % (len(out.encode()), over, warned))
if not over:
    print("  INFO  (W1) the over-ceiling half was not exercised: the repo's whole answer is under %d B" % CEILING)
rc, out2, err2 = run(BIN, SMALL, ["--for=small_fn helper", "--page-bytes=0"])
say(rc == 0 and "ripwire: --page-bytes=0" not in err2, "(W2) [C] a whole answer under the ceiling prints no size line")

# ── (M) the flagless map ─────────────────────────────────────────────────────────────────────────────────────────────
def map_content(doc):
    """The root's content, legend comments removed."""
    body = rows_of(doc)
    m = re.search(r"<r\b[^>]*>", body)
    return body[m.end():body.rindex("</r>")] if m else ""


rc, whole_map, _ = run(BIN, WIDE, ["--page-bytes=0"])
say(rc == 0 and len(whole_map) > CEILING, "(M0) [P] the fixture's whole map (--page-bytes=0, refused on the parent) is %d B, over the ceiling" % len(whole_map))
mpages, args = [], []
for _ in range(50):
    rc, out, _ = run(BIN, WIDE, args)
    mpages.append(out)
    # the page's continuation is next=, or page_next= when the map's root already carries a next= of its own
    nxt = root_attr(out, "r", "page_next") or (root_attr(out, "r", "next") if root_attr(out, "r", "has_more") == "1" else None)
    if rc != 0 or not nxt:
        break
    args = shlex.split(nxt)
say(len(mpages[0]) <= CEILING, "(M1) [P] the bare map prints %d chars <= %d" % (len(mpages[0]), CEILING))
say(len(mpages) > 1 and ceiling_ok(mpages), "(M2) [P] every page of the map's next= chain is <= %d chars (%d pages, max %d)" % (CEILING, len(mpages), max(map(len, mpages))))
joined = "".join(map_content(p) for p in mpages)
whole_content = map_content(whole_map)
for tag in set(re.findall(r"<\w+\b[^>]*>", joined)):
    if joined.count(tag) > whole_content.count(tag):   # a container re-opened across a page seam: close-then-reopen is the seam
        joined = joined.replace("</%s>%s" % (re.match(r"<(\w+)", tag).group(1), tag), "")
say(joined == map_content(whole_map), "(M3) [P] the pages' rows rebuild the whole map's rows (%d vs %d B)" % (len(joined), len(map_content(whole_map))))
say(root_attr(mpages[-1], "r", "has_more") == "0" and root_attr(mpages[-1], "r", "page_next") is None and root_attr(mpages[0], "r", "pages") == str(len(mpages)),
    "(M4) [P] the chain ends where pages= says (%s pages): has_more=\"0\", no page continuation" % root_attr(mpages[0], "r", "pages"))
say(all(well_formed(p) for p in mpages) and all("\n" not in p.rstrip("\n") for p in mpages), "(M5) [C] every map page is well-formed XML with no newline (G4)")
mut = joined.replace("<ls ", "<!-- -->", 1) if "<ls " in joined else joined[:-10]
say(mut != map_content(whole_map), "(M6) [M] mutation: the rebuild check FAILS when one row is dropped")
rc, again, _ = run(BIN, WIDE, [])
say(again == mpages[0], "(M7) [C] determinism: the first map page is byte-identical across two runs")
# (M10) every page counts the legend the compact layer writes it AFTER the cut — continuation pages included. At 24,000 B the
# fixture's pages have slack; at 6,000 B a page filled to the size went over by that legend (6,155 B, found on WP4 nushell's
# page 2 at 25,412 B before the fix).
small_pages, args = [], ["--page-bytes=6000"]
for _ in range(40):
    rc, out, _ = run(BIN, WIDE, args)
    small_pages.append(out)
    nxt = root_attr(out, "r", "page_next") or (root_attr(out, "r", "next") if root_attr(out, "r", "has_more") == "1" else None)
    if rc != 0 or not nxt:
        break
    args = shlex.split(nxt)
sj = "".join(map_content(p) for p in small_pages)
for tag in set(re.findall(r"<\w+\b[^>]*>", sj)):
    if sj.count(tag) > whole_content.count(tag):
        sj = sj.replace("</%s>%s" % (re.match(r"<(\w+)", tag).group(1), tag), "")
say(len(small_pages) > 3 and all(len(p.encode()) <= 6000 for p in small_pages) and sj == whole_content,
    "(M10) [P] at --page-bytes=6000 every page, its compact legend included, is <= 6,000 B (%d pages, max %d) and they rebuild the map"
    % (len(small_pages), max(len(p.encode()) for p in small_pages)))
rc, _, err = run(BIN, WIDE, ["--page-bytes=24000:99"])
say(rc != 0 and "page" in err, "(M8) [C] a page past the last refuses (exit %d)" % rc)
rc, _, err = run(BIN, BIG, ["--hotspots", "--page-bytes=24000"])
say(rc != 0, "(M9) [C] --page-bytes beside a report verb refuses rather than being read by nothing (exit %d)" % rc)

# ── (G) --grep: matches, paged under the ceiling (PG1) ──────────────────────────────────────────────────────────────
# grepw/  30 C modules x 5 code lines holding needle_marker, each ~330 characters, plus its extern (180 in-index hits, ~45 KB at the parent's
#         100-row page), plus 6 .txt notes x 40 lines (240 UNINDEXED hits, more than the in-index list, so the chain must
#         continue past the in-index list's end — on the parent next= stopped there and 90 unindexed rows had no page).
for m in range(30):
    lines = "".join("int gfn_%02d_%d(int a) { return needle_marker + %s; }\n" % (m, k, " + ".join("a * %d" % (j + k) for j in range(48)))
                    for k in range(5))
    w(os.path.join(W, "grepw", "src", "gmod%02d.c" % m), "extern int needle_marker;\n" + lines)
for n in range(6):
    w(os.path.join(W, "grepw", "notes", "note%d.txt" % n), "".join("note %d line %d mentions needle_marker in passing, with some padding text after it\n" % (n, k) for k in range(40)))
GREPW = os.path.join(W, "grepw")


def grep_rows(doc):
    """(list, path, line) for every hit row of one answer: the in-index list (<hit> and its folded <at> sites) and <unindexed>."""
    body = rows_of(doc)
    m = re.search(r"<grep\b[^>]*>", body)
    body = body[m.end():] if m else ""
    cut = [i for i in (body.find("<unindexed"), body.find("<enc")) if i >= 0]
    idx, rest = (body[:min(cut)], body[min(cut):]) if cut else (body, "")
    aux = rest[rest.find("<unindexed"):rest.find("</unindexed>")] if "<unindexed" in rest else ""
    out = []
    for name, part in (("idx", idx), ("aux", aux)):
        for f in re.finditer(r'<f p="([^"]*)"[^>]*>(.*?)</f>', part, re.S):
            out += [(name, f.group(1), int(l)) for l in re.findall(r'<(?:hit|at) l="(\d+)"', f.group(2))]
    return out


def grep_chain(binary, root, first_args):
    pages, rows, args = [], [], first_args
    for _ in range(60):
        rc, out, _ = run(binary, root, args)
        pages.append(out)
        rows += grep_rows(out)
        nxt = root_attr(out, "grep", "next")
        if rc != 0 or not nxt or "--offset=" not in nxt:
            break   # a cut page's next= is the next page; an uncut one's is a follow-up verb (--at=, --for=)
        args = shlex.split(nxt)
    return pages, rows


rc, gwhole, gerr = run(BIN, GREPW, ["--grep=needle_marker", "--page-bytes=0"])
gwhole_rows = grep_rows(gwhole)
say(rc == 0 and len([r for r in gwhole_rows if r[0] == "idx"]) == 180 and len([r for r in gwhole_rows if r[0] == "aux"]) == 240,
    "(G0) [P] --grep --page-bytes=0 (refused on the parent) is the whole answer: %d in-index + %d unindexed rows (180 + 240)"
    % (len([r for r in gwhole_rows if r[0] == "idx"]), len([r for r in gwhole_rows if r[0] == "aux"])))
say(len(gwhole) > CEILING and "ripwire: --page-bytes=0" in gerr, "(G0b) [P] the whole answer is %d chars, over the ceiling, and stderr names its size" % len(gwhole))
gpages, grows = grep_chain(BIN, GREPW, ["--grep=needle_marker"])
say(len(gpages[0]) <= CEILING, "(G1) [P] a default --grep answer prints %d chars <= %d" % (len(gpages[0]), CEILING))
say(len(gpages) > 1 and ceiling_ok(gpages), "(G2) [P] every page of the next= chain is <= %d chars (%d pages, max %d)" % (CEILING, len(gpages), max(map(len, gpages))))
say(sorted(grows) == sorted(gwhole_rows) and len(set(grows)) == len(grows),
    "(G3) [P] the chain's rows are the whole answer's rows, each once, both lists (%d vs %d rows, %d distinct)" % (len(grows), len(gwhole_rows), len(set(grows))))
say(all(well_formed(p) for p in gpages) and all("\n" not in p.rstrip("\n") for p in gpages), "(G4) [C] every page is well-formed XML with no newline (G4)")
say(not (sorted(grows[:7] + grows[8:]) == sorted(gwhole_rows)), "(G5) [M] mutation: the rebuild check FAILS when one row of the chain is dropped")
rc, gagain, _ = run(BIN, GREPW, ["--grep=needle_marker"])
say(gagain == gpages[0], "(G6) [C] determinism: the default page is byte-identical across two runs")
rc, glim, _ = run(BIN, GREPW, ["--grep=needle_marker", "--limit=100"])
say(len(grep_rows(glim)) >= 200 and root_attr(glim, "grep", "shown") == "100", "(G7) [C] an explicit --limit=100 is the caller's page, not cut by the ceiling (%d chars)" % len(glim))
# (G9-G11) owner ruling 192: the root's has_more=/next_offset= describe the WHOLE chain (in-index AND unindexed rows). On the
# lane before the ruling (aa305d201) the pages past the in-index list's end said has_more="0" while next= still served rows.
def window_agrees(doc):
    nxt = root_attr(doc, "grep", "next") or ""
    paging = "--offset=" in nxt
    hm, no = root_attr(doc, "grep", "has_more"), root_attr(doc, "grep", "next_offset")
    m = re.search(r"--offset=(\d+)", nxt)
    return (hm == "1") == paging and (not paging or (m and no == m.group(1)))
bad_pages = [i + 1 for i, p in enumerate(gpages) if not window_agrees(p)]
say(not bad_pages, "(G9) [P] every page's has_more= is 1 exactly when next= pages on, and next_offset= is the offset next= continues from (disagree: %s)" % bad_pages)
hm_rows, args = [], ["--grep=needle_marker"]
for _ in range(60):
    rc, out, _ = run(BIN, GREPW, args)
    hm_rows += grep_rows(out)
    if root_attr(out, "grep", "has_more") != "1":
        break
    args = ["--grep=needle_marker", "--offset=" + root_attr(out, "grep", "next_offset"), "--legend=compact"]
say(sorted(hm_rows) == sorted(gwhole_rows) and len(set(hm_rows)) == len(hm_rows),
    "(G10) [P] a loop that reads ONLY has_more=/next_offset= rebuilds the whole answer, both lists, each row once (%d vs %d rows)" % (len(hm_rows), len(gwhole_rows)))
flipped = gpages[-2].replace('has_more="1"', 'has_more="0"', 1) if len(gpages) > 1 else ""
say(len(gpages) > 1 and not window_agrees(flipped), "(G11) [M] mutation: a page whose has_more= is flipped to 0 while next= pages on IS caught")
rc, _, err = run(BIN, GREPW, ["--grep=needle_marker", "--page-bytes=6000"])
say(rc != 0 and "--grep pages by matches" in err, "(G8) [P] --page-bytes=N>0 beside --grep refuses, naming its unit (exit %d)" % rc)

# ── (K) --clones: clone groups, paged under the ceiling (PG1) ───────────────────────────────────────────────────────
# clonew/  45 distinct function shapes x 8 copies, each copy in its own deep path: 45 groups of 8 members, ~1 KB a row, so the
#          parent's 40-row head printed ~40 KB; its --offset=K alone printed every row from K, and its root named no next=.
OPS = ["+", "-", "*", "/", "%", "^", "&", "|"]
for k in range(45):
    stmts = "".join("  v = v %s w%d;\n  w%d = w%d %s %d;\n" % (OPS[(k >> (j % 6)) % 8 if j < 6 else (k * 7 + j) % 8], j % 3, j % 3, j % 3, OPS[(k + j) % 8], j + 1)
                    for j in range(12 + k % 5))
    for c in range(8):
        w(os.path.join(W, "clonew", "component_area_%02d" % c, "subsystem_handlers", "shape_%02d_copy_%d.c" % (k, c)),
          "int shape_%02d_impl_%d(int v, int w0, int w1, int w2) {\n%s  return v;\n}\n" % (k, c, stmts))
CLONEW = os.path.join(W, "clonew")
GROUP = re.compile(r"<group\b.*?</group>", re.S)


def clone_chain(binary, root, first_args):
    pages, rows, args = [], [], first_args
    for _ in range(60):
        rc, out, _ = run(binary, root, args)
        pages.append(out)
        rows += GROUP.findall(rows_of(out))
        nxt = root_attr(out, "clones", "next")
        if rc != 0 or not nxt:
            break
        args = shlex.split(nxt)
    return pages, rows


rc, cwhole, cerr = run(BIN, CLONEW, ["--clones", "--page-bytes=0"])
cwhole_rows = GROUP.findall(rows_of(cwhole))
ctotal = int(root_attr(cwhole, "clones", "total") or -1)
say(rc == 0 and len(cwhole_rows) == ctotal and ctotal >= 45, "(K0) [P] --clones --page-bytes=0 (refused on the parent) holds every group: %d rows, total=%d" % (len(cwhole_rows), ctotal))
say(len(cwhole) > CEILING and "ripwire: --page-bytes=0" in cerr, "(K0b) [P] the whole answer is %d chars, over the ceiling, and stderr names its size" % len(cwhole))
cpages, crows = clone_chain(BIN, CLONEW, ["--clones"])
say(len(cpages[0]) <= CEILING, "(K1) [P] a default --clones answer prints %d chars <= %d" % (len(cpages[0]), CEILING))
say(len(cpages) > 1 and ceiling_ok(cpages), "(K2) [P] every page of the next= chain is <= %d chars (%d pages, max %d)" % (CEILING, len(cpages), max(map(len, cpages))))
say(sorted(crows) == sorted(cwhole_rows) and len(set(crows)) == len(crows) == ctotal,
    "(K3) [P] the chain's groups are the whole answer's groups, each once (%d vs %d rows)" % (len(crows), len(cwhole_rows)))
say(crows[:len(GROUP.findall(rows_of(cpages[0])))] == cwhole_rows[:len(GROUP.findall(rows_of(cpages[0])))],
    "(K4) [P] page 1 is the head of the verb's own order (biggest first), not a re-sort")
say(all(well_formed(p) for p in cpages) and all("\n" not in p.rstrip("\n") for p in cpages), "(K5) [C] every page is well-formed XML with no newline (G4)")
say(not (sorted(crows[1:]) == sorted(cwhole_rows)), "(K6) [M] mutation: the rebuild check FAILS when one group of the chain is dropped")
rc, cagain, _ = run(BIN, CLONEW, ["--clones"])
say(cagain == cpages[0], "(K7) [C] determinism: the default page is byte-identical across two runs")
rc, _, err = run(BIN, CLONEW, ["--clones", "--page-bytes=0", "--limit=5"])
say(rc != 0 and "--clones' own page size" in err, "(K8) [P] --page-bytes=0 with --limit=N refuses: two sizes (exit %d)" % rc)

# ── (X) --expand=<a name with > 16 definitions, several per file>: the unserved chain reaches every one, once (PG1) ──
# multi/  8 files x 5 structs, each with str_of() of 40 lines: 40 definitions, five per file — so a FILE:LINE:NAME selector
#         that ignored LINE matched five, and the 16-selector list left the rest unnamed (gson toString: 19 of 33, CL1 §18).
for f in range(8):
    structs = "".join("struct Shape%d_%d {\n  int str_of(int x) {\n%s    return x;\n  }\n};\n"
                      % (f, s_, "".join("    x += %d * x + %d;\n" % (k + s_, k + f) for k in range(40))) for s_ in range(5))
    w(os.path.join(W, "multi", "src", "shapes%d.cpp" % f), structs)
MULTI = os.path.join(W, "multi")
BTAG = re.compile(r"<b\s[^>]*>")


def served_defs(doc):
    """(path, line) of every definition an --expand answer serves: a <b> body, or a whole-file <src p= sym="name:line,…"> entry."""
    body = rows_of(doc)
    out = [(re.search(r'\sp="([^"]*)"', t).group(1), int(re.search(r'\sl="(\d+)"', t).group(1))) for t in BTAG.findall(body)]
    for p_, syms in re.findall(r'<src p="([^"]*)" sym="([^"]*)"', body):
        out += [(p_, int(x.rsplit(":", 1)[1])) for x in syms.split(",") if x]
    return out


rc, xwhole, _ = run(BIN, MULTI, ["--expand=str_of", "--page-bytes=0"])
xall = served_defs(xwhole)
say(rc == 0 and len(set(xall)) == 40, "(X0) [C] --expand=str_of --page-bytes=0 serves all %d definitions (40)" % len(set(xall)))
xpages, xserved, args = [], [], ["--expand=str_of"]
for _ in range(40):
    rc, out, _ = run(BIN, MULTI, args)
    xpages.append(out)
    xserved += served_defs(out)
    nxt = root_attr(out, "ctx", "unserved_next")
    if rc != 0 or not nxt:
        break
    args = shlex.split(nxt)
say(ceiling_ok(xpages) and len(xpages) > 1, "(X1) [C] every page of the unserved_next= chain is <= %d chars (%d pages, max %d)" % (CEILING, len(xpages), max(map(len, xpages))))
say(sorted(xserved) == sorted(set(xall)), "(X2) [P] following unserved_next= serves every definition exactly once (%d served, %d distinct, of %d)"
    % (len(xserved), len(set(xserved)), len(set(xall))))
say(root_attr(xpages[-1], "ctx", "unserved_total") is None, "(X3) [C] the chain ends: the last page names nothing unserved")
one = sorted(set(xall))[7]
rc, xone, _ = run(BIN, MULTI, ["--expand=%s:%d:str_of" % one])
say(served_defs(xone) == [one], "(X4) [P] a FILE:LINE:NAME selector serves that one definition, not its %d same-file namesakes (%s)" % (len(served_defs(xone)) - 1, "%s:%d" % one))
say(not (sorted(xserved + xserved[:1]) == sorted(set(xall))), "(X5) [M] mutation: the exactly-once check FAILS when a definition is served twice")
say(all(well_formed(p) for p in xpages), "(X6) [C] every page is well-formed XML")
rc, xagain, _ = run(BIN, MULTI, ["--expand=str_of"])
say(xagain == xpages[0], "(X7) [C] determinism: the first page is byte-identical across two runs")
rc, _, err = run(BIN, MULTI, ["--expand=str_of", "--offset=40"])
say(rc != 0 and "past the 40 definitions" in err, "(X8) [P] an --offset past the last definition refuses (exit %d)" % rc)

# ── (RC/BC) the MCP verbs (research audit 2026-11-26 item 2): memory_recall and batch ────────────────────────────────
# memory_recall: a caller's budget_tokens shapes an answer past the ceiling; it pages by its body bytes, and the pages' bodies
# rebuild the CLI --recall's whole answer byte for byte. batch: sixteen bounded sub-answers made an unbounded aggregate; it pages
# by whole <q> sub-answers, and the pages carry every <q> exactly once.
import json


def mcp_session(calls, cwd=W):
    lines = [json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})]
    for i, (tool, a) in enumerate(calls):
        lines.append(json.dumps({"jsonrpc": "2.0", "id": i + 2, "method": "tools/call", "params": {"name": tool, "arguments": a}}))
    r = subprocess.run([BIN, "--mcp", "--no-cache"], input="\n".join(lines) + "\n", capture_output=True, text=True, errors="replace", cwd=cwd)
    got = {}
    for ln in r.stdout.splitlines():
        try:
            m = json.loads(ln)
        except ValueError:
            continue
        got[m.get("id")] = m
    return [got.get(i + 2, {}) for i in range(len(calls))]


def payload(m):
    c = m.get("result", {}).get("content", [])
    return c[0].get("text", "") if c else "ERROR " + m.get("error", {}).get("message", "")


DOCS = os.path.join(W, "docs")
for d in range(6):
    paras = "".join("## Cache key section %d.%d\n\nThe cache key folds the parser version, the options key and the tree digest; "
                    "eviction runs oldest first and the budget is per root. Paragraph %d of doc %d.\n\n" % (d, k, k, d) for k in range(260))
    w(os.path.join(DOCS, "design_cache_%d.md" % d), "# Cache key design %d\n\n" % d + paras)
TASK = "how does the cache key and eviction budget work"
rc, cli_whole, _ = run(BIN, DOCS, ["--recall=" + TASK, "--max-tokens=60000"])
pages, offset = [], 0
for _ in range(40):
    (m,) = mcp_session([("memory_recall", {"path": DOCS, "task": TASK, "budget_tokens": 60000, "offset": offset})])
    t = payload(m)
    pages.append(t)
    hm = re.search(r" has_more=1 next_offset=(\d+)", t.split("\n", 1)[0])
    if not hm:
        break
    offset = int(hm.group(1))
say(len(cli_whole) > 2 * CEILING, "(RC0) [C] the fixture's whole recall at budget_tokens=60000 is past the ceiling (%d B): the arms below judge a real cut" % len(cli_whole))
say(len(pages) > 1 and all(len(p.encode()) <= CEILING for p in pages),
    "(RC1) [P] memory_recall budget_tokens=60000 pages under the ceiling (%d pages, largest %d B)" % (len(pages), max(len(p.encode()) for p in pages)))
joined = "".join(p.split("\n", 1)[1] if "\n" in p else "" for p in pages)
say(len(pages) > 1 and joined == cli_whole.split("\n", 1)[1], "(RC2) [P] the pages' bodies rebuild the CLI --recall's whole body byte for byte (%d vs %d B)" % (len(joined), len(cli_whole.split("\n", 1)[1])))
(m,) = mcp_session([("memory_recall", {"path": DOCS, "task": TASK})])
rc, cli_default, _ = run(BIN, DOCS, ["--recall=" + TASK])
say(payload(m) == cli_default and " offset=" not in payload(m).split("\n", 1)[0],
    "(RC3) [C] the DEFAULT memory_recall fits and is unchanged: byte-identical to the CLI --recall (%d B)" % len(payload(m)))
(m,) = mcp_session([("memory_recall", {"path": DOCS, "task": TASK, "budget_tokens": 60000})])
whole_t = payload(m)
notes = whole_t[len(cli_whole):]
say(whole_t.startswith(cli_whole) and notes.startswith("\n_over_ceiling: ") and "offset=0" in notes,
    "(RC5) [P] an explicit budget_tokens with no offset is served WHOLE (the CLI's %d B, then a trailing _over_ceiling: line naming offset=0)" % len(cli_whole))
(m,) = mcp_session([("memory_recall", {"path": DOCS, "task": TASK, "budget_tokens": 60000, "offset": 10 ** 8})])
say("past the end" in payload(m), "(RC4) [P] an offset past the body refuses, naming where offsets come from")

queries = [{"verb": "grep", "pattern": "mod%02d_fn" % k} for k in range(16)]
bpages, offset = [], 0
for _ in range(20):
    (m,) = mcp_session([("batch", {"path": BIG, "queries": queries, "offset": offset})])
    t = payload(m)
    bpages.append(t)
    nx = root_attr(t, "batch", "next_offset")
    if root_attr(t, "batch", "has_more") != "1" or nx is None:
        break
    offset = int(nx)
qs = [int(i) for p in bpages for i in re.findall(r'<q i="(\d+)"', p)]
(whole_m,) = mcp_session([("batch", {"path": BIG, "queries": queries[:2]})])
say(len(bpages) > 1 and all(len(p.encode()) <= CEILING for p in bpages),
    "(BC1) [P] a 16-query batch pages under the ceiling (%d pages, largest %d B)" % (len(bpages), max(len(p.encode()) for p in bpages)))
say(sorted(qs) == list(range(16)), "(BC2) [P] the pages carry every <q> exactly once, in order (%s)" % qs)
say(all(well_formed(p) for p in bpages), "(BC3) [C] every batch page is well-formed XML")
say(root_attr(payload(whole_m), "batch", "offset") is None and payload(whole_m).count("<q i=") == 2,
    "(BC4) [C] a batch that fits carries no page attributes (unchanged)")

# ── (N) answers that fit are unchanged ───────────────────────────────────────────────────────────────────────────────
if BASE:
    for root, args in ((SMALL, ["--lint"]), (SMALL, ["--expand=small_fn"]), (SMALL, ["--expand=helper,small_fn"]), (BIG, ["--expand=giant_body", "--pack-budget-bytes=65536"]),
                       (SMALL, []), (BIG, []), (WIDE, ["--page-bytes=0"]), (SMALL, ["--grep=helper"]), (BIG, ["--grep=hub_total"]), (SMALL, ["--clones"]),
                       (BIG, ["--clones"]), (GREPW, ["--grep=needle_marker", "--limit=100"]), (MULTI, ["--expand=str_of", "--pack-budget-bytes=65536"])):
        _, a, _ = run(BIN, root, args)
        _, b, _ = run(BASE, root, [x for x in args if x != "--page-bytes=0"])   # the parent has no map --page-bytes: its bare map IS the whole one
        say(a == b, "(N) [N] %s on %s is byte-identical to the parent (%d B)" % (" ".join(args) or "(flagless map)", os.path.basename(root), len(a)))
    for args in (["--lint", "--limit=50"], ["--lint", "--limit=50", "--offset=50"]):
        _, a, _ = run(BIN, BIG, args)
        _, b, _ = run(BASE, BIG, args)
        nxt = root_attr(a, "lint", "next")
        say(nxt == " ".join(args[:2]) + " --offset=%d" % (50 * len(args) - 50) and re.sub(r'\snext="[^"]*"', "", rows_of(a), count=1) == rows_of(b),
            "(N) [N] %s: an explicit page is the parent's byte for byte plus the root's next=\"%s\"" % (" ".join(args), nxt))
    _, a, _ = run(BIN, REPO, WQ)
    _, b, _ = run(BASE, REPO, WQ)
    say(a == b, "(N-W) [N] --page-bytes=0's stdout is byte-identical to the parent (the size line is stderr only)")
else:
    print("  SKIP  (N) arms need BASE_BIN=<parent binary>")

# ── (O) OPEN: default calls this gate measures but does not page (reported, not asserted) ─────────────────────────
for args in (["--for=hub_total callers", "--signatures-only"],):
    _, out, _ = run(BIN, BIG, args)
    print("  INFO  (O) %s prints %d chars%s" % (" ".join(args) or "(flagless map)", len(out), "  OVER the ceiling" if len(out) > CEILING else ""))

print("outputceilingcheck: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
sys.exit(1 if bad else 0)
PY
