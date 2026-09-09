#!/usr/bin/env python3
# loop_ledger.py — what a ripwire call costs across a WHOLE EDIT LOOP, from the agent's own transcript.
#
# THE GAP. Every number ripwire prints is per call: est_tokens on the answer it just wrote. The claim the
# tool makes is per LOOP — "the agent needs no further native read after the call" (METHODOLOGY §9
# principle 1). Those are different quantities, and only the second one can go negative: an answer that
# costs 1,400 tokens and saves three 2,000-token file reads is a win; the same answer followed by the
# three reads anyway is a 1,400-token loss. Nothing in the tree measured the second quantity in TOKENS.
# `bench/substitution_report.py` counts the CALLS (the meter's terminality section, §5) and is the
# ancestor of this file; it deliberately prints no byte or token figure, so a verb could hold its
# terminality rate steady while its answers doubled in size and the report would not move.
#
# WHAT THIS READS, AND THE PRIVACY RULE. Claude Code writes one JSONL per session under
# ~/.claude/projects/<mangled-cwd>/. This script reads ONE project's directory, named on the command
# line, and prints AGGREGATES: per-session token counts and ratios, and distribution summaries over
# sessions. It never prints a prompt, a file path from a transcript, a tool argument, or a session id
# unless --sessions is passed (a local-only debugging aid). Nothing it prints is intended to be pasted
# anywhere that the transcripts themselves would not be.
#
# WHAT IT COUNTS.
#   * TOOL-RESULT tokens, split ripwire / native / other. This is context an answer PUT INTO the window.
#     ripwire  = mcp__ripwire__* tools, plus Bash commands that invoke the binary (`ripwire`,
#                `build/ripwire`, `./build/ripwire`, `asan/ripwire`).
#     native   = Read / Grep / Glob / NotebookRead, plus Bash commands whose head is a retrieval command
#                (grep, rg, cat, head, sed -n, find, ls, awk-over-a-file). These are the calls ripwire is
#                a substitute FOR — the same family split bench/substitution_report.py uses.
#     other    = everything else (edits, builds, git, gates, agent plumbing). Counted, never in a ratio.
#   * NON-TERMINAL ripwire calls: a ripwire call with at least one native call in the NEXT 3 tool calls.
#     Three is the substitution meter's own definition of a post-call sweep, kept identical on purpose so
#     the two instruments are comparable; the meter's own window is 5 and is reported beside it.
#   * PROVIDER-REPORTED session usage from `message.usage` (input / output / cache_creation /
#     cache_read). This is the codeburn-style measurement: what the API actually billed, not an estimate.
#     It is reported beside the tool-result totals so the tool-result share of a session is visible.
#
# TOKENIZER. tiktoken if importable (o200k_base), else bytes / 2.5 with `tokenizer=estimated` stamped on
# the output — never silently. The provider `usage` numbers need no tokenizer and are exact.
#
# Usage:
#   python3 bench/tokenaudit/loop_ledger.py ~/.claude/projects/<dir> [--json OUT] [--sessions]

import argparse
import collections
import glob
import json
import os
import re
import statistics
import sys

NATIVE_TOOLS = frozenset(("Read", "Grep", "Glob", "NotebookRead"))
SWEEP_LOOKAHEAD = 3   # the substitution meter's post-call sweep definition

# ── THE BASH CLASSIFIER IS THE METER'S, DELIBERATELY ──────────────────────────────────────────────
# The first version of this file matched a retrieval command only at the START of the line, and on
# this operator's log that under-counted native retrieval by ~3x: almost every Bash line here begins
# with plumbing (`cd X && grep …`, `echo "=== x ==="; sed -n …`), which is the exact gap
# hooks/ripwire-nudge.sh recorded and fixed in its 2026-08-12 classifier-gap round. The rules below
# are that function's, ported: walk the SEQUENCED segments (`;`, `&&`, `||`) and stop at the first
# the head table decides; do NOT walk pipeline stages (a `| grep` filters the FIRST command's output
# and is not a second observation); `grep -c`/`-q` is a poll, not a search; `cat > f` is a write;
# `sed -n` is a whole-file read; `ls -R` is a walk. The parity is the point — the two instruments
# measure the same population differently ONLY where they are meant to, so a disagreement between
# this file and bench/substitution_report.py is a finding rather than a definition mismatch.
RIPWIRE_WORD = re.compile(r"(^|[\s;&|(`\"'])(\./)?(build/|asan/)?ripwire(?![\w/])")
SEQ_SPLIT = re.compile(r"(?:;|&&|\|\||\n)")
GREP_POLL = re.compile(r"(^|\s)(-[A-Za-z]*[cq][A-Za-z]*|--count|--quiet)(\s|$)")
SED_QUIET = re.compile(r"(^|\s)-[A-Za-z]*n(\s|$)")
LS_WALK = re.compile(r"(^|\s)-[A-Za-z]*R[A-Za-z]*(\s|$)|--recursive(\s|$)")
AWK_PATTERN = re.compile(r"['\"]/")


def classify_segment(seg):
    words = seg.strip().split()
    if not words:
        return None
    lead = words[0]
    if lead == "sudo" and len(words) > 1:
        words = words[1:]
        lead = words[0]
    sub = words[1] if len(words) > 1 else ""
    base = lead.rsplit("/", 1)[-1]
    if base == "ripwire":
        return "ripwire"
    if base in ("grep", "egrep", "fgrep", "zgrep", "rg", "ag", "ack", "ack-grep", "ugrep"):
        return "other" if GREP_POLL.search(seg) else "native"
    if base in ("ps", "pgrep"):
        return "other"
    if base in ("find", "fd", "fdfind"):
        return "native"
    if base in ("cat", "head", "tail", "less", "more", "bat", "nl", "tac"):
        return "other" if sub.startswith(">") else "native"
    if base == "ls":
        return "native" if LS_WALK.search(seg) else None
    if base in ("awk", "gawk", "mawk"):
        return "native" if AWK_PATTERN.search(seg) else None
    if base == "sed":
        return "native" if SED_QUIET.search(seg) else None
    if base == "git":
        return "other"
    return None


def classify(name, inp):
    if isinstance(name, str) and name.startswith("mcp__ripwire__"):
        return "ripwire"
    if name in NATIVE_TOOLS:
        return "native"
    if name == "Bash":
        cmd = inp.get("command") or "" if isinstance(inp, dict) else ""
        # ripwire anywhere on the line wins before the walk, exactly as the meter's head table puts
        # `ripwire` first: `ripwire . --for=x | head -40` is one ripwire call, not a `head`.
        if RIPWIRE_WORD.search(cmd):
            return "ripwire"
        for seg in SEQ_SPLIT.split(cmd):
            verdict = classify_segment(seg)
            if verdict is not None:
                return verdict
    return "other"


def result_text(entry):
    """The bytes a tool result actually put into the context window, as text."""
    out = []
    tur = entry.get("toolUseResult")
    if isinstance(tur, str):
        out.append(tur)
    elif tur is not None:
        out.append(json.dumps(tur, ensure_ascii=False))
    else:
        msg = entry.get("message") or {}
        content = msg.get("content")
        if isinstance(content, list):
            for b in content:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    c = b.get("content")
                    out.append(c if isinstance(c, str) else json.dumps(c, ensure_ascii=False))
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project_dir")
    ap.add_argument("--json", default=None)
    ap.add_argument("--sessions", action="store_true", help="print per-session rows (local debugging only)")
    args = ap.parse_args()

    try:
        import tiktoken
        enc = tiktoken.get_encoding("o200k_base")
        def tok(s):
            return len(enc.encode(s, disallowed_special=()))
        tokenizer = "o200k_base"
    except Exception:
        def tok(s):
            return int(len(s.encode("utf-8", "replace")) / 2.5 + 0.5)
        tokenizer = "estimated(bytes/2.5)"

    files = sorted(glob.glob(os.path.join(os.path.expanduser(args.project_dir), "*.jsonl")))
    sessions = {}

    for path in files:
        # calls: ordered [(family, tool_use_id)]; results: tool_use_id -> tokens
        calls = []
        results = {}
        usage = collections.Counter()
        sid = None
        with open(path, errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                sid = sid or e.get("sessionId")
                msg = e.get("message") or {}
                if e.get("type") == "assistant":
                    u = msg.get("usage") or {}
                    for k in ("input_tokens", "output_tokens",
                              "cache_creation_input_tokens", "cache_read_input_tokens"):
                        v = u.get(k)
                        if isinstance(v, int):
                            usage[k] += v
                    content = msg.get("content")
                    if isinstance(content, list):
                        for b in content:
                            if isinstance(b, dict) and b.get("type") == "tool_use":
                                calls.append((classify(b.get("name"), b.get("input")), b.get("id")))
                elif e.get("type") == "user":
                    ids = []
                    content = msg.get("content")
                    if isinstance(content, list):
                        for b in content:
                            if isinstance(b, dict) and b.get("type") == "tool_result":
                                ids.append(b.get("tool_use_id"))
                    if ids:
                        t = tok(result_text(e))
                        # a result block carries one id in practice; split evenly if ever more
                        for i in ids:
                            results[i] = results.get(i, 0) + t // max(1, len(ids))
        if not calls:
            continue

        fam_tokens = collections.Counter()
        fam_calls = collections.Counter()
        for fam, cid in calls:
            fam_calls[fam] += 1
            fam_tokens[fam] += results.get(cid, 0)

        nonterminal = 0
        rip_total = 0
        for i, (fam, _) in enumerate(calls):
            if fam != "ripwire":
                continue
            rip_total += 1
            if any(calls[j][0] == "native" for j in range(i + 1, min(i + 1 + SWEEP_LOOKAHEAD, len(calls)))):
                nonterminal += 1

        sessions[sid or os.path.basename(path)] = {
            "calls": dict(fam_calls),
            "result_tokens": dict(fam_tokens),
            "ripwire_calls": rip_total,
            "nonterminal_ripwire_calls": nonterminal,
            "provider_usage": dict(usage),
        }

    # ── aggregates only ───────────────────────────────────────────────────────────────────────────
    tot = collections.Counter()
    tot_calls = collections.Counter()
    usage_tot = collections.Counter()
    rip = nonterm = 0
    with_rip = []
    for sid, s in sessions.items():
        for k, v in s["result_tokens"].items():
            tot[k] += v
        for k, v in s["calls"].items():
            tot_calls[k] += v
        for k, v in s["provider_usage"].items():
            usage_tot[k] += v
        rip += s["ripwire_calls"]
        nonterm += s["nonterminal_ripwire_calls"]
        if s["ripwire_calls"]:
            with_rip.append(s)

    report = {
        "schema": "ripwire.loopledger/v1",
        "tokenizer": tokenizer,
        "sweep_lookahead": SWEEP_LOOKAHEAD,
        "sessions": len(sessions),
        "sessions_with_a_ripwire_call": len(with_rip),
        "tool_calls": dict(tot_calls),
        "tool_result_tokens": dict(tot),
        "ripwire_calls": rip,
        "nonterminal_ripwire_calls": nonterm,
        "provider_usage_tokens": dict(usage_tot),
    }
    if rip:
        report["nonterminality_rate"] = round(nonterm / rip, 4)
    n = tot["native"] + tot["ripwire"]
    if n:
        report["ripwire_share_of_retrieval_tokens"] = round(tot["ripwire"] / n, 4)
    if tot_calls["native"] + tot_calls["ripwire"]:
        report["ripwire_share_of_retrieval_calls"] = round(
            tot_calls["ripwire"] / (tot_calls["native"] + tot_calls["ripwire"]), 4)
    for fam in ("ripwire", "native"):
        per = [s["result_tokens"].get(fam, 0) / s["calls"][fam]
               for s in sessions.values() if s["calls"].get(fam)]
        if per:
            report["median_tokens_per_%s_call" % fam] = round(statistics.median(per), 1)
            report["mean_tokens_per_%s_call" % fam] = round(statistics.mean(per), 1)
    if usage_tot:
        billed = sum(usage_tot.values())
        if billed:
            report["tool_result_share_of_billed_tokens"] = round(
                (tot["ripwire"] + tot["native"] + tot["other"]) / billed, 4)

    json.dump(report, sys.stdout, indent=1, sort_keys=True)
    sys.stdout.write("\n")
    if args.json:
        with open(args.json, "w") as f:
            json.dump(report, f, indent=1, sort_keys=True)
            f.write("\n")
    if args.sessions:
        for sid, s in sorted(sessions.items()):
            sys.stderr.write("%s %s\n" % (sid[:8], json.dumps(s, sort_keys=True)))


if __name__ == "__main__":
    main()
