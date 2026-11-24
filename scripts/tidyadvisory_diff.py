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
  --selftest           run the built-in checks and exit 0 only if they pass (an exception to "always 0")

GATING MODES (0.7.1; each is opt-in, and each is the only way this script exits non-zero besides --selftest)
  --scope GLOBS        the report came from a `--checks='-*,GLOBS'` run: compare it against only the baseline rows whose
                       check matches GLOBS (comma list, clang-tidy's `*` globs). With --normalized-out the candidate is a
                       PARTIAL regeneration: every out-of-scope baseline row kept as it is, the in-scope rows replaced.
  --scope-files GLOBS  narrow --scope further to rows whose file matches GLOBS (comma list, `*` globs): a report taken
                       from one translation unit regenerates only the headers it is authoritative for.
  --gate               exit 1 when status=ok and there is a NEW row, exit 2 when status is anything but ok (a crashed run,
                       a missing input or a suspect-empty report is not a pass). GONE rows never fail: fewer findings is
                       the direction the ratchet wants. scripts/tidycheck.sh --ratchet runs this on every CI event.
  --ratchet FILE       compare the baseline's row count per check with FILE's ceilings (.clang-tidy-ratchet.txt): exit 1
                       when any check has MORE rows than its ceiling (a check absent from FILE has ceiling 0) and also when
                       it has FEWER — a fixed row lowers the ceiling in the same commit, so the next change cannot spend
                       the slack. --ratchet-update rewrites FILE from the baseline (and exits 0).
  --annotate TSV       rewrite --baseline in place with the one-line reasons in TSV (file TAB check TAB anchor TAB reason;
                       `*` as file or anchor matches any, an anchor ending in `*` is a prefix). Rows, order and header stay;
                       only the 4th field changes. Exit 1 if a TSV line matches no row (a reason for nothing is a typo).

status= is one of: ok | noinput (no report file) | nobaseline (no baseline file) | tool-failed (rc != 0) |
suspect-empty (0 findings parsed against a non-empty baseline: a crashed or truncated run looks like this, not like a
clean tree). Only status=ok means NEW/GONE are trustworthy; the workflow acts on nothing else.
"""
import argparse
import collections
import fnmatch
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
# churn it), then optionally TAB and the one-line reason a row is kept (`kept: ...`; carried across regeneration). Sorted. Every row is either a fix still to come or a triaged false positive / accepted finding; a fixed
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


def read_baseline(path, reasons=None):
    """-> key rows. A row may carry a 4th TAB field, the one-line reason it is kept (`kept: ...`); it is not part of the
    key (an anchor never holds a TAB: collapse() splits on whitespace) and, when `reasons` is a dict, is collected
    into it by key so a regeneration can carry it forward."""
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln.strip() or ln.startswith("#"):
                continue
            parts = ln.split("\t", 3)
            if len(parts) < 2:
                continue            # not a key row; ignored rather than guessed at
            key = "\t".join((parts + [""])[:3])
            rows.append(key)
            if reasons is not None and len(parts) == 4 and parts[3].strip():
                reasons.setdefault(key, parts[3].strip())
    return rows


def write_rows(path, keys, note, reasons=None):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(BASELINE_HEADER)
        fh.write("# generated from: %s\n" % (note or "an advisory clang-tidy report"))
        fh.write("# rows: %d\n" % len(keys))
        for k in sorted(keys):
            why = (reasons or {}).get(k)
            fh.write(k + ("\t" + why if why else "") + "\n")


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


def in_scope(check, globs, path=None, fglobs=None):
    """globs as clang-tidy reads them: a check is in scope when a plain glob matches it and no `-glob` does."""
    plus = [g for g in globs if not g.startswith("-")]
    minus = [g[1:] for g in globs if g.startswith("-")]
    return any(fnmatch.fnmatchcase(check, g) for g in plus) and not any(fnmatch.fnmatchcase(check, g) for g in minus) and (
        not fglobs or path is None or any(fnmatch.fnmatchcase(path, g) for g in fglobs))


def scope_globs(text):
    return [g.strip() for g in (text or "").split(",") if g.strip()]


RATCHET_HEADER = """\
# .clang-tidy-ratchet.txt - the per-check ceiling on .clang-tidy-baseline.txt's row count. check TAB ceiling, sorted.
# test/tidyratchetcheck.sh fails when the baseline has MORE rows of a check than its ceiling (a check not listed here
# has ceiling 0) and when it has FEWER: lower the ceiling in the commit that fixes the row, so the slack cannot be spent.
# Generated, never hand-edited: python3 scripts/tidyadvisory_diff.py --baseline .clang-tidy-baseline.txt
#                                   --ratchet .clang-tidy-ratchet.txt --ratchet-update
"""


def read_ratchet(path):
    ceil = {}
    with open(path, encoding="utf-8") as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln.strip() or ln.startswith("#"):
                continue
            c, _, n = ln.partition("\t")
            ceil[c] = int(n)
    return ceil


def ratchet(a):
    counts = collections.Counter(r.split("\t", 2)[1] for r in read_baseline(a.baseline))
    if a.ratchet_update:
        with open(a.ratchet, "w", encoding="utf-8") as fh:
            fh.write(RATCHET_HEADER)
            fh.write("# total: %d\n" % sum(counts.values()))
            for c in sorted(counts):
                fh.write("%s\t%d\n" % (c, counts[c]))
        print("tidyadvisory_diff: ratchet rewritten: %d check(s), %d row(s)" % (len(counts), sum(counts.values())))
        return 0
    ceil = read_ratchet(a.ratchet)
    grew, shrank = [], []
    for c in sorted(set(counts) | set(ceil)):
        have, cap = counts.get(c, 0), ceil.get(c, 0)
        if have > cap:
            grew.append((c, have, cap))
        elif have < cap:
            shrank.append((c, have, cap))
    print("tidyadvisory_diff: ratchet baseline=%d ceiling=%d grew=%d shrank=%d" % (
        sum(counts.values()), sum(ceil.values()), len(grew), len(shrank)))
    for c, have, cap in grew:
        print("  GREW    %s: %d rows, ceiling %d — a new finding is fixed, not baselined (or argue it in review)" % (c, have, cap))
    for c, have, cap in shrank:
        print("  SHRANK  %s: %d rows, ceiling %d — lower the ceiling in this commit (--ratchet-update)" % (c, have, cap))
    return 1 if (grew or shrank) else 0


def annotate(a):
    reasons = {}
    rows = read_baseline(a.baseline, reasons)
    rules = []
    with open(a.annotate, encoding="utf-8") as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln.strip() or ln.startswith("#"):
                continue
            f, c, an, why = ln.split("\t", 3)
            rules.append([f, c, an, why.strip(), 0])

    def hit(rule, key):
        f, c, an = key.split("\t", 2)
        if rule[1] != c or rule[0] not in ("*", f):
            return False
        pat = rule[2]
        return pat == "*" or an == pat or (pat.endswith("*") and an.startswith(pat[:-1]))
    for key in set(rows):
        for rule in rules:
            if hit(rule, key):
                reasons[key] = rule[3]
                rule[4] += 1
                break
    with open(a.baseline, encoding="utf-8") as fh:
        head = [ln for ln in fh if ln.startswith("#")]
    with open(a.baseline, "w", encoding="utf-8") as fh:
        fh.writelines(head)
        for k in sorted(rows):
            fh.write(k + ("\t" + reasons[k] if k in reasons else "") + "\n")
    unused = [r for r in rules if r[4] == 0]
    print("tidyadvisory_diff: annotated %d of %d row(s) from %d rule(s); %d rule(s) matched nothing" % (
        sum(1 for k in set(rows) if k in reasons), len(rows), len(rules), len(unused)))
    for r in unused:
        print("  UNUSED  %s\t%s\t%s" % tuple(r[:3]))
    return 1 if unused else 0


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
    reasons = {}
    if a.baseline and os.path.isfile(a.baseline):
        base = read_baseline(a.baseline, reasons)
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
    full_base = list(base)
    findings, base, row_in = apply_scope(a, findings, base, extra)
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
    else:
        print_listing(new, gone, lines_of)
    if a.normalized_out and status != "noinput":
        kept = [r for r in full_base if not row_in(r)] if row_in else []
        write_rows(a.normalized_out, kept + [keyof(f) for f in findings], a.note, reasons)
    if a.issue_body and status == "ok" and nrows:
        with open(a.issue_body, "w", encoding="utf-8") as fh:
            fh.write(issue_body(list(new), lines_of, list(gone), len(base), a.sha, a.run_url, nrows))
    if a.status_out:
        with open(a.status_out, "w") as fh:
            fh.write("status=%s\nparsed=%d\nbaseline=%d\nnew=%d\ngone=%d\n" % (status, len(findings), len(base), nrows, sum(gone.values())))
    return gate_verdict(status, nrows) if a.gate else 0


def apply_scope(a, findings, base, extra):
    """--scope / --scope-files: -> (in-scope findings, in-scope baseline rows, the row predicate or None)."""
    globs = scope_globs(a.scope)
    if not globs:
        return findings, base, None
    fglobs = scope_globs(getattr(a, "scope_files", ""))

    def row_in(r):
        f, c, _ = r.split("\t", 2)
        return in_scope(c, globs, f, fglobs)
    kept = [f for f in findings if in_scope(f[2], globs, f[0], fglobs)]
    if len(kept) != len(findings):
        extra.append("%d finding(s) outside --scope ignored" % (len(findings) - len(kept)))
    return kept, [r for r in base if row_in(r)], row_in


def print_listing(new, gone, lines_of):
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


def gate_verdict(status, nrows):
    """--gate's exit: 0 pass, 1 a NEW in-scope row, 2 any status but ok (never a pass)."""
    if status != "ok":
        print("tidyadvisory_diff: GATE ERROR status=%s — not a pass%s" % (status, (
            "; if every in-scope row was fixed, regenerate the baseline" if status == "suspect-empty" else "")))
        return 2
    print("tidyadvisory_diff: GATE %s — %d NEW row(s) in scope" % ("FAIL" if nrows else "PASS", nrows))
    return 1 if nrows else 0


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

    selftest_modes(check)
    return 0 if ok else 1


def selftest_modes(check):
    """--scope / --gate / --ratchet / reasons: each red arm beside its green twin, on throwaway files."""
    import io
    import contextlib
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        def put(name, text):
            path = os.path.join(tmp, name)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            return path
        base = put("base.txt", "# header\nsrc/a.h\tbugprone-exception-escape\tvoid f()\nsrc/a.h\tbugprone-branch-clone\tif( x )\n")
        rc0 = put("rc", "0\n")
        same = put("same.txt", "/r/src/a.h:3:6: warning: an exception may be thrown [bugprone-exception-escape]\n    3 | void f()\n")
        new = put("new.txt", "/r/src/a.h:3:6: warning: an exception may be thrown [bugprone-exception-escape]\n    3 | void f()\n"
                             "/r/src/b.h:9:6: warning: an exception may be thrown [bugprone-exception-escape]\n    9 | void g()\n")
        empty = put("empty.txt", "")

        def gate(report, scope, rc=rc0, out=None):
            ns = argparse.Namespace(report=report, baseline=base, rc=rc, root="/r", normalized_out=out, issue_body=None,
                                    status_out=None, run_url="", sha="", note="", scope=scope, gate=True)
            with contextlib.redirect_stdout(io.StringIO()):
                return run(ns)
        check(gate(same, "bugprone-exception-escape") == 0, "gate PASSES a scoped report whose only row is baselined (the branch-clone row is out of scope, not GONE)")
        check(gate(new, "bugprone-exception-escape") == 1, "gate FAILS a NEW in-scope row (planted src/b.h exception-escape)")
        check(gate(new, "bugprone-unchecked-optional-access,bugprone-exception-*") == 1, "a glob in --scope matches the planted row's check")
        check(gate(new, "*,-bugprone-exception-escape,-bugprone-branch-clone") == 0, "a -glob in --scope excludes a check, as clang-tidy's --checks does (no row left in scope: pass)")
        check(gate(new, "bugprone-branch-clone") == 2, "gate is an ERROR, not a pass, on an empty scoped report against a non-empty scoped baseline")
        check(gate(empty, "bugprone-use-after-move") == 0, "gate PASSES an empty report when the scope has no baseline rows (a zero-row check)")
        check(gate(same, "bugprone-exception-escape", rc=put("rc1", "1\n")) == 2, "gate is an ERROR when clang-tidy's exit status is non-zero")
        check(gate(os.path.join(tmp, "missing.txt"), "bugprone-exception-escape") == 2, "gate is an ERROR on a missing report")
        nsf = argparse.Namespace(report=new, baseline=base, rc=rc0, root="/r", normalized_out=None, issue_body=None, status_out=None,
                                 run_url="", sha="", note="", scope="bugprone-exception-escape", scope_files="src/a.h", gate=True)
        with contextlib.redirect_stdout(io.StringIO()):
            rc_files = run(nsf)
        check(rc_files == 0, "--scope-files src/a.h leaves the planted src/b.h row outside the comparison (gate passes)")
        cand = os.path.join(tmp, "cand.txt")
        gate(new, "bugprone-exception-escape", out=cand)
        rows = read_baseline(cand)
        check(len(rows) == 3 and any("branch-clone" in r for r in rows) and any("void g()" in r for r in rows),
              "a scoped --normalized-out keeps the out-of-scope rows and replaces the in-scope ones (got %d rows)" % len(rows))
        why = put("why.txt", "src/a.h\tbugprone-exception-escape\tvoid f()\tkept: bad_alloc only\n")
        ns = argparse.Namespace(report=same, baseline=why, rc=rc0, root="/r", normalized_out=cand, issue_body=None, status_out=None,
                                run_url="", sha="", note="", scope="", gate=True)
        with contextlib.redirect_stdout(io.StringIO()):
            rc_why = run(ns)
        carried = {}
        read_baseline(cand, carried)
        check(rc_why == 0 and carried == {"src/a.h\tbugprone-exception-escape\tvoid f()": "kept: bad_alloc only"},
              "a row's kept: reason is not part of its key and survives regeneration (%r)" % carried)

        selftest_ratchet(check, put, tmp, base)


def selftest_ratchet(check, put, tmp, base):
    import io
    import contextlib
    def ratch(baseline, ceil, update=False):
        ns = argparse.Namespace(baseline=baseline, ratchet=ceil, ratchet_update=update)
        with contextlib.redirect_stdout(io.StringIO()):
            return ratchet(ns)
    ceil = os.path.join(tmp, "ratchet.txt")
    check(ratch(base, ceil, update=True) == 0 and read_ratchet(ceil) == {"bugprone-exception-escape": 1, "bugprone-branch-clone": 1},
          "--ratchet-update writes one ceiling per check")
    check(ratch(base, ceil) == 0, "ratchet PASSES a baseline that matches its ceilings")
    grown = put("grown.txt", open(base).read() + "src/b.h\tbugprone-exception-escape\tvoid g()\n")
    check(ratch(grown, ceil) == 1, "ratchet FAILS a baseline that grew by one row")
    other = put("other.txt", open(base).read() + "src/b.h\tbugprone-use-after-move\tuse( x );\n")
    check(ratch(other, ceil) == 1, "ratchet FAILS a row of a check that has no ceiling (ceiling 0)")
    fewer = put("fewer.txt", "src/a.h\tbugprone-branch-clone\tif( x )\n")
    check(ratch(fewer, ceil) == 1, "ratchet FAILS a baseline that shrank until the ceiling is lowered (no slack to spend)")


def parse_args():
    ap = argparse.ArgumentParser(description="diff an advisory clang-tidy report against .clang-tidy-baseline.txt (advisory: exit 0)")
    for flag in ("--report", "--baseline", "--rc", "--root", "--ratchet", "--annotate"):
        ap.add_argument(flag)
    for flag in ("--normalized-out", "--issue-body", "--status-out"):
        ap.add_argument(flag, dest=flag[2:].replace("-", "_"))
    for flag in ("--run-url", "--sha", "--note", "--scope", "--scope-files"):
        ap.add_argument(flag, dest=flag[2:].replace("-", "_"), default="")
    for flag in ("--selftest", "--gate", "--ratchet-update"):
        ap.add_argument(flag, dest=flag[2:].replace("-", "_"), action="store_true")
    return ap.parse_args()


def file_mode(a):
    """--annotate / --ratchet: the two modes that read only the baseline (and their own file). None: neither asked."""
    if a.annotate:
        if not a.baseline or not os.path.isfile(a.baseline) or not os.path.isfile(a.annotate):
            print("tidyadvisory_diff: --annotate needs an existing --baseline and TSV")
            return 2
        return annotate(a)
    if a.ratchet:
        if not a.baseline or not os.path.isfile(a.baseline) or (not a.ratchet_update and not os.path.isfile(a.ratchet)):
            print("tidyadvisory_diff: --ratchet needs an existing --baseline and ratchet file")
            return 2
        return ratchet(a)
    return None


def main():
    a = parse_args()
    if a.selftest:
        return selftest()
    done = file_mode(a)
    if done is not None:
        return done
    try:
        return run(a)
    except Exception as e:      # advisory: a bug here must not red the job, but it must not look like a clean run either
        print("tidyadvisory_diff: ERROR %s: %s" % (type(e).__name__, e))
        if a.gate:
            return 2            # gating: a script bug is never a pass
        if a.status_out:
            try:
                open(a.status_out, "w").write("status=script-error\nparsed=0\nbaseline=0\nnew=0\ngone=0\n")
            except OSError:
                pass
        return 0


if __name__ == "__main__":
    sys.exit(main())
