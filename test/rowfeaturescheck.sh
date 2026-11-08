#!/usr/bin/env bash
# rowfeaturescheck.sh — ROW-FEATURE-DUMP, the dev-only RIPWIRE_ROW_FEATURES=<path> switch (src/rowfeatures.h, rowfeatstate.h).
#
# THE CONTRACT THIS PINS:
#   BYTES    the answer is byte-identical with and without the switch (CLI --for on three fixtures in two languages, the MCP
#            `for` verb, and a TSV path that cannot be opened).
#   ROWS     the TSV holds one line per printed answer row, in output order: the grader's reading of a row (an opening
#            <d|y|s|u …> tag after XML comments are masked, <u v="used"> excluded); tag, n= and p= match row by row.
#   COLUMNS  one '#' header naming 53 columns, every line 53 fields, the numeric columns parse, qhash = FNV-1a 64 of the question;
#            the ROW-FEATURES-2 columns parse too, and cov_any (coverage='s own share) is never below the name/doc/body shares.
#   HEAD_RR  rr_lift=1 on exactly the <sigs> rows the head round-robin moved up (their r= in the RIPWIRE_NO_HEAD_RR=1 answer is
#            larger), pre_rank = that answer's r=, and RIPWIRE_NO_HEAD_RR=1 reads rr_on=0 with no lift.
#   SCORE    score = lex*tier + the stage deltas; in score order (pre_rank) score never rises and score_rank rises; a question
#            naming a file carries the file lift in d_mention (a row the words never matched: lex 0, d_mention = score).
#   NEWEV    (ROW-FEATURES-2, test/rowfeaturesfix/cov) coverage differs between rows by field: the head's body carries the
#            question, the callee's name does, the caller's doc comment does and its body does not; the quoted literal is hit
#            in the one body holding it; the callee is reached from the head (cp_head 1, in, res), the caller reaches it (out);
#            one file holds every row (ans_file_rank 1, file_top10_share 1).
#
# Arms: R1 bytes (mono TS, pair C, py, cov TS, MCP, unopenable path)  R2 rows  R3 columns  R4 HEAD_RR  R5 score  R6 mention
#       R7 MCP rows  R8 new evidence (coverage by field, quoted literal, call path, file share)
# Mutants (run by hand, each turns this red): M1 mention snapshot misplaced, M2 delta sign, M3 lift condition inverted,
#       M4 cov_body read off the doc span (R8), M5 cp_dir swapped (R8).
# Usage:  bash test/rowfeaturescheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/rowfeaturescheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_HEAD_RR RIPWIRE_ROW_FEATURES RIPWIRE_NO_MENTION RIPWIRE_NO_DOC_MENTION RIPWIRE_COCHANGE
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "rowfeaturescheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
MONO="$ROOT/test/forheadrrfix/mono"; PAIR="$ROOT/test/forheadrrfix/pair"; PY="$ROOT/test/receiverevidencefix/py"; COV="$ROOT/test/rowfeaturesfix/cov"
for d in "$MONO" "$PAIR" "$PY" "$COV"; do [ -d "$d" ] || { echo "fixture $d missing"; exit 2; }; done

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

Q_MONO="How does the scheduler dispatch queued jobs to workers?"
Q_PAIR="How is the job scheduler initialised and run?"
Q_PY="How does the tui app render the screen widget?"
Q_MENTION="How do the widgets in src/tui/compositor.py get arranged on screen?"
Q_COV='Where is the ledger balance total checked for "unbalanced books"?'

# run OUT DIR TSV(""=off) NOHRR(0|1) QUESTION — one --for call, rc kept beside the output
run(){ local out="$1" dir="$2" tsv="$3" nohrr="$4" q="$5"
    ( cd "$dir" || exit 97
      [ "$nohrr" = 1 ] && export RIPWIRE_NO_HEAD_RR=1
      [ -n "$tsv" ] && export RIPWIRE_ROW_FEATURES="$tsv"
      "$BIN" "$dir" --no-cache --for="$q" ) >"$out" 2>"$out.err"
    printf '%s' "$?" >"$out.rc"; }
ran(){ [ "$( cat "$1.rc" )" = 0 ] && [ -s "$1" ] && return 0; no "$2: rc=$( cat "$1.rc" ) bytes=$( wc -c <"$1" | tr -d ' ' )"; return 1; }

cat > "$TMP/chk.py" <<'PY'
import html, json, re, sys
cmd, args = sys.argv[1], sys.argv[2:]
NCOL = 53
def load(p): return open(p, "rb").read().decode("utf-8", "replace")
def fail(m): print(m); sys.exit(1)
ROW = re.compile(r'<(d|y|s|u)((?:\s+[\w:-]+="[^"]*")*)\s*(/?)>')
def attrs(s): return dict(re.findall(r'([\w:-]+)="([^"]*)"', s))
def arows(t):   # the grader's reading (tmp grader arows): comments masked, <u v="used"> excluded, output order
    m = re.sub(r"<!--.*?-->", lambda x: " " * len(x.group(0)), t, flags=re.S)
    out = []
    for x in ROW.finditer(m):
        a = attrs(x.group(2))
        if x.group(1) == "u" and a.get("v") == "used": continue
        out.append((x.group(1), a))
    return out
def tsv(p):
    lines = load(p).split("\n")
    if lines and lines[-1] == "": lines.pop()
    head = [l for l in lines if l.startswith("#")]
    body = [l.split("\t") for l in lines if not l.startswith("#")]
    return head, body
H = None
def col(name): return H.index(name)
def mcpbody(p):
    body = ""
    for line in load(p).splitlines():
        try: o = json.loads(line)
        except ValueError: continue
        if o.get("id") == 2:
            for c in o.get("result", {}).get("content", []): body += c.get("text", "")
    return body
def fnv(s):
    h = 0xcbf29ce484222325
    for b in s.encode("utf-8"): h = ((h ^ b) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return "%016x" % h
def header(p):
    global H
    head, body = tsv(p)
    if len(head) != 1: fail("expected one header line, got %d" % len(head))
    H = head[0][1:].split("\t")
    if len(H) != NCOL: fail("header names %d columns, want %d" % (len(H), NCOL))
    return body
if cmd == "rows":          # ANSWER TSV [mcp] — one line per answer row, in order, tag/n/p equal
    body = header(args[1]); t = mcpbody(args[0]) if len(args) > 2 else load(args[0]); rows = arows(t)
    if len(body) != len(rows): fail("TSV lines %d, answer rows %d" % (len(body), len(rows)))
    if not rows: fail("no answer rows to compare")
    for i, ((tag, a), f) in enumerate(zip(rows, body)):
        want = (str(i + 1), tag, a.get("n", ""), a.get("p", ""))
        got = (f[col("pos")], f[col("tag")], f[col("n")], f[col("p")])
        if want != got: fail("row %d: answer %s, TSV %s" % (i + 1, want, got))
    print("%d rows, %d lines, order and tag/n/p equal" % (len(rows), len(body)))
elif cmd == "cols":        # TSV QUESTION — field counts, numeric columns, qhash
    body = header(args[0]); q = args[1]
    ints = ["pos", "sym", "score_rank", "ccx", "loc", "hops_head", "hops_anchor", "same_file", "same_dir", "rr_on", "test_path", "generated", "vendored"]
    flts = ["score", "lex", "tier", "d_anchor", "d_mention", "d_pathcut", "d_exp", "d_cochange", "d_docmention", "score_ratio"]
    resolved = 0
    for f in body:
        if len(f) != NCOL: fail("line with %d fields: %s" % (len(f), f[:4]))
        if f[col("qhash")] != fnv(q): fail("qhash %s, want %s" % (f[col("qhash")], fnv(q)))
        if f[col("sym")] == "-1": continue
        resolved += 1
        for c in ints: int(f[col(c)])
        for c in flts: float(f[col(c)])
        for c in ("rr_lift", "pre_rank", "fanin", "tested"):
            if f[col(c)] != "": int(f[col(c)])
        if f[col("edge_head")] not in ("self", "member", "owner", "sibling", "none") and not re.fullmatch(r"(out|in):(call|name|link|import)", f[col("edge_head")]):
            fail("edge_head %r" % f[col("edge_head")])
        for c in ("cov_name", "cov_doc", "cov_body", "cov_any", "terms_hit", "terms_q", "quote_hit", "cp_top3", "cp_seed"):
            if f[col(c)] != "": int(f[col(c)])
        int(f[col("quote_lits")]); int(f[col("cp_head")]); int(f[col("ans_file_rank")])
        if not 0.0 <= float(f[col("file_top10_share")]) <= 1.0: fail("file_top10_share %s" % f[col("file_top10_share")])
        if f[col("cp_dir")] not in ("-", "in", "out"): fail("cp_dir %r" % f[col("cp_dir")])
        if f[col("cp_prov")] and not re.fullmatch(r"(res|scip|binding|split|import|lastseg|impl|other)(\+(res|scip|binding|split|import|lastseg|impl|other))?", f[col("cp_prov")]):
            fail("cp_prov %r" % f[col("cp_prov")])
        if f[col("cov_any")] != "":
            if int(f[col("cov_any")]) < max(int(f[col(c)]) for c in ("cov_name", "cov_doc", "cov_body")): fail("%s cov_any below a field share" % f[col("n")])
    if resolved == 0: fail("no resolved row")
    print("%d lines x %d fields, %d resolved, numeric columns parse, qhash = FNV-1a(question)" % (len(body), NCOL, resolved))
elif cmd == "rr":          # TSV OFFANSWER OFFTSV — rr_lift = moved up vs the RIPWIRE_NO_HEAD_RR=1 answer, pre_rank = its r=
    body = header(args[0]); off = {a.get("n"): int(a["r"]) for tag, a in arows(load(args[1])) if tag == "d" and "r" in a}
    lifted = []
    for f in body:
        if f[col("src")] != "sigs" or f[col("tag")] != "d": continue
        n, r = f[col("n")], int(f[col("r")])
        if f[col("rr_on")] != "1": fail("rr_on=%s on the round-robin answer" % f[col("rr_on")])
        if int(f[col("pre_rank")]) != off.get(n, -1): fail("%s pre_rank %s, the RIPWIRE_NO_HEAD_RR=1 answer's r=%s" % (n, f[col("pre_rank")], off.get(n)))
        want = "1" if off[n] > r else "0"
        if f[col("rr_lift")] != want: fail("%s rr_lift %s, want %s (off r=%d, on r=%d)" % (n, f[col("rr_lift")], want, off[n], r))
        if want == "1": lifted.append(n)
    if not lifted: fail("the fixture lifted no row")
    _, ob = tsv(args[2])
    for f in ob:
        if f[col("src")] == "sigs" and (f[col("rr_on")] != "0" or f[col("rr_lift")] == "1"): fail("RIPWIRE_NO_HEAD_RR=1 row %s reads rr_on=%s rr_lift=%s" % (f[col("n")], f[col("rr_on")], f[col("rr_lift")]))
    print("rr_lift on exactly the moved-up rows %s; pre_rank = the score-order r=; off reads rr_on=0" % lifted)
elif cmd == "score":       # TSV — the component identity and score order
    body = header(args[0]); sig = []
    for f in body:
        if f[col("sym")] == "-1": continue
        s = float(f[col("score")]); parts = float(f[col("lex")]) * float(f[col("tier")]) + sum(float(f[col(c)]) for c in ("d_anchor", "d_mention", "d_pathcut", "d_exp", "d_cochange", "d_docmention"))
        if abs(s - parts) > 1e-3 * max(1.0, abs(s)): fail("%s score %s != lex*tier + deltas %.6g" % (f[col("n")], s, parts))
        if f[col("src")] == "sigs" and f[col("pre_rank")]: sig.append((int(f[col("pre_rank")]), s, int(f[col("score_rank")]), f[col("n")]))
    sig.sort()
    for (r0, s0, k0, n0), (r1, s1, k1, n1) in zip(sig, sig[1:]):
        if s1 > s0 * (1 + 1e-5) + 1e-6: fail("score rises in score order: %s %s -> %s %s" % (n0, s0, n1, s1))
        if k1 <= k0: fail("score_rank does not rise in score order: %s %d -> %s %d" % (n0, k0, n1, k1))
    if len(sig) < 5: fail("only %d sigs rows" % len(sig))
    print("score = lex*tier + deltas on every resolved row; %d sigs rows in score order" % len(sig))
elif cmd == "newev":       # TSV — the cov fixture's rows (see NEWEV above)
    body = header(args[0]); by = {f[col("n")]: f for f in body}
    want = {"reconcileAccounts", "ledgerBalanceTotal", "auditReport"}
    if not want <= set(by): fail("rows %s, want %s" % (sorted(by), sorted(want)))
    hd, ce, cr = by["reconcileAccounts"], by["ledgerBalanceTotal"], by["auditReport"]
    v = lambda f, c: int(f[col(c)])
    if body[0][col("n")] != "reconcileAccounts": fail("head %s" % body[0][col("n")])
    if not v(hd, "cov_body") > v(ce, "cov_body") > 0: fail("cov_body head %s callee %s" % (hd[col("cov_body")], ce[col("cov_body")]))
    if not v(ce, "cov_name") > v(hd, "cov_name"): fail("cov_name callee %s head %s" % (ce[col("cov_name")], hd[col("cov_name")]))
    if not (v(cr, "cov_doc") > 0 and v(cr, "cov_body") == 0): fail("caller cov_doc %s cov_body %s" % (cr[col("cov_doc")], cr[col("cov_body")]))
    if not (v(hd, "terms_hit") > v(cr, "terms_hit") > 0 and v(hd, "terms_q") >= v(hd, "terms_hit")): fail("terms_hit %s %s of %s" % (hd[col("terms_hit")], cr[col("terms_hit")], hd[col("terms_q")]))
    if [(f[col("quote_lits")], f[col("quote_hit")]) for f in (hd, ce, cr)] != [("1", "1"), ("1", "0"), ("1", "0")]: fail("quote_lits/quote_hit %s" % [(f[col("quote_lits")], f[col("quote_hit")]) for f in (hd, ce, cr)])
    if (hd[col("cp_head")], ce[col("cp_head")], cr[col("cp_head")]) != ("0", "1", "1"): fail("cp_head %s %s %s" % (hd[col("cp_head")], ce[col("cp_head")], cr[col("cp_head")]))
    if (ce[col("cp_seed")], ce[col("cp_dir")], ce[col("cp_prov")]) != ("1", "in", "res"): fail("callee cp %s" % [ce[col(c)] for c in ("cp_seed", "cp_dir", "cp_prov")])
    if (cr[col("cp_seed")], cr[col("cp_dir")], cr[col("cp_prov")]) != ("1", "out", "res"): fail("caller cp %s" % [cr[col(c)] for c in ("cp_seed", "cp_dir", "cp_prov")])
    if any((f[col("ans_file_rank")], f[col("file_top10_share")]) != ("1", "1") for f in body): fail("file columns %s" % [(f[col("ans_file_rank")], f[col("file_top10_share")]) for f in body])
    print("cov_body %s>%s, cov_name %s>%s, doc-only caller %s/%s, quote hit on the head only, cp in/out at 1 hop, one file" % (
        hd[col("cov_body")], ce[col("cov_body")], ce[col("cov_name")], hd[col("cov_name")], cr[col("cov_doc")], cr[col("cov_body")]))
elif cmd == "mention":     # TSV NAME — the named file's row the words never matched carries the lift in d_mention
    body = header(args[0]); hit = [f for f in body if f[col("n")] == args[1]]
    if not hit: fail("no row %s" % args[1])
    f = hit[0]
    if not (float(f[col("lex")]) == 0.0 and float(f[col("d_mention")]) > 0 and abs(float(f[col("d_mention")]) - float(f[col("score")])) < 1e-4):
        fail("%s lex=%s d_mention=%s score=%s" % (args[1], f[col("lex")], f[col("d_mention")], f[col("score")]))
    print("%s: lex 0, d_mention = score = %s" % (args[1], f[col("score")]))
PY
chk(){ local label="$1"; shift; local m; if m="$( python3 "$TMP/chk.py" "$@" 2>&1 )"; then ok "$label: $m"; else no "$label: $m"; fi; }

# ── R1: bytes ───────────────────────────────────────────────────────────────────────────────────────────────────────────
for spec in "mono|$MONO|$Q_MONO" "pair|$PAIR|$Q_PAIR" "py|$PY|$Q_PY" "mention|$PY|$Q_MENTION" "cov|$COV|$Q_COV"; do
    IFS='|' read -r name dir q <<<"$spec"
    run "$TMP/$name.off" "$dir" "" 0 "$q"; run "$TMP/$name.on" "$dir" "$TMP/$name.tsv" 0 "$q"
    if ran "$TMP/$name.off" "R1 $name" && ran "$TMP/$name.on" "R1 $name (switch)"; then
        if cmp -s "$TMP/$name.off" "$TMP/$name.on"; then ok "R1 $name: the answer is byte-identical with the switch ($( wc -c <"$TMP/$name.on" | tr -d ' ' ) B)"
        else no "R1 $name: the answer changed under the switch"; fi
    fi
done
run "$TMP/bad.on" "$MONO" "$TMP/no/such/dir/x.tsv" 0 "$Q_MONO"
if ran "$TMP/bad.on" "R1 unopenable" && cmp -s "$TMP/mono.off" "$TMP/bad.on" && grep -q "RIPWIRE_ROW_FEATURES" "$TMP/bad.on.err"; then ok "R1 unopenable TSV path: the answer is unchanged and stderr says so"
else no "R1 unopenable TSV path: answer changed or no stderr note"; fi
mcp(){ local out="$1" tsv="$2"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$MONO"'","task":"'"$Q_MONO"'"}}}' \
        | ( cd "$MONO" || exit 97; mkdir -p "$TMP/mcphome"; [ -n "$tsv" ] && export RIPWIRE_ROW_FEATURES="$tsv"; TMPDIR="$TMP/mcphome" "$BIN" --mcp ) >"$out" 2>/dev/null
    printf '%s' "$?" >"$out.rc"; }
mcp "$TMP/mcp.off" ""; mcp "$TMP/mcp.on" "$TMP/mcp.tsv"
if ran "$TMP/mcp.off" "R1 mcp" && ran "$TMP/mcp.on" "R1 mcp (switch)"; then
    if cmp -s "$TMP/mcp.off" "$TMP/mcp.on"; then ok "R1 mcp for: byte-identical with the switch"; else no "R1 mcp for: the answer changed under the switch"; fi
fi

# ── R2/R3: rows and columns ─────────────────────────────────────────────────────────────────────────────────────────────
for spec in "mono|$Q_MONO" "pair|$Q_PAIR" "py|$Q_PY" "mention|$Q_MENTION" "cov|$Q_COV"; do
    IFS='|' read -r name q <<<"$spec"
    chk "R2 $name" rows "$TMP/$name.on" "$TMP/$name.tsv"
    chk "R3 $name" cols "$TMP/$name.tsv" "$q"
done

# ── R4: the head round-robin ────────────────────────────────────────────────────────────────────────────────────────────
for name in mono py; do
    dir="$MONO"; q="$Q_MONO"; [ "$name" = py ] && { dir="$PY"; q="$Q_PY"; }
    run "$TMP/$name.nohrr" "$dir" "$TMP/$name.nohrr.tsv" 1 "$q"
    ran "$TMP/$name.nohrr" "R4 $name (off)" && chk "R4 $name" rr "$TMP/$name.tsv" "$TMP/$name.nohrr" "$TMP/$name.nohrr.tsv"
done

# ── R5/R6: score components ─────────────────────────────────────────────────────────────────────────────────────────────
for name in mono pair py mention; do chk "R5 $name" score "$TMP/$name.tsv"; done
chk "R6 mention" mention "$TMP/mention.tsv" add_widget

# ── R7: MCP rows ────────────────────────────────────────────────────────────────────────────────────────────────────────
chk "R7 mcp" rows "$TMP/mcp.on" "$TMP/mcp.tsv" mcp
chk "R7 mcp cols" cols "$TMP/mcp.tsv" "$Q_MONO"

# ── R8: new evidence (ROW-FEATURES-2) ───────────────────────────────────────────────────────────────────────────────────
chk "R8 cov" newev "$TMP/cov.tsv"

if [ "$fail" = 0 ]; then echo "rowfeaturescheck: OK"; else echo "rowfeaturescheck: FAILED"; fi
exit "$fail"
