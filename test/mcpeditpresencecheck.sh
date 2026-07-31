#!/usr/bin/env bash
# mcpeditpresencecheck.sh — §H2 gate: an edit verb whose PAYLOAD field was never sent must REFUSE,
# and must leave the target file byte-identical.
#
# THE BUG THIS GATE PINS (PLAN_outputAudit4_2026-07-30.md §H2, destructive class). The three edit-verb
# dispatch arms in src/mcp.h guarded only `!path.empty() && !symbol.empty()` and never tested the payload
# field, so an OMITTED new_body / text reached runEditVerb as an EMPTY STRING and was applied:
#
#     {"name":"replace_symbol_body","arguments":{"path":"<dir>","symbol":"alpha","file":"a.h"}}
#         →  {"applied":"replace_symbol_body", ...}     and alpha's definition was DELETED from disk.
#
# i.e. the one class of request where "accept and serve the default" is not a wrong ANSWER but a wrong
# WRITE, reported as success. Every sibling required field on this surface was already guarded, and the
# machinery for this one existed and was simply not wired: mcprefusal.h's kMcpRequiredFields already
# declares new_body/text Required, mcp.h's argPresent already answers the presence question, and the
# W3FIX H5 SHAPE check on the same two fields already worked (`new_body:42` refuses). Only PRESENCE
# was missed — and only on the two fields whose omission writes to disk.
#
# WHAT IS ASSERTED (the contract, not the sentence):
#   (a) each of the three edit verbs, payload field OMITTED → JSON-RPC error -32602 naming the VERB, the
#       FIELD, the problem and an EXAMPLE — and the target file's sha256 is byte-identical before/after.
#       The HASH is the assertion that matters: a gate that only reads the response cannot tell a refusal
#       from a refusal-that-also-wrote.
#   (b) the same three on the BATCH arm. The edit verbs are batch-EXCLUDED by construction
#       (mcpverbs.h kBatchServedVerbs is read-only; unknownSubVerbRefusal refuses anything outside it), so
#       the assertion here is that the EXCLUSION holds — a sub-query naming an edit verb is refused as an
#       unknown sub-verb and writes nothing. Stated as an assertion rather than skipped, because "the batch
#       arm cannot reach the write path" is exactly the kind of claim that silently stops being true.
#   (c) the field PRESENT but an EMPTY STRING (`new_body:""` / `text:""`).
#       RULING (this lane, from the code's own contract): empty == missing == REFUSED, file unchanged.
#       An empty new_body is NOT read as a legitimate "delete the body" request, because:
#         1. the table row that owns this field's wording declares it "the complete, well-formed
#            replacement definition" (mcprefusal.h kMcpRequiredFields) — "" is not one;
#         2. mcp.h's argPresent answers PRESENCE by emptiness for all 13 schema-typed string fields, so
#            `symbol:""` is already "missing required field: symbol" on both arms — a second, opposite
#            reading for new_body/text would make them the only two string fields on the surface where an
#            empty value means something, which is the divergence the shared vocabulary exists to prevent;
#         3. the permissive reading's failure mode IS §H2: a mistyped/unset argument silently deletes a
#            definition and reports success. A destructive verb must not infer intent from an empty string.
#   (d) a CONTROL: the same three verbs WITH their payload field succeed and change the file as documented,
#       so this gate can never go green by breaking the edit verbs.
#   (e) an ENUMERATION arm: every Required/AnyOf row of mcprefusal.h's kMcpRequiredFields is exercised by
#       OMITTING that field and asserting the refusal names it. The rows are PARSED OUT OF THE SOURCE, not
#       restated here (the §B6 M14 lesson: a gate that restates the table cannot catch the table), so a
#       required field that a future dispatch arm forgets to guard reds HERE — the sibling-completeness
#       lens, mechanized. For the three edit verbs the same arm also asserts the corpus sha256 is unchanged.
#
# NEVER edits test/fixture: every mutation happens on a scratch corpus written under mktemp.
#
#   bash test/mcpeditpresencecheck.sh                                   # build/ripwire
#   bash test/mcpeditpresencecheck.sh /path/to/base/ripwire             # must FAIL (pre-fix binary)
#   RIPWIRE_BIN=asan/ripwire bash test/mcpeditpresencecheck.sh          # both seams bind the same way
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }
echo "mcpeditpresencecheck: BIN=$BIN"

# ─── the scratch corpus (two same-named-free defs, so `symbol` resolves uniquely) ─────────────────────
mkCorpus()
{
    local d="$1"
    mkdir -p "$d"
    cat >"$d/a.h" <<'CPP'
#pragma once

// alpha adds one to its argument (the def the edit verbs address).
int alpha( int x )
{
    return x + 1;
}

// beta doubles alpha's answer.
int beta( int x )
{
    return alpha( x ) * 2;
}
CPP
}

# sha256 of every file in the corpus, sorted — the "nothing was written" assertion.
corpusHash()
{
    local d="$1"
    if command -v shasum >/dev/null 2>&1; then ( cd "$d" && find . -type f | LC_ALL=C sort | xargs shasum -a 256 ) | shasum -a 256
    else ( cd "$d" && find . -type f | LC_ALL=C sort | xargs sha256sum ) | sha256sum
    fi
}

# one tools/call request through a fresh stdio server; prints the last response line.
mcpCall()
{
    printf '%s\n%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" | "$BIN" --mcp 2>/dev/null | tail -1
}

# the response's error message, or "__OK__:<inner text>" on success.
errOrOk()
{
    python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERR__%d:%s" % (r["error"].get("code", 0), r["error"].get("message", "")))
else:           print("__OK__:" + r["result"]["content"][0]["text"].replace("\n", " "))
' <"$1"
}

# assert: a refusal that is -32602, names the verb, names the field, states the problem, shows an example.
assertRefusal()
{
    local label="$1" msg="$2" verb="$3" field="$4"
    case "$msg" in
        __ERR__-32602:*) ok "$label: refused with -32602";;
        __OK__:*)        no "$label: SUCCEEDED — the verb served an empty payload: $( printf '%.140s' "${msg#__OK__:}" )"; return;;
        *)               no "$label: wrong error code/shape: $( printf '%.140s' "$msg" )"; return;;
    esac
    case "$msg" in *"$verb"*)  ok "$label: refusal names the verb ($verb)";;
                    *)         no "$label: refusal does not name the verb: $msg";; esac
    case "$msg" in *"$field"*) ok "$label: refusal names the field ($field)";;
                    *)         no "$label: refusal does not name the field: $msg";; esac
    case "$msg" in *"missing required field"*) ok "$label: refusal states the problem (missing required field)";;
                    *)                         no "$label: refusal does not state the problem: $msg";; esac
    case "$msg" in *"e.g. $field="*) ok "$label: refusal shows a runnable $field example";;
                    *)               no "$label: refusal carries no $field example: $msg";; esac
}

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (a) payload field OMITTED → refusal, and the file is byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
omitCase()
{
    local verb="$1" field="$2"
    local W="$TMP/omit_$verb"; rm -rf "$W"; mkCorpus "$W"
    local before after
    before="$( corpusHash "$W" )"
    mcpCall "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$verb\",\"arguments\":{\"path\":\"$W\",\"symbol\":\"alpha\",\"file\":\"a.h\"}}}" >"$TMP/resp"
    local msg; msg="$( errOrOk "$TMP/resp" )"
    assertRefusal "$verb (no $field)" "$msg" "$verb" "$field"
    after="$( corpusHash "$W" )"
    [ "$before" = "$after" ] && ok "$verb (no $field): corpus sha256 byte-identical [$before]" \
                             || no "$verb (no $field): THE FILE WAS WRITTEN — sha256 $before → $after"
    grep -q 'return x + 1;' "$W/a.h" && ok "$verb (no $field): alpha's body still on disk" \
                                     || no "$verb (no $field): alpha's body was destroyed"
}
omitCase replace_symbol_body new_body
omitCase insert_before_symbol text
omitCase insert_after_symbol  text

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (b) the BATCH arm: the edit verbs stay batch-EXCLUDED (no second route to the write path) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHY an exclusion assertion and not a refusal assertion: batch serves kBatchServedVerbs (read verbs
# only) and runBatchSub refuses everything else as an unknown sub-verb BEFORE any argument is judged, so
# there is no batch route into runEditVerb to guard. That is a claim about the code, so it is asserted:
# both the payload-present and payload-omitted spellings must be refused inline AND write nothing.
batchCase()
{
    local verb="$1" payload="$2" label="$3"
    local W="$TMP/batch_${verb}_$label"; rm -rf "$W"; mkCorpus "$W"
    local before after
    before="$( corpusHash "$W" )"
    mcpCall "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"batch\",\"arguments\":{\"path\":\"$W\",\"queries\":[{\"verb\":\"$verb\",\"symbol\":\"alpha\",\"file\":\"a.h\"$payload}]}}}" >"$TMP/bresp"
    local msg; msg="$( errOrOk "$TMP/bresp" )"
    case "$msg" in
        *"unknown sub-verb"*"$verb"*) ok "batch/$verb ($label): refused as an unknown sub-verb";;
        *"applied"*)                  no "batch/$verb ($label): THE BATCH ARM APPLIED AN EDIT: $( printf '%.160s' "$msg" )";;
        *)                            no "batch/$verb ($label): unexpected answer: $( printf '%.160s' "$msg" )";;
    esac
    after="$( corpusHash "$W" )"
    [ "$before" = "$after" ] && ok "batch/$verb ($label): corpus sha256 byte-identical" \
                             || no "batch/$verb ($label): THE FILE WAS WRITTEN — $before → $after"
}
batchCase replace_symbol_body  ',"new_body":"int alpha( int x ) { return 7; }"' withpayload
batchCase replace_symbol_body  ''                                              nopayload
batchCase insert_before_symbol ',"text":"// x"'                                withpayload
batchCase insert_before_symbol ''                                              nopayload
batchCase insert_after_symbol  ',"text":"// x"'                                withpayload
batchCase insert_after_symbol  ''                                              nopayload

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (c) payload field PRESENT but an EMPTY STRING → refused (see the RULING in the header) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
emptyCase()
{
    local verb="$1" field="$2"
    local W="$TMP/empty_$verb"; rm -rf "$W"; mkCorpus "$W"
    local before after
    before="$( corpusHash "$W" )"
    mcpCall "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$verb\",\"arguments\":{\"path\":\"$W\",\"symbol\":\"alpha\",\"file\":\"a.h\",\"$field\":\"\"}}}" >"$TMP/eresp"
    local msg; msg="$( errOrOk "$TMP/eresp" )"
    # RULING (header, item c): "" is not "delete the body" — the table declares this field "the complete,
    # well-formed replacement definition", and every other string field on this surface already reads ""
    # as absent. So the expected answer is the SAME missing-field refusal an omitted field gets.
    assertRefusal "$verb ($field=\"\")" "$msg" "$verb" "$field"
    after="$( corpusHash "$W" )"
    [ "$before" = "$after" ] && ok "$verb ($field=\"\"): corpus sha256 byte-identical" \
                             || no "$verb ($field=\"\"): THE FILE WAS WRITTEN — $before → $after"
}
emptyCase replace_symbol_body new_body
emptyCase insert_before_symbol text
emptyCase insert_after_symbol  text

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (d) CONTROL: the same three verbs WITH their payload still work ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
controlCase()
{
    local verb="$1" args="$2" needle="$3"
    local W="$TMP/ctl_$verb"; rm -rf "$W"; mkCorpus "$W"
    local before after
    before="$( corpusHash "$W" )"
    mcpCall "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$verb\",\"arguments\":{\"path\":\"$W\",\"symbol\":\"alpha\",\"file\":\"a.h\",$args}}}" >"$TMP/cresp"
    local msg; msg="$( errOrOk "$TMP/cresp" )"
    case "$msg" in
        *"\"applied\":\"$verb\""*) ok "$verb (control): applied";;
        *)                         no "$verb (control): did NOT apply: $( printf '%.200s' "$msg" )";;
    esac
    grep -q "$needle" "$W/a.h" && ok "$verb (control): the payload is on disk verbatim" \
                               || no "$verb (control): payload not found in the file"
    after="$( corpusHash "$W" )"
    [ "$before" != "$after" ] && ok "$verb (control): the file changed, as documented" \
                              || no "$verb (control): the file did NOT change"
}
controlCase replace_symbol_body  '"new_body":"int alpha( int x )\n{\n    return 99;\n}"' 'return 99;'
controlCase insert_before_symbol '"text":"// INSERTED-BEFORE"'                           'INSERTED-BEFORE'
controlCase insert_after_symbol  '"text":"// INSERTED-AFTER"'                            'INSERTED-AFTER'

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (e) ENUMERATION: every Required/AnyOf row of kMcpRequiredFields refuses when omitted ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# The rows come from the SOURCE table, parsed — never restated here. A verb whose dispatch arm forgets to
# guard a field the table declares Required reds on this arm, which is the §H2 class in general form.
mkCorpus "$TMP/enum"
python3 - "$BIN" "$ROOT/src/mcprefusal.h" "$TMP/enum" <<'PY'
import json, re, subprocess, sys, hashlib, os

binpath, tablesrc, corpus = sys.argv[1], sys.argv[2], sys.argv[3]

# ── parse kMcpRequiredFields out of mcprefusal.h: rows of { "verb", "field", …, FieldRule::X } ──
src = open(tablesrc, encoding="utf-8").read()
block = src.split("kMcpRequiredFields[] = {", 1)[1].split("\n};", 1)[0]
rows = []
for m in re.finditer(r'^\s*\{\s*"([^"]*)"\s*,\s*"([^"]+)"\s*,(.*?)\},\s*$', block, re.M | re.S):
    verb, field, tail = m.group(1), m.group(2), m.group(3)
    rule = "Required"
    if "FieldRule::AnyOf" in tail:    rule = "AnyOf"
    elif "FieldRule::Optional" in tail: rule = "Optional"
    rows.append((verb, field, rule))
if not rows:
    print("  FAIL  (e) could not parse kMcpRequiredFields out of the source")
    sys.exit(1)

# plausible in-domain values, by field, so the ONLY thing missing is the field under test.
VAL = {
    "symbol": '"alpha"', "pattern": '"alpha"', "file": '"a.h"', "task": '"what does alpha do"',
    "type": '"alpha"', "kind": '"fn"', "from": '"beta"', "to": '"alpha"',
    "handle": '"a.h::alpha"', "trace": '"  File \\"a.h\\", line 4, in alpha"',
    "new_body": '"int alpha( int x )\\n{\\n    return 5;\\n}"', "text": '"// note\\n"',
    "queries": '[{"verb":"grep","pattern":"alpha"}]', "symbols": '["alpha","beta"]',
}
# ── ITEM B: the WRITE set comes from src/mcp.h's VERB REGISTRY, parsed — never restated here ──────────────
#
# This was a hardcoded literal set while isMcpEditVerb is — by the §H2 fix's own design — the ONE keying point
# a fourth edit verb joins. So a fourth verb would have inherited the source gate AND the table-driven refusal
# assertion below, but NOT the "corpus sha256 byte-identical" assertion — the one arm that proves the refusal
# happened BEFORE any byte was written. That is the §B6 M14 lesson (a gate that restates the table cannot catch
# the table) one field over, in the same file whose header cites it.
#
# WHERE the set is read from moved once, in the wave-1 sweep: isMcpEditVerb used to spell the three names out
# as a disjunction, and this parse read those literals. The predicate now reads kMcpVerbTable's own
# `McpVerbGroup::Edit` column (the registry a new verb joins anyway — the disjunction was a SECOND list, and
# the one a fourth verb would not have been in, which silently cost it the remote-edit refusal, the workspace
# check and the §H2 presence check). So this parse follows it to the registry, which is strictly better: the
# gate now derives its write set from the same row a new verb is added to.
#
# It still fails CLOSED. When the predicate moved, this parse returned the empty set and the gate FAILED rather
# than silently asserting nothing — that failure is what routed the gate update, and it is worth more than the
# literal it replaced. Keep that property in any future rewrite.
mcpsrc = open(os.path.join(os.path.dirname(tablesrc), "mcp.h"), encoding="utf-8").read()
_reg = mcpsrc.split("kMcpVerbTable[]", 1)
EDIT_VERBS = set(re.findall(r'\{\s*"([^"]+)"\s*,[^{}]*?McpVerbGroup::Edit\s*\}',
                            _reg[1].split("\n};", 1)[0])) if len(_reg) > 1 else set()
if not EDIT_VERBS:
    print("  FAIL  (e) could not parse kMcpVerbTable's McpVerbGroup::Edit rows out of src/mcp.h —"
          " the write set must be DERIVED, not assumed")
    sys.exit(1)
# and the predicate must actually READ that column, or the derivation above describes a table nothing consults.
_pred = mcpsrc.split("inline bool isMcpEditVerb(", 1)
if len(_pred) < 2 or "McpVerbGroup::Edit" not in _pred[1].split("\n}", 1)[0]:
    print("  FAIL  (e) isMcpEditVerb no longer reads McpVerbGroup::Edit — this gate would be probing a table"
          " the guard has stopped consulting")
    sys.exit(1)
print("  INFO  (e) write set derived from src/mcp.h kMcpVerbTable (group Edit), read back by isMcpEditVerb: %s"
      % ", ".join(sorted(EDIT_VERBS)))

def corpus_hash():
    h = hashlib.sha256()
    for root, dirs, files in os.walk(corpus):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(root, f)
            h.update(os.path.relpath(p, corpus).encode())
            h.update(open(p, "rb").read())
    return h.hexdigest()

def call(verb, args):
    body = ",".join('"%s":%s' % (k, v) for k, v in args)
    req = ('{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s"%s}}}'
           % (verb, corpus, ("," + body) if body else ""))
    lines = '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n' + req + "\n"
    out = subprocess.run([binpath, "--mcp"], input=lines, capture_output=True, text=True).stdout
    last = [l for l in out.splitlines() if l.strip()][-1]
    r = json.loads(last)
    if "error" in r: return ("err", r["error"].get("code"), r["error"].get("message", ""))
    return ("ok", 0, r["result"]["content"][0]["text"][:160].replace("\n", " "))

fails = 0
def check(cond, msg):
    global fails
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond: fails += 1

verbs = sorted({v for v, f, r in rows if v}, key=lambda v: v)
for verb in verbs:
    req  = [f for v, f, r in rows if v == verb and r == "Required"]
    anyf = [f for v, f, r in rows if v == verb and r == "AnyOf"]
    unknown = [f for f in req + anyf if f not in VAL]
    if unknown:
        check(False, "(e) %s: no test value for %s — extend this gate's VAL table" % (verb, ",".join(unknown)))
        continue

    # one case per Required field (omit it, fill the rest); AnyOf groups are omitted as a GROUP.
    cases = [([f2 for f2 in req if f2 != f], f) for f in req]
    if anyf: cases.append((list(req), "/".join(anyf)))

    for present, omitted in cases:
        before = corpus_hash()
        kind, code, msg = call(verb, [(f, VAL[f]) for f in present])
        first = omitted.split("/")[0]
        check(kind == "err" and code == -32602,
              "(e) %-24s omitting %-14s → -32602 refusal  [%s]" % (verb, omitted, msg[:70]))
        if kind == "err":
            check("missing required field" in msg and first in msg,
                  "(e) %-24s omitting %-14s → the refusal NAMES the field" % (verb, omitted))
        if verb in EDIT_VERBS:
            check(before == corpus_hash(),
                  "(e) %-24s omitting %-14s → corpus sha256 byte-identical" % (verb, omitted))

print("  INFO  (e) enumerated %d verbs / %d table rows" % (len(verbs), len(rows)))
sys.exit(1 if fails else 0)
PY
[ $? -eq 0 ] || fail=1

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
