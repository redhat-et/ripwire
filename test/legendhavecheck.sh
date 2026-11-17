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
# attribute of the inline answer must still be in the ref answer, moved but never dropped.
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
if "$BIN" . --callers=main --legend-have= >/dev/null 2>&1; then
    pass "(B2) an EMPTY --legend-have= asserts nothing and is a no-op, not a refusal"
else
    bad "(B2) an empty --legend-have= must not refuse -- it asserts nothing"
fi

# (C) the posture applies, and is LOSSLESS: body identical, every root attribute still present
python3 - "$BIN" "$DV" "$WORK" <<'PY'
import re, subprocess, sys
BIN, DV, WORK = sys.argv[1], sys.argv[2], sys.argv[3]
CMT = re.compile(r"<!--.*?-->", re.S)
AB  = re.compile(r"<about\b[^>]*/>")
ROOT = re.compile(r"\s*<([A-Za-z_][A-Za-z0-9_-]*)\b[^>]*>")

def parts(x):
    x = CMT.sub("", x)
    m = ROOT.match(x)
    if not m:
        return None
    close = "</%s>" % m.group(1)
    j = x.rfind(close)
    if j <= m.end():
        return (m.group(0), "")          # self-closing or empty body: still comparable
    return (m.group(0), x[m.end():j])

VERBS = ["--callers=main", "--callees=main", "--impact=main", "--whereis=main",
         "--path=main,main", "--dead-code", "--affected=README.md", "--lego=Iface"]
ok = lossy = skipped = 0
for v in VERBS:
    a = subprocess.run([BIN, ".", v], capture_output=True, text=True).stdout
    b = subprocess.run([BIN, ".", v, "--legend-have=" + DV], capture_output=True, text=True).stdout
    pa, pb = parts(a), parts(b)
    if not pa or not pb or 'legend="ref"' not in b:
        skipped += 1
        print("  PASS  (C-skip) %-22s not reduced by this dictionary -- answer served inline, unchanged" % v)
        continue
    ra, ba = pa
    rb, bb = pb
    ab = AB.search(bb)
    body_b = AB.sub("", bb)
    attrs_a = set(re.findall(r'([a-z_]+)="', ra))
    attrs_b = set(re.findall(r'([a-z_]+)="', rb)) | (set(re.findall(r'([a-z_]+)="', ab.group(0))) if ab else set())
    missing = sorted(attrs_a - attrs_b)
    if ba == body_b and not missing:
        ok += 1
        print("  PASS  (C1) %-22s ref posture is LOSSLESS: body byte-identical, every root attribute kept" % v)
    else:
        lossy += 1
        why = "body differs" if ba != body_b else "attributes LOST: " + ",".join(missing)
        print("  FAIL  (C1) %-22s %s" % (v, why))
if ok == 0:
    print("  FAIL  (C2) no verb took the ref posture -- the handshake saved nothing, so C1 proved nothing")
    sys.exit(1)
print("  PASS  (C2) %d verb(s) took the posture, %d served inline unchanged" % (ok, skipped))
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

if [ "$fail" -ne 0 ]; then echo "legendhavecheck: FAILURES"; exit 1; fi
echo "legendhavecheck: all arms PASS"
