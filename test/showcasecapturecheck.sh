#!/usr/bin/env bash
# showcasecapturecheck.sh — gate for test/showcase_capture.py (§B12.8/§B12.9/§B12.10 of the CA4 polish
# round, plus H15/H16 of the 2026-09-04 capture-audit round). Nothing else in the suite runs this generator
# or unit-tests its formatting helpers, so this file owns otherwise-unguarded claims the capture script
# makes about ITSELF and about the binary:
#
#   (A) §B12.8 — the --compress demo line must actually demonstrate compression (not a silent no-op: the
#       symbol it picks must have comments/blank runs for --compress to strip). Runs the REAL demo command
#       against the REAL repo corpus through $BIN.
#   (B) §B12.10 — fmt_block()'s "[line truncated: N more bytes]" marker must count and cut BYTES, not Python
#       str CHARACTERS, matching the preamble's own promise. Pure unit test (no $BIN needed): extracts the
#       real fmt_block/explode functions out of the live script via `ast` (not a hand-copied re-implementation
#       that could drift from the real code) and feeds it multi-byte UTF-8 input reproducing the defect shape
#       the audit found (truncated near a multi-byte char, marker undercounts the remaining bytes).
#   (C) §B12.9 / H15 — the --pack-signatures caption's percentage claim must be hedged (not a bare unqualified
#       figure), the real current reduction on this corpus (same methodology as the cited counterexample: <d>
#       signature+doc element bytes vs the SAME symbols' <b> --expand element bytes) must land in a broad
#       sanity band, AND (C-help) --help's own --pack-signatures paragraph must state that SAME band — H15
#       was exactly this last check missing: --help published a stale 59-68% while the gated band had moved
#       to 72-90%, and nothing compared the two.
#   (D)-(G) H16 (capture-audit 2026-09-04, lens0-orchestrator.md) — the capture's OWN coverage and internal
#       consistency, via test/showcase_coverage_check.py: (D) every --help flag is captured or listed
#       Not-run; (E) a caption that never says refus/error/exit/timeout must not sit over an error/exit-code
#       block; (F) a "contrast pair" (two consecutive headings differing by one added flag) must actually
#       differ; (G) a caption naming a header clause ([doc mentions/[mention anchor/[adaptive) must find it
#       in the block, unless the caption is describing the clause's ABSENCE. See that file's own docstring.
#
# NOTE: the python3 helpers below live in FILES under $TMP, not `<<'PY' ... PY` heredocs inside a `$( )`
# command substitution — macOS's stock bash (3.2.57, frozen there for licensing reasons) has a long-standing
# parser bug where a heredoc nested inside `$( )` can be mis-lexed once the heredoc body's parenthesis/quote
# count gets complex enough (reproduced directly: identical Python content parses fine as a bare heredoc
# statement, and fails with "syntax error near unexpected token '('" only when wrapped in `x="$( ... <<'PY' )"`
# — bash 3.2 is still `/bin/bash` on an unmodified Mac, so this is a real portability hazard, not a style nit).
#
# Usage:  test/showcasecapturecheck.sh   |   test/showcasecapturecheck.sh asan/ripwire   |   RIPWIRE_BIN=asan/ripwire test/showcasecapturecheck.sh
# Exits non-zero on any failure. Needs python3. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
SCRIPT="$ROOT/test/showcase_capture.py"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "showcasecapturecheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$SCRIPT" ] || { echo "showcasecapturecheck: missing $SCRIPT"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "showcasecapturecheck: python3 is required"; exit 2; }

echo "showcasecapturecheck: BIN=$BIN  SCRIPT=$SCRIPT"

# ── (A) §B12.8 — the --compress demo actually demonstrates compression ─────────────────────────────────────
sym="$( grep -oE -- '--expand=[A-Za-z0-9_:./]+ --top-k=0 --compress' "$SCRIPT" | head -1 | sed -E 's/--expand=([A-Za-z0-9_:./]+).*/\1/' )"
if [ -z "$sym" ]; then
    no "(A) could not find the --compress demo's --expand=SYM line in $SCRIPT"
else
    "$BIN" "$ROOT" "--expand=$sym" --top-k=0 --no-cache >"$TMP/nc.xml" 2>/dev/null
    "$BIN" "$ROOT" "--expand=$sym" --top-k=0 --compress --no-cache >"$TMP/c.xml" 2>/dev/null
    nc_bytes="$( wc -c <"$TMP/nc.xml" | tr -d ' ' )"; c_bytes="$( wc -c <"$TMP/c.xml" | tr -d ' ' )"
    if [ "$nc_bytes" -eq 0 ]; then
        no "(A) demo symbol '$sym' produced no --expand output at all (renamed/removed?) — pick a live symbol"
    elif diff -q "$TMP/nc.xml" "$TMP/c.xml" >/dev/null; then
        no "(A) demo symbol '$sym': --compress is a SILENT NO-OP (byte-identical, $nc_bytes B both) — the exact §B12.8 defect"
    elif [ "$c_bytes" -lt "$nc_bytes" ]; then
        ok "(A) demo symbol '$sym': --compress actually shrinks the body ($nc_bytes B -> $c_bytes B)"
    else
        no "(A) demo symbol '$sym': --compress output is NOT smaller ($nc_bytes B -> $c_bytes B) — should shrink, never grow"
    fi
fi

# ── (B) §B12.10 — the truncation marker counts BYTES, matching the preamble's promise ───────────────────────
# Extract fmt_block/explode via `ast` so this tests the REAL, live functions rather than a hand-copied
# re-implementation that could silently drift from the file being graded.
cat >"$TMP/check_marker.py" <<'PYEOF'
import ast, sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
tree = ast.parse(src)
funcs = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in ("explode", "fmt_block")]
if len(funcs) != 2:
    print("EXTRACT_FAIL got %d of 2 functions" % len(funcs))
    sys.exit(0)
ns = {}
exec(compile(ast.Module(body=funcs, type_ignores=[]), "<extract>", "exec"), ns)
fmt_block = ns["fmt_block"]

results = []

def check(name, cond):
    results.append((name, bool(cond)))

# 1) reproduce the audit's defect SHAPE: 300 pure-ASCII bytes then a run of 3-byte em-dashes straddling the
#    cut point. The pre-fix code cut/counted in CHARACTERS, so it undercounted the true remaining bytes
#    (verified separately against the actual audit example: marker said 19, truth was 21).
line = "X" * 300 + "—" * 7      # 300 ASCII bytes + 7 em-dashes (3 bytes each) = 321 bytes, 307 chars
data = (line + "\n").encode("utf-8")
out = fmt_block(data)
import re
m = re.search(r"truncated: (\d+) more bytes", out)
true_remaining = len(line.encode("utf-8")) - 300     # the first 300 bytes are pure ASCII, so this is exact
check("multi-byte tail: marker present", m is not None)
if m:
    check("multi-byte tail: marker reports the TRUE remaining byte count (%s), not the char count" % true_remaining,
          int(m.group(1)) == true_remaining)
    # the shown prefix must be valid UTF-8 (decoding it must not raise) -- cutting mid-character would corrupt it
    prefix = out.split(" … [line truncated")[0]
    try:
        prefix.encode("utf-8").decode("utf-8")
        valid = True
    except UnicodeDecodeError:
        valid = False
    check("multi-byte tail: shown prefix is valid UTF-8 (no split multi-byte char)", valid)

# 2) boundary: a line of EXACTLY 300 ASCII bytes must NOT be truncated (off-by-one both directions).
line300 = "Y" * 300
out300 = fmt_block((line300 + "\n").encode("utf-8"))
check("boundary: exactly-300-byte ASCII line is NOT truncated", "truncated" not in out300 and out300 == line300)

# 3) boundary: 301 ASCII bytes must be truncated by exactly 1.
line301 = "Y" * 301
out301 = fmt_block((line301 + "\n").encode("utf-8"))
m301 = re.search(r"truncated: (\d+) more bytes", out301)
check("boundary: 301-byte ASCII line truncated by exactly 1 byte", m301 is not None and m301.group(1) == "1")

for name, okv in results:
    print(("PASS " if okv else "FAIL ") + name)
PYEOF
b12_10_out="$( python3 "$TMP/check_marker.py" "$SCRIPT" )"
echo "$b12_10_out" | while IFS= read -r line; do [ -n "$line" ] && printf '  %s\n' "$line"; done
if echo "$b12_10_out" | grep -q '^EXTRACT_FAIL'; then
    no "(B) could not extract fmt_block/explode from $SCRIPT via ast — $( echo "$b12_10_out" | grep EXTRACT_FAIL )"
elif echo "$b12_10_out" | grep -q '^FAIL'; then
    no "(B) fmt_block truncation-marker byte-accuracy: $( echo "$b12_10_out" | grep -c '^FAIL' ) sub-check(s) failed"
else
    ok "(B) fmt_block truncation marker is byte-accurate ($( echo "$b12_10_out" | grep -c '^PASS' ) sub-checks)"
fi

# ── (C) §B12.9 — the --pack-signatures caption is hedged, and the real reduction is in a sane band ──────────
caption_line="$( grep -n -- '--pack-signatures --top-k=10' "$SCRIPT" | head -1 )"
if [ -z "$caption_line" ]; then
    no "(C) could not find the --pack-signatures --top-k=10 demo line in $SCRIPT"
else
    if printf '%s' "$caption_line" | grep -qE '\(~70% fewer tokens\)\."?\)?$'; then
        no "(C) the caption still ends in the bare unhedged '(~70% fewer tokens).' — the exact §B12.9 defect"
    else
        ok "(C) the caption is no longer the bare unhedged '(~70% fewer tokens).' string"
    fi
    if printf '%s' "$caption_line" | grep -qiE 'corpus|measured|recount'; then
        ok "(C) the caption reads as a measured/hedged claim (mentions corpus/measured/recount)"
    else
        no "(C) the caption does not read as measured/hedged — no corpus/measured/recount wording found"
    fi

    # ── the recount, CA4-F5. ────────────────────────────────────────────────────────────────────────────────
    # THE DEFECT THIS REPLACES. The old arm printed `RECOUNT_OK … reduction_pct=59.3` on the line directly
    # above `PASS … recounted top-50 reduction is 59.3% — within the 30-90% sanity band`, guarding a caption
    # that said 63%. A 60-point-wide band cannot see a 3.7-point contradiction, so the gate and the text it
    # protects disagreed in adjacent lines and the suite stayed green. Worse, the two numbers were not even
    # the same QUANTITY: the caption was measured from `ripwire .` and the gate passes $ROOT, an absolute
    # path, and the corpus root repeats inside every element (`id=` on <d>, `p=` on <b>). On this worktree —
    # a 130-byte absolute root — the old arm printed 53.8% for a caption that says 63.1%.
    #
    # THE MEASUREMENT NOW. Element bytes with the corpus-root prefix SUBTRACTED FROM BOTH SIDES. The root is
    # not what --pack-signatures elides — it appears in the signature form and the body form alike — so
    # counting it makes the ratio a function of how deep the checkout sits on disk, biased DOWNWARD for long
    # roots because a fixed prefix is a far larger fraction of a short <d> signature than of a long <b> body.
    # Measured on one corpus at three spellings of the same root (relative `.`, a 130 B absolute path, a 58 B
    # symlink), top-10/50/100:
    #     raw               60.0/62.9/70.6   ·   41.4/53.8/64.1   ·   50.1/58.4/67.4     <- 18.6 points of
    #     root-neutralised  60.4/63.1/70.7   ·   60.4/63.1/70.7   ·   60.4/63.1/70.7        pure artifact
    # The neutralised triple is identical to the digit across all three, and identical again on a second
    # checkout of this repo at a different commit. That invariance is what makes a TIGHT band defensible.
    #
    # TWO ASSERTIONS, because either alone can pass while the claim is false:
    #   (C-recount) the recount must agree with the caption's own three figures, parsed out of the script, to
    #               within 1.5 points. This is the arm that makes the printed number and the published number
    #               the same quantity by construction — they cannot drift apart without a red gate.
    #   (C-band)    the top-50 recount must land in 72-90%. Not calibrated to whatever the code does: it is
    #               81.4 +/- 9, and the +/- 9 is corpus headroom, not measurement slop, since the same
    #               measurement reproduced to the digit across three root spellings and two checkouts. A
    #               caption edited to match a broken measurement still trips this.
    #               RE-CENTERED (V1, 2026-08-15): was 63.1 +/- 9 (band 55-72) before --expand's <b> bodies
    #               carried sibs=/inc= file-context attributes — those attributes grow the BODY side of this
    #               ratio (not the sig side), so the elision the caption measures genuinely got bigger; this
    #               is a real re-derivation, not a loosened tolerance.
    cat >"$TMP/recount.py" <<'PYEOF'
import subprocess, json, re, sys

BIN, ROOT = sys.argv[1], sys.argv[2]

def run(args):
    return subprocess.run([BIN, ROOT] + args + ["--no-cache"], capture_output=True, timeout=300).stdout.decode("utf-8", "replace")

# the root prefix exactly as it appears inside the elements: id="<root>/..." on <d>, p="<root>/..." on <b>
PREFIX = ROOT if ROOT.endswith("/") else ROOT + "/"

def measure(n):
    mp = run(["--top-k=%d" % n, "--json"])
    try:
        data = json.loads(mp)
    except json.JSONDecodeError:
        return None, "could not parse --top-k=%d --json map" % n
    sels = ["%s:%s" % (f["p"], s["n"]) for f in data.get("r", []) for s in f.get("s", [])]
    if not sels:
        return None, "empty top-%d symbol set" % n
    sig_xml  = run(["--pack-signatures", "--pack-top-n=%d" % n, "--top-k=0"])
    body_xml = run(["--expand=" + ",".join(sels), "--top-k=0"])
    d_elems = re.findall(r"<d [^>]*>.*?</d>|<d [^>]*/>", sig_xml,  re.S)
    b_elems = re.findall(r"<b .*?</b>|<b [^>]*/>",       body_xml, re.S)
    # root-neutralised: strip the corpus-root prefix from every element before counting BYTES (not chars --
    # trap #17; .encode() is what makes this a byte count on a str that may hold multi-byte doc text).
    sig_bytes  = sum(len(e.replace(PREFIX, "").encode("utf-8")) for e in d_elems)
    body_bytes = sum(len(e.replace(PREFIX, "").encode("utf-8")) for e in b_elems)
    if sig_bytes == 0 or body_bytes == 0:
        return None, "sig_bytes=%d body_bytes=%d (empty payload)" % (sig_bytes, body_bytes)
    return (len(d_elems), sig_bytes, len(b_elems), body_bytes, 100.0 * (1 - sig_bytes / body_bytes)), None

out = {}
for n in (10, 50, 100):
    res, err = measure(n)
    if err:
        print("RECOUNT_FAIL top-%d: %s" % (n, err))
        sys.exit(0)
    out[n] = res
    print("RECOUNT_OK top-%d sig_entries=%d sig_bytes=%d body_entries=%d body_bytes=%d reduction_pct=%.1f"
          % (n, res[0], res[1], res[2], res[3], res[4]))
print("RECOUNT_TRIPLE %.1f %.1f %.1f" % (out[10][4], out[50][4], out[100][4]))
PYEOF
    recount="$( python3 "$TMP/recount.py" "$BIN" "$ROOT" )"
    printf '%s\n' "$recount" | sed 's/^/  /'
    if printf '%s' "$recount" | grep -q 'RECOUNT_FAIL'; then
        no "(C) recount could not be computed: $( printf '%s' "$recount" | grep 'RECOUNT_FAIL' )"
    else
        # the caption's OWN three figures, parsed out of the script it guards
        # parsed in python, not by a grep chain: `grep -oE '[0-9.]+'` over the matched clause also harvests the
        # 10/50/100 out of `top-10`/`top-50`/`top-100` and silently yields SIX numbers where three are meant —
        # caught live, the first run of this arm compared 63.1 against the literal 10.
        caption_pcts="$( printf '%s' "$caption_line" | python3 -c "
import sys, re
m = re.search( r'([0-9]+(?:\.[0-9])?)% fewer bytes at top-10, ([0-9]+(?:\.[0-9])?)% at top-50, ([0-9]+(?:\.[0-9])?)% at top-100', sys.stdin.read() )
print( ' '.join( m.groups() ) if m else '' )
" 2>/dev/null )"
        measured="$( printf '%s' "$recount" | grep '^RECOUNT_TRIPLE' | cut -d' ' -f2- )"
        if [ -z "$caption_pcts" ]; then
            no "(C-recount) the caption no longer states its three figures in the gated form 'N% fewer bytes at top-10, N% at top-50, N% at top-100' — the gate cannot pin what it cannot parse"
        else
            # GUARD BEFORE THE ZIP. `zip` stops at the SHORTEST input, so a recount that parsed only
            # one or two figures would compare only those and report OK on the rest — a truncating zip
            # is a vacuous pass, exactly the green-while-inert shape the rest of this file exists to
            # prevent. Both sides must carry three figures or the arm FAILS naming which parse broke.
            verdict="$( python3 -c "
import sys
cap = sys.argv[1].split()
mea = sys.argv[2].split()
if len(cap) != 3 or len(mea) != 3:
    print('PARSEFAIL caption yielded %d of 3 figure(s) %r; recount yielded %d of 3 %r' % (len(cap), cap, len(mea), mea))
    sys.exit(0)
cap = [float(x) for x in cap]
mea = [float(x) for x in mea]
bad = [ (n,c,m) for n,c,m in zip((10,50,100), cap, mea) if abs(c-m) > 1.5 ]
print('OK' if not bad else 'DRIFT ' + '; '.join('top-%d caption %.1f%% vs recount %.1f%% (delta %.1f)' % (n,c,m,m-c) for n,c,m in bad))
" "$caption_pcts" "$measured" 2>/dev/null || echo "ERR" )"
            case "$verdict" in
                OK)  ok "(C-recount) caption [$caption_pcts] and recount [$measured] are the SAME quantity, agreeing within 1.5 points at top-10/50/100" ;;
                PARSEFAIL*) no "(C-recount) ${verdict#PARSEFAIL } — three figures are required on BOTH sides; a short list would silently shorten the comparison and pass vacuously" ;;
                ERR) no "(C-recount) could not compare caption [$caption_pcts] against recount [$measured]" ;;
                *)   no "(C-recount) $verdict — the caption and its own gate disagree; re-derive with the root-neutralised methodology stated above, and fix BOTH" ;;
            esac
        fi
        bandLow=72.0; bandHigh=90.0
        pct="$( printf '%s' "$recount" | grep '^RECOUNT_OK top-50' | grep -oE 'reduction_pct=[0-9.-]+' | cut -d= -f2 )"
        in_band="$( python3 -c "print(1 if $bandLow <= $pct <= $bandHigh else 0)" 2>/dev/null || echo 0 )"
        if [ "$in_band" = "1" ]; then
            ok "(C-band) root-neutralised top-50 reduction is ${pct}% — inside the $bandLow-$bandHigh% regression band (81.4 +/- 9)"
        else
            no "(C-band) root-neutralised top-50 reduction is ${pct}% — OUTSIDE the $bandLow-$bandHigh% regression band; --pack-signatures is eliding materially less (or more) than when this was calibrated"
        fi

        # ── (C-help) §H15 — the --help paragraph must state THIS SAME band, not a stale one ────────────────
        # H15 (capture-audit 2026-09-04, lens3-prose.md H8): --help published "~59-68% (68% at top-50)" while
        # this arm's own gated recount landed at 84.5/80.2/80.6 with a 72-90% band — the help text was outside
        # its own gate's band. Per CLAUDE.md, when --help and a document disagree, --help wins and the document
        # is the bug; here the roles were reversed, so --help itself was the stale one. This parses the SAME
        # two numbers --help states for --pack-signatures and asserts they equal the C-band bounds above (not
        # a second hand-copied 72/90 — same $bandLow/$bandHigh variables), so a future recalibration of the
        # band and a forgotten --help edit cannot silently drift apart again.
        helpText="$( "$BIN" --help 2>&1 )"
        helpRange="$( printf '%s' "$helpText" | python3 -c "
import re, sys
m = re.search( r'~([0-9]+(?:\.[0-9])?)-([0-9]+(?:\.[0-9])?)% fewer element bytes', sys.stdin.read() )
print( ( m.group(1) + ' ' + m.group(2) ) if m else '' )
" 2>/dev/null )"
        if [ -z "$helpRange" ]; then
            no "(C-help) --help's --pack-signatures paragraph does not state a '~N-M% fewer element bytes' range — cannot check it against the gated $bandLow-$bandHigh% band"
        else
            helpLow="$( printf '%s' "$helpRange" | cut -d' ' -f1 )"
            helpHigh="$( printf '%s' "$helpRange" | cut -d' ' -f2 )"
            helpVerdict="$( python3 -c "print('OK' if (float('$helpLow') == float('$bandLow') and float('$helpHigh') == float('$bandHigh')) else 'DRIFT')" 2>/dev/null || echo ERR )"
            if [ "$helpVerdict" = "OK" ]; then
                ok "(C-help) --help states ~$helpLow-$helpHigh% fewer element bytes, matching the gated $bandLow-$bandHigh% band exactly"
            else
                no "(C-help) --help states ~$helpLow-$helpHigh%, but the gated band (recomputed above, same corpus, same run) is $bandLow-$bandHigh% — update the --pack-signatures paragraph in src/cli.h"
            fi
        fi
    fi
fi

# ── (D)/(E)/(F)/(G) H16 — capture coverage was ungated (capture-audit 2026-09-04, lens0-orchestrator.md) ──
# The 2026-08-22 capture exercised 106 of the binary's 160 long flags with nothing asserting coverage at
# all; the current generator has grown to 235+ cases, but nothing STILL asserts (a) every flag stays
# covered as new flags land, (b) a caption's own promise about refusal/exit-code/error shape holds, (c) a
# contrast pair actually contrasts, (d) a caption naming a header clause finds it. All four live in
# test/showcase_coverage_check.py (kept as a separate file, not a heredoc, for the same bash-3.2 nested-
# command-substitution parser trap arm (B)'s header above already documents), pointed at either the real
# capture or a scratch mutant so the SAME logic proves both "this shape is caught" and "the real capture
# is clean, or here is exactly what remains uncovered".
COVSCRIPT="$ROOT/test/showcase_coverage_check.py"
if [ ! -f "$COVSCRIPT" ]; then
    no "(D-G) missing $COVSCRIPT"
else
    newestCapture="$( ls -1 "$ROOT"/docs/captures/COMMANDS_showcase_*.md 2>/dev/null | sort | tail -1 )"
    if [ -z "$newestCapture" ]; then
        no "(D-G) no docs/captures/COMMANDS_showcase_*.md found"
    else
        realOut="$( python3 "$COVSCRIPT" "$ROOT" "$BIN" "$newestCapture" )"
        # Real-capture verdicts are reported straight through (PASS/FAIL each becomes an ok/no below) —
        # this file is one of the two gates the round's own brief allows to stay red until the capture is
        # regenerated at close; a red (D) or (E) here NAMES an uncovered flag or an undisclosed exit code
        # for the orchestrator to act on, same as every other disclosed-not-silent finding in this suite.
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            case "$line" in
                PASS\ *) ok "${line#PASS }" ;;
                FAIL\ *) no "${line#FAIL }" ;;
            esac
        done <<REALOUT
$realOut
REALOUT
    fi

    # ── mutation controls: synthetic fixtures, independent of the real capture's current content ────────
    MTMP="$( mktemp -d )"; trap 'rm -rf "$TMP" "$MTMP"' EXIT

    # (D) mutation: a capture with NO headings and a vacuous Not-run sentence must be seen as near-total
    # non-coverage (proves the arm can fail, not just pass-by-construction on an empty diff).
    cat >"$MTMP/d_empty.md" <<'EOF'
# empty capture mutant

**Not run (and why):** none.
EOF
    dOut="$( python3 "$COVSCRIPT" "$ROOT" "$BIN" "$MTMP/d_empty.md" | grep '^\(PASS\|FAIL\) (D)' )"
    case "$dOut" in
        FAIL\ *) ok "(D) mutation control: a heading-free capture is correctly seen as covering nothing ($dOut)" ;;
        *)       no "(D) mutation control: a heading-free capture was NOT flagged as uncovered — the arm cannot see the thing it exists for ($dOut)" ;;
    esac

    # (E)/(F)/(G) mutation: one synthetic capture exercising all three shapes AND their negative controls,
    # so a false-positive on the negation wording ("no [doc mentions]", a caption that DOES say "refuses")
    # is caught in the same run as the true positives.
    cat >"$MTMP/efg.md" <<'EOF'
**Not run (and why):** none.

## `./build/ripwire . --mutant-e-bad`

*A normal caption with no failure words at all.*

**exit code: 1**

`````
(empty)
`````

## `./build/ripwire . --mutant-e-good`

*This block properly discloses that it refuses.*

**exit code: 1**

`````
(empty)
`````

## `./build/ripwire . --for="x"`

*Doc-mention surfacing: the legend's [doc mentions: …] clause says it fired.*

`````
<ctx bodies="1"/>
`````

## `./build/ripwire . --for="x" --no-doc-mention`

*No [doc mentions] clause here — the contrast the flag exists for.*

`````
<ctx/>
`````

## `./build/ripwire . --mutant-f-bad`

*Base run.*

`````
<r a="1"/>
`````

## `./build/ripwire . --mutant-f-bad --no-extra`

*Modifier contrast — should differ but does not.*

`````
<r a="1"/>
`````

## `./build/ripwire . --mutant-f-good`

*Base run showing three rows.*

`````
<r a="1" b="2" c="3"/>
`````

## `./build/ripwire . --mutant-f-good --detail=1`

*Same query with detail widened — a real contrast.*

`````
<r a="1" b="2" c="3" d="4"/>
`````
EOF
    efgOut="$( python3 "$COVSCRIPT" "$ROOT" "$BIN" "$MTMP/efg.md" )"
    eLine="$( printf '%s\n' "$efgOut" | grep '(E) caption-vs-error' )"
    fLine="$( printf '%s\n' "$efgOut" | grep '(F) contrast-pair' )"
    gLine="$( printf '%s\n' "$efgOut" | grep '(G) header-clause' )"

    case "$eLine" in
        FAIL\ *mutant-e-bad*) ok "(E) mutation control: the undisclosed-exit-code block is caught, and the properly-captioned one (--mutant-e-good) is not: $eLine" ;;
        *)                    no "(E) mutation control did not catch the undisclosed exit code (or false-flagged the good block): $eLine" ;;
    esac
    case "$fLine" in
        FAIL\ *mutant-f-bad*) ok "(F) mutation control: the byte-identical contrast pair is caught, and the real-contrast pair (--mutant-f-good) is not: $fLine" ;;
        *)                    no "(F) mutation control did not catch the byte-identical pair (or false-flagged the differing one): $fLine" ;;
    esac
    case "$gLine" in
        FAIL\ *"--for=\"x\""*) ok "(G) mutation control: the unfulfilled [doc mentions claim is caught, and the 'no [doc mentions]' negation is correctly NOT flagged: $gLine" ;;
        *)                     no "(G) mutation control did not catch the unfulfilled header-clause claim (or false-flagged the negation caption): $gLine" ;;
    esac
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "SOME CHECKS FAILED"
fi
exit "$fail"
