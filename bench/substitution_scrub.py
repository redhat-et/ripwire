#!/usr/bin/env python3
# substitution_scrub.py — separate the substitution meter's FIXTURE rows from its real observations.
# Stdlib only, deterministic, never destructive (house style: bench/substitution_report.py,
# bench/mine_traces.py).
#
# WHY THIS EXISTS. hooks/ripwire-nudge.sh appends one row per observed tool call to a single global
# log (schema: docs/SUBSTITUTION_METER.md). test/hookcheck.sh drives that same hook with invented
# payloads by the dozen, and until 2026-08-12 those invocations resolved the operator's real log:
# synthetic rows landed in the live data, carrying the same schema, the same classes and a plausible
# session id, indistinguishable at analysis time from something an agent did. Every rate computed
# from such a log is contaminated, and the contamination is not uniform — a gate run is a burst of
# nudge-firing native calls with no ripwire calls at all, which drags the headline rate toward zero
# and inflates the nudge-efficacy denominator specifically.
#
# The leak itself is fixed in the hook and the gate (§FIXTURE in hooks/ripwire-nudge.sh, section (13)
# of test/hookcheck.sh). A guard stops NEW pollution; it cannot repair a log that already has some.
# That is this script's whole job.
#
# NEVER IN PLACE. The input is opened read-only and is never written, moved or truncated. `--out`
# names a NEW file and is refused if it resolves to the input. Without `--out` this is a read-only
# report — which is the right default for a file that is somebody's only copy of their telemetry.
#
# EVERY RULE IS REPORTED, WHICHEVER MODE RUNS. The four rules below are printed with their counts and
# a sample of the evidence every time, so an operator can see what a heuristic WOULD have taken
# before deciding to let it. Rules are tried in order and a row is attributed to the FIRST one that
# matches, so the counts partition the removals and never double-count them.
#
#   1. fixture-session-id   the session id is one test/hookcheck.sh writes. Exact, not a guess.
#   2. synthetic-session-id the session id is neither a UUID (what an agent harness issues) nor the
#                           hook's own `ppid<N>` fallback — i.e. somebody hand-drove the hook.
#   3. fixture-repo-temp    `repo` sits under a temp tree, which is where a gate's throwaway git
#                           fixtures live and where real work essentially never does.
#   4. fixture-payload      a synthetic payload (`needle`, `alpha`, `**/*.cpp`, …) AND a fixture repo
#                           basename. Deliberately narrow: it is the net for a fixture that somehow
#                           reused a real-looking session id, not a content filter.
#
# Usage:
#   python3 bench/substitution_scrub.py [~/.ripwire/substitution.jsonl]      # report only
#   python3 bench/substitution_scrub.py LOG --out cleaned.jsonl              # + write the clean copy
#   python3 bench/substitution_scrub.py LOG --out cleaned.jsonl --ids-only   # rule 1 only
import argparse
import collections
import json
import os
import re
import sys

# ---- rule 1: the exact ids test/hookcheck.sh writes. Kept as data rather than mined from the gate at
#      runtime: a scrub run must give the same answer years after the gate file has moved on, and a
#      stale entry here costs nothing while a missing one is caught by rules 2-3 anyway. ----
FIXTURE_SESSION_IDS = frozenset("""
    grepcase grepcase2 bashcase rgcase gitdiffcase gitdiffstatcase gitlogcase gitshowcase
    readcase readnongit globcase sscase ssnongit othercase editcase filegrepcase
    gitstatuscase gitcommitcase nongitcase noctxcase multiline lspipe buildsweep
    guardcase fallbackcase X
    smoketest install-verify-one
""".split())

# `gitmisc-<mangled command>`, `meter1`…`meter24`/`meter13_3`, `sweepgrep`/`sweepbash`/…,
# `cdcase_7`, `clscase_12` — the generated families.
FIXTURE_SESSION_PREFIXES = ("gitmisc-", "meter", "sweep", "cdcase_", "clscase_")

# ---- rule 2: what a REAL session id looks like. Claude Code issues a UUID; the hook falls back to
#      `ppid<N>` when a payload carries no session_id, and those rows are genuine observations. ----
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
PPID_RE = re.compile(r"^ppid[0-9]+$")

# ---- rule 3: temp trees. macOS hands `mktemp -d` a /var/folders path and resolves it through
#      /private; Linux uses /tmp. A row tagged with one of these came from a throwaway fixture repo. --
TEMP_REPO_PREFIXES = ("/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/",
                      "/var/folders/", "/private/var/folders/")

# ---- rule 4: synthetic payloads, AND a fixture repo basename. Both halves are required. ----
FIXTURE_DETAILS = frozenset("""
    needle needleone needletwo needlethree alpha beta gamma delta
    n x a b c d **/*.cpp **/*.c **/*.h **/*.py src/foo.cpp one_file.txt
""".split())
FIXTURE_REPO_NAMES = frozenset(("repo", "repo2", "nonrepo"))

RULES = ("fixture-session-id", "synthetic-session-id", "fixture-repo-temp", "fixture-payload")
RULE_WHY = {
    "fixture-session-id":   "session id is a known test/hookcheck.sh fixture",
    "synthetic-session-id": "session id is neither a UUID nor the hook's ppid<N> fallback",
    "fixture-repo-temp":    "repo path is inside a temp tree (a throwaway gate fixture)",
    "fixture-payload":      "synthetic payload in a fixture repo (needle/alpha/**.cpp in repo|repo2|nonrepo)",
}


def load(path):
    """Every non-blank line, in file order, as (line, parsed-object-or-None). A line that does not
    parse is carried through with `None`: it is not this script's business to decide that a line it
    cannot read is disposable, and dropping one would make the cleaned copy lossy in a way no report
    could show."""
    entries = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                obj = None
            entries.append((line, obj if isinstance(obj, dict) else None))
    return entries


def classify(row):
    """The first rule that matches, or None for a row this script believes is a real observation."""
    session = str(row.get("session", ""))
    repo = str(row.get("repo", ""))
    detail = str(row.get("detail", ""))

    if session in FIXTURE_SESSION_IDS or session.startswith(FIXTURE_SESSION_PREFIXES):
        return "fixture-session-id"
    if session and not UUID_RE.match(session) and not PPID_RE.match(session):
        return "synthetic-session-id"
    if repo.startswith(TEMP_REPO_PREFIXES):
        return "fixture-repo-temp"
    if detail in FIXTURE_DETAILS and os.path.basename(repo) in FIXTURE_REPO_NAMES:
        return "fixture-payload"
    return None


def main():
    ap = argparse.ArgumentParser(description="separate substitution-meter fixture rows from real ones")
    ap.add_argument("log", nargs="?",
                    default=os.path.join(os.environ.get("RIPWIRE_HOME",
                                                        os.path.join(os.path.expanduser("~"), ".ripwire")),
                                         "substitution.jsonl"),
                    help="path to substitution.jsonl (default: ~/.ripwire/substitution.jsonl)")
    ap.add_argument("--out", default=None,
                    help="write the cleaned copy here (a NEW file; omit for a read-only report)")
    ap.add_argument("--ids-only", action="store_true",
                    help="remove only rule-1 rows (the exact fixture id list), keep every heuristic match")
    ap.add_argument("--samples", type=int, default=3, help="evidence lines to show per rule (default 3)")
    args = ap.parse_args()

    if not os.path.exists(args.log):
        print("substitution_scrub: no log at %s" % args.log, file=sys.stderr)
        return 2
    if args.out and os.path.abspath(args.out) == os.path.abspath(args.log):
        print("substitution_scrub: --out must not be the input log — this tool is never destructive",
              file=sys.stderr)
        return 2

    entries = load(args.log)
    active = (RULES[:1] if args.ids_only else RULES)

    # A malformed line has no verdict and is therefore always kept — see load().
    verdicts = [(line, obj, classify(obj) if obj is not None else None) for line, obj in entries]
    malformed = sum(1 for _line, obj in entries if obj is None)
    by_rule = collections.Counter(v for _, _, v in verdicts if v)
    samples = collections.defaultdict(list)
    sessions_by_rule = collections.defaultdict(set)
    for _line, obj, why in verdicts:
        if not why:
            continue
        sessions_by_rule[why].add(str(obj.get("session", "")))
        if len(samples[why]) < args.samples:
            samples[why].append("session=%s repo=%s class=%s detail=%s"
                                % (obj.get("session"), obj.get("repo"), obj.get("class"),
                                   str(obj.get("detail", ""))[:48]))

    kept = [(line, obj) for line, obj, why in verdicts if why not in active]
    removed = [(line, obj, why) for line, obj, why in verdicts if why in active]

    print("substitution scrub — %s" % args.log)
    print("rows=%d  malformed=%d  sessions=%d  mode=%s"
          % (len(entries), malformed,
             len({str(o.get("session", "")) for _l, o in entries if o is not None}),
             "ids-only" if args.ids_only else "all rules"))

    print("")
    print("removed, by reason (rules are tried in order; each row is attributed to the first match)")
    print("-" * 92)
    for rule in RULES:
        mark = " " if rule in active else "-"        # "-" = matched but KEPT, because of --ids-only
        print(" %s %-22s %6d row(s)   %4d session(s)   %s"
              % (mark, rule, by_rule.get(rule, 0), len(sessions_by_rule.get(rule, ())), RULE_WHY[rule]))
        for s in samples.get(rule, ()):
            print("      e.g. %s" % s)
    if args.ids_only:
        print("   ('-' rules matched rows that --ids-only KEPT in the cleaned copy)")
    print("")
    print("  removed  %6d row(s)" % len(removed))
    print("  kept     %6d row(s) in %d session(s), %d malformed line(s) preserved verbatim"
          % (len(kept), len({str(o.get("session", "")) for _l, o in kept if o is not None}), malformed))

    # What survives, named — the number the ledger actually wants is "how many REAL sessions are in
    # here", and a session id list is short enough to print and audit by eye.
    print("")
    print("surviving sessions (rows, session)")
    print("-" * 92)
    surviving = collections.Counter(str(o.get("session", "")) for _l, o in kept if o is not None)
    for sid, n in sorted(surviving.items(), key=lambda kv: (-kv[1], kv[0])):
        print("  %6d  %s" % (n, sid))
    if not surviving:
        print("  (none)")

    if not args.out:
        print("")
        print("read-only report; pass --out PATH to write the cleaned copy (the input is never touched)")
        return 0

    # Line order is preserved exactly, malformed lines included: the cleaned file is the input minus
    # some lines, never a re-serialization. A row that round-trips through json.dumps is a row whose
    # bytes changed, and the log's own gate asserts one row is one line as WRITTEN.
    with open(args.out, "w", encoding="utf-8") as fh:
        for line, _obj in kept:
            fh.write(line if line.endswith("\n") else line + "\n")
    print("")
    print("wrote %s  (%d row(s); %s unchanged)" % (args.out, len(kept), args.log))
    return 0


if __name__ == "__main__":
    sys.exit(main())
