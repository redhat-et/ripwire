#!/usr/bin/env bash
# --legend-have=DICTV: the CLI legend handshake and the ref posture it unlocks.
#
# WHAT THIS GUARDS. The legend is a near-FIXED per-answer cost (measured 2026-11-16 over 311 recorded
# answers: 531..4,305 B, median 1,796), so its SHARE grows as answers shrink -- 14.0 % of a --for bundle
# and 62.6 % of a --whereis answer. 93 % of every legend clause emitted has already been sent to the
# reader. The handshake is how a CLI run can skip the resend without lying: the caller NAMES the
# dictionary version it holds, so the answer depends on argv alone (reproducible) and a reader holding a
# different dictionary is REFUSED rather than handed a pointer it cannot resolve.
#
# The bar this gate holds is not the byte saving. It is that the saving is LOSSLESS: every row and every
# attribute of the inline answer must still be in the ref answer -- and ON ITS ROOT, where the inline answer
# has it (ref-posture-disclosure, 2026-11-17). "Moved but never dropped" was this gate's first bar, and it
# passed an answer whose capped="1" sat after its last row; test/refdisclosurecheck.sh holds the placement.
set -u
BIN="${RIPWIRE_BIN:-${1:-./build/ripwire}}"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; fi
fail=0
pass() { printf '  PASS  %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# (A0) OBTAIN THE DICTIONARY, THEN NAME IT. This gate used to cut the dictionary to its first line and pass the
# version it found there: 78 B read, the rest asserted -- the unbacked claim the flag exists to prevent, taught by
# the gate that guards it. The whole text is held in $DICT, the version is read from the held copy, and arms (M)
# and (T) below check the definitions an answer drops against THAT copy, not against a second run.
DICT="$WORK/dict.txt"
"$BIN" --legend-dict >"$DICT" 2>/dev/null
DV=$(sed -n '1s/.*dictv=\([0-9a-f]\{16\}\).*/\1/p' "$DICT")
if [ -z "$DV" ]; then bad "(A0) --legend-dict prints no dictv= -- the handshake has no version to name"; echo "FAILURES"; exit 1; fi
DICT_BYTES=$(wc -c <"$DICT" | tr -d ' '); DICT_LINES=$(wc -l <"$DICT" | tr -d ' ')
if [ "$DICT_LINES" -gt 100 ]; then pass "(A0) the dictionary is HELD ($DICT_BYTES B, $DICT_LINES lines) and names its version on line 1 ($DV)"
else bad "(A0) --legend-dict printed $DICT_LINES line(s) -- a version with no definitions behind it"; fi

# (B) a stale version is REFUSED, naming both -- the arm that keeps the posture honest
err="$WORK/stale.err"
"$BIN" . --callers=main --legend-have=0000000000000000 >/dev/null 2>"$err"; rc=$?
if [ "$rc" -ne 0 ] && grep -q "does not match this binary's legend dictionary" "$err" && grep -q "$DV" "$err"; then
    pass "(B1) a stale --legend-have= is refused (rc=$rc) and the message names THIS binary's version"
else
    bad "(B1) a stale --legend-have= must refuse and name both versions -- rc=$rc, stderr: $(head -c 200 "$err")"
fi
# (B2) AN EMPTY VALUE REFUSES. This arm asserted the OPPOSITE when it was written -- that an empty value
# "asserts nothing and is a no-op" -- and test/emptyvaluerefusecheck.sh was right to fail it: §B5's owner
# ruling (2026-07-29) is refuse-all, 20 of the 21 hand-written arms refuse, and the odd one out was this
# flag. The ruling's argument is the stronger one here: `--legend-have=` is usually a shell variable that
# expanded to nothing, and ignoring it serves a FULL-PRICE answer at exit 0 while the caller believes the
# bytes were reduced. Absent and present-but-empty must therefore differ, and both halves are asserted.
eout="$WORK/empty.out"; eerr="$WORK/empty.err"
"$BIN" . --callers=main --legend-have= >"$eout" 2>"$eerr"; rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$eout" ] && grep -qF -- "--legend-have" "$eerr"; then
    pass "(B2) an EMPTY --legend-have= refuses (rc=1), names the flag, and writes no stdout"
else
    bad "(B2) an empty --legend-have= must refuse naming the flag with empty stdout -- rc=$rc, $(wc -c <"$eout" | tr -d ' ')B stdout"
fi
if "$BIN" . --callers=main >/dev/null 2>&1; then
    pass "(B3) the flag ABSENT is still a no-op -- an empty value and no flag are different things"
else
    bad "(B3) omitting --legend-have= must not refuse"
fi
# §B5 also requires the refusal to be byte-identical under --json: the table machinery writes to stderr
# before any serializer is chosen, and that has to stay true.
"$BIN" . --callers=main --legend-have= --json >/dev/null 2>"$WORK/empty_json.err"
if cmp -s "$eerr" "$WORK/empty_json.err"; then
    pass "(B4) the empty-value refusal is byte-identical under --json"
else
    bad "(B4) the empty-value refusal differs under --json"
fi

# (C) the posture applies, and is LOSSLESS: body identical, every root attribute still present
python3 - "$BIN" "$DV" "$WORK" <<'PY'
import re, subprocess, sys
BIN, DV, WORK = sys.argv[1], sys.argv[2], sys.argv[3]
CMT = re.compile(r"<!--.*?-->", re.S)
AB  = re.compile(r"<about\b[^>]*/>")
ROOT = re.compile(r"\s*<([A-Za-z_][A-Za-z0-9_-]*)\b[^>]*>")
# NAME AND VALUE. An earlier version of this arm compared attribute NAME SETS, which passes when count="2"
# becomes count="1" -- it would have reported "lossless" while the answer's data had changed. Values are
# compared as a multiset so a duplicated attribute cannot hide either.
ATTR = re.compile(r'([A-Za-z_][A-Za-z0-9_-]*)="([^"]*)"')

def row_paths(x):
    """Every p= path in the body, flattened across grouped rows, as a multiset."""
    out = []
    for m in re.finditer(r'\bp="([^"]*)"', x or ""):
        out += [q for q in m.group(1).split(",") if q]
    return sorted(out)

def parts(x):
    x = CMT.sub("", x)
    m = ROOT.match(x)
    if not m:
        return None
    close = "</%s>" % m.group(1)
    j = x.rfind(close)
    return (m.group(0), x[m.end():j] if j > m.end() else "")

def pairs(*texts):
    out = []
    for t in texts:
        out += ATTR.findall(t or "")
    return sorted(out)

VERBS = ["--callers=main", "--callees=main", "--impact=main", "--whereis=main",
         "--path=main,main", "--dead-code", "--affected=README.md", "--lego=Iface"]
ok = lossy = skipped = 0
for v in VERBS:
    ra_ = subprocess.run([BIN, ".", v], capture_output=True, text=True)
    rb_ = subprocess.run([BIN, ".", v, "--legend-have=" + DV], capture_output=True, text=True)
    a, b = ra_.stdout, rb_.stdout
    pa, pb = parts(a), parts(b)
    if not pa or not pb or 'legend="ref"' not in b:
        # UNREDUCED is only acceptable if the answer really was served unchanged. Without this, a verb that
        # returned empty stdout or a DIFFERENT inline answer would pass as "skipped" -- the non-vacuity arm
        # below only stops EVERY verb from skipping, not one of them from hiding a changed answer.
        if a == b and ra_.returncode == rb_.returncode:
            skipped += 1
            print("  PASS  (C-skip) %-22s not reduced by this dictionary, and served byte-identical (rc=%d)"
                  % (v, rb_.returncode))
        else:
            lossy += 1
            print("  FAIL  (C-skip) %-22s not reduced, but the answer CHANGED (%d B -> %d B, rc %d -> %d)"
                  % (v, len(a), len(b), ra_.returncode, rb_.returncode))
        continue
    ra, ba = pa
    rb, bb = pb
    ab = AB.search(bb)
    body_b = AB.sub("", bb)
    want = pairs(ra)
    have = pairs(rb)
    # every ORIGINAL pair must survive with its value ON THE ROOT; <about> is the legend pointer (legend=/dict=/dictv=)
    # and a root fact found only there counts as LOST, which is what it is to a reader of the prefix
    missing = [kv for kv in want if have.count(kv) < want.count(kv)]
    missing += [kv for kv in pairs(ab.group(0) if ab else "") if kv[0] not in ("legend", "have", "dict", "dictv")]
    if ba == body_b and not missing:
        ok += 1
        print("  PASS  (C1) %-22s LOSSLESS: body byte-identical, every root attribute kept ON THE ROOT with its value" % v)
    elif not missing and row_paths(ba) == row_paths(body_b):
        # GROUPING. The ref posture UNGROUPS compact `<g n= p="a,b,c">` rows, because a ref reader is not
        # carrying the grouping clause -- so the body legitimately differs and gets LONGER, not shorter.
        # Measured 2026-11-16 on a 68-path --affected answer: 2,881 B -> 2,950 B, four <g> rows -> three, and
        # the p= multiset identical. Content-preserving, so it passes -- but only against the multiset, never
        # against "it differs, so it must be grouping".
        ok += 1
        print("  PASS  (C1) %-22s LOSSLESS: grouped rows expanded (%d B -> %d B), p= multiset identical"
              % (v, len(ba), len(body_b)))
    else:
        lossy += 1
        why = "body differs and the p= multiset differs too" if ba != body_b else (
            "name=value pairs LOST: " + ", ".join("%s=%s" % kv for kv in missing[:4]))
        print("  FAIL  (C1) %-22s %s" % (v, why))
if ok == 0:
    print("  FAIL  (C2) no verb took the ref posture -- the handshake saved nothing, so C1 proved nothing")
    sys.exit(1)

# (C3) the grouping tier is UNEXERCISED by the verbs above: no answer on this repository carries a `<g>` row
# (measured: 0 for --affected/--impact/--callers here), and an arm that cannot fire proves nothing. So the
# comparison itself is tested on a synthetic pair, both directions, rather than left unproven.
G_BEFORE = '<x><g n="3" p="a/one.ts,b/two.ts,c/three.ts" hops="3"/><t p="d/four.ts"/></x>'
G_AFTER  = '<x><t p="a/one.ts" hops="3"/><t p="b/two.ts" hops="3"/><t p="c/three.ts" hops="3"/><t p="d/four.ts"/></x>'
G_LOSSY  = '<x><t p="a/one.ts" hops="3"/><t p="b/two.ts" hops="3"/><t p="d/four.ts"/></x>'
if row_paths(G_BEFORE) == row_paths(G_AFTER) and row_paths(G_BEFORE) != row_paths(G_LOSSY):
    print("  PASS  (C3) the grouping-aware comparison accepts an expansion AND rejects a dropped row")
else:
    print("  FAIL  (C3) the grouping-aware comparison does not distinguish an expansion from a dropped row")
    lossy += 1
if any(re.search(r"<g\b", subprocess.run([BIN, ".", v], capture_output=True, text=True).stdout or "")
       for v in VERBS):
    print("  PASS  (C3b) a verb here does emit <g>, so the grouping tier is live, not only synthetic")
else:
    print("  PASS  (C3b) NOT-ESTABLISHED on this repository: no verb here emits <g>, so (C3) is the only "
          "evidence for the grouping tier -- stated rather than implied")
print("  PASS  (C2) %d verb(s) took the posture, %d served inline byte-identical" % (ok, skipped))
sys.exit(1 if lossy else 0)
PY
[ $? -eq 0 ] || fail=1

# (D) determinism -- the whole point of naming the version instead of remembering a session
d1="$WORK/d1"; d2="$WORK/d2"
"$BIN" . --callers=main --legend-have="$DV" >"$d1" 2>/dev/null
"$BIN" . --callers=main --legend-have="$DV" >"$d2" 2>/dev/null
if cmp -s "$d1" "$d2"; then pass "(D1) two identical invocations produce byte-identical answers"
else bad "(D1) --legend-have= output is not reproducible across runs"; fi

# (E) the DEFAULT path is untouched. Measured 2026-11-16: routing a --for bundle through the compact
# capture moves it by 290 B, which is why the ref stage uses a capture of its OWN for the natively
# compact verbs. This arm is what keeps that true.
for v in "--callers=main" "--for=how does ranking work"; do
    n1="$WORK/n1"; n2="$WORK/n2"
    "$BIN" . "$v" >"$n1" 2>/dev/null
    "$BIN" . "$v" >"$n2" 2>/dev/null
    if cmp -s "$n1" "$n2"; then pass "(E1) $v without the flag is unchanged and reproducible"
    else bad "(E1) $v without the flag is not reproducible"; fi
done

# (F) --legend=full is refused with the flag: the dictionary reduces the inline posture it holds
if "$BIN" . --callers=main --legend=full --legend-have="$DV" >/dev/null 2>&1; then
    bad "(F1) --legend=full with --legend-have= must refuse -- the posture reduces the dialect the dictionary holds"
else
    pass "(F1) --legend=full with --legend-have= is refused"
fi

# (G) THE SERVER TRANSPORTS. This arm exists because the flag DEADLOCKED --mcp before it was refused: the ref
# stage replays a captured document once the verb returns, and a server does not return while a client is
# connected, so responses landed in the capture and a live client waited forever. Measured before the fix: a
# response in 0.0 s without the flag, NOTHING in 6 s with it. The fix is a refusal at intake, so what this arm
# holds is that the combination exits non-zero QUICKLY and says why -- never that it answers.
# The house bounded_run idiom (crashsweepcheck / namedfileinputcheck): `timeout` is GNU coreutils and the
# macOS CI runner has none, so a bare `timeout 10` exits 127 there and this arm reports a refusal that never
# ran. It passed locally only because Homebrew put one on PATH. GNU timeout kills with 124, the perl-alarm
# fallback with 142; neither counts as the refusal being asserted.
bounded_run(){ if command -v timeout >/dev/null 2>&1; then timeout 10 "$@"; else perl -e 'alarm 10; exec @ARGV' "$@"; fi; }
for t in "--mcp" "--lsp" "--listen=127.0.0.1:8799"; do
    serr="$WORK/srv.err"
    start=$(date +%s)
    bounded_run "$BIN" . $t --legend-have="$DV" >/dev/null 2>"$serr"; rc=$?
    took=$(( $(date +%s) - start ))
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && [ "$rc" -ne 142 ] && [ "$rc" -ne 127 ] && [ "$took" -lt 5 ] && grep -q "server transport" "$serr"; then
        pass "(G1) $t with --legend-have= is refused at intake in ${took}s (rc=$rc), not captured into a deadlock"
    else
        bad "(G1) $t with --legend-have= must refuse fast and name the transport -- rc=$rc after ${took}s: $(head -c 150 "$serr")"
    fi
done

# (H) a failing stdout write must not be reported as success. The captured answer reaches stdout in ONE place and
# that place decides the exit code; an unchecked fwrite/fflush there exits 0 having written only into the capture.
# stdout is CLOSED here rather than pointed at /dev/full, which does not exist on macOS.
if "$BIN" . --callers=main --legend-have="$DV" >&- 2>/dev/null; then
    bad "(H1) a captured answer that cannot reach stdout must exit non-zero, not report success"
else
    pass "(H1) a captured answer that cannot reach stdout exits non-zero"
fi
if "$BIN" . --callers=main >&- 2>/dev/null; then
    bad "(H2) the same must hold on the compact path, which shares the one checked replay"
else
    pass "(H2) the compact path's replay is checked too (same seam)"
fi

# ── (S) A PROSE SURFACE SAYS THE HANDSHAKE DID NOTHING (A17, lane s1-small; found by lane A4, results/A4_SITU_PACK_1118 F1) ──
# --situ under a valid --legend-have= exited 0 with byte-identical stdout and an EMPTY stderr, 33 of 33 — the silence the C4
# rule in applyCliRefPosture exists to prevent, while --for says `not-applicable`. Every surface legendNonXmlReadSurface names
# answers with no XML legend to reduce, so each must say so on stderr and leave stdout byte for byte as it was. Two of them
# are run here (--situ, the measured one; --recall=, a second branch of the same test); [N] a stale value is still refused.
ABIN="$( cd "$( dirname "$BIN" )" && pwd )/$( basename "$BIN" )"   # the arms below cd into their corpus
SX="$WORK/sx"; mkdir -p "$SX"
printf 'def area(w, h):\n    return w * h\n' >"$SX/geo.py"
printf '# Notes\n\nArea is width times height.\n' >"$SX/NOTES.md"
( cd "$SX" && git init -q && git -c user.email=s@example.invalid -c user.name=s add -A \
    && git -c user.email=s@example.invalid -c user.name=s commit -qm one ) >/dev/null 2>&1
printf 'def area(w, h):\n    return w * h * 1\n' >"$SX/geo.py"
for row in "situ|--situ|--situ" "recall|--recall=area width|--recall"; do
    tag="${row%%|*}"; rest="${row#*|}"; arg="${rest%%|*}"; surf="${rest#*|}"
    ( cd "$SX" && "$ABIN" . "$arg" --no-cache >"$WORK/s_$tag.plain" 2>/dev/null ); rc0=$?
    ( cd "$SX" && "$ABIN" . "$arg" --no-cache --legend-have="$DV" >"$WORK/s_$tag.have" 2>"$WORK/s_$tag.err" ); rc1=$?
    if [ "$rc0" = "$rc1" ] && [ -s "$WORK/s_$tag.plain" ] && cmp -s "$WORK/s_$tag.plain" "$WORK/s_$tag.have"; then
        pass "(S1) $arg under --legend-have=: same exit ($rc1), stdout byte-identical ($( wc -c <"$WORK/s_$tag.have" | tr -d ' ' ) B)"
    else
        bad "(S1) $arg under --legend-have=: rc $rc0 -> $rc1, or stdout moved/empty"
    fi
    if grep -q -- "--legend-have=: not-applicable" "$WORK/s_$tag.err" && grep -qF -- "$surf" "$WORK/s_$tag.err"; then
        pass "(S2) $arg under --legend-have=: stderr says not-applicable and names $surf"
    else
        bad "(S2) $arg under --legend-have=: stderr is silent about the unused handshake: '$( grep -v '^\[' "$WORK/s_$tag.err" | head -c 200 )'"
    fi
done
( cd "$SX" && "$ABIN" . --situ --no-cache --legend-have=0000000000000000 >/dev/null 2>"$WORK/s_stale.err" ); rc=$?
if [ "$rc" -ne 0 ] && grep -q "does not match this binary's legend dictionary" "$WORK/s_stale.err" && ! grep -q "not-applicable" "$WORK/s_stale.err"; then
    pass "(S3) [N] a stale --legend-have= on --situ is still refused (rc=$rc), with no not-applicable line"
else
    bad "(S3) [N] a stale --legend-have= on --situ: rc=$rc, stderr '$( head -c 200 "$WORK/s_stale.err" )'"
fi

# ── (M)/(T) THE HANDSHAKE'S OTHER HALF: what it DROPS must be OBTAINABLE, and the guidance must OBTAIN it ─────────────
# Arms (A0)..(H) hold that the ref answer keeps every row and attribute. None of them asked the question the flag's
# name raises: the caller asserts it HOLDS the dictionary, so is every definition the answer dropped actually IN the
# dictionary, and does the command the tool teaches actually put the dictionary in the caller's hands? Both were false
# (2026-11-17). The <file-scope> (t=modscope) reading was written by the compact composer and was no dictionary entry,
# so a reduced answer dropped it and a reader holding all 130 KB still had no definition of the row it was shown:
# 25 of 239 answers on three corpora, every one that carried it. And the refusal, the --help-adjacent skills, the
# SessionStart primer and THIS gate all read line 1 of the dictionary (78 B) and then asserted the other 130,243.
#   (M0) non-vacuity, counted on this gate's OWN fixture: a <file-scope> row, reduced answers, entries dropped. 0 = FAIL.
#   (M1) every clause a reduced answer dropped is a line of the dictionary the taught command printed.
#   (M1x) control: delete ANY ONE of those lines from the held dictionary and (M1) must go red -- each is load-bearing.
#   (M2) the <file-scope> reading specifically: carried by the compact legend, dropped by the handshake, held by the dictionary.
#   (M3) an answer the handshake did NOT reduce keeps its compact legend whole (the other honest outcome). Its cell is
#        the Elixir inert-quote variant of declined_calls=, a reading the composer swaps in and the dictionary does not
#        hold: kept inline, so it is not the <file-scope> defect -- but it is the same KIND of clause, and this arm is
#        what says so if a later change starts dropping it.
#   (T1) the command the refusal teaches, run as written, prints the WHOLE dictionary: every dropped definition, and a
#        line-1 dictv= the handshake accepts.   (T1x) the same check on that command cut to its first line must FAIL.
#   (T2) no guidance site -- refusal, --help, the skills, the primer, this gate -- pipes the dictionary into a
#        first-line cut.   (T2x) the scanner fires on a planted instance.
#   (T3) the cost the guidance states is the cost: every "about N KB" beside the handshake is within 10 % of the bytes.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODFIX="$WORK/modfix"; mkdir -p "$MODFIX/src"
printf 'export function setPhase(p: string): void { console.log(p) }\nexport function boot(): void { setPhase("boot") }\n' >"$MODFIX/src/lifecycle.ts"
printf "import { setPhase, boot } from './lifecycle'\nsetPhase('starting')\nboot()\n" >"$MODFIX/src/index.ts"
"$BIN" . --callers=main --legend-have= >/dev/null 2>"$WORK/teach.err"
"$BIN" --help=all >"$WORK/help.txt" 2>/dev/null
python3 - "$BIN" "$WORK" "$ROOT" "$MODFIX" "$DICT" <<'PY'
import os, re, subprocess, sys
BIN, WORK, ROOT, MODFIX, DICT = sys.argv[1:6]
fail = 0
def say(ok, arm, msg):
    global fail
    print("  %s  (%s) %s" % ("PASS" if ok else "FAIL", arm, msg))
    if not ok:
        fail = 1
def out(args, **kw):
    return subprocess.run(args, capture_output=True, **kw).stdout.decode("utf-8", "replace")

held = open(DICT, encoding="utf-8").read()
PURPOSE = re.compile(r"^ripwire\.([A-Za-z0-9_-]+)/v1 <[^>]*>: (.*)$")
def parse(text):
    """The held dictionary as (purposes by schema key, every other line)."""
    purposes, entries = {}, set()
    for line in text.split("\n")[1:]:
        m = PURPOSE.match(line)
        if m:
            purposes.setdefault(m.group(1), []).append(m.group(2))
        elif line:
            entries.add(line)
    return purposes, entries
LEGEND = re.compile(r"<!-- ripwire (\S+) schema=ripwire\.\1/v1: (.*?) -->", re.S)
WINDOW = re.compile(r"^ window: [a-z_= ]+ \(capped=1 cut(?:; next_offset= pastes as offset=)?\)\.")
SUBCAP = re.compile(r"^ [A-Za-z0-9_]+_capped=(?:/[A-Za-z0-9_]+_capped=)*: 1 = cut\.")
def residue(answer, purposes, entries, used=None):
    """What the compact legend of `answer` says that the dictionary does not: '' when every clause is a held line."""
    m = LEGEND.search(answer)
    if not m:
        return "NO-COMPACT-LEGEND"
    key, body = m.group(1), m.group(2)
    for p in purposes.get(key, []):
        if body.startswith(p + "."):
            body = body[len(p) + 1:]
            break
    else:
        return "PURPOSE " + body[:90]
    # the window and sub-cap clauses are spelled per answer; the dictionary's core holds their generic reading
    if any(e.startswith("window: ") for e in entries):
        body = WINDOW.sub("", body)
    if any(e.startswith("X_capped= ") for e in entries):
        body = SUBCAP.sub("", body)
    for e in sorted(entries, key=lambda s: (-len(s), s)):
        clause = " " + e + "."
        if clause in body:
            body = body.replace(clause, "\0")
            if used is not None:
                used.add(e)
    return body.replace("\0", "").strip()

purposes, entries = parse(held)
DV = re.search(r"dictv=([0-9a-f]{16})", held.split("\n", 1)[0]).group(1)
CELLS = [(MODFIX, v) for v in ("--callers=setPhase", "--impact=setPhase", "--uses=setPhase", "--around=setPhase", "--callees=boot")]
CELLS += [(".", v) for v in ("--callers=main", "--callees=main", "--impact=main", "--whereis=main", "--dead-code")]
ELIXIR = os.path.join(ROOT, "test", "elixirfix")
CELLS += [(ELIXIR, "--callees=quoted")]
NAME, READING = "&lt;file-scope&gt;", "<file-scope> (t=modscope): "
reduced, kept, used, bad_rows, scoped = [], [], set(), [], 0
for root, verb in CELLS:
    extra = ["--no-cache"] if root != "." else []
    compact = out([BIN, root, verb, "--legend=compact"] + extra)
    have    = out([BIN, root, verb, "--legend-have=" + DV] + extra)
    label   = "%s %s" % ({MODFIX: "fixture", ELIXIR: "elixirfix"}.get(root, "repo"), verb)
    legend  = LEGEND.search(compact)
    if 'legend="ref"' not in have:
        kept.append((label, legend is not None and legend.group(0) in have))
        continue
    reduced.append((label, compact, have))
    left = residue(compact, purposes, entries, used)
    if left:
        bad_rows.append("%s drops a clause no dictionary line holds: [%s]" % (label, left[:150]))
    if root == MODFIX and NAME in have:
        scoped += 1
        m2 = legend is not None and READING in legend.group(2)
        line = [e for e in entries if e.startswith(READING)]
        ok = m2 and READING not in have and len(line) == 1 and (" " + line[0] + ".") in legend.group(2)
        say(ok, "M2", "%s: the <file-scope> reading is carried by the compact legend (%s), dropped by the handshake (%s) and "
            "held by the dictionary as one line (%d found)" % (label, m2, READING not in have, len(line)))
say(scoped >= 1 and len(reduced) >= 3 and len(used) >= 5, "M0",
    "non-vacuity on this gate's own fixture: %d reduced answer(s) show a <file-scope> row, %d of %d cells took the ref "
    "posture, %d distinct dictionary lines were dropped (floors 1 / 3 / 5; below a floor this arm fails)"
    % (scoped, len(reduced), len(CELLS), len(used)))
say(not bad_rows, "M1", "every clause the %d reduced answers dropped is a line of the held dictionary%s"
    % (len(reduced), "" if not bad_rows else " -- " + "; ".join(bad_rows[:3])))
silent = [e for e in sorted(used) if not any(residue(c, purposes, entries - {e}) for _, c, _ in reduced)]
say(used and not silent, "M1x", "control: deleting any ONE of the %d dropped lines from the held dictionary turns (M1) red"
    "%s" % (len(used), "" if not silent else " -- but %d deletion(s) went unnoticed, first: [%s]" % (len(silent), silent[0][:80])))
if kept:
    say(all(ok for _, ok in kept), "M3", "%d cell(s) the handshake did not reduce keep their compact legend whole (%s)%s"
        % (len(kept), ", ".join(l for l, _ in kept), "" if all(ok for _, ok in kept) else " -- lost on: " + ", ".join(l for l, ok in kept if not ok)))
else:
    print("  PASS  (M3) NOT-ESTABLISHED: every cell was reduced, so no kept-inline answer was observed -- stated, not implied")

# ---- (T) the guidance ---------------------------------------------------------------------------------------------
teach = open(os.path.join(WORK, "teach.err"), encoding="utf-8").read()
helpt = open(os.path.join(WORK, "help.txt"), encoding="utf-8", errors="replace").read()
full  = subprocess.run([BIN, "--legend-dict"], capture_output=True).stdout
def obtains(cmd):
    """Run a taught command as written (ripwire -> BIN). Why it does NOT deliver what its value asserts, or '' when it does.
    The command may print the whole dictionary or one TIER of it (lane dict-core-packs: --legend-dict=core, =KEY). Either
    way the bar is the same: line 1 names a version and entries=N, the N lines after it are ALL there and hash to that
    version, and the handshake accepts it. test/legendtiercheck.sh (K1) holds what an answer may then drop."""
    got = subprocess.run(["sh", "-c", 'ripwire() { "$RW_BIN" "$@"; }; ' + cmd], capture_output=True,
                         env=dict(os.environ, RW_BIN=os.path.abspath(BIN))).stdout
    lines = got.decode("utf-8", "replace").split("\n")
    m = re.search(r"\b(?:have|dictv)=([0-9a-f]{16})\b", lines[0])
    n = re.search(r"\bentries=(\d+)\b", lines[0])
    if not m or not n:
        return "its line 1 names no have=/dictv= and entries="
    body = lines[1:1 + int(n.group(1))]
    h = 14695981039346656037
    for b in ("".join(l + "\n" for l in body)).encode():
        h = ((h ^ b) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    if len(body) != int(n.group(1)) or "%016x" % h != m.group(1):
        return "prints %d of the %s line(s) its version stands for (%d B)" % (len(body), n.group(1), len(got))
    if subprocess.run([BIN, ".", "--callers=main", "--legend-have=" + m.group(1)], capture_output=True).returncode != 0:
        return "its line 1 names a version the handshake refuses"
    return ""
taught = [c for c in re.findall(r"`([^`]+)`", teach) if c.startswith("ripwire --legend-dict")]
say(len(taught) >= 1, "T0", "the empty-value refusal teaches a `ripwire --legend-dict ...` command (%d found; zero fails this arm)" % len(taught))
CUT = " | he" + "ad -1"   # spelled in two pieces so (T2) can scan this file
for cmd in taught:
    why = obtains(cmd)
    say(not why, "T1", "taught command `%s` delivers what --legend-have= asserts: every line its version hashes, and a value the handshake accepts%s"
        % (cmd, "" if not why else " -- NO: " + why))
    why = obtains(cmd + CUT)
    say(bool(why), "T1x", "control: the same command cut to its first line is REJECTED (%s)" % (why or "it passed -- (T1) cannot see the defect"))

SCAN = re.compile(r"legend-dict[^\n|`]*\|\s*head\b")
sites = {"the empty-value refusal": teach, "--help=all": helpt}
for rel in ("src/cli.h", "src/wrap.h", "src/main.cpp", "src/mcp.h", "test/legendhavecheck.sh"):
    sites[rel] = open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read()
skills = os.path.join(ROOT, "skills")
for d, _, names in sorted(os.walk(skills)):
    for n in sorted(names):
        if n.endswith(".md"):
            p = os.path.join(d, n)
            sites[os.path.relpath(p, ROOT)] = open(p, encoding="utf-8", errors="replace").read()
hits = ["%s:%d" % (name, text[:m.start()].count("\n") + 1) for name, text in sorted(sites.items()) for m in SCAN.finditer(text)]
say(not hits, "T2", "no guidance site pipes the dictionary into a first-line cut (%d sites read)%s"
    % (len(sites), "" if not hits else " -- " + ", ".join(hits[:8])))
say(len(sites) >= 8 and SCAN.search("ripwire --legend-dict" + CUT) is not None and SCAN.search("ripwire --legend-dict") is None, "T2x",
    "control: the scanner fires on a planted first-line cut and not on the bare command")

# (T3) THE COST STATED IS THE COST. Every guidance site states what the CORE costs to read, and any size stated beside
# the handshake is within 10 % of a text the binary really prints: the core tier, or the whole dictionary.
core = subprocess.run([BIN, "--legend-dict=core"], capture_output=True).stdout
COST = re.compile(r"about ([0-9]+(?:\.[0-9]+)?) KB")
stated = []
COST_SITES = ("the empty-value refusal", "--help=all", "skills/ripwire-router/SKILL.md", "skills/ripwire-mcp/SKILL.md", "src/wrap.h")
for name in COST_SITES:
    text = sites.get(name, "")
    for m in re.finditer(r"legend-(?:have|dict)", text):
        for c in COST.finditer(text[max(0, m.start() - 700): m.end() + 700]):
            stated.append((name, float(c.group(1))))
stated = sorted(set(stated))
near = lambda kb, size: abs(kb * 1000 - size) * 10 <= size
off = ["%s says about %g KB" % s for s in stated if not near(s[1], len(core)) and not near(s[1], len(full))]
mute = [n for n in COST_SITES if not any(s[0] == n and near(s[1], len(core)) for s in stated)]
say(bool(core) and not mute and not off, "T3",
    "the cost stated beside the handshake is the cost: %d of %d guidance sites state the core's (%d B), every stated size is "
    "within 10 %% of the core or of the whole dictionary (%d B)%s%s"
    % (len(COST_SITES) - len(mute), len(COST_SITES), len(core), len(full),
       "" if not off else " -- WRONG: " + "; ".join(off), "" if not mute else " -- SILENT on the core's cost: " + ", ".join(mute)))
sys.exit(fail)
PY
[ $? -eq 0 ] || fail=1

if [ "$fail" -ne 0 ]; then echo "legendhavecheck: FAILURES"; exit 1; fi
echo "legendhavecheck: all arms PASS"
