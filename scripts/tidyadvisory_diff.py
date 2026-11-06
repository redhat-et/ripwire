#!/usr/bin/env python3
"""tidyadvisory_diff.py - compare the nightly ADVISORY clang-tidy report against .clang-tidy-baseline.txt.

WHAT IT IS FOR. The advisory clang-tidy step (ci.yml, `style` job; schedule and workflow_dispatch only) reports on
the broad .clang-tidy catalogue and never gates. A report nobody reads is not a signal, so this script turns a report
into a diff: NEW rows (not in the baseline) are what the nightly tracking issue lists; GONE rows (in the baseline, no
longer reported) are baseline entries to prune. It is advisory itself: it always exits 0.

KEY OF A FINDING. file TAB check TAB anchor, with
  file    the path relative to the repo (the checkout root, else the CI runner's work dir, else the part from src/ on),
  check   the bracketed check name clang-tidy prints (`[bugprone-branch-clone]`),
  anchor  the trimmed source text of the line clang-tidy points at, whitespace collapsed (the excerpt line under the
          warning). No line or column number is in the key, so an edit elsewhere in the file does not churn the baseline.
Findings are deduplicated by (file, line, col, check) first: a header included by several translation units is printed
once per TU. The comparison is a MULTISET on the key, so two identical lines in one file are two entries.

MODES (all flags optional except --report)
  --report FILE        the advisory clang-tidy output (a GitHub log with a timestamp prefix per line also parses)
  --baseline FILE      .clang-tidy-baseline.txt: `#` comment lines, blank lines, then sorted key rows
  --rc FILE            the file holding clang-tidy's exit status; nonzero => status=tool-failed (rows are shown, nothing else
                       should act on them: a crashed run's GONE list is not evidence)
  --root DIR           strip this checkout root from paths
  --normalized-out F   write the report's key rows, sorted, under the baseline header (a ready baseline candidate)
  --issue-body F       write the markdown body of the tracking issue (written only when there are NEW rows)
  --status-out F       write key=value lines: status, parsed, new, gone, baseline, ...
  --run-url U --sha S --note TEXT   shown in the issue body / the `generated from` header line
  --selftest           run the built-in checks and exit 0 only if they pass (the one exception to "always 0")

status= is one of: ok | noinput (no report file) | nobaseline (no baseline file) | tool-failed (rc != 0) |
suspect-empty (0 findings parsed against a non-empty baseline: a crashed or truncated run looks like this, not like a
clean tree). Only status=ok means NEW/GONE are trustworthy; the workflow acts on nothing else.
"""
import argparse
import collections
import os
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
STAMP = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z ")
HDR = re.compile(r"^(?P<path>.+?):(?P<line>\d+):(?P<col>\d+): (?P<sev>warning|error): (?P<msg>.*) \[(?P<check>[A-Za-z0-9_.,-]+)\]\s*$")
ANY_DIAG = re.compile(r"^.+?:\d+:\d+: (?:warning|error|note): ")
GUTTER = re.compile(r"^\s*\d+ \|(?: (?P<code>.*))?$")
CARET = re.compile(r"^[\s|^~]*$")
RUNNER = re.compile(r"^/(?:home|Users)/[^/]+/work/[^/]+/[^/]+/(?P<rel>.+)$")
MAX_BODY = 60000          # GitHub's issue body limit is 65536 characters; stay clear and disclose any cut

BASELINE_HEADER = """\
# .clang-tidy-baseline.txt - the advisory clang-tidy findings accepted as of the commit below.
# One row per finding: file TAB check TAB anchor (the trimmed source line; no line numbers, so unrelated edits do not
# churn it). Sorted. Every row is either a fix still to come or a triaged false positive / accepted finding; a fixed
# finding's row is deleted, never kept as a record.
# The nightly advisory run (ci.yml `style` job, schedule/workflow_dispatch) diffs its report against this file with
# scripts/tidyadvisory_diff.py and opens or updates ONE tracking issue (label clang-tidy-advisory) listing the NEW rows.
# REGENERATE: take the `tidy-advisory` artifact of a nightly or workflow_dispatch run, review its
# tidy-advisory-baseline-candidate.txt against this file, and commit the rows you accept (or the whole candidate).
# Locally: python3 scripts/tidyadvisory_diff.py --report <clang-tidy output> --baseline .clang-tidy-baseline.txt
#          --normalized-out <file>   (python3 scripts/tidyadvisory_diff.py --selftest checks the parser)
"""


def clean(line):
    return STAMP.sub("", ANSI.sub("", line.rstrip("\n").rstrip("\r")))


def relpath(path, root):
    if root:
        r = root.rstrip("/") + "/"
        if path.startswith(r):
            return path[len(r):]
    m = RUNNER.match(path)
    if m:
        return m.group("rel")
    i = path.find("/src/")
    if i >= 0:
        return path[i + 1:]
    return path


def collapse(text):
    return " ".join(text.split())


def parse(lines, root):
    """-> (findings, unattributed_errors). findings: list of (file, line, check, anchor), deduped by (file, line, col, check)."""
    seen = set()
    found = []
    errs = 0
    ls = [clean(x) for x in lines]
    for i, ln in enumerate(ls):
        m = HDR.match(ln)
        if not m:
            if ": error: " in ln and ANY_DIAG.match(ln):
                errs += 1          # a compile error with no [check] tag: the report may be incomplete
            continue
        f = relpath(m.group("path"), root)
        key = (f, int(m.group("line")), int(m.group("col")), m.group("check"))
        if key in seen:
            continue
        seen.add(key)
        anchor = ""
        if i + 1 < len(ls):
            nxt = ls[i + 1]
            g = GUTTER.match(nxt)
            if g:
                anchor = collapse(g.group("code") or "")
            elif nxt.strip() and not ANY_DIAG.match(nxt) and not CARET.match(nxt):
                anchor = collapse(nxt)       # a clang without the line-number gutter
        found.append((f, int(m.group("line")), m.group("check"), anchor))
    return found, errs


def keyof(f):
    return "%s\t%s\t%s" % (f[0], f[2], f[3])


def read_baseline(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln.strip() or ln.startswith("#"):
                continue
            parts = ln.split("\t", 2)
            if len(parts) < 2:
                continue            # not a key row; ignored rather than guessed at
            rows.append("\t".join((parts + [""])[:3]))
    return rows


def write_rows(path, keys, note):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(BASELINE_HEADER)
        fh.write("# generated from: %s\n" % (note or "an advisory clang-tidy report"))
        fh.write("# rows: %d\n" % len(keys))
        for k in sorted(keys):
            fh.write(k + "\n")


def esc(text):
    return text.replace("`", "'")


def issue_body(new_keys, new_lines, gone_keys, base_n, sha, url, nrows):
    by_check = collections.defaultdict(list)
    for k in sorted(new_keys):
        f, c, a = k.split("\t", 2)
        by_check[c].append((f, a, sorted(new_lines.get(k, []))))
    head = []
    head.append("The nightly ADVISORY clang-tidy report (clang-tidy 22, the `.clang-tidy` catalogue) has **%d finding(s) that are not in "
                "`.clang-tidy-baseline.txt`** (baseline %d rows)%s." % (nrows, base_n, " at `%s`" % sha if sha else ""))
    if url:
        head.append("Run: %s" % url)
    head.append("")
    head.append("The advisory step never gates. Each row below is either a real defect to fix or a false positive / accepted finding to add to the "
                "baseline. Keys are file + check + the trimmed source line, so line numbers here are for finding the spot only.")
    head.append("")
    tail = []
    if gone_keys:
        tail.append("### Baseline rows no longer reported (%d): delete them from `.clang-tidy-baseline.txt`" % len(gone_keys))
        tail.append("")
        for k in sorted(gone_keys)[:40]:
            f, c, a = k.split("\t", 2)
            tail.append("- `%s` `%s` `%s`" % (f, c, esc(a)[:100]))
        if len(gone_keys) > 40:
            tail.append("- ... and %d more (see the run's `tidy-advisory` artifact)" % (len(gone_keys) - 40))
        tail.append("")
    tail.append("### Regenerate / triage")
    tail.append("")
    tail.append("Download the `tidy-advisory` artifact of the run above. `tidy-advisory-baseline-candidate.txt` is the full sorted key list; "
                "`tidy-advisory-diff.txt` is the NEW / GONE listing. Commit the rows you accept to `.clang-tidy-baseline.txt` and delete the "
                "fixed ones. This issue is updated by each nightly run and closed by the first run with no NEW rows.")
    body_mid = ["### NEW rows by check", ""]
    used = sum(len(x) + 1 for x in head + tail + body_mid)
    cut = 0
    total = sum(len(v) for v in by_check.values())
    shown = 0
    out = []
    for c in sorted(by_check, key=lambda c: (-len(by_check[c]), c)):
        block = ["#### `%s` (%d)" % (c, len(by_check[c])), ""]
        rows = []
        for f, a, lines in by_check[c]:
            at = ", ".join("%s:%d" % (f, n) for n in lines[:4]) or f
            rows.append("- `%s` - `%s`" % (at, esc(a)[:110]))
        chunk = block + rows + [""]
        size = sum(len(x) + 1 for x in chunk)
        if used + size > MAX_BODY:
            # keep as many rows of this check as fit, then stop
            keep = []
            budget = MAX_BODY - used - sum(len(x) + 1 for x in block) - 200
            for r in rows:
                if budget - len(r) - 1 < 0:
                    break
                keep.append(r)
                budget -= len(r) + 1
            if keep:
                out += block + keep + [""]
                shown += len(keep)
                used += sum(len(x) + 1 for x in block + keep)
            cut = total - shown
            break
        out += chunk
        shown += len(rows)
        used += size
    if cut:
        out.append("(%d more NEW row(s) did not fit in this issue body; the artifact's `tidy-advisory-diff.txt` lists all %d.)" % (cut, total))
        out.append("")
    return "\n".join(head + body_mid + out + tail) + "\n"


def run(a):
    status = "ok"
    extra = []
    if not a.report or not os.path.isfile(a.report):
        status = "noinput"
        findings, errs = [], 0
    else:
        with open(a.report, encoding="utf-8", errors="replace") as fh:
            findings, errs = parse(fh.readlines(), a.root)
    base = []
    if a.baseline and os.path.isfile(a.baseline):
        base = read_baseline(a.baseline)
    elif status == "ok":
        status = "nobaseline"
    rc = None
    if a.rc and os.path.isfile(a.rc):
        try:
            rc = int(open(a.rc).read().strip() or "x")
        except ValueError:
            rc = -1
        if rc != 0 and status == "ok":
            status = "tool-failed"
            extra.append("clang-tidy exit status %s" % rc)
    elif a.rc and status == "ok":
        status = "tool-failed"
        extra.append("no exit-status file %s" % a.rc)
    if status == "ok" and not findings and base:
        status = "suspect-empty"
        extra.append("0 findings parsed against %d baseline rows" % len(base))
    cur = collections.Counter(keyof(f) for f in findings)
    old = collections.Counter(base)
    new = cur - old
    gone = old - cur
    lines_of = collections.defaultdict(list)
    for f in findings:
        lines_of[keyof(f)].append(f[1])
    nrows = sum(new.values())
    print("tidyadvisory_diff: status=%s parsed=%d baseline=%d new=%d gone=%d%s" % (
        status, len(findings), len(base), nrows, sum(gone.values()), ("  (" + "; ".join(extra) + ")") if extra else ""))
    if errs:
        print("tidyadvisory_diff: %d compile error line(s) with no [check] tag: the report may be incomplete" % errs)
    if status == "noinput":
        print("tidyadvisory_diff: no report file: %s" % a.report)
    if status in ("noinput",):
        pass
    else:
        for title, ctr in (("NEW", new), ("GONE", gone)):
            print("%s (%d)" % (title, sum(ctr.values())))
            last = None
            for k in sorted(ctr, key=lambda k: (k.split("\t")[1], k)):
                f, c, an = k.split("\t", 2)
                if c != last:
                    print("  [%s]" % c)
                    last = c
                where = ",".join(str(n) for n in sorted(lines_of.get(k, []))[:4])
                print("    %s%s  %s%s" % (f, (":" + where) if (where and title == "NEW") else "", an[:110],
                                         "  x%d" % ctr[k] if ctr[k] > 1 else ""))
    if a.normalized_out and status != "noinput":
        write_rows(a.normalized_out, [keyof(f) for f in findings], a.note)
    if a.issue_body and status == "ok" and nrows:
        with open(a.issue_body, "w", encoding="utf-8") as fh:
            fh.write(issue_body(list(new), lines_of, list(gone), len(base), a.sha, a.run_url, nrows))
    if a.status_out:
        with open(a.status_out, "w") as fh:
            fh.write("status=%s\nparsed=%d\nbaseline=%d\nnew=%d\ngone=%d\n" % (status, len(findings), len(base), nrows, sum(gone.values())))
    return 0


def selftest():
    ok = True

    def check(cond, what):
        nonlocal ok
        print(("  PASS  " if cond else "  FAIL  ") + what)
        ok = ok and bool(cond)

    # nonzero only when something is red; each arm has a positive twin
    sample = [
        "2026-11-05T19:29:33.4802634Z /home/runner/work/ripwire/ripwire/src/a.h:10:5: warning: m1 [bugprone-branch-clone]\n",
        "2026-11-05T19:29:33.4803506Z    10 |     if( x ) { f(); } else { f(); }\n",
        "2026-11-05T19:29:33.4804247Z       |     ^\n",
        "/home/runner/work/ripwire/ripwire/src/a.h:10:5: warning: m1 [bugprone-branch-clone]\n",          # same finding, second TU
        "   10 |     if( x ) { f(); } else { f(); }\n",
        "/home/runner/work/ripwire/ripwire/src/a.h:20:3: note: a note, not a finding\n",
        "\x1b[1m/home/runner/work/ripwire/ripwire/src/b.cpp:7:1: \x1b[0m\x1b[0;1;35mwarning: \x1b[0m\x1b[1mm2 [perf-x]\x1b[0m\n",
        "/home/runner/work/ripwire/ripwire/src/c.h:3:9: warning: 2 adjacent parameters [bugprone-easily-swappable-parameters]\n",
        "    3 |   int f( int a,\n",
        "      |          ^~~~~~\n",
    ]
    f, errs = parse(sample, None)
    check(len(f) == 3, "three findings after the dedupe across TUs, the note skipped and the ANSI-wrapped header read (got %d)" % len(f))
    check(f[0] == ("src/a.h", 10, "bugprone-branch-clone", "if( x ) { f(); } else { f(); }"), "key = relative path, check, collapsed source line (%r)" % (f[0],))
    check(f[2][3] == "int f( int a," and f[1][3] == "", "a span's first excerpt line is the anchor; a finding with no excerpt gets an empty one")
    # a line shift does not change the key (the point of the anchor)
    shifted, _ = parse([sample[0].replace(":10:5", ":99:5"), sample[1]], None)
    check(keyof(shifted[0]) == keyof(f[0]), "line number is not in the key")
    # the crash twin: unparseable garbage yields nothing, not a finding
    g, e = parse(["clang-tidy: segfault\n", "/x/y.cpp:1:1: error: unknown type name 'Foo'\n"], None)
    check(g == [] and e == 1, "a compile error with no [check] is counted as unattributed, not as a finding")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description="diff an advisory clang-tidy report against .clang-tidy-baseline.txt (advisory: exit 0)")
    ap.add_argument("--report")
    ap.add_argument("--baseline")
    ap.add_argument("--rc")
    ap.add_argument("--root")
    ap.add_argument("--normalized-out", dest="normalized_out")
    ap.add_argument("--issue-body", dest="issue_body")
    ap.add_argument("--status-out", dest="status_out")
    ap.add_argument("--run-url", dest="run_url", default="")
    ap.add_argument("--sha", default="")
    ap.add_argument("--note", default="")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    try:
        return run(a)
    except Exception as e:      # advisory: a bug here must not red the job, but it must not look like a clean run either
        print("tidyadvisory_diff: ERROR %s: %s" % (type(e).__name__, e))
        if a.status_out:
            try:
                open(a.status_out, "w").write("status=script-error\nparsed=0\nbaseline=0\nnew=0\ngone=0\n")
            except OSError:
                pass
        return 0


if __name__ == "__main__":
    sys.exit(main())
