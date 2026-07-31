#!/usr/bin/env python3
# mine_traces.py — mine (query, gold_files) retrieval-eval pairs from LOCAL Claude Code session
# transcripts (DESIGN_traceEvals.md). Stdlib-only, house style matching bench/locbench/run_locbench.py
# (dependency-light, LLM-free, deterministic).
#
# WHAT THIS IS. Claude Code already writes every user prompt and every Edit/Write/Read tool call (with
# file paths) to ~/.claude/projects/<repo-slug>/*.jsonl for its own resume feature. This is free,
# already-on-disk ore for a retrieval eval: segment a session into tasks (§2.1), gold = the files that
# task's Edit/Write calls actually touched (§2.2), tag sessions that used ctxpack itself so the consumer
# never grades ctxpack's own homework as independent evidence (§3.2). See DESIGN_traceEvals.md in full —
# this file implements it verbatim.
#
# PRIVACY (§4, hard rule): local-only, opt-in, explicit invocation only. Reads only
# ~/.claude/projects/**/*.jsonl and writes only local files. Refuses to write inside the target repo's
# working tree unless --export-sanitized is passed (a hard repo-root-prefix check, non-zero exit, no
# file created — see main()). No network client exists in this script. No wall-clock data is ever
# written to the artifact (mined_at was considered and rejected post-review — see DESIGN_traceEvals.md
# §5.1 — it would break the Gate #1 byte-identical determinism contract).
#
# USAGE:
#   python3 bench/mine_traces.py --repo /path/to/repo                  # writes ~/.ctxpack/traceevals/<hash>.jsonl
#   python3 bench/mine_traces.py --repo . --dry-run                    # segment/gold histogram, no write
#   python3 bench/mine_traces.py --repo . --only-committed             # opt-in strict filter, §3.1
#   python3 bench/mine_traces.py --repo . --export-sanitized out.jsonl # query redacted to a skeleton,
#                                                                       # session_id dropped — the only way
#                                                                       # mined data may land inside the repo
#
# Deterministic given (repo, the session *.jsonl files' bytes, --only-committed's git HEAD): sorted file
# order, sorted dedup passes, no RNG, no timestamps in the artifact — two runs are byte-identical (Gate #1).

import argparse
import collections
import glob
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys

MINER_VERSION   = 1
MIN_QUERY_CHARS = 24     # §2.1 — below this, a "user" turn is noise, not a task trigger
QUERY_TRUNC     = 2000   # §2.1 — mirrors bench/locbench's --query-chars posture
JACCARD_NEAR_DUP = 0.90  # §2.3 — near-dup gold-set collapse threshold

CTXPACK_BASH_RE = re.compile(r'(?:^|[\s;|&])ctxpack(?:\s|$)')   # §3.2 — Bash-invoked ctxpack

# a small, deliberately short stopword list for the --export-sanitized skeleton's "top subtokens" —
# NOT used anywhere in the real (unsanitized) artifact, which keeps the verbatim query.
_SKELETON_STOPWORDS = {
    "the", "and", "for", "that", "this", "with", "from", "into", "then", "than", "have", "has", "had",
    "was", "were", "are", "not", "but", "you", "your", "all", "any", "can", "will", "would", "could",
    "should", "also", "its", "our", "out", "how", "what", "when", "where", "which", "who", "why", "use",
    "using", "used", "please", "let", "make", "need", "want", "one", "two", "now", "just", "like",
}


# ── §1: locate the session transcripts for `repo` ───────────────────────────────────────────────────
def project_slug(repo_abspath: str) -> str:
    # Claude Code's own project-dir naming: the absolute repo path with every '/' and '.' → '-'.
    return re.sub(r"[/.]", "-", repo_abspath)


def project_dir(repo_abspath: str) -> pathlib.Path:
    return pathlib.Path.home() / ".claude" / "projects" / project_slug(repo_abspath)


# ── §2.1: real user turns ────────────────────────────────────────────────────────────────────────────
def _collapse_ws(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def real_user_text(message_content):
    # Returns the collapsed, non-trivial text of a REAL user turn, or None. A `content` that is a list
    # of blocks where every block is a `tool_result` (a synthetic reply, not a real prompt) yields no
    # `text`-type block and so correctly returns None here.
    if isinstance(message_content, str):
        t = _collapse_ws(message_content)
        return t if len(t) >= MIN_QUERY_CHARS else None
    if isinstance(message_content, list):
        texts = [b.get("text", "") for b in message_content if isinstance(b, dict) and b.get("type") == "text"]
        t = _collapse_ws(" ".join(texts))
        return t if len(t) >= MIN_QUERY_CHARS else None
    return None


def tool_use_blocks(message_content):
    if not isinstance(message_content, list):
        return
    for b in message_content:
        if isinstance(b, dict) and b.get("type") == "tool_use":
            yield b


# ── §2.2: gold, in-repo filter, revert detection ─────────────────────────────────────────────────────
def norm_rel(repo_root: str, file_path):
    # Repo-relative POSIX path if `file_path` is inside `repo_root`, else None (scratchpad/memory noise
    # — §2.2's "Writes outside the repo tree" exclusion). String-based only: no disk access, so this
    # works identically for real sessions and hand-authored fixtures whose paths don't exist on disk.
    if not file_path:
        return None
    ap = os.path.normpath(file_path)
    root = os.path.normpath(repo_root)
    if ap == root or not ap.startswith(root + os.sep):
        return None
    rel = os.path.relpath(ap, root)
    return rel.replace(os.sep, "/")


class Segment:
    __slots__ = ("query_parts", "start_line", "end_line", "edits", "edit_stack", "write_touched",
                 "has_edit", "assisted", "_next_order")

    def __init__(self, query, start_line):
        self.query_parts = [query]
        self.start_line = start_line
        self.end_line = start_line
        self.edits = {}          # relpath -> {"order": int, "count": int}
        self.edit_stack = {}     # relpath -> [(old,new), ...]  (Edit-tool only; revert detection)
        self.write_touched = set()   # relpaths touched by Write at least once (revert-undetectable — keep)
        self.has_edit = False
        self.assisted = False
        self._next_order = 1

    @property
    def query(self):
        return "\n---\n".join(self.query_parts)


def record_edit(seg: Segment, repo_root: str, tool_name: str, tool_input: dict):
    rel = norm_rel(repo_root, tool_input.get("file_path"))
    if rel is None:
        return
    e = seg.edits.get(rel)
    if e is None:
        e = {"order": seg._next_order, "count": 0}
        seg.edits[rel] = e
        seg._next_order += 1
    e["count"] += 1
    seg.has_edit = True
    if tool_name == "Edit":
        old, new = tool_input.get("old_string"), tool_input.get("new_string")
        if old is not None and new is not None:
            stack = seg.edit_stack.setdefault(rel, [])
            if stack and stack[-1] == (new, old):
                stack.pop()          # this edit exactly undoes the immediately-prior one
            else:
                stack.append((old, new))
    else:
        seg.write_touched.add(rel)   # Write: no before/after diff recorded here — degrade to "keep" (§3.1)


def segment_gold(seg: Segment):
    # §3.1 mitigation: drop a gold file whose net edits in this segment cancel out to nothing (detectable
    # only for Edit-tool sequences, via the undo-stack in record_edit). Not determinable (Write-touched,
    # or no Edit history at all) → keep, never silently drop unprovable signal.
    gold = []
    for rel, e in seg.edits.items():
        reverted = rel in seg.edit_stack and not seg.edit_stack[rel] and rel not in seg.write_touched
        if reverted:
            continue
        gold.append((rel, e["order"], e["count"]))
    gold.sort(key=lambda x: x[1])
    return gold


# ── walk one session file → raw (pre-dedup) pairs ────────────────────────────────────────────────────
def mine_session_file(path: str, repo_root: str, min_gold: int):
    pairs = []
    session_id = pathlib.Path(path).stem
    seg = None

    def finalize(s: "Segment"):
        gold = segment_gold(s)
        if len(gold) < min_gold:
            return
        pairs.append({
            "query": s.query[:QUERY_TRUNC],
            "gold_files": [{"path": p, "edit_order": o, "edit_count": c} for p, o, c in gold],
            "session_id": session_id,
            "segment_start_line": s.start_line,
            "segment_end_line": s.end_line,
            "ctxpack_assisted": s.assisted,
        })

    with open(path, encoding="utf-8", errors="replace") as fh:
        for lineno, raw in enumerate(fh, start=1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                ev = json.loads(raw)
            except json.JSONDecodeError:
                continue
            etype = ev.get("type")
            if etype == "user":
                # §2.1 "real user turn": harness-generated turns (task-notification wake-ups, resume
                # frames) carry origin.kind != "human" — events, not asks. Absent origin → keep
                # (older transcripts and hand-authored fixtures don't carry the field; degrade permissive).
                origin_kind = (ev.get("origin") or {}).get("kind")
                if origin_kind is not None and origin_kind != "human":
                    continue
                text = real_user_text((ev.get("message") or {}).get("content"))
                if text is None:
                    continue      # synthetic tool_result-only turn, or below MIN_QUERY_CHARS — not a trigger
                text = text[:QUERY_TRUNC]
                if seg is None:
                    seg = Segment(text, lineno)
                elif seg.has_edit:
                    finalize(seg)                      # a fresh ask after completed work = a new segment (§2.1)
                    seg = Segment(text, lineno)
                else:
                    seg.query_parts.append(text)        # follow-up BEFORE any edit → folds into the running query
                    seg.end_line = lineno
            elif etype == "assistant":
                if seg is None:
                    continue     # no real user turn opened a segment yet — nothing to attribute this to
                for tb in tool_use_blocks((ev.get("message") or {}).get("content")):
                    name = tb.get("name", "")
                    tin = tb.get("input") or {}
                    if name in ("Edit", "Write"):
                        record_edit(seg, repo_root, name, tin)
                    elif name == "Bash" and CTXPACK_BASH_RE.search(tin.get("command", "") or ""):
                        seg.assisted = True
                    elif name.startswith("mcp__") and "ctxpack" in name.lower():
                        seg.assisted = True
                seg.end_line = lineno
            # system / queue-operation / attachment / frame-link / custom-title / ai-title: ignored (§1)
    if seg is not None:
        finalize(seg)
    return pairs


# ── §3.1 opt-in strict filter ────────────────────────────────────────────────────────────────────────
def committed_paths(repo_root: str) -> set:
    # Proxy for "this session's edits were later committed": every path that has EVER appeared in a
    # commit on the current HEAD's history. Cheap (one git call), deterministic given the repo's current
    # history (not wall-clock) — a documented approximation, not "this exact session was committed".
    try:
        out = subprocess.run(
            ["git", "-C", repo_root, "log", "--name-only", "--pretty=format:"],
            capture_output=True, text=True, timeout=30, check=False,
        )
        return {l.strip() for l in out.stdout.splitlines() if l.strip()}
    except Exception:
        return set()


# ── §2.3 dedup ────────────────────────────────────────────────────────────────────────────────────────
def _normalize_query(q: str) -> str:
    return _collapse_ws(q).lower()


def _gold_set(pair) -> frozenset:
    return frozenset(gf["path"] for gf in pair["gold_files"])


def _jaccard(a: frozenset, b: frozenset) -> float:
    if not a and not b:
        return 1.0
    union = len(a | b)
    return (len(a & b) / union) if union else 0.0


def dedup(pairs):
    # (1) exact-query dedup: hash of normalized text; on collision keep the LARGER gold set (ties: the
    #     first-seen, sorted (session-file, line) order — deterministic).
    by_hash = {}
    order = []
    for p in pairs:
        h = _normalize_query(p["query"])
        kept = by_hash.get(h)
        if kept is None:
            by_hash[h] = p
            order.append(h)
        elif len(p["gold_files"]) > len(kept["gold_files"]):
            by_hash[h] = p
    stage1 = [by_hash[h] for h in order]

    # (2) near-dup gold-set dedup (Jaccard >= 0.90) — collapses recurring tasks regardless of wording.
    #     The first-seen pair in sorted order is the keeper; dedup_count tallies what collapsed into it.
    kept, kept_sets = [], []
    for p in stage1:
        gs = _gold_set(p)
        merged = False
        for i, ks in enumerate(kept_sets):
            if _jaccard(gs, ks) >= JACCARD_NEAR_DUP:
                kept[i]["dedup_count"] = kept[i].get("dedup_count", 1) + 1
                merged = True
                break
        if not merged:
            p["dedup_count"] = 1
            kept.append(p)
            kept_sets.append(gs)
    return kept


def pair_id(query: str) -> str:
    return hashlib.sha1(_normalize_query(query).encode("utf-8")).hexdigest()[:8]


def build_record(p) -> dict:
    # Field order matches DESIGN_traceEvals.md §5.1's example exactly. NO wall-clock field anywhere
    # (mined_at was proposed and explicitly rejected — see the file header and §5.1's resolution note).
    return {
        "pair_id": pair_id(p["query"]),
        "query": p["query"],
        "gold_files": p["gold_files"],
        "gold_symbols": None,      # v1: always null (§7 — a future diff-to-parse pass could fill this)
        "session_id": p["session_id"],
        "segment_start_line": p["segment_start_line"],
        "segment_end_line": p["segment_end_line"],
        "ctxpack_assisted": p["ctxpack_assisted"],
        "dedup_count": p.get("dedup_count", 1),
        "miner_version": MINER_VERSION,
    }


# ── §4: --export-sanitized skeleton redaction ───────────────────────────────────────────────────────
def skeletonize(query: str) -> str:
    words = re.findall(r"[A-Za-z0-9_]+", query.lower())
    words = [w for w in words if len(w) >= 3 and w not in _SKELETON_STOPWORDS]
    freq = collections.Counter(words)
    top = sorted(freq.items(), key=lambda kv: (-kv[1], kv[0]))[:8]
    return "[REDACTED skeleton] tokens=%d top=%s" % (len(words), ",".join(w for w, _ in top))


def sanitize_record(rec: dict) -> dict:
    rec = dict(rec)
    rec["query"] = skeletonize(rec["query"])
    rec.pop("session_id", None)
    return rec


def default_out_path(repo_root: str) -> str:
    h = hashlib.sha1(repo_root.encode("utf-8")).hexdigest()[:16]
    return str(pathlib.Path.home() / ".ctxpack" / "traceevals" / (h + ".jsonl"))


def _percentile(sorted_vals, p):
    if not sorted_vals:
        return 0
    idx = min(len(sorted_vals) - 1, int(len(sorted_vals) * p))
    return sorted_vals[idx]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Mine (query, gold-files) retrieval-eval pairs from local Claude Code session "
                    "transcripts (DESIGN_traceEvals.md). Local-only, opt-in, LLM-free."
    )
    ap.add_argument("--repo", default=os.getcwd(), help="repo root whose sessions to mine (default: cwd)")
    ap.add_argument("--out", default=None, help="output minedpair.jsonl path (default: ~/.ctxpack/traceevals/<hash>.jsonl)")
    ap.add_argument("--export-sanitized", dest="export_sanitized", default=None,
                    help="write a SANITIZED artifact to PATH (query redacted to a skeleton, session_id "
                        "dropped) — the only way mined data may land inside the repo tree")
    ap.add_argument("--min-gold", type=int, default=2, help="minimum distinct in-repo gold files per pair (default 2)")
    ap.add_argument("--dry-run", action="store_true", help="print the segment/gold histogram; write nothing")
    ap.add_argument("--only-committed", action="store_true",
                    help="opt-in strict filter (§3.1): drop pairs whose gold files never appear in `git log` history")
    args = ap.parse_args(argv)

    repo_root = os.path.abspath(args.repo)
    pdir = project_dir(repo_root)
    if not pdir.is_dir():
        print(f"mine_traces: no session transcripts found for {repo_root} (looked in {pdir})", file=sys.stderr)
        return 1

    session_files = sorted(glob.glob(str(pdir / "*.jsonl")))   # sorted = deterministic mine order (Gate #1)
    raw_pairs = []
    for sf in session_files:
        raw_pairs.extend(mine_session_file(sf, repo_root, args.min_gold))

    if args.only_committed:
        committed = committed_paths(repo_root)
        raw_pairs = [p for p in raw_pairs if all(gf["path"] in committed for gf in p["gold_files"])]

    deduped = dedup(raw_pairs)
    records = [build_record(p) for p in deduped]

    if args.dry_run:
        n_assisted = sum(1 for r in records if r["ctxpack_assisted"])
        gold_sizes = sorted(len(r["gold_files"]) for r in records)
        qlens = sorted(len(r["query"]) for r in records)
        print(f"mine_traces: {len(session_files)} session file(s), {len(raw_pairs)} raw segment pair(s) "
             f"(>= {args.min_gold} gold files), {len(records)} after dedup")
        print(f"  ctxpack_assisted={n_assisted} unassisted={len(records) - n_assisted}")
        if gold_sizes:
            print(f"  gold-set size: min={gold_sizes[0]} median={_percentile(gold_sizes, 0.5)} max={gold_sizes[-1]}")
        if qlens:
            print(f"  query length:  min={qlens[0]} median={_percentile(qlens, 0.5)} max={qlens[-1]}")
        return 0

    sanitize = args.export_sanitized is not None
    out_path = os.path.abspath(args.export_sanitized if sanitize else (args.out or default_out_path(repo_root)))

    if not sanitize and (out_path == repo_root or out_path.startswith(repo_root + os.sep)):
        # §4 hard rule — refuse, non-zero exit, NO file created. Not a suggestion.
        print(f"mine_traces: refusing to write inside the repo tree ({out_path}) without --export-sanitized",
             file=sys.stderr)
        return 1

    out_dir = os.path.dirname(out_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        for rec in records:
            if sanitize:
                rec = sanitize_record(rec)
            fh.write(json.dumps(rec, ensure_ascii=False))
            fh.write("\n")

    print(f"mine_traces: wrote {len(records)} pair(s) to {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
