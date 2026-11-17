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

DV=$("$BIN" --legend-dict 2>/dev/null | head -1 | grep -oE '[0-9a-f]{8,}' | head -1)
if [ -z "$DV" ]; then bad "(A0) --legend-dict prints no dictv= -- the handshake has no version to name"; echo "FAILURES"; exit 1; fi
pass "(A0) --legend-dict names a dictionary version ($DV)"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

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
    missing += [kv for kv in pairs(ab.group(0) if ab else "") if kv[0] not in ("legend", "dict", "dictv")]
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

if [ "$fail" -ne 0 ]; then echo "legendhavecheck: FAILURES"; exit 1; fi
echo "legendhavecheck: all arms PASS"
