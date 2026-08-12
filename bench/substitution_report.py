#!/usr/bin/env python3
# substitution_report.py — read the substitution meter's JSONL log and print counts. Stdlib only,
# deterministic, no arguments beyond the log path (house style: bench/mine_traces.py, bench/calib_json.py).
#
# WHAT THIS REPORTS, AND WHAT IT DELIBERATELY DOES NOT. hooks/ripwire-nudge.sh appends one row per
# observed tool call to ~/.ripwire/substitution.jsonl (schema: docs/SUBSTITUTION_METER.md). This
# script counts those rows. It prints no verdict, no confidence interval and no interpretation —
# every number here is a count or a ratio of counts, and the reader decides what it means. That is
# deliberate: the meter is in its OBSERVE-FIRST phase, the arm assignment is not yet alternating, and
# a rate computed over a non-randomized sample is a description of what happened, not an effect.
#
#   substitution rate = ripwire / (ripwire + native)
#
# where `ripwire` is the ripwire-cli + ripwire-mcp families and `native` is the grep/find/read/glob
# family — the calls ripwire is a substitute FOR. The `git`, `other` and `meta` families (git
# diff/log/remote/state, build, gate runs, shell plumbing) and `unclassified` are counted and printed
# but kept OUT of the ratio: the first are different questions than retrieval, the last is by
# definition a call this tool could not read, and folding either into a headline rate would launder
# an unknown into a denominator.
#
# THE ARM HAS ALWAYS BEEN `treatment`. No control session has ever been run, so every rate below is a
# LEVEL, never a difference, and nothing here is a causal claim about the nudge.
#
# THE CONFOUND, MADE VISIBLE RATHER THAN CORRECTED. The hook's own nudge is a cause of the next
# ripwire call, so a single pooled rate partly measures the hook talking to itself. The split below is
# the whole point: `post_nudge=0` rows are the calls made BEFORE any nudge fired in that session — the
# closest thing to an unprompted baseline this log contains — and `post_nudge=1` rows are everything
# after. Read them separately; do not average them and call it a rate.
#
# SEQUENCE BUNDLES (§4). The efficiency opportunity is hypothesized to live in multi-call CHAINS
# (grep -> read -> read) rather than single calls, so §4 counts within-session class bigrams and
# trigrams in seq order. A chain that recurs is a candidate SCENARIO for one verb to absorb whole.
# Counts only — which chain is worth absorbing is the S4 survey's judgment, not this script's.
#
# Usage:
#   python3 bench/substitution_report.py [~/.ripwire/substitution.jsonl] [--top N] [--tag REPO]
import argparse
import collections
import json
import os
import sys

RIPWIRE_FAMILY = "ripwire"
NATIVE_FAMILY = "native"


def load(path):
    """Rows, in file order. A malformed line is counted and skipped — never fatal, never silent."""
    rows, bad = [], 0
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                bad += 1
                continue
            if isinstance(obj, dict):
                rows.append(obj)
            else:
                bad += 1
    return rows, bad


def rate(rip, nat):
    total = rip + nat
    return None if total == 0 else rip / total


def fmt_rate(rip, nat):
    r = rate(rip, nat)
    total = rip + nat
    if r is None:
        return "     n/a  (0 calls)"
    return "%6.1f%%  (%d ripwire / %d total)" % (100.0 * r, rip, total)


def split_counts(rows):
    rip = sum(1 for r in rows if r.get("family") == RIPWIRE_FAMILY)
    nat = sum(1 for r in rows if r.get("family") == NATIVE_FAMILY)
    return rip, nat


def section(title):
    print("")
    print(title)
    print("-" * len(title))


def main():
    ap = argparse.ArgumentParser(description="count substitution-meter rows")
    ap.add_argument("log", nargs="?",
                    default=os.path.join(os.environ.get("RIPWIRE_HOME",
                                                        os.path.join(os.path.expanduser("~"), ".ripwire")),
                                         "substitution.jsonl"),
                    help="path to substitution.jsonl (default: ~/.ripwire/substitution.jsonl)")
    ap.add_argument("--top", type=int, default=15, help="how many n-gram rows to print (default 15)")
    ap.add_argument("--tag", default=None, help="restrict to one repo tag")
    args = ap.parse_args()

    if not os.path.exists(args.log):
        print("substitution_report: no log at %s" % args.log, file=sys.stderr)
        print("  the meter writes one lazily once hooks/ripwire-nudge.sh is registered "
              "(skills/install.sh --hook).", file=sys.stderr)
        return 2

    rows, bad = load(args.log)
    if args.tag:
        rows = [r for r in rows if r.get("tag") == args.tag]

    print("substitution meter — %s" % args.log)
    print("rows=%d  malformed=%d  sessions=%d  repos=%d%s"
          % (len(rows), bad,
             len({r.get("session") for r in rows}),
             len({r.get("tag") for r in rows}),
             ("  tag=%s" % args.tag) if args.tag else ""))
    if not rows:
        print("\n(no rows to report)")
        return 0

    # ── §1 the headline ─────────────────────────────────────────────────────────────────────────────
    section("1. substitution rate = ripwire / (ripwire + native)")
    rip, nat = split_counts(rows)
    print("  overall           %s" % fmt_rate(rip, nat))

    print("")
    print("  by nudge exposure (the hook's own nudge is a cause — read these apart, never pooled):")
    for label, pred in (
        ("pre-nudge   (post_nudge=0)", lambda r: not r.get("post_nudge")),
        ("post-nudge  (post_nudge=1)", lambda r: bool(r.get("post_nudge"))),
    ):
        sub = [r for r in rows if pred(r)]
        print("    %-27s %s" % (label, fmt_rate(*split_counts(sub))))
    print("    %-27s %s" % ("calls a nudge fired on", "%d" % sum(1 for r in rows if r.get("nudged"))))

    # The pre-registered readout in docs/EVALS.md §4 reads exactly this block. `post_sweep` is
    # RECORDED by the hook, not reconstructed here, so the grouping is an assignment the analysis
    # reads rather than one it infers. A v1 row has no `post_sweep` field at all; absent reads as 0,
    # which is correct — the escalation did not exist when that row was written.
    print("")
    print("  by SWEEP-escalation exposure (docs/EVALS.md §4 registers the band on the 2nd line):")
    for label, pred in (
        ("pre-sweep   (post_sweep=0)", lambda r: not r.get("post_sweep")),
        ("post-sweep  (post_sweep=1)", lambda r: bool(r.get("post_sweep"))),
    ):
        sub = [r for r in rows if pred(r)]
        print("    %-27s %s" % (label, fmt_rate(*split_counts(sub))))
    esc = [r for r in rows if str(r.get("nudge", "")).startswith("sweep")]
    print("    %-27s %d  in %d session(s)"
          % ("escalations fired", len(esc), len({r.get("session") for r in esc})))
    byv = collections.Counter(r.get("v", "?") for r in rows)
    if len(byv) > 1:
        print("    %-27s %s" % ("SCHEMA MIX", ", ".join("v%s=%d" % (k, n) for k, n in sorted(byv.items(),
                                                                                            key=str))))
        print("      counts are NOT comparable across the v1/v2 boundary — the classifier widened.")
        print("      Replay the v1 rows' `detail` through the current hook before comparing rates.")

    print("")
    print("  by arm (dormant until alternation is switched on — expect all-treatment for now):")
    for arm in sorted({r.get("arm", "?") for r in rows}):
        sub = [r for r in rows if r.get("arm", "?") == arm]
        print("    %-27s %s" % (arm, fmt_rate(*split_counts(sub))))

    # ── §2 the composition of both sides ────────────────────────────────────────────────────────────
    section("2. calls by class (what the rate is made of)")
    byclass = collections.Counter(r.get("class", "?") for r in rows)
    byfamily = collections.Counter(r.get("family", "?") for r in rows)
    for fam in ("ripwire", "native", "git", "other", "meta"):
        if not byfamily.get(fam):
            continue
        print("  %-8s %6d" % (fam, byfamily[fam]))
        for cls, n in sorted(byclass.items(), key=lambda kv: (-kv[1], kv[0])):
            if any(r.get("class") == cls and r.get("family") == fam for r in rows):
                print("      %-16s %6d" % (cls, n))
    unc = byclass.get("unclassified", 0)
    if unc:
        print("")
        print("  NOTE: %d unclassified row(s) are excluded from the rate above. They are logged, not"
              % unc)
        print("        dropped — a growing count here means the classifier needs a rule, and the")
        print("        `detail` field on those rows is the evidence for which one.")

    # ── §3 per repo ─────────────────────────────────────────────────────────────────────────────────
    section("3. by repo")
    tags = collections.Counter(r.get("tag", "?") for r in rows)
    for tag, n in sorted(tags.items(), key=lambda kv: (-kv[1], kv[0])):
        sub = [r for r in rows if r.get("tag") == tag]
        print("  %-24s %6d calls   %s" % (tag[:24], n, fmt_rate(*split_counts(sub))))

    # ── §4 within-session chains ────────────────────────────────────────────────────────────────────
    # Ordering inside a session is `seq`, the hook's per-session monotonic counter — not `ts`, which is
    # second-resolution and collides freely inside an agent loop. Rows are grouped by session and
    # n-grams are taken over ADJACENT observed calls only; a session contributes no n-gram that spans
    # a gap this meter never saw, because a gap this meter never saw is not a gap it can measure.
    section("4. command-class chains within a session (scenario bundles)")
    sessions = collections.defaultdict(list)
    for r in rows:
        if r.get("class") == "session-start":
            continue
        sessions[r.get("session")].append(r)
    seqs = []
    for _sid, rs in sorted(sessions.items(), key=lambda kv: str(kv[0])):
        rs.sort(key=lambda r: (r.get("seq", 0),))
        seqs.append([r.get("class", "?") for r in rs])

    print("  %d session(s), %d call(s) in chains, longest %d"
          % (len(seqs), sum(len(s) for s in seqs), max((len(s) for s in seqs), default=0)))
    for n, label in ((2, "bigrams"), (3, "trigrams")):
        grams = collections.Counter()
        for s in seqs:
            for i in range(len(s) - n + 1):
                grams[tuple(s[i:i + n])] += 1
        print("")
        print("  top %s (n-gram, count):" % label)
        if not grams:
            print("    (none — no session has %d adjacent observed calls)" % n)
            continue
        for gram, c in sorted(grams.items(), key=lambda kv: (-kv[1], kv[0]))[:args.top]:
            print("    %-46s %6d" % (" -> ".join(gram), c))

    return 0


if __name__ == "__main__":
    sys.exit(main())
