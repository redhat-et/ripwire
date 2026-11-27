#!/usr/bin/env bash
# mcpforrowscheck.sh — MCP `for` serves its <sigs>/<tail> rows as LINES (lane MR1, owner ruling 168): the CLI --for's ROWLINES + RANKSEQ
# (src/forrowlines.h, lane FMT2, owner ruling 153) on the MCP twin, with the same opt-outs — the `rows` argument mirroring --rows=
# (lines|elements, the argument over the environment) and RIPWIRE_NO_ROWLINES=1 — the same two legend clauses and the same decoder
# (test/rowlines.py). WHY: MCP `for` still served the element dialect, so an MCP agent paid the per-row markup FMT1 measured the CLI
# saving on (lane LG2: MCP's first-call legend 5,269 B against the CLI's 4,554 B, results LG2_FIRST_LEGEND_1121 §3).
#
#   test/mcpforrowscheck.sh [BIN]     # BIN defaults to $RIPWIRE_BIN, then build/ripwire; BASE_BIN= adds arm (B1)
#
# Arm classes (LANE_CONSTRAINTS §17): [P] NEW — red on 36a95d732 (no line form on MCP, `rows` an unknown field); [N] must not change;
# [M] a mutation control: the same comparison FAILS on a damaged answer.
#   (P0)  presence: the default MCP `for` answer's <sigs> and <tail> each hold one CDATA and no element; at least one definition line,
#         one pointer line and one verbatim row (else the arms below prove nothing)
#   (P1)  LOSSLESS: decode(default) == the rows="elements" answer == the RIPWIRE_NO_ROWLINES=1 answer, byte for byte, on four tasks
#         (two trees), budget_tokens included
#   (M1)  one byte dropped from a line, and one r= wrongly elided, each make decode(answer) differ from the element twin
#   (P2)  the argument over the environment, both ways: rows="lines" under RIPWIRE_NO_ROWLINES=1 is the default answer; rows="elements"
#         with the variable unset is the element answer
#   (P3)  refusals: rows="xml" and rows="" are -32602 errors naming the field and both values; no answer is served
#   (P4)  clauses: each clause once, last before </ctx>, only where its form is used; none on the element twin
#   (P5)  est_tokens= equals the element twin's (an upper bound, as on the CLI)
#   (P6)  THE SESSION LEGEND STAYS LOSSLESS (--mcp-legend=session, the default): three `for` calls in one server; call 1 is inline and
#         carries both clauses; calls 2-3 are in the ref posture, carry line-form rows and NO clause (served by call 1); every call
#         decodes to the element session's same call BYTE FOR BYTE — so the ref posture dropped exactly what it drops from the element
#         form (the <sigs> demote: note, a verbatim line here, included: legenddict.h dropServedCommentLines) and re-sent nothing it
#         would not (the term scan reads the line rows: forrowlines.h rowsAsElements; legendrefcheck (C)/(J) pin "never twice");
#         and every legend sentence the element session's call carries was sent by the line session by then; under
#         --mcp-legend=inline every call carries the clauses
#   (M2)  the (P6) sentence check fails when one sentence the line session sent is taken out of what it sent
#   (P7)  batch: a `for` sub-query is in line form by default and decodes to its RIPWIRE_NO_ROWLINES=1 twin
#   (N1)  not applied to the file page (limit=/offset=): byte-identical with and without the variable
#   (N2)  the CLI --for is untouched: its default answer is byte-identical to BASE_BIN's when given, and decodes to its own twin
#   (B1)  BASE_BIN=: rows="elements" (on this binary) == BASE_BIN's default MCP `for` answer, byte for byte — the opt-out is today
#   (C1)  xmllint clean and no newline outside CDATA on every answer above; two runs byte-identical
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "mcpforrowscheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "mcpforrowscheck: xmllint required"; exit 2; }
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
echo "mcpforrowscheck: BIN=$BIN${BASE_BIN:+ BASE_BIN=$BASE_BIN}"
unset RIPWIRE_NO_ROWLINES

BIN="$BIN" BASE="${BASE_BIN:-}" DIR="$DIR" REPO="$ROOT" python3 - <<'PY'
import json, os, re, subprocess, sys
BIN, BASE, W, REPO = os.environ["BIN"], os.environ["BASE"], os.environ["DIR"], os.environ["REPO"]
sys.path.insert(0, os.path.join(REPO, "test"))
from rowlines import decode, RSEQ_CLAUSE, ROWS_CLAUSE
bad = 0


def say(okay, msg):
    global bad
    print("  %s  %s" % ("PASS" if okay else "FAIL", msg))
    bad += 0 if okay else 1


def mcp(root, calls, env_off=False, extra=(), binary=None):
    """one server process, one answer (bytes, or b'ERR:'+json) per tools/call"""
    env = dict(os.environ)
    env.pop("RIPWIRE_NO_ROWLINES", None)
    if env_off:
        env["RIPWIRE_NO_ROWLINES"] = "1"
    req = [{"jsonrpc": "2.0", "id": 0, "method": "initialize"}]
    req += [{"jsonrpc": "2.0", "id": i, "method": "tools/call", "params": c} for i, c in enumerate(calls, 1)]
    p = subprocess.run([binary or BIN, root, "--mcp"] + list(extra), input="".join(json.dumps(r) + "\n" for r in req).encode(),
                       capture_output=True, env=env)
    got = {}
    for line in p.stdout.decode("utf8", "replace").splitlines():
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if isinstance(r.get("id"), int) and r["id"] > 0:
            got[r["id"]] = r
    out = []
    for i in range(1, len(calls) + 1):
        r = got.get(i, {})
        if "error" in r or r.get("result", {}).get("isError"):
            out.append(b"ERR:" + json.dumps(r.get("error") or r.get("result")).encode())
        else:
            out.append("".join(c.get("text", "") for c in r.get("result", {}).get("content", [])).encode("utf8"))
    return out


def call(task, **kw):
    a = {"task": task}
    a.update(kw)
    return {"name": "for", "arguments": a}


SECT = re.compile(rb"<(sigs|tail)\b[^>]*>(.*?)</\1>", re.S)


def line_form(doc):
    """[(section, is one CDATA)] of the top-level sigs/tail"""
    return [(m.group(1), m.group(2).startswith(b"<![CDATA[") and m.group(2).endswith(b"]]>") and m.group(2).count(b"<![CDATA[") == 1)
            for m in SECT.finditer(doc)]


def outside_cdata(doc):
    return re.sub(rb"<!\[CDATA\[.*?\]\]>", b"", doc, flags=re.S)


def wellformed(doc):
    r = subprocess.run(["xmllint", "--noout", "-"], input=doc, capture_output=True)
    return r.returncode == 0 and b"\n" not in outside_cdata(doc)


def est(doc):
    m = re.search(rb' est_tokens="(\d+)"', doc[:doc.find(b">")])
    return m.group(1) if m else None


SRC = os.path.join(REPO, "src")
TESTS = os.path.join(REPO, "test")
TASKS = [(SRC, "rank symbols by pagerank and serialize the map", {}),
         (SRC, "mcp legend session dictionary ref posture", {}),
         (SRC, "rank symbols by pagerank and serialize the map", {"budget_tokens": 3000}),
         (TESTS, "decode row lines back to elements", {})]
answers = []
for root, task, kw in TASKS:
    on = mcp(root, [call(task, **kw)])[0]
    off = mcp(root, [call(task, **kw)], env_off=True)[0]
    elem = mcp(root, [call(task, rows="elements", **kw)])[0]
    answers.append((task, kw, on, off, elem))

# (P0)
on0 = answers[0][2]
forms = line_form(on0)
body = b"\n".join(m.group(2) for m in SECT.finditer(on0))
lines = [l for l in body.replace(b"<![CDATA[", b"\n").replace(b"]]>", b"\n").split(b"\n") if l]
say(len(forms) == 2 and all(f for _, f in forms), "(P0) default MCP `for`: <sigs> and <tail> are one CDATA each (%s)" % forms)
say(any(b" | " in l and not l.startswith(b"<") for l in lines) and any(b"\t" in l or (b" " in l and b" | " not in l) for l in lines if not l.startswith(b"<"))
    and any(l.startswith(b"<") for l in lines), "(P0) the rows hold a definition line, a pointer line and a verbatim row (non-vacuous)")

# (P1) (P4) (P5)
for task, kw, on, off, elem in answers:
    tag = "%r%s" % (task[:32], " budget" if kw else "")
    say(not on.startswith(b"ERR:") and decode(on) == off, "(P1) decode(default) == RIPWIRE_NO_ROWLINES=1 twin: %s (%d -> %d B)" % (tag, len(off), len(on)))
    say(elem == off, "(P1) rows=\"elements\" == RIPWIRE_NO_ROWLINES=1 twin: %s" % tag)
    say(len(on) < len(off), "(P1) the line form is shorter: %s" % tag)
    tail = on[on.rfind(b"</tail>") + 7:] if b"</tail>" in on else on
    say(on.count(ROWS_CLAUSE) == 1 and on.count(RSEQ_CLAUSE) <= 1 and on.endswith(ROWS_CLAUSE + b"</ctx>")
        and ROWS_CLAUSE not in off and RSEQ_CLAUSE not in off, "(P4) clauses once, last before </ctx>, none on the twin: %s" % tag)
    say(est(on) is not None and est(on) == est(off), "(P5) est_tokens= is the element twin's: %s (%s)" % (tag, est(on)))

# (M1)
on = answers[0][2]
i = on.find(b"<![CDATA[") + 9
j = on.find(b"\n", i)
say(decode(on[:j - 1] + on[j:]) != answers[0][3], "(M1) one byte dropped from a line -> decode differs from the twin")
k = on.find(b'rseq="1"')
say(k > 0 and decode(re.sub(rb'( r="\d+")', b"", on, count=1)) != answers[0][3], "(M1) a kept r= removed -> decode differs from the twin")

# (P2)
t0, kw0 = TASKS[0][1], TASKS[0][2]
say(mcp(SRC, [call(t0, rows="lines")], env_off=True)[0] == answers[0][2], "(P2) rows=\"lines\" under RIPWIRE_NO_ROWLINES=1 == the default answer")
say(answers[0][4] == answers[0][3] and answers[0][4] != answers[0][2], "(P2) rows=\"elements\" with the variable unset == the element answer")

# (P3)
for v in ("xml", ""):
    r = mcp(SRC, [call(t0, rows=v)])[0]
    # SEP-1303 (lane mcp-metadata): the refusal is an isError result, not -32602; the helper already maps both to ERR:
    say(r.startswith(b"ERR:") and b'"isError": true' in r and b"rows" in r and b"lines" in r and b"elements" in r,
        "(P3) rows=%r refused (isError) naming the field and both values" % v)

# (P6)
SESS = ["rank symbols by pagerank and serialize the map", "mcp legend session dictionary ref posture", "decode row lines back to elements"]
s_on = mcp(SRC, [call(t) for t in SESS])
s_off = mcp(SRC, [call(t) for t in SESS], env_off=True)
s_inl = mcp(SRC, [call(t) for t in SESS], extra=["--mcp-legend=inline"])
say(ROWS_CLAUSE in s_on[0] and all(f for _, f in line_form(s_on[0])), "(P6) session call 1 (inline): line form, carries the row clause")
for n in (1, 2):
    say(b'<about legend="ref"' in s_on[n] and ROWS_CLAUSE not in s_on[n] and RSEQ_CLAUSE not in s_on[n] and all(f for _, f in line_form(s_on[n])),
        "(P6) session call %d (ref): line form, no clause re-sent (call 1 served it)" % (n + 1))
for n in range(3):
    say(decode(s_on[n]) == s_off[n], "(P6) session call %d decodes to the element session's call %d byte for byte (%d B vs %d B)" % (n + 1, n + 1, len(s_on[n]), len(s_off[n])))
COMMENT = re.compile(rb"<!--(.*?)-->", re.S)


def data_only(doc):
    """the answer without its comments (CDATA kept whole): rows, attributes, text — every fact but the legend"""
    out, at = [], 0
    for m in re.finditer(rb"<!\[CDATA\[.*?\]\]>|<!--.*?-->", doc, re.S):
        out.append(doc[at:m.start()] + (m.group(0) if m.group(0).startswith(b"<![CDATA[") else b""))
        at = m.end()
    return b"".join(out) + doc[at:]


def pieces(doc):
    """every legend sentence an answer sent, as comment text split at '. ' and '; '"""
    return {x.strip() for m in COMMENT.finditer(doc) for x in re.split(rb"\. |; ", m.group(1)) if x.strip()}


sent = set()
for n in range(3):
    sent |= pieces(decode(s_on[n]))
    missing = sorted(pieces(s_off[n]) - sent)
    say(data_only(decode(s_on[n])) == data_only(s_off[n]) and not missing,
        "(P6) session call %d: decodes to the element session's rows and attributes byte for byte, and every legend sentence the element "
        "session's call carries was sent by the line session by then (%d B vs %d B)" % (n + 1, len(s_on[n]), len(s_off[n]))
        if not missing else "(P6) session call %d: legend sentences never sent in the line session: %r" % (n + 1, missing[:3]))
drop = sorted(pieces(s_off[2]))[0]
say(drop in sent and pieces(s_off[2]) - (sent - {drop}), "(M2) [M] the sentence check fails when one sentence the line session sent is taken out")
say(all(ROWS_CLAUSE in d for d in s_inl), "(P6) --mcp-legend=inline: every call carries the row clause")

# (P7)
bq = {"name": "batch", "arguments": {"queries": [{"verb": "for", "task": t0}]}}
b_on, b_off = mcp(SRC, [bq], extra=["--mcp-legend=inline"])[0], mcp(SRC, [bq], env_off=True, extra=["--mcp-legend=inline"])[0]


def sub_answer(batch):
    """the one <q>'s payload: its CDATA, the ]]> splits joined back"""
    q = batch[batch.find(b"<q "):batch.rfind(b"</q>")]
    return b"".join(re.findall(rb"<!\[CDATA\[(.*?)\]\]>", q[q.find(b">") + 1:], re.S))


bs_on, bs_off = sub_answer(b_on), sub_answer(b_off)
say(bs_on.startswith(b"<ctx") and all(f for _, f in line_form(bs_on)) and decode(bs_on) == bs_off,
    "(P7) batch `for` sub-query: line form, decodes to its RIPWIRE_NO_ROWLINES=1 twin (%d -> %d B)" % (len(bs_off), len(bs_on)))

# (N1)
fp_on = mcp(SRC, [call(t0, limit=5, offset=0)])[0]
fp_off = mcp(SRC, [call(t0, limit=5, offset=0)], env_off=True)[0]
say(fp_on == fp_off and fp_on.startswith(b"<files"), "(N1) the file page (limit=/offset=) is byte-identical with and without the variable")

# (N2)
cli = subprocess.run([BIN, "src", "--no-cache", "--for=" + t0], cwd=REPO, capture_output=True).stdout
cli_off = subprocess.run([BIN, "src", "--no-cache", "--for=" + t0, "--rows=elements"], cwd=REPO, capture_output=True).stdout
say(decode(cli) == cli_off and cli != cli_off, "(N2) the CLI --for still serves lines and decodes to its own --rows=elements twin")
if BASE:
    cli_base = subprocess.run([BASE, "src", "--no-cache", "--for=" + t0], cwd=REPO, capture_output=True).stdout
    say(cli == cli_base, "(N2) the CLI --for default answer is byte-identical to BASE_BIN's")
    # (B1)
    for root, task, kw in TASKS:
        say(mcp(root, [call(task, rows="elements", **kw)])[0] == mcp(root, [call(task, **kw)], binary=BASE)[0],
            "(B1) rows=\"elements\" == BASE_BIN's default MCP `for`: %r%s" % (task[:32], " budget" if kw else ""))
    say(s_off == mcp(SRC, [call(t) for t in SESS], binary=BASE), "(B1) the RIPWIRE_NO_ROWLINES=1 session == BASE_BIN's session, 3 calls")

# (C1)
every = [a for t in answers for a in t[2:]] + s_on + s_off + s_inl
say(all(wellformed(d) for d in every), "(C1) xmllint clean, no newline outside CDATA: %d answers" % len(every))
say(mcp(SRC, [call(t0)])[0] == answers[0][2], "(C1) deterministic: two runs byte-identical")
print("mcpforrowscheck: %s" % ("FAIL (%d)" % bad if bad else "PASS"))
sys.exit(1 if bad else 0)
PY
