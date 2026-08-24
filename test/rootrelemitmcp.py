#!/usr/bin/env python3
"""rootrelemitmcp.py — the MCP-dialect arm of test/rootrelemitcheck.sh.

Same two assertions the CLI arms make, against the long-lived stdio server instead of argv:

  ARM 1  the same corpus at two very different absolute depths returns BYTE-IDENTICAL payloads once the
         root spelling itself is masked
  ARM 2  every occurrence of the absolute root sits inside a disclosed envelope anchor
         (root="…" / "root":"…" / "wrote":"…")

The MCP surface matters on its own because its emitters take the same `rootArg` the CLI's do but several
call sites historically passed nothing, so a verb could be root-relative from argv and absolute over MCP
for the identical question. That divergence is exactly what this arm pins.

Usage:  test/rootrelemitmcp.py <ripwire-binary> <shortRoot> <deepRoot>
Exit 0 = ALL PASS, 1 = SOME FAILED.
"""
import json
import re
import subprocess
import sys

BIN, SHORT, DEEP = sys.argv[1], sys.argv[2], sys.argv[3]

# (verb, extra-args) — the read verbs whose payload can name a corpus path.
VERBS = [
    ("analyze", {}),
    ("explore", {}),
    ("find_symbol", {"symbol": "total_area"}),
    ("find_referencing_symbols", {"symbol": "area_of_triangle"}),
    ("grep", {"pattern": "return"}),
    ("memory_recall", {"task": "geometry"}),
    ("mentions", {"symbol": "area_of_triangle"}),
    ("for", {"task": "compute the area"}),
    ("lego", {"type": "Point"}),
    ("owners", {"symbol": "area_of_triangle"}),
    ("impact", {"symbol": "area_of_triangle"}),
    ("uses", {"symbol": "area_of_triangle"}),
    ("path_between", {"from": "total_area", "to": "area_of_triangle"}),
    ("connect", {"symbols": "total_area,area_of_triangle"}),
    ("exemplar", {"task": "compute the area"}),
    ("edit_check", {"symbol": "total_area"}),
    ("cochange", {"file": "geometry.h"}),
    ("situational_awareness", {}),
    ("whereis", {"symbol": "total_area"}),
    ("doc_drift", {}),
    ("from_trace", {"trace": "at total_area (app.py:8)"}),
    ("fetch_body", {"symbol": "total_area"}),
    ("quality_delta", {}),
]


def session(root):
    """Run every verb against one long-lived server rooted at `root`; return {verb: raw-json-text}."""
    p = subprocess.Popen([BIN, "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, bufsize=1)

    def send(obj):
        p.stdin.write(json.dumps(obj) + "\n")
        p.stdin.flush()
        return p.stdout.readline()

    send({"jsonrpc": "2.0", "id": 0, "method": "initialize",
          "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                     "clientInfo": {"name": "rootrelemit", "version": "1"}}})
    out = {}
    for i, (verb, extra) in enumerate(VERBS, start=1):
        args = {"path": root}
        args.update(extra)
        try:
            out[verb] = send({"jsonrpc": "2.0", "id": i, "method": "tools/call",
                              "params": {"name": verb, "arguments": args}})
        except Exception as exc:                       # a verb that dies must not mask the others
            out[verb] = "TRANSPORT-ERROR " + str(exc)
    try:
        p.stdin.close()
        p.wait(timeout=60)
    except Exception:
        p.kill()
    return out


def normalize(text, root):
    """Mask the root spelling, then the two fields allowed to still vary with depth — see the long note in
    rootrelemitcheck.sh's mask(): the size fields honestly count the anchor's own bytes, and the `_index`
    stamp folds each file's mtime so two independent copies can never agree on it. Neither is a path."""
    out = text.replace(root, "@ROOT@")
    out = re.sub(r"\b(est_tokens|total_bytes|bytes|est_bytes)(=\\?\"?|\\?\"\s*:\s*)\d+", r"\1\2@N@", out)
    out = re.sub(r"\[index: [^\]]*\]", "[index: @IDX@]", out)
    return out


def leaks(text, root):
    """(non-anchored occurrences, total, anchored) of `root` in `text`."""
    # the payload is JSON-escaped inside the envelope, so match both the bare and the escaped spelling
    total = text.count(root)
    esc = re.escape(root)
    anchored = 0
    for pat in (r'\\?"root\\?"\s*:\s*\\?"' + esc,
                r'\sroot=\\?"' + esc,
                r'\\?"wrote\\?"\s*:\s*\\?"' + esc,
                r'<root\s+label=\\?"[^"\\]*\\?"\s+p=\\?"' + esc):
        anchored += len(re.findall(pat, text))
    return total - anchored, total, anchored


def main():
    print("  ── MCP dialect ──")
    a, b = session(SHORT), session(DEEP)
    failed = 0
    for verb, _ in VERBS:
        ta, tb = a.get(verb, ""), b.get(verb, "")
        if not ta and not tb:
            print(f"  PASS  mcp:{verb} — no payload (nothing to check)")
            continue

        # ARM 1 — depth independence
        if normalize(ta, SHORT) == normalize(tb, DEEP):
            print(f"  PASS  mcp:{verb} ARM1 depth-independent")
        else:
            print(f"  FAIL  mcp:{verb} ARM1 payload DIFFERS with checkout depth "
                  f"({len(ta)}B vs {len(tb)}B)")
            failed = 1

        # ARM 2 — no absolute path outside an envelope anchor
        lk, tot, anc = leaks(tb, DEEP)
        if lk == 0:
            print(f"  PASS  mcp:{verb} ARM2 no absolute path outside the envelope ({anc} anchor(s))")
        else:
            print(f"  FAIL  mcp:{verb} ARM2 {lk} absolute-path leak(s) of {tot} occurrence(s)")
            failed = 1
    return failed


if __name__ == "__main__":
    sys.exit(main())
