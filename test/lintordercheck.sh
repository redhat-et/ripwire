#!/usr/bin/env bash
# lintordercheck.sh — LT1: --lint's page 1 shows the most important findings first, its zero-count rules are ONE
# disclosed row, and --page-bytes=0 is one "whole answer" switch on every verb the output ceiling pages.
#
#   test/lintordercheck.sh [BIN]     # BIN defaults to $RIPWIRE_BIN, then build/ripwire; BASE_BIN= adds the (N*) arms
#
# WHY. The output ceiling (src/outputceiling.h) made a default --lint answer a byte-budgeted page of findings. Its order was
# (file path, offset, rule, ...), so page 1 was whatever sorts first by PATH. MEASURED on GA1 DEV ga-eslint-01 (parent
# dfc8d95fd): 571 findings, 99 on page 1, the first a do-while in Makefile.js, then 10 rows of a vendored ponyfill under
# docs/src/assets/js/ — and 31 of the 39 <rule> rows said count="0".
#
# THE RULE (src/verbs_lint.h sortLintRows, the note above it). Rows sort by
#   (1) the file's TIER: a shipped-not-authored file (a tool/vendored/generated path, a minified file, a bundle) LAST
#   (2) rule SEVERITY, error > warn > info (the lint catalog; a user rule's own sev=)
#   (3) the file's CENTRALITY: source before a test/bench/fixture path (filter.h pathTierOf), then its place in the map's
#       PageRank order (its best symbol's rank)
#   (4) file path, offset, rule, sev, text — the old total order, kept as the tie-break
# Every rule that found nothing is folded into ONE <zero_rules n= ran= inert=> row; the rows with a count stay first.
# --page-bytes=0 is the whole answer on --lint, --expand, the bare map and --for; over the ceiling one stderr line says so.
#
# Arm classes (LANE_CONSTRAINTS §17): [P] a NEW bar — RED on the parent dfc8d95fd; [C] holds on every binary; [N] must NOT
# change against the parent (needs BASE_BIN); [M] a mutation control: the same check FAILS on a doctored input.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASE="${BASE_BIN:-}"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "lintordercheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "lintordercheck: xmllint required"; exit 2; }
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
echo "lintordercheck: BIN=$BIN${BASE:+ BASE_BIN=$BASE}"

BIN="$BIN" BASE="$BASE" DIR="$DIR" REPO="$ROOT" python3 - <<'PY'
import html, os, re, shlex, subprocess, sys
BIN, BASE, W, REPO = os.environ["BIN"], os.environ["BASE"], os.environ["DIR"], os.environ["REPO"]
CEILING = 24000        # src/outputceiling.h kOutputCeilingChars
WHOLE_LINE = "--page-bytes=0: this whole answer is"
bad = 0


def say(okay, msg):
    global bad
    print("  %s  %s" % ("PASS" if okay else "FAIL", msg))
    bad += 0 if okay else 1


def w(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(s)


# ── the corpus, written here ─────────────────────────────────────────────────────────────────────────────────────────
# lo/   a_leaf.cpp      an UNCALLED file with an error finding (strcpy); it sorts FIRST by path
#       lib/packed.c    a minified file (one 800 B line, whitespace under 7 %) with error findings — --skipped's minified-suspect
#       min/bundle.cpp  a generated-asset path (filter.h kDemoOrGeneratedDirs "min/") with an error finding
#       src/core.cpp    the CENTRAL file: 40 modules call it; one error (strcpy) and one warn (a C-style cast)
#       src/userNN.cpp  40 modules x 15 magic numbers (info): ~600 rows, so the default page must cut
#       tests/helper_test.cpp  a TEST file (filter.h pathTierOf TestOrBench) with an error finding
# ex/   giant.cpp: giant_body() is 1,400 lines — a bare --expand cuts it under the ceiling
# wide/ 750 tiny C files — a bare map over the ceiling
# small/ one file: every answer fits
LO, EX, WIDE, SMALL = (os.path.join(W, d) for d in ("lo", "ex", "wide", "small"))
w(os.path.join(LO, "a_leaf.cpp"), "#include <cstring>\nvoid leaf_copy(char* d, const char* s) { strcpy(d, s); }\n")
w(os.path.join(LO, "lib", "packed.c"), "#include <string.h>\n" + "".join("void p%02d(char*d,const char*s){strcpy(d,s);strcat(d,s);}" % k for k in range(14)) + "\n")
w(os.path.join(LO, "tests", "helper_test.cpp"), "#include <cstring>\nvoid helper_copy(char* d, const char* s) { strcpy(d, s); }\n")
w(os.path.join(LO, "min", "bundle.cpp"), "#include <cstring>\nvoid bundle_copy(char* d, const char* s) { strcpy(d, s); }\n")
w(os.path.join(LO, "src", "core.cpp"), "#include <cstring>\nvoid core_copy(char* d, const char* s) { strcpy(d, s); }\n"
  "int core_cast(double v) { return (int)v; }\n")
for m in range(40):
    fns = "".join("int user%02d_f%02d(int x) {\n  core_copy(0, 0);\n  return core_cast(x) * %d + %d;\n}\n" % (m, k, 1000 + k, 7000 + m) for k in range(8))
    w(os.path.join(LO, "src", "user%02d.cpp" % m), "void core_copy(char* d, const char* s);\nint core_cast(double v);\n" + fns)
body = "".join("  acc += step_value(i, %d);\n" % k for k in range(1400))
w(os.path.join(EX, "giant.cpp"), "int step_value(int i, int k);\nint giant_body(int i) {\n  int acc = 0;\n" + body + "  return acc;\n}\n"
  "int step_value(int i, int k) { return i + k; }\n")
for dd in range(30):
    for f in range(25):
        nxt = "process_record_%02d_%02d" % (dd, (f + 1) % 25)
        w(os.path.join(WIDE, "pkg_component_%02d" % dd, "module_handler_%02d_%02d.c" % (dd, f)),
          "int %s(int x);\nint process_record_%02d_%02d(int x) { return x > 3 ? %s(x - 1) : x; }\n"
          "int validate_entry_%02d_%02d(int y) { return process_record_%02d_%02d(y) + 1; }\n" % (nxt, dd, f, nxt, dd, f, dd, f))
w(os.path.join(SMALL, "a.cpp"), "#include <cstring>\nint helper(int x) { return (int)(x * 2.0); }\nvoid cp(char* d) { strcpy(d, \"x\"); }\n")
DEMOTED = ("lib/packed.c", "min/bundle.cpp")


def run(binary, root, args):
    r = subprocess.run([binary, root] + args, capture_output=True, stdin=subprocess.DEVNULL)
    return r.returncode, r.stdout.decode("utf8", "replace"), r.stderr.decode("utf8", "replace")


def rows_of(doc):
    return re.sub(r"<!--.*?-->", "", doc, flags=re.S)


def root_attr(doc, tag, name):
    m = re.search(r"<%s\b[^>]*>" % tag, rows_of(doc))
    a = m and re.search(r'\s%s="([^"]*)"' % name, m.group(0))
    return html.unescape(a.group(1)) if a else None


FROW = re.compile(r"<f rule=.*?</f>", re.S)
SEV_RANK = {"error": 0, "warn": 1, "info": 2}
_, catalog, _ = run(BIN, SMALL, ["--lint-catalog"])
SEV = {m.group(1): m.group(2) for m in re.finditer(r'<rule name="([^"]+)" sev="([^"]+)"', rows_of(catalog))}
say(len(SEV) >= 30 and set(SEV.values()) == {"error", "warn", "info"}, "(K0) [C] the lint catalog names %d rules over error/warn/info" % len(SEV))


def row_key(r):
    rule = re.search(r'rule="([^"]*)"', r).group(1)
    path = re.search(r'p="([^"]*):\d+"', r).group(1)
    return rule, path


def order_ok(rows):
    """The tier and severity keys: every demoted row after every authored one; severity non-increasing inside each tier."""
    keys = [(row_key(r)[1] in DEMOTED, SEV_RANK.get(SEV.get(row_key(r)[0], ""), 3)) for r in rows]
    return all(keys[i] <= keys[i + 1] for i in range(len(keys) - 1)) and len(keys) > 0


def lint_chain(binary, root, first_args):
    pages, rows, args = [], [], first_args
    for _ in range(200):
        _, out, _ = run(binary, root, args)
        pages.append(out)
        rows += FROW.findall(rows_of(out))
        nxt = root_attr(out, "lint", "next")
        if not nxt:
            break
        args = shlex.split(nxt)
    return pages, rows


def zero_fold_ok(doc):
    """No <rule> row says count="0" (a compiled="0" user rule excepted); one <zero_rules> row names the rest, and the
    named rules plus the counted rows are exactly the catalog, with no name twice."""
    body = rows_of(doc)
    rules = re.findall(r"<rule [^>]*/>", body)
    counted = [re.search(r'name="([^"]*)"', r).group(1) for r in rules]
    zero_rows = [r for r in rules if ' count="0"' in r and ' compiled="0"' not in r]
    folds = re.findall(r"<zero_rules\b[^>]*/>", body)
    if zero_rows or len(folds) != 1:
        return False
    attr = lambda k: (re.search(r'\s%s="([^"]*)"' % k, folds[0]) or [None, ""])[1]
    ran, inert = [x for x in attr("ran").split(",") if x], [x for x in attr("inert").split(",") if x]
    names = counted + ran + inert
    inert_root = int(root_attr(doc, "lint", "inert_rules") or 0)
    return len(names) == len(set(names)) and set(names) == set(SEV) and attr("n") == str(len(ran) + len(inert)) and inert_root == len(inert)


# ── (A) the order: page 1 starts with the central file's highest-severity finding ─────────────────────────────────────
rc, page1, _ = run(BIN, LO, ["--lint"])
p1rows = FROW.findall(rows_of(page1))
first = row_key(p1rows[0]) if p1rows else ("", "")
say(first == ("unsafe-c-fn", "src/core.cpp"), "(A1) [P] page 1's first finding is the central file's error-severity row (got rule=%s p=%s)" % first)
rc, whole, err_whole = run(BIN, LO, ["--lint", "--page-bytes=0"])
wrows = FROW.findall(rows_of(whole))
total = int(root_attr(whole, "lint", "findings") or 0)
say(rc == 0 and len(wrows) == total and total > 300, "(A2) [P] --lint --page-bytes=0 serves the whole set: %d rows of findings=%d (rc=%d)" % (len(wrows), total, rc))
say(order_ok(wrows), "(A3) [P] in the whole answer every minified/generated-path row sorts after every authored row, severity non-increasing within each")
demoted_first = next((i for i, r in enumerate(wrows) if row_key(r)[1] in DEMOTED), -1)
say(demoted_first == len(wrows) - sum(1 for r in wrows if row_key(r)[1] in DEMOTED) and demoted_first > 0,
    "(A4) [P] the demoted files' rows are exactly the tail (first at %d of %d)" % (demoted_first, len(wrows)))
errors = [row_key(r)[1] for r in wrows if row_key(r)[0] == "unsafe-c-fn" and row_key(r)[1] not in DEMOTED]
say(errors[:2] == ["src/core.cpp", "a_leaf.cpp"], "(A5) [P] among equal tier and severity, the central file precedes the uncalled one (%s)" % errors[:2])
err_paths = [row_key(r)[1] for r in wrows if row_key(r)[0] == "unsafe-c-fn"]
first_warn = next((i for i, r in enumerate(wrows) if SEV.get(row_key(r)[0]) == "warn"), -1)
test_at = next((i for i, r in enumerate(wrows) if row_key(r)[1] == "tests/helper_test.cpp"), -1)
say(err_paths[:3] == ["src/core.cpp", "a_leaf.cpp", "tests/helper_test.cpp"] and 0 <= test_at < first_warn,
    "(A7) [P] a test file's error row follows the source files' error rows and precedes every warn row (%s; test at %d, first warn at %d)" % (err_paths[:3], test_at, first_warn))
_, health, _ = run(BIN, LO, ["--skipped"])
say('p="lib/packed.c" why="minified-suspect"' in health, "(A6) [C] the fixture's lib/packed.c IS --skipped's minified-suspect (the house's own verdict, reused)")

# ── (B) zero-count rules fold into one disclosed row ─────────────────────────────────────────────────────────────────
say(zero_fold_ok(page1), "(B1) [P] page 1: no count=\"0\" <rule> row; one <zero_rules> names every other catalog rule, n= and inert= agree")
rows_with_count = re.findall(r'<rule name="[^"]*" count="[1-9]', rows_of(page1))
say(rows_with_count and rows_of(page1).find("<zero_rules") > rows_of(page1).rfind("<rule ") and rows_of(page1).find("<zero_rules") < rows_of(page1).find("<f "),
    "(B2) [P] the tally stays first: counted <rule> rows, then <zero_rules>, then the findings")
_, sel, _ = run(BIN, LO, ["--lint", "--lint-select=naming-"])
fold = re.search(r"<zero_rules\b[^>]*/>", rows_of(sel))
say(fold is not None and "unsafe-c-fn" not in fold.group(0) and "naming-" in fold.group(0),
    "(B3) [P] under --lint-select the fold names only selected rules (a deselected rule has no row and no name)")
lint_legend = re.search(r"<!--.*?-->", page1, re.S)
say(lint_legend is not None and "zero_rules" in lint_legend.group(0) and "ran=" in lint_legend.group(0) and "inert=" in lint_legend.group(0),
    "(B4) [P] the default (compact) legend defines zero_rules ran= inert=")
_, full, _ = run(BIN, LO, ["--lint", "--legend=full"])
say("zero_rules" in full.split("<lint ")[0] and zero_fold_ok(full), "(B5) [P] --legend=full defines it too, and folds the same way")

# ── (C) lossless + deterministic ─────────────────────────────────────────────────────────────────────────────────────
pages, chain = lint_chain(BIN, LO, ["--lint"])
say(len(pages) > 1 and all(len(p) <= CEILING for p in pages), "(C1) [C] the default answer pages: %d pages, max %d chars <= %d" % (len(pages), max(map(len, pages)), CEILING))
say(chain == wrows, "(C2) [P] the next= chain rebuilds the whole answer's rows in order (%d vs %d rows)" % (len(chain), len(wrows)))
_, whole2, _ = run(BIN, LO, ["--lint", "--page-bytes=0"])
_, page1b, _ = run(BIN, LO, ["--lint"])
say(whole2 == whole and page1b == page1, "(C3) [C] determinism: the whole answer and page 1 are byte-identical across two runs")
_, viaLimit, _ = run(BIN, LO, ["--lint", "--limit=100000"])
lrows = FROW.findall(rows_of(viaLimit))
say(lrows == chain and len(lrows) > 300, "(C4) [C] the explicit --limit=N still works: --limit=100000 serves the chain's rows in the chain's order (%d rows)" % len(lrows))
if BASE:
    _, base_whole, _ = run(BASE, LO, ["--lint", "--limit=100000"])
    brows = FROW.findall(rows_of(base_whole))
    say(sorted(brows) == sorted(lrows), "(N1) [N] the SET of findings is the parent's (%d vs %d rows) — only the order moved" % (len(lrows), len(brows)))
    _, bsmall, _ = run(BASE, SMALL, ["--lint", "--limit=100000"])
    _, nsmall, _ = run(BIN, SMALL, ["--lint", "--limit=100000"])
    say(sorted(FROW.findall(rows_of(bsmall))) == sorted(FROW.findall(rows_of(nsmall))), "(N2) [N] small/: the same set of findings as the parent")

# ── (D) --page-bytes=0 is the whole answer on every paged verb ───────────────────────────────────────────────────────
say(WHOLE_LINE in err_whole and len(whole) > CEILING, "(D1) [P] --lint --page-bytes=0 over the ceiling (%d chars) says so on stderr" % len(whole))
say(len(wrows) == total > 0 and root_attr(whole, "lint", "next") is None and root_attr(whole, "lint", "has_more") in (None, "0"), "(D2) [P] the whole --lint answer names no next page")
rc, small_whole, small_err = run(BIN, SMALL, ["--lint", "--page-bytes=0"])
say(rc == 0 and WHOLE_LINE not in small_err, "(D3) [P] a whole --lint answer under the ceiling prints no stderr line (rc=%d)" % rc)
rc, ex_def, _ = run(BIN, EX, ["--expand=giant_body"])
rc2, ex_whole, ex_err = run(BIN, EX, ["--expand=giant_body", "--page-bytes=0"])
lines = ex_whole.count("acc += step_value(i, ")
say('truncated="1"' in ex_def and len(ex_def) <= CEILING, "(D4) [C] the default --expand cuts the 1,400-line body under the ceiling (%d chars)" % len(ex_def))
say(rc2 == 0 and lines == 1400 and 'truncated="1"' not in ex_whole, "(D5) [P] --expand --page-bytes=0 serves the whole body: %d of 1400 lines (rc=%d)" % (lines, rc2))
say(WHOLE_LINE in ex_err and len(ex_whole) > CEILING, "(D6) [P] ...and says on stderr that it is over the ceiling (%d chars)" % len(ex_whole))
rc, map_whole, map_err = run(BIN, WIDE, ["--page-bytes=0"])
say(rc == 0 and root_attr(map_whole, "r", "pages") is None and len(map_whole) > CEILING, "(D7) [C] the bare map --page-bytes=0 is whole (%d chars, no pages=)" % len(map_whole))
say(WHOLE_LINE in map_err, "(D8) [P] the whole bare map over the ceiling says so on stderr")
rc, for_whole, for_err = run(BIN, REPO, ["--for=lint findings order severity page window", "--page-bytes=0"])
say(rc == 0 and root_attr(for_whole, "ctx", "pages") is None and ((WHOLE_LINE in for_err) == (len(for_whole) > CEILING)),
    "(D9) [C] --for --page-bytes=0 is whole (%d chars) and the stderr line rides exactly an over-ceiling answer" % len(for_whole))
rc, _, err = run(BIN, LO, ["--lint", "--page-bytes=6000"])
say(rc != 0 and "--page-bytes" in err and "--offset" in err, "(D10) [P] --lint --page-bytes=N (N>0) refuses and names --lint's own unit (rc=%d)" % rc)
rc, _, err = run(BIN, LO, ["--lint", "--page-bytes=0", "--limit=5"])
say(rc != 0 and "does not combine with --limit" in err, "(D11) [P] --lint --page-bytes=0 --limit=N refuses: two sizes for one answer (rc=%d)" % rc)
rc, _, err = run(BIN, EX, ["--expand=giant_body", "--page-bytes=0", "--pack-budget-bytes=4000"])
say(rc != 0 and "does not combine with --pack-budget-bytes" in err, "(D12) [P] --expand --page-bytes=0 --pack-budget-bytes=N refuses: two sizes for one answer (rc=%d)" % rc)
rc, ex_exp, _ = run(BIN, EX, ["--expand=giant_body", "--pack-budget-bytes=200000"])
say(rc == 0 and ex_exp.count("acc += step_value(i, ") == 1400, "(D13) [C] the explicit --pack-budget-bytes=N still works (whole body at 200,000)")
rc, off_whole, _ = run(BIN, LO, ["--lint", "--offset=100", "--page-bytes=0"])
say(rc == 0 and FROW.findall(rows_of(off_whole)) == wrows[100:], "(D14) [P] --lint --offset=K --page-bytes=0 is the whole rest from K")

# ── (M) mutation controls (on the --limit rows, which every binary serves) ───────────────────────────────────────────
ref = sorted(lrows, key=lambda r: (row_key(r)[1] in DEMOTED, SEV_RANK.get(SEV.get(row_key(r)[0], ""), 3)))
say(order_ok(ref), "(M0) [C] the order check PASSES on the --limit rows re-sorted by tier and severity (its positive control)")
demoted_row = next(r for r in ref if row_key(r)[1] in DEMOTED)
say(not order_ok([demoted_row] + [r for r in ref if r is not demoted_row]), "(M1) [M] the order check FAILS when a demoted row is moved to the front")
info_row = next(r for r in ref if SEV.get(row_key(r)[0]) == "info" and row_key(r)[1] not in DEMOTED)
say(not order_ok([info_row] + [r for r in ref if r is not info_row]), "(M2) [M] the order check FAILS when an info row precedes an error row in the same tier")
say(not zero_fold_ok(page1.replace("<zero_rules", '<rule name="goto" count="0" shown_rows="0" rows_capped="0"/><zero_rules', 1)),
    "(M3) [M] the fold check FAILS on a doc carrying a count=\"0\" rule row")
say(not zero_fold_ok(re.sub(r'(<zero_rules[^>]*ran=")([^",]+),', r"\1", page1, count=1)), "(M4) [M] the fold check FAILS when the fold drops one rule's name")
say(chain[:7] + chain[8:] != lrows and chain + chain[:1] != lrows, "(M5) [M] the lossless check FAILS on a chain missing one row or repeating one")
say(not (WHOLE_LINE in "" and len(whole) > CEILING), "(M6) [M] the stderr check FAILS on an over-ceiling answer with an empty stderr")

print("lintordercheck: %s (%d failing)" % ("PASS" if bad == 0 else "FAIL", bad))
sys.exit(1 if bad else 0)
PY
