#!/usr/bin/env python3
# routing_ab_report.py — the adoption-within-two readout for the Claude Code prompt router A/B
# pre-registered in docs/EVALS.md §4 ("Claude Code prompt router"). Stdlib only, deterministic, no
# interpretation beyond the pre-registered band itself.
#
# NOT bench/routing_report.py. That script already exists (`feat: close the Codex routing feedback
# loop`, shipped 2026-08-28, gated by test/codexpromptroutecheck.sh, documented in docs/EVALS.md's
# "`--help-task` adoption" section) and reports ONE completed-route denominator, by intent, for the
# Codex router — it has no concept of an arm and is not filtered by `agent`, so it silently pools any
# `agent="claude"` rows that land in the same log into its Codex-labelled counts (confirmed against
# the real ~/.ripwire/routing.jsonl: 38 claude-agent rows currently read straight through it). This
# script is that instrument's sibling, not a replacement: a different metric (a between-arm DIFFERENCE,
# not a level), a different population (`agent="claude"` only), and a different gating question (a
# pre-registered KEEP/REWORD/REMOVE band with a hard minimum-n floor, not an `underpowered` label on a
# single count). Reusing the Codex script's parsing shape (`load_rows`-style tolerant JSONL read) was
# preferred over inventing a new one; the arm/join/band logic below has no analogue there to reuse.
#
# WHAT IS BEING MEASURED. hooks/ripwire-claude-route.sh writes one `UserPromptSubmit` row per submitted
# prompt to ~/.ripwire/routing.jsonl — `status="recommend"` when the `--help-task` classifier names a
# verb, `status="abstain"` otherwise — and, only on a `recommend`, a pending file that its own
# `--observe` arm (called from hooks/ripwire-nudge.sh's PreToolUse path) consumes to write a
# `RouteObservation` row: did either of the next two ripwire-family tool calls in that session use the
# recommended verb (`outcome="adopted"`), or not (`"missed"`/`"continued"`). Both arms — the injected
# `treatment` and the silent `control` — write identical rows; only the arm actually spoken to differs.
# `bench/substitution_report.py` reads the SEPARATE substitution meter (~/.ripwire/substitution.jsonl,
# one row per observed tool call) that the join-coverage line below cross-checks against.
#
# THE UNIT IS A RECOMMENDED PROMPT. For each `UserPromptSubmit` row with `status="recommend"`, adoption
# is TRUE iff some `RouteObservation` row for the same (`session_hash`, `prompt_hash`) pair, at
# `position` 1 or 2 (the pre-registered two-call window — the hook itself never writes a `position`
# past 2, since its pending file is gone by the third ripwire-family call, but the window is enforced
# here too rather than trusted blindly from the log), carries `outcome="adopted"`.
#
# THE BAND, restated as data rather than re-derived, so this script and docs/EVALS.md §4 cannot quietly
# diverge: KEEP >= +10pp, REWORD 0..+10pp, REMOVE <= 0pp, treatment-minus-control adoption-within-two,
# and NO VERDICT below 40 recommended prompts per arm — that floor is enforced unconditionally below;
# there is no flag that overrides it, and none should be added.
#
# WHAT THIS NEVER OPENS. Exactly the two paths named by --routing and --meter — nothing else on disk,
# ever. routing.jsonl carries no prompt text by construction (a cksum and a byte length only), and this
# script never reads a field that could hold any (`detail`, transcripts, repo content); every number
# printed below is a count, a rate, or a file path the caller supplied.
#
# CODEX SHARES routing.jsonl. hooks/ripwire-codex-route.sh writes to it with no `agent` field and no
# `arm` — pooling those rows into either arm would put an un-armed population on one side of the band,
# so every row read here is filtered to `agent="claude"` first, exactly as the hook's own `--observe`
# arm filters (`.agent // "codex"`).
#
# Usage:
#   python3 bench/routing_ab_report.py [--routing PATH] [--meter PATH] [--since AT] [--until AT]
# Exit 0 on a normal readout OR a refusal (refusing below the floor is a correct answer, not a
# failure); non-zero only when an input file's content cannot be read as this instrument's data at all.
import argparse
import os
import subprocess
import sys
import json

MIN_RECOMMENDED_PER_ARM = 40   # docs/EVALS.md §4 — pre-registered before the first row existed
KEEP_PP = 10.0                 # KEEP >= +10pp; REWORD is (0, +10)pp; REMOVE <= 0pp
ARMS = ("treatment", "control")
AGENT = "claude"                # routing.jsonl is shared with the Codex router; see header


def default_home():
    return os.environ.get("RIPWIRE_HOME", os.path.join(os.path.expanduser("~"), ".ripwire"))


def load_jsonl(path):
    """(rows, malformed, existed). Opens exactly `path` and nothing else. A line that is not valid JSON
    or not a JSON object is counted and skipped rather than raising, mirroring
    bench/substitution_report.py's load(); a log that does not exist yet is 0 rows, not an error — this
    instrument may ship before the router has written its first row."""
    if not os.path.exists(path):
        return [], 0, False
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
    return rows, bad, True


def is_malformed(rows, bad):
    """A file is unreadable AS THIS INSTRUMENT'S DATA when it has content and NONE of it parsed — a
    handful of dropped lines from a torn write is tolerated (counted, disclosed, not fatal); a file
    that is entirely something else (binary, prose, the wrong schema) is not."""
    return (len(rows) + bad) > 0 and len(rows) == 0


def cksum_hash(text):
    """The exact hash hooks/ripwire-claude-route.sh's hash_text() computes for a session id:
    `printf '%s' text | cksum`, first field. Shelled out to the real `cksum` binary rather than
    reimplemented, so this can never drift from the hook's own definition of session_hash."""
    try:
        proc = subprocess.run(["cksum"], input=text.encode("utf-8", "replace"),
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    out = proc.stdout.decode("ascii", "replace").strip()
    return out.split()[0] if out else None


def filter_window(rows, since, until):
    """Rows with `at` in [since, until) — lexical comparison on the ISO8601-Z timestamp, the same
    literal-bounds style bench/substitution_report.py's --window2 uses. Applied to the whole log before
    it is split into prompts/observations, so a recommended prompt just inside the window whose
    observation landed just outside it is dropped from both sides consistently rather than half-joined."""
    if since:
        rows = [r for r in rows if str(r.get("at", "")) >= since]
    if until:
        rows = [r for r in rows if str(r.get("at", "")) < until]
    return rows


def split_events(rows):
    """(prompts, observations) — `agent="claude"` rows only; see header."""
    prompts = [r for r in rows if r.get("agent") == AGENT and r.get("event") == "UserPromptSubmit"]
    obs = [r for r in rows if r.get("agent") == AGENT and r.get("event") == "RouteObservation"]
    return prompts, obs


def adoption_key(row):
    return (row.get("session_hash"), row.get("prompt_hash"))


def compute_arm(prompts, obs, arm):
    """One arm's numbers: prompts (all statuses), recommended, adopted-within-two, its rate, sessions."""
    arm_prompts = [r for r in prompts if r.get("arm") == arm]
    recommended = [r for r in arm_prompts if r.get("status") == "recommend"]
    sessions = len({r.get("session_hash") for r in arm_prompts if r.get("session_hash")})

    adopted_keys = set()
    for r in obs:
        if r.get("arm") != arm or r.get("outcome") != "adopted":
            continue
        if r.get("position") not in (1, 2):    # the two-call window, enforced here too — see header
            continue
        adopted_keys.add(adoption_key(r))

    adopted_n = sum(1 for r in recommended if adoption_key(r) in adopted_keys)
    rate = (100.0 * adopted_n / len(recommended)) if recommended else None
    return {
        "prompts": len(arm_prompts),
        "recommended": len(recommended),
        "adopted": adopted_n,
        "rate": rate,
        "sessions": sessions,
    }


def join_coverage(prompts, meter_rows):
    """(routing rows whose session_hash has >=1 meter row, routing rows total). The meter's `session`
    field is the raw session id; routing's `session_hash` is that id's cksum (see cksum_hash) — so the
    meter's distinct sessions are hashed once and compared as a set against every routing row's
    session_hash. This is the ONLY place this script touches the meter log's content at all."""
    total = len(prompts)
    if total == 0:
        return 0, 0
    meter_sessions = {str(r.get("session")) for r in meter_rows if r.get("session")}
    meter_hashes = set()
    for s in meter_sessions:
        h = cksum_hash(s)
        if h is not None:
            meter_hashes.add(h)
    covered = sum(1 for r in prompts if r.get("session_hash") in meter_hashes)
    return covered, total


def verdict_line(t, c):
    """The pre-registered decision, or the refusal line naming the band and how many more recommended
    prompts each arm needs. Never a verdict below the floor — there is no flag that overrides this."""
    need_t = max(0, MIN_RECOMMENDED_PER_ARM - t["recommended"])
    need_c = max(0, MIN_RECOMMENDED_PER_ARM - c["recommended"])
    if need_t or need_c:
        return ("UNDERPOWERED -- band (docs/EVALS.md §4) needs >= %d recommended prompts per arm: "
                "treatment has %d (needs %d more), control has %d (needs %d more)"
                % (MIN_RECOMMENDED_PER_ARM, t["recommended"], need_t, c["recommended"], need_c))
    diff_pp = t["rate"] - c["rate"]
    if diff_pp >= KEEP_PP:
        label = "KEEP"
    elif diff_pp <= 0:
        label = "REMOVE"
    else:
        label = "REWORD"
    return ("%s -- treatment %.1f%% - control %.1f%% = %+.1fpp  "
            "(band: KEEP >= +%.0fpp, REWORD 0..+%.0fpp, REMOVE <= 0pp)"
            % (label, t["rate"], c["rate"], diff_pp, KEEP_PP, KEEP_PP))


def main():
    ap = argparse.ArgumentParser(
        description="adoption-within-two A/B readout for the Claude Code prompt router (docs/EVALS.md §4)")
    ap.add_argument("--routing", default=os.path.join(default_home(), "routing.jsonl"),
                     help="path to routing.jsonl (default: $RIPWIRE_HOME or ~/.ripwire, routing.jsonl)")
    ap.add_argument("--meter", default=os.path.join(default_home(), "substitution.jsonl"),
                     help="path to substitution.jsonl (default: $RIPWIRE_HOME or ~/.ripwire, substitution.jsonl)")
    ap.add_argument("--since", default=None, help="only rows with at >= this ISO8601 timestamp")
    ap.add_argument("--until", default=None, help="only rows with at < this ISO8601 timestamp")
    args = ap.parse_args()

    routing_rows, routing_bad, routing_existed = load_jsonl(args.routing)
    meter_rows, meter_bad, meter_existed = load_jsonl(args.meter)

    if is_malformed(routing_rows, routing_bad):
        print("routing_ab_report: %s has content but no line parses as a JSON object -- malformed input"
              % args.routing, file=sys.stderr)
        return 1
    if is_malformed(meter_rows, meter_bad):
        print("routing_ab_report: %s has content but no line parses as a JSON object -- malformed input"
              % args.meter, file=sys.stderr)
        return 1

    routing_rows = filter_window(routing_rows, args.since, args.until)
    prompts, obs = split_events(routing_rows)

    print("routing_ab_report -- routing=%s meter=%s" % (args.routing, args.meter))
    print("rows read: routing=%d (malformed=%d, %s)  meter=%d (malformed=%d, %s)"
          % (len(routing_rows), routing_bad, "found" if routing_existed else "not found",
             len(meter_rows), meter_bad, "found" if meter_existed else "not found"))
    if args.since or args.until:
        print("window: [%s, %s)" % (args.since or "-inf", args.until or "+inf"))

    print("")
    print("%-10s %8s %12s %10s %8s %9s" % ("arm", "prompts", "recommended", "adopted", "rate", "sessions"))
    arm_stats = {}
    for arm in ARMS:
        st = compute_arm(prompts, obs, arm)
        arm_stats[arm] = st
        rate_s = "n/a" if st["rate"] is None else "%.1f%%" % st["rate"]
        print("%-10s %8d %12d %10d %8s %9d"
              % (arm, st["prompts"], st["recommended"], st["adopted"], rate_s, st["sessions"]))

    covered, total = join_coverage(prompts, meter_rows)
    if total:
        print("\njoin coverage: %d/%d routing row(s) (%.1f%%) have a session with >=1 meter row"
              % (covered, total, 100.0 * covered / total))
    else:
        print("\njoin coverage: no routing rows to join")

    print("")
    print(verdict_line(arm_stats["treatment"], arm_stats["control"]))

    return 0


if __name__ == "__main__":
    sys.exit(main())
