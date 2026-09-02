#!/usr/bin/env python3
# substitution_report.py — read the substitution meter's JSONL log and print counts. Stdlib only,
# deterministic, no arguments beyond the log path (house style: bench/mine_traces.py, bench/calib_json.py).
#
# WHAT THIS REPORTS, AND WHAT IT DELIBERATELY DOES NOT. hooks/ripwire-nudge.sh appends one row per
# observed tool call to ~/.ripwire/substitution.jsonl (schema: docs/SUBSTITUTION_METER.md). This
# script counts those rows. It prints no verdict, no confidence interval and no interpretation —
# every number here is a count or a ratio of counts, and the reader decides what it means.
#
# THE ARM ALTERNATES NOW (since 2026-08-19, `arm=auto`), so §1's arm block is a real comparison rather
# than a placeholder — see "by arm" below. It still prints no verdict and no significance test: the
# decision rule and the pre-registered band live in docs/EVALS.md §4, and a script that printed a
# p-value beside a rate would invite reading one number as the other.
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
# WHICH ROWS ARE COMPARABLE. `arm=auto` (2026-08-19) is what first produced a mixed population; every
# row before that deploy is `treatment` by construction and belongs to no comparison. `--window2` is
# the named cut for that — `2026-08-19T12 <= ts < 2026-09-02T00`, excluding the `smoketest` session —
# and it is the window docs/EVALS.md §4's "PreToolUse nudge A/B" readout is computed over. Without it,
# the arm block below pools the pre-deploy all-treatment rows into the treatment arm and understates
# nothing in particular, which is worse than understating something specific.
#
# WHAT THE ARM BLOCK CANNOT CONTROL FOR, AND SAYS SO. The two arms do not sample the same repositories
# in the same proportions, and repositories differ enormously in baseline substitution. So the block
# prints THREE cuts, in increasing order of how much they control for that: pooled (an artifact,
# printed first and labelled), per repository, and per session with the SESSION as the unit — which is
# the unit `meter_auto_arm` actually randomizes. Read the last one.
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
# TERMINALITY (§5, Track T item T0). An output only saves tokens if it ENDS the question that prompted
# it; one that spawns a sweep is net-additive. §5 turns that into a per-verb count: for each ripwire
# call, look ahead within its session and ask whether a native-search call followed. The window and
# the sweep set are stated in the section's own header and in docs/SUBSTITUTION_METER.md, because a
# terminality number is meaningless without them. Counts and ratios only, as everywhere else here —
# and never a percentage without the n beside it, with an explicit NOTE row under any verb whose n is
# too small to read as a rate.
#
# Usage:
#   python3 bench/substitution_report.py [~/.ripwire/substitution.jsonl] [--top N] [--tag REPO] [--window2]
import argparse
import collections
import json
import os
import re
import sys

RIPWIRE_FAMILY = "ripwire"
NATIVE_FAMILY = "native"

# ── §5 terminality: the three constants the metric is made of ───────────────────────────────────────
# THE SWEEP SET is wider than the `native` family on purpose. `git diff`/`git log`/`git show --stat`
# are history RETRIEVAL — a map followed by a raw git-history sweep did not terminate the question any
# more than a map followed by grep did — so the git-history classes count here even though they are
# deliberately outside §1's substitution ratio, where they are a different QUESTION rather than a
# different tool for the same one. The state-changing git classes (`git-misc`, `git-remote`) are not
# retrieval and are not in the set.
SWEEP_CLASSES = frozenset(("grep", "read", "glob", "find", "git-diff", "git-log", "git-show-stat"))
# The look-ahead is capped so a ripwire call is never blamed for a sweep half a session later.
TERMINALITY_WINDOW = 5
# Below this an n is printed with a NOTE instead of being read as a rate. Not a significance test —
# there is no test to run on a non-randomized single-operator log — just a floor under the reader.
SMALL_N = 10

# A verb-agnostic OPTION is skipped when scanning a command line for the verb. This list is small,
# lexical and deliberately NOT a mirror of the binary's dispatch table (src/main.cpp
# scanReportVerbPrecedence): a mirror of ~70 verbs would rot silently, and the cost of being wrong
# here is one row attributed to a modifier, which the table shows by name rather than hiding. A
# modifier this list does not know is reported AS the verb — that is the disclosure, not a claim of
# completeness.
NON_VERB_FLAGS = frozenset((
    "--no-cache", "--cache-dir", "--no-route", "--route", "--token-budget", "--top-k", "--rank-by",
    "--stable", "--metrics", "--format", "--exclude", "--include", "--jobs", "--lang", "--no-color",
))

# The A/B window, as literals rather than a computed range — see --window2.
WINDOW2_FROM = "2026-08-19T12"
WINDOW2_TO = "2026-09-02T00"

MCP_PREFIX = "mcp__ripwire__"
# The hook caps `detail` at 200 characters, so a long command line can be cut mid-flag. Such a row is
# LABELLED as truncated rather than counted under whatever prefix survived: silently filing `--qualit`
# apart from `--quality-delta` would split one verb's n across two rows and understate both.
DETAIL_CAP = 200
FLAG_RE = re.compile(r"^(--[A-Za-z0-9][A-Za-z0-9-]*)")
# Where the ripwire command ENDS: a pipe, a redirect (`>`, `2>`, `2>&1`), a separator. Flags after one
# of these belong to some other program — `ripwire . | grep -n --color foo` is a map, not a --color.
BREAK_RE = re.compile(r"^(?:[0-9]*[<>]|[|;&])")


def ripwire_token(toks):
    """Index of the word that IS the ripwire command, or None. Matched by basename, so
    `./build/ripwire`, an absolute path and a bare `ripwire` all hit, and a `cd X && VAR=y` prefix in
    front of it is simply skipped over rather than parsed."""
    for i, tok in enumerate(toks):
        if os.path.basename(tok.strip("'\"")) == "ripwire":
            return i
    return None


def ripwire_verb(row):
    """The verb a ripwire-family row asked for, as a label. MCP rows carry it in the tool name; CLI
    rows carry a whole command line in `detail`, so the ripwire word is located (above) and the first
    flag after it — before any shell break — is the verb. A flagless run is the core map.

    Three ways the 200-character `detail` cap defeats that, each named rather than guessed at: cut
    before the ripwire word at all is `(unparsed)`; cut after it with no flag and no shell break yet
    is `(truncated)`, since the verb may be just past the cap; and cut in the MIDDLE of the flag
    yields that flag with a trailing `...`. A complete flag that happens to end a 200-character line
    is indistinguishable from a cut one and is marked the same way — the label errs toward saying so.
    """
    tool = str(row.get("tool") or "")
    if tool.startswith(MCP_PREFIX):
        return "mcp:" + (tool[len(MCP_PREFIX):] or "?")
    detail = str(row.get("detail") or "")
    toks = detail.split()
    capped = len(detail) >= DETAIL_CAP
    start = ripwire_token(toks)
    if start is None:
        return "(unparsed)"
    for i in range(start + 1, len(toks)):
        if BREAK_RE.match(toks[i]):
            return "(map)"          # the ripwire command ended at a pipe/redirect: it took no verb
        m = FLAG_RE.match(toks[i])
        if m and m.group(1) not in NON_VERB_FLAGS:
            return m.group(1) + ("..." if capped and i == len(toks) - 1 else "")
    return "(truncated)" if capped else "(map)"


def session_order(rows):
    """Sessions -> their rows in `seq` order. `session-start` rows are boundaries, not calls, and are
    dropped here for the same reason §4 drops them: they are not a thing an agent chose to run."""
    sessions = collections.defaultdict(list)
    for i, r in enumerate(rows):
        if r.get("class") == "session-start":
            continue
        sessions[str(r.get("session"))].append((r.get("seq", 0), i, r))
    out = []
    for _sid, rs in sorted(sessions.items(), key=lambda kv: str(kv[0])):
        rs.sort(key=lambda t: (t[0], t[1]))
        out.append([t[2] for t in rs])
    return out


def window_verdict(seq_rows, idx):
    """(follow-up class or None, calls seen) for the window after the ripwire call at `idx`.

    The window is the calls after it up to — whichever comes first — the next ripwire call, the end
    of the session, or TERMINALITY_WINDOW calls. `None` means TERMINAL: no sweep-class call appeared
    in it. Otherwise the FIRST sweep-class call is the follow-up — three greps in a row are one
    follow-up, not three."""
    seen = 0
    for nxt in seq_rows[idx + 1:idx + 1 + TERMINALITY_WINDOW]:
        if nxt.get("family") == RIPWIRE_FAMILY:
            break
        seen += 1
        if nxt.get("class") in SWEEP_CLASSES:
            return str(nxt.get("class")), seen
    return None, seen


def terminality(rows):
    """Per-verb (n, terminal, follow-up counter), plus the number of EMPTY windows.

    An empty window — the very next call was another ripwire call, or the session ended — is TERMINAL
    by the definition above, since no sweep happened. That is the definition's softest spot, so the
    count is returned and printed rather than folded in silently: a run of consecutive ripwire calls
    manufactures terminal windows, and the disclosure is what lets a reader discount them."""
    stats = {}
    empty = 0
    for seq_rows in session_order(rows):
        for idx, r in enumerate(seq_rows):
            if r.get("family") != RIPWIRE_FAMILY:
                continue
            st = stats.setdefault(ripwire_verb(r), [0, 0, collections.Counter()])
            st[0] += 1
            follow, seen = window_verdict(seq_rows, idx)
            if seen == 0:
                empty += 1
            if follow is None:
                st[1] += 1
            else:
                st[2][follow] += 1
    return stats, empty


def top_followup(counter):
    """The commonest follow-up class, ties broken alphabetically so the table is deterministic."""
    if not counter:
        return "(none)"
    cls, n = sorted(counter.items(), key=lambda kv: (-kv[1], kv[0]))[0]
    return "%s (%d)" % (cls, n)


def terminality_row(verb, n, term, counter):
    print("  %-24s %6d %10s   %s"
          % (verb, n, "%.1f%%" % (100.0 * term / n) if n else "n/a", top_followup(counter)))
    if 0 < n < SMALL_N:
        print("    NOTE: n=%d (<%d) -- too few calls to read as a rate" % (n, SMALL_N))


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


# ── the arm comparison (§1). See the header for why three cuts and why the last one is the one to read.
ARM_MIN_SESSION_ROWS = 30       # a session below this is a fragment, not a session's worth of behaviour
ARM_MIN_TAG_CALLS = 200         # below this a per-repo ratio is two small numbers divided by each other


def arm_rate(rows, arm):
    """(ripwire, native) for one arm."""
    return split_counts([r for r in rows if r.get("arm", "?") == arm])


def ratio(a, b):
    """a/b as a float, or None when either side has no denominator. Never rounded here — the caller
    formats. A ratio, not a difference, because the LEVELS are operator telemetry: see the standing
    rule recorded in docs/EVALS.md §4."""
    ra, rb = rate(*a), rate(*b)
    return None if (ra is None or rb is None or rb == 0) else ra / rb


def fmt_ratio(r):
    return "     n/a" if r is None else "%8.3f" % r


def session_shares(rows, arm, min_rows=ARM_MIN_SESSION_ROWS):
    """One substitution share per session on `arm`, for sessions with at least `min_rows` rows. A
    session whose rows straddle both arms is DROPPED rather than assigned: that can only happen if the
    arm config changed mid-session, and a unit of randomization that changed identity is not a unit."""
    per = collections.defaultdict(list)
    for r in rows:
        per[str(r.get("session"))].append(r)
    out = []
    for _sid, rs in sorted(per.items(), key=lambda kv: kv[0]):
        arms = {r.get("arm", "?") for r in rs}
        if len(arms) != 1 or arms.pop() != arm:
            continue
        rip, nat = split_counts(rs)
        if len(rs) >= min_rows and rip + nat > 0:
            out.append(rip / (rip + nat))
    return out


def median(values):
    if not values:
        return None
    ordered = sorted(values)
    mid = len(ordered) // 2
    return ordered[mid] if len(ordered) % 2 else 0.5 * (ordered[mid - 1] + ordered[mid])


def post_marker_split(rows, arm, marker):
    """(before, after) row lists around the FIRST call in each session carrying `marker`.

    The marker is written by the hook in BOTH arms — a control session records where a treatment
    session would have been spoken to — so this window is symmetric and the control side is a real
    counterfactual rather than an absence. The firing call itself carries marker=0 (the hook reads the
    flag before setting it), so the moment is the last marker=0 row before the first marker=1 row."""
    per = collections.defaultdict(list)
    for r in rows:
        if r.get("class") == "session-start":
            continue
        per[str(r.get("session"))].append(r)
    before, after, seen = [], [], 0
    for _sid, rs in sorted(per.items(), key=lambda kv: kv[0]):
        arms = {r.get("arm", "?") for r in rs}
        if len(arms) != 1 or arms.pop() != arm:
            continue
        rs.sort(key=lambda r: (r.get("seq", 0),))
        at = next((i for i, r in enumerate(rs) if r.get(marker)), None)
        if at is None or at == 0:
            continue
        seen += 1
        before += rs[max(0, at - 1 - WINDOW_CALLS):at]
        after += rs[at:at + WINDOW_CALLS]
    return before, after, seen


WINDOW_CALLS = 15               # calls either side of the marker moment; stated because a ratio without it means nothing


def arm_section(rows):
    arms = sorted({r.get("arm", "?") for r in rows})
    print("")
    print("  by arm — ratios, not levels (the decision rule and its band: docs/EVALS.md §4):")
    if len(arms) < 2:
        print("    only one arm present (%s) — this log measures a LEVEL, never a difference." % ", ".join(arms))
        for arm in arms:
            print("    %-27s %s" % (arm, fmt_rate(*arm_rate(rows, arm))))
        return
    tre, con = arm_rate(rows, "treatment"), arm_rate(rows, "control")
    print("    %-34s %6s / %-6s  %s" % ("cut", "n(T)", "n(C)", "T/C"))
    print("    %-34s %6d / %-6d %s   <- ARTIFACT: the arms do not sample the same repos" %
          ("pooled (do not read as an effect)", tre[0] + tre[1], con[0] + con[1], fmt_ratio(ratio(tre, con))))

    tags = collections.Counter()
    for r in rows:
        if r.get("family") in (RIPWIRE_FAMILY, NATIVE_FAMILY):
            tags[r.get("tag", "?")] += 1
    for tag, _n in tags.most_common():
        sub = [r for r in rows if r.get("tag") == tag]
        t, c = arm_rate(sub, "treatment"), arm_rate(sub, "control")
        nt, nc = t[0] + t[1], c[0] + c[1]
        if min(nt, nc) < ARM_MIN_TAG_CALLS:
            continue
        print("    %-34s %6d / %-6d %s" % ("repo " + tag[:29], nt, nc, fmt_ratio(ratio(t, c))))
    skipped = sum(1 for tag in tags
                  if min(sum(arm_rate([r for r in rows if r.get("tag") == tag], a)) for a in ("treatment", "control"))
                  < ARM_MIN_TAG_CALLS)
    if skipped:
        print("    (%d repo(s) omitted: fewer than %d rate-eligible calls on one side)" % (skipped, ARM_MIN_TAG_CALLS))

    ts, cs = session_shares(rows, "treatment"), session_shares(rows, "control")
    mt, mc = median(ts), median(cs)
    print("    %-34s %6d / %-6d %s   <- SESSIONS are the unit of randomization: read this one" %
          ("per-session median (>=%d rows)" % ARM_MIN_SESSION_ROWS, len(ts), len(cs),
           fmt_ratio(None if (mt is None or not mc) else mt / mc)))
    print("      n here counts SESSIONS, not calls. No confidence interval is printed: this script")
    print("      reports counts, and the bootstrap interval for this statistic is in docs/EVALS.md §4.")

    print("")
    print("  around the nudge/sweep moment — %d calls either side, treatment beside its counterfactual:" % WINDOW_CALLS)
    print("    %-34s %6s / %-6s  %s" % ("", "n(bef)", "n(aft)", "after/before"))
    for marker, label in (("post_nudge", "any nudge moment"), ("post_sweep", "sweep escalation moment")):
        for arm in ("treatment", "control"):
            before, after, seen = post_marker_split(rows, arm, marker)
            b, a = split_counts(before), split_counts(after)
            tail = "  (the counterfactual: nothing was said here)" if arm == "control" else ""
            print("    %-34s %6d / %-6d %s   %d session(s)%s" %
                  ("%s, %s" % (label, arm), b[0] + b[1], a[0] + a[1], fmt_ratio(ratio(a, b)), seen, tail))
    print("      A decline that the CONTROL arm reproduces is regression to the mean after a sweep,")
    print("      not an effect of anything the hook said. That is what retired both tiers on 2026-09-02.")


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
    ap.add_argument("--window2", action="store_true",
                    help="restrict to the A/B window: 2026-08-19T12 <= ts < 2026-09-02T00, session != smoketest")
    args = ap.parse_args()

    if not os.path.exists(args.log):
        print("substitution_report: no log at %s" % args.log, file=sys.stderr)
        print("  the meter writes one lazily once hooks/ripwire-nudge.sh is registered "
              "(skills/install.sh --hook).", file=sys.stderr)
        return 2

    rows, bad = load(args.log)
    if args.window2:
        # The bounds are LITERAL and CLOSED on both sides on purpose: the lower one is the `arm=auto`
        # deploy (rows before it are all-treatment by construction and belong to no comparison), and
        # the upper one freezes the window so a published number does not drift as the log grows.
        rows = [r for r in rows
                if WINDOW2_FROM <= str(r.get("ts", "")) < WINDOW2_TO and r.get("session") != "smoketest"]
    if args.tag:
        rows = [r for r in rows if r.get("tag") == args.tag]

    print("substitution meter — %s" % args.log)
    print("rows=%d  malformed=%d  sessions=%d  repos=%d%s%s"
          % (len(rows), bad,
             len({r.get("session") for r in rows}),
             len({r.get("tag") for r in rows}),
             ("  tag=%s" % args.tag) if args.tag else "",
             ("  window2=[%s,%s)" % (WINDOW2_FROM, WINDOW2_TO)) if args.window2 else ""))
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

    arm_section(rows)

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

    # ── §5 terminality by verb ──────────────────────────────────────────────────────────────────────
    # §4 asks which chains recur; this asks the sharper question underneath it — of the chains that
    # START with ripwire, how many END there. The definitions are printed above the table rather than
    # left to the docs, because a terminality percentage read without its window rule is a number
    # somebody will quote wrong. The reader gets counts; which verb to enrich is Track T's judgment.
    section("5. terminality by verb (did the output END the question, or spawn a sweep?)")
    print("  window   : the calls after a ripwire call, up to the next ripwire call, the session end,")
    print("             or %d calls -- whichever comes first" % TERMINALITY_WINDOW)
    print("  TERMINAL : no sweep-class call in the window.  sweep = %s"
          % " ".join(sorted(SWEEP_CLASSES)))
    print("")
    print("  %-24s %6s %10s   %s" % ("verb", "n", "terminal%", "top follow-up"))
    stats, empty = terminality(rows)
    if not stats:
        print("  (no ripwire-family calls in this log -- nothing to measure)")
        return 0
    for verb, (n, term, counter) in sorted(stats.items(), key=lambda kv: (-kv[1][0], kv[0])):
        terminality_row(verb, n, term, counter)
    allc = collections.Counter()
    for _v, (_n, _t, counter) in stats.items():
        allc.update(counter)
    terminality_row("(all)", sum(s[0] for s in stats.values()), sum(s[1] for s in stats.values()), allc)
    print("")
    print("  empty windows: %d of %d -- the next observed call was another ripwire call, or the"
          % (empty, sum(s[0] for s in stats.values())))
    print("                 session ended. These count TERMINAL by the definition above.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
