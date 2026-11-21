#!/usr/bin/env bash
# rowlinescheck.sh — ROWLINES + RANKSEQ (src/forrowlines.h; lane FMT2, owner ruling 136): the rows of an answer-first `--for` answer's
# <sigs> and <tail> are text lines in ONE CDATA per section, and a sigs row whose rank is the previous row's + 1 does not spell it.
#
# The contract is LOSSLESS: test/rowlines.py decode() of the answer is the RIPWIRE_NO_ROWLINES=1 twin of the same binary byte for byte.
# Every arm is NEW (red on a binary without the form: (L0) finds no line-form section), except where it says otherwise.
# ARMS
#   (L0)  presence: the answer's <sigs> and <tail> each hold exactly one CDATA and no element; the twin holds elements; the answer
#         carries at least one definition line, one pointer line and one verbatim row (else the arms below are vacuous)
#   (L1)  lossless: decode(answer) == twin, byte for byte — the whole answer (--page-bytes=0), the default page 1, page 2, a budget
#         the answer fits, a budget that sheds, --signatures-only, and pages 1 and 2 at 3000 B (page 2 re-opens <sigs>)
#   (L1n) MUTATION NEGATIVE CONTROL: the same comparison FAILS when one byte is dropped from a line, and when the r= a continuation
#         page's first row must keep is elided (the decoder then numbers the rows from 1)
#   (L2)  legend: each of the two clauses is present exactly once where its form is used, last before </ctx>, and absent from the twin;
#         a continuation page carries neither (it re-sends no legend), and page 1 carries the clause of every section it names as
#         continued= or deferred=, so the pages after it are defined
#   (L3)  RANKSEQ only when + 1: read against the twin's rows, a row has no r= IF AND ONLY IF its rank is the previous row's + 1 and
#         r= is its last attribute; <sigs rseq="1"> iff any was dropped; a continuation page's first sigs row keeps its r=
#   (L4)  CDATA is never ended early: no line-form section's text holds "]]>", and a fixture whose signature holds "]]>" keeps
#         that section in ELEMENT form (and still decodes to its twin)
#   (L5)  well formed (xmllint) and no newline outside CDATA (G4), on every answer above
#   (L6)  deterministic: two runs byte-identical
#   (L7)  not applied: --legend=first and --json are byte-identical with and without the knob
#   (L8)  est_tokens= is the element form's (equal to the twin's): an upper bound on the bytes served, never an under-read
#   (L9)  lossless on OTHER trees: every 6th test/*fix fixture (sorted), one generic task each — decode(answer) == twin on every one
#         that answers, and at least 10 of them are in line form (else the arm proves nothing)
#   (L10) the form's whole LEGEND cost is its two clauses: the answer's comment bytes exceed the twin's by exactly their sizes
#         (compactlegendcheck's size targets read the element form, so this arm is where that cost is pinned; a third clause, or a
#         longer one, fails here)
#   (R1)  --rows= (owner ruling 153: lines by default, both forms reachable): --rows=elements is the RIPWIRE_NO_ROWLINES=1 twin
#         byte for byte (the element form, which (L1) ties to the answer and the lane's 89-question run ties to the pre-FMT2
#         binary), and --rows=lines is the default answer byte for byte — whole answer and page 1
#   (R1n) the arm can fail: the two forms differ, so (R1)'s comparison crossed over (elements against the default) is unequal
#   (R2)  FLAG OVER ENV, both directions: RIPWIRE_NO_ROWLINES=1 --rows=lines serves lines; --rows=elements serves elements
#         with the variable unset and set
#   (R3)  refused in the house shape (exit 1, empty stdout, one stderr sentence naming the flag and the accepted values): an
#         unknown value, an empty value, and the flag without --for
#   (R4)  --version discloses the default form in this environment: rows=lines, and rows=elements under RIPWIRE_NO_ROWLINES=1
#         (zero answer bytes: the answer root is unchanged)
#   Every (R) arm is NEW: red on a binary without the flag (it refuses --rows= as unknown, so every file below is empty).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "rowlinescheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "rowlinescheck: xmllint required"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "rowlinescheck: BIN=$BIN"
cd "$ROOT" || exit 2
unset RIPWIRE_NO_ROWLINES
TASK="rank symbols by pagerank and serialize the map"
rw(){ "$BIN" src --no-cache --for="$TASK" "$@" 2>/dev/null; }
pair(){ name="$1"; shift; rw "$@" >"$WORK/$name.on"; RIPWIRE_NO_ROWLINES=1 rw "$@" >"$WORK/$name.off"; }
pair whole  --page-bytes=0
pair page1
pair page2  --page-bytes=12000:2
pair fits   --token-budget=100000
pair sheds  --token-budget=4000
pair sigonly --signatures-only
pair small1 --page-bytes=3000
pair small2 --page-bytes=3000:2
rw --page-bytes=0 >"$WORK/whole.on2"
for arm in "--legend=first" "--json"; do
    tag="$( printf '%s' "$arm" | tr -c 'a-z0-9' '_' )"
    rw $arm >"$WORK/n_$tag.on"; RIPWIRE_NO_ROWLINES=1 rw $arm >"$WORK/n_$tag.off"
    if [ -s "$WORK/n_$tag.on" ] && cmp -s "$WORK/n_$tag.on" "$WORK/n_$tag.off"; then ok "(L7) $arm: byte-identical with and without RIPWIRE_NO_ROWLINES"
    else no "(L7) $arm: the answer changed with the knob (or is empty)"; fi
done
# (R) the --rows= flag
rw --page-bytes=0 --rows=elements                          >"$WORK/r_whole.el"
rw --page-bytes=0 --rows=lines                             >"$WORK/r_whole.li"
rw --rows=elements                                         >"$WORK/r_page1.el"
rw --rows=lines                                            >"$WORK/r_page1.li"
RIPWIRE_NO_ROWLINES=1 rw --page-bytes=0 --rows=lines       >"$WORK/r_env_li"
RIPWIRE_NO_ROWLINES=1 rw --page-bytes=0 --rows=elements    >"$WORK/r_env_el"
same(){ [ -s "$1" ] && cmp -s "$1" "$2"; }
if same "$WORK/r_whole.el" "$WORK/whole.off" && same "$WORK/r_page1.el" "$WORK/page1.off"; then ok "(R1) --rows=elements is the RIPWIRE_NO_ROWLINES=1 twin byte for byte (whole answer, page 1)"
else no "(R1) --rows=elements is not the element-form twin (or is empty)"; fi
if same "$WORK/r_whole.li" "$WORK/whole.on" && same "$WORK/r_page1.li" "$WORK/page1.on"; then ok "(R1) --rows=lines is the default answer byte for byte (whole answer, page 1)"
else no "(R1) --rows=lines is not the default answer (or is empty)"; fi
if [ -s "$WORK/r_whole.el" ] && ! cmp -s "$WORK/r_whole.el" "$WORK/whole.on" && ! cmp -s "$WORK/r_whole.li" "$WORK/whole.off"; then ok "(R1n) [negative control] crossed over, (R1)'s comparison is unequal: the two forms differ"
else no "(R1n) the two forms are byte-identical (or empty): (R1) could not tell them apart"; fi
if same "$WORK/r_env_li" "$WORK/whole.on"; then ok "(R2) RIPWIRE_NO_ROWLINES=1 --rows=lines serves the line form: the flag decides over the variable"
else no "(R2) with the variable set, --rows=lines did not serve the line form"; fi
if same "$WORK/r_env_el" "$WORK/whole.off" && same "$WORK/r_whole.el" "$WORK/whole.off"; then ok "(R2) --rows=elements serves the element form with the variable unset and set"
else no "(R2) --rows=elements did not serve the element form in both environments"; fi
refused(){   # label, the stderr text required, then the argv
    label="$1"; want="$2"; shift 2
    "$BIN" src --no-cache "$@" >"$WORK/ref.out" 2>"$WORK/ref.err"; rc=$?
    if [ "$rc" -eq 1 ] && [ ! -s "$WORK/ref.out" ] && grep -qF -- "$want" "$WORK/ref.err" && [ "$( grep -c . "$WORK/ref.err" )" -eq 1 ]; then ok "(R3) $label: refused (exit 1, no answer, one sentence: $want)"
    else no "(R3) $label: rc=$rc, stdout $( wc -c <"$WORK/ref.out" | tr -d ' ' ) B, stderr: $( head -c 200 "$WORK/ref.err" )"; fi
}
refused "an unknown value"        "ripwire: --rows needs lines or elements — got 'xml'"  --for="$TASK" --rows=xml
refused "an empty value"          "ripwire: --rows= is empty — it needs lines or elements" --for="$TASK" --rows=
refused "the flag without --for"  "ripwire: --rows shapes the rows of a --for answer only" --rows=elements
v_def="$( "$BIN" --version 2>/dev/null )"; v_env="$( RIPWIRE_NO_ROWLINES=1 "$BIN" --version 2>/dev/null )"
case "$v_def" in *", rows=lines, built_from="*) case "$v_env" in *", rows=elements, built_from="*) ok "(R4) --version says rows=lines, and rows=elements under RIPWIRE_NO_ROWLINES=1" ;; *) no "(R4) --version under the variable: $v_env" ;; esac ;;
    *) no "(R4) --version does not disclose rows=lines: $v_def" ;; esac
# (L4) fixture: a Python signature whose text holds the CDATA terminator
mkdir -p "$WORK/fx"
cat >"$WORK/fx/terminator.py" <<'PY'
def cdata_terminator_probe(table, picks=[[0]]>[[1]]):
    """rank symbols for the terminator probe"""
    return table[picks]


def cdata_terminator_caller(table):
    return cdata_terminator_probe(table)
PY
"$BIN" "$WORK/fx" --no-cache --for="cdata_terminator_probe terminator probe" --page-bytes=0 >"$WORK/fx.on" 2>/dev/null
RIPWIRE_NO_ROWLINES=1 "$BIN" "$WORK/fx" --no-cache --for="cdata_terminator_probe terminator probe" --page-bytes=0 >"$WORK/fx.off" 2>/dev/null
# (L9) other trees
n=0
for d in $( ls -d test/*fix | sort | awk 'NR % 6 == 1' ); do
    n=$(( n + 1 ))
    "$BIN" "$d" --no-cache --for="main run init parse handle get set name value" --page-bytes=0 >"$WORK/t$n.on" 2>/dev/null
    RIPWIRE_NO_ROWLINES=1 "$BIN" "$d" --no-cache --for="main run init parse handle get set name value" --page-bytes=0 >"$WORK/t$n.off" 2>/dev/null
done
echo "$n" >"$WORK/trees.n"
for f in whole page1 page2 fits sheds sigonly small1 small2 fx; do
    if xmllint --noout "$WORK/$f.on" 2>/dev/null; then ok "(L5) $f: well formed"; else no "(L5) $f: xmllint rejects the answer"; fi
done
if cmp -s "$WORK/whole.on" "$WORK/whole.on2"; then ok "(L6) two runs byte-identical"; else no "(L6) two runs differ"; fi
python3 - "$WORK" "$ROOT/test" <<'PY'
import os, re, sys
W = sys.argv[1]; sys.path.insert(0, sys.argv[2])
import rowlines as R
bad = 0
def rd(n): return open(os.path.join(W, n), "rb").read()
def say(ok, msg):
    global bad
    print("  %s  %s" % ("PASS" if ok else "FAIL", msg)); bad += 0 if ok else 1
ANSWERS = ("whole", "page1", "page2", "fits", "sheds", "sigonly", "small1", "small2")
on = {n: rd(n + ".on") for n in ANSWERS + ("fx",)}; off = {n: rd(n + ".off") for n in ANSWERS + ("fx",)}
def sections(b): return {name: b[e:c] for name, s, e, c in R.top_sections(b)}
def is_lines(body): return body.startswith(b"<![CDATA[") and body.endswith(b"]]>") and body.find(b"]]>") == len(body) - 3 and b"<![CDATA[" not in body[9:]
def lines(body): return body[9:-3].split(b"\n")

# (L0) presence, and the three kinds of line
sw, st = sections(on["whole"]), sections(off["whole"])
all_lines = [l for name in (b"sigs", b"tail") if name in sw and is_lines(sw[name]) for l in lines(sw[name])]
kinds = dict(verbatim=sum(l.startswith(b"<") for l in all_lines),
             definition=sum((not l.startswith(b"<")) and R.parse_definition(l) is not None for l in all_lines),
             pointer=sum((not l.startswith(b"<")) and R.parse_definition(l) is None for l in all_lines))
say(all(n in sw and is_lines(sw[n]) for n in (b"sigs", b"tail")) and all(n in st and st[n].startswith(b"<") and not is_lines(st[n]) for n in (b"sigs", b"tail"))
    and min(kinds.values()) > 0, "(L0) <sigs> and <tail> are one CDATA of lines each, the twin holds elements; lines: %s" % kinds)

# (L1) lossless on every answer
for n in ANSWERS:
    say(len(off[n]) > 0 and on[n] != off[n] and R.decode(on[n]) == off[n],
        "(L1) %s: decode(answer) is the RIPWIRE_NO_ROWLINES=1 twin byte for byte (%d B served, %d B element form)" % (n, len(on[n]), len(off[n])))
say(R.decode(off["whole"]) == off["whole"], "(L1) an element-form answer decodes to itself")

# (L1n) the comparison can fail: drop one byte of a definition line; elide a rank that is not sequential
def differs(mutant):
    try: return R.decode(mutant) != off["whole"]
    except Exception: return True          # a line the decoder cannot read is not the twin either
w = on["whole"]; m = re.search(rb"\n[^<\n]", w[w.index(b"<sigs"):w.index(b"</sigs>")])
i = w.index(b"<sigs") + m.start() + 1 if m else -1      # the first byte of the first definition/pointer line of <sigs>
say(i > 0 and differs(w[:i] + w[i + 1:]), "(L1n) [mutation negative control] one byte dropped from a line: the decode no longer equals the twin")
s2 = on["small2"]; m = re.search(rb"(<sigs[^>]*><!\[CDATA\[[^<\n][^\n]*?)[ \t]r=\d+(?= \| |\n|\]\]>)", s2)
def differs2(mutant):
    try: return R.decode(mutant) != off["small2"]
    except Exception: return True
say(m is not None and differs2(s2[:m.start(0)] + m.group(1) + s2[m.end(0):]),
    "(L1n) [mutation negative control] the r= a continuation page's first row must keep, elided: the decode no longer equals the twin")

# (L2) the legend clauses
for n in ANSWERS:
    b = on[n]; secs = sections(b); rs = b' rseq="1">' in b; rl = any(is_lines(v) for v in secs.values())
    page1 = b' page="1"' in b[:b.index(b">")]; later = re.search(rb' page="(?!1")\d+"', b[:b.index(b">")]) is not None
    rs, rl = rs and not later, rl and not later      # a continuation page re-sends no legend: page 1 defined its lines
    want_r = rs or (page1 and re.search(rb' (?:continued|deferred)="(?:[^"]* )?sigs(?: [^"]*)?"', b[:b.index(b">")]) is not None)
    want_l = rl or want_r or (page1 and re.search(rb' (?:continued|deferred)="(?:[^"]* )?tail(?: [^"]*)?"', b[:b.index(b">")]) is not None)
    tailtext = (R.RSEQ_CLAUSE if want_r else b"") + (R.ROWS_CLAUSE if want_l else b"") + b"</ctx>"
    okc = b.count(R.RSEQ_CLAUSE) == int(want_r) and b.count(R.ROWS_CLAUSE) == int(want_l) and b.rstrip(b"\n").endswith(tailtext)
    say(okc and R.RSEQ_CLAUSE not in off[n] and R.ROWS_CLAUSE not in off[n],
        "(L2) %s: rank clause %d, line clause %d, each once and last before </ctx>; the twin has neither" % (n, want_r, want_l))
say(b"-->" + R.ROWS_CLAUSE in on["whole"] or b"-->" + R.RSEQ_CLAUSE in on["whole"], "(L2) whole: the clauses follow the document legend")

# (L3) RANKSEQ only when + 1 — read against the twin's rows
def twin_rows(b):
    body = sections(b).get(b"sigs", b"")
    return [(body[s:e], R.open_tag(body, s)[1]) for s, e, name in R.rows_of(body) if name in (b"d", b"t")]
def served_rows(b):
    """the answer's sigs rows with ROWLINES undone and RANKSEQ left in place"""
    secs = sections(b); body = secs.get(b"sigs", b"")
    if is_lines(body): body = b"".join(R.parse_line(l) for l in lines(body))
    return [R.open_tag(body, s)[1] for s, e, name in R.rows_of(body) if name in (b"d", b"t")]
for n in ("whole", "page1", "small1", "small2", "sigonly"):
    tw, sv = twin_rows(off[n]), served_rows(on[n])
    okr = len(tw) == len(sv) and len(tw) > 0; prev = 0; dropped = 0
    for (_, ta), sa in zip(tw, sv):
        r = int(dict(ta)[b"r"]); expect_drop = r == prev + 1 and ta[-1][0] == b"r"; is_dropped = b"r" not in dict(sa)
        okr = okr and expect_drop == is_dropped; dropped += is_dropped; prev = r
    flag = b' rseq="1">' in on[n]
    say(okr and flag == (dropped > 0), "(L3) %s: %d of %d sigs rows spell no r=, exactly the rows whose rank is the previous + 1 with r= last; rseq=1 %s"
        % (n, dropped, len(tw), "set" if flag else "absent"))
p2 = served_rows(on["small2"])
say(len(p2) > 0 and b"r" in dict(p2[0]) and int(dict(p2[0])[b"r"]) > 1,
    "(L3) a continuation page that re-opens <sigs> (3000 B pages, page 2): its first row keeps its r= (%s)" % (b"r=" + dict(p2[0]).get(b"r", b"?") if p2 else b"no sigs rows").decode())

# (L4) the CDATA terminator
inner_ok = all(b"]]>" not in v[9:-3] for b in on.values() for v in sections(b).values() if is_lines(v))
fx_secs = sections(on["fx"]); fx_twin = sections(off["fx"])
holds = [n for n, v in fx_twin.items() if b"]]&gt;" in v]
say(inner_ok, "(L4) no line-form section's text holds the CDATA terminator")
say(len(holds) > 0 and all(not is_lines(fx_secs[n]) for n in holds) and R.decode(on["fx"]) == off["fx"],
    "(L4) fixture: the section whose signature holds ']]>' (%s) stays in element form, and the answer decodes to its twin" % b",".join(holds).decode())

# (L5) no newline outside CDATA
def newline_outside_cdata(b): return b"\n" in re.sub(rb"<!\[CDATA\[.*?\]\]>", b"", b.rstrip(b"\n"), flags=re.S)
say(not any(newline_outside_cdata(b) for b in on.values()), "(L5) no newline outside CDATA in any answer (G4)")

# (L9) other trees
T = int(rd("trees.n").strip()); answered = same = inline = 0
for k in range(1, T + 1):
    a, b = rd("t%d.on" % k), rd("t%d.off" % k)
    if not b.startswith(b"<ctx"): continue
    answered += 1; inline += a != b
    try: same += R.decode(a) == b
    except Exception: pass
say(answered > 0 and same == answered and inline >= 10, "(L9) %d fixture trees, %d answered: decode(answer) is the twin on %d, %d of them in line form (need >= 10)" % (T, answered, same, inline))

# (L10) the legend cost
comments = lambda b: sum(len(m) for m in re.findall(rb"<!--.*?-->", re.sub(rb"<!\[CDATA\[.*?\]\]>", b"", b, flags=re.S), flags=re.S))
cost = len(R.RSEQ_CLAUSE) + len(R.ROWS_CLAUSE)
say(comments(on["whole"]) - comments(off["whole"]) == cost and comments(on["page1"]) - comments(off["page1"]) == cost,
    "(L10) the answer's legend is the twin's plus the two clauses, %d B (%d + %d), on the whole answer and on page 1" % (cost, len(R.RSEQ_CLAUSE), len(R.ROWS_CLAUSE)))

# (L8) est_tokens= is the element form's
est = lambda b: re.search(rb' est_tokens="(\d+)"', b[:b.index(b">")])
say(all(est(on[n]) and est(off[n]) and est(on[n]).group(1) == est(off[n]).group(1) for n in ANSWERS),
    "(L8) est_tokens= equals the element-form twin's on every answer: an upper bound on the bytes served")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1
if [ "$fail" -eq 0 ]; then echo "rowlinescheck: all arms PASS"; else echo "rowlinescheck: FAILED"; fi
exit "$fail"
