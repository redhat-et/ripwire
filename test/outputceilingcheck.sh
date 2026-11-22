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
w(os.path.join(W, "small", "a.cpp"), "int helper(int x) { return (int)(x * 2.0); }\nint small_fn(int x) { return helper(x) + 1; }\n")
BIG, SMALL = os.path.join(W, "big"), os.path.join(W, "small")


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

# ── (N) answers that fit are unchanged ───────────────────────────────────────────────────────────────────────────────
if BASE:
    for args in (["--lint"], ["--expand=small_fn"], ["--expand=helper,small_fn"], ["--expand=giant_body", "--pack-budget-bytes=65536"]):
        root = BIG if "giant_body" in args[0] else SMALL
        _, a, _ = run(BIN, root, args)
        _, b, _ = run(BASE, root, args)
        say(a == b, "(N) [N] %s on %s is byte-identical to the parent (%d B)" % (" ".join(args), os.path.basename(root), len(a)))
    for args in (["--lint", "--limit=50"], ["--lint", "--limit=50", "--offset=50"]):
        _, a, _ = run(BIN, BIG, args)
        _, b, _ = run(BASE, BIG, args)
        nxt = root_attr(a, "lint", "next")
        say(nxt == " ".join(args[:2]) + " --offset=%d" % (50 * len(args) - 50) and re.sub(r'\snext="[^"]*"', "", rows_of(a), count=1) == rows_of(b),
            "(N) [N] %s: an explicit page is the parent's byte for byte plus the root's next=\"%s\"" % (" ".join(args), nxt))
else:
    print("  SKIP  (N) arms need BASE_BIN=<parent binary>")

# ── (O) OPEN: default calls this gate measures but CL1 did not page (reported, not asserted) ────────────────────────
for args in ([], ["--grep=hub_total"], ["--for=hub_total callers", "--signatures-only"], ["--clones"]):
    _, out, _ = run(BIN, BIG, args)
    print("  INFO  (O) %s prints %d chars%s" % (" ".join(args) or "(flagless map)", len(out), "  OVER the ceiling" if len(out) > CEILING else ""))

print("outputceilingcheck: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
sys.exit(1 if bad else 0)
PY
