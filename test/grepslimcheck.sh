#!/usr/bin/env bash
# grepslimcheck.sh — gate for GREP-SLIM: on the compact legend (the CLI default) --grep leaves out the plain <enc>
# tail rows (name, callers=, defs=, cx=, and the callers_floor=/floor_next= that qualify that count) and names them
# on the root as enc_cut=N; their legend clauses go with them (the compact legend is present-only). A row that says
# more stays: --handles (h=/handle_omitted=), a metrics lens (amp=/tested=), an L4 carrier (reads=/vals=).
# The cut is a PAYLOAD cut, in both legend dialects (compact stays a legend-only change of the full answer);
# RIPWIRE_GREP_SLIM=0 is the kill switch (the pre-slim bytes).
#
#   N  (negative) the OFF answer carries plain <enc> rows (FAIL on zero cases); the ON answer carries none of them,
#      and enc_cut= equals the number OFF printed.
#   E  (equivalence twin) the OFF answer with those rows, enc_cut= and the legend removed == the ON answer with
#      enc_cut= and the legend removed: every hit, file, count and next= is identical.
#   S  (size) ON is smaller than OFF by at least the removed rows' bytes less the enc_cut= attribute and its clause.
#   L  (legend) ON defines enc_cut= and no longer carries the callers= enc clause; OFF carries callers= and no enc_cut.
#   T  (tight size) fewer than 3 plain rows beside a kept row are not cut (enc_cut= and its clause would cost more).
#   K  (dialects) the full-legend answer cuts the same rows (its payload == the compact payload, enc_cut= on both roots) and
#      its prose defines enc_cut=; --handles keeps every row (ON == OFF).
#
#   test/grepslimcheck.sh            # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/grepslimcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "grepslimcheck: BIN=$BIN  CORPUS=$FIX"

PATS="distance perimeter Point area diagonal"
i=0
for p in $PATS; do
    i=$(( i + 1 ))
    ( cd "$FIX" && env -u RIPWIRE_GREP_SLIM "$BIN" . --no-cache --grep="$p" >"$TMP/on.$i" 2>/dev/null ) || no "--grep=$p exited non-zero ($?)"
    ( cd "$FIX" && RIPWIRE_GREP_SLIM=0 "$BIN" . --no-cache --grep="$p" >"$TMP/off.$i" 2>/dev/null ) || no "--grep=$p exited non-zero ($?)"
    ( cd "$FIX" && env -u RIPWIRE_GREP_SLIM "$BIN" . --no-cache --legend=full --grep="$p" >"$TMP/fon.$i" 2>/dev/null ) || no "--grep=$p exited non-zero ($?)"
    ( cd "$FIX" && RIPWIRE_GREP_SLIM=0 "$BIN" . --no-cache --legend=full --grep="$p" >"$TMP/foff.$i" 2>/dev/null ) || no "--grep=$p exited non-zero ($?)"
    ( cd "$FIX" && env -u RIPWIRE_GREP_SLIM "$BIN" . --no-cache --handles --grep="$p" >"$TMP/hon.$i" 2>/dev/null ) || no "--grep=$p exited non-zero ($?)"
    ( cd "$FIX" && RIPWIRE_GREP_SLIM=0 "$BIN" . --no-cache --handles --grep="$p" >"$TMP/hoff.$i" 2>/dev/null ) || no "--grep=$p exited non-zero ($?)"
    printf '%s\n' "$p" >"$TMP/pat.$i"
done

python3 -I - "$TMP" "$i" <<'PY'
import re, sys
tmp, n = sys.argv[1], int(sys.argv[2])
fails = 0
def say(okv, msg):
    global fails
    print(('  PASS  ' if okv else '  FAIL  ') + msg)
    if not okv: fails += 1
def rd(k, j): return open('%s/%s.%d' % (tmp, k, j), encoding='utf-8', errors='replace').read()
LEG = re.compile(r'<!--.*?-->', re.S)
ROW = re.compile(r'<enc [^>]*/>')
def plain(r):   # a row the slim tail leaves out: no handle, lens or carrier attribute
    return not re.search(r'\s(h|handle_omitted|amp|tested|reads|reads_at|vals|vals_total)="', r)
def strip(s): return re.sub(r'\senc_cut="\d+"', '', LEG.sub('', s))
cases = removed_total = 0
for j in range(1, n + 1):
    pat = rd('pat', j).strip(); on, off = rd('on', j), rd('off', j)
    rows = [r for r in ROW.findall(off) if plain(r)]
    if not rows: continue
    if len(rows) < 3 and len(rows) < len(ROW.findall(off)):   # tight-size rule (kGrepEncCutMinRows): too few to pay beside a kept row
        say(on == off, '(T) %s: %d plain rows beside a kept row stay (ON == OFF)' % (pat, len(rows))); continue
    cases += 1; removed_total += len(rows)
    # N
    left = [r for r in ROW.findall(on) if plain(r)]
    cut = re.search(r'<grep [^>]*\benc_cut="(\d+)"', on)
    say(not left and cut is not None and int(cut.group(1)) == len(rows),
        '(N) %s: OFF prints %d plain enc rows, ON prints %d, enc_cut=%s' % (pat, len(rows), len(left), cut.group(1) if cut else 'absent'))
    # E
    twin = off
    for r in rows: twin = twin.replace(r, '', 1)
    say(strip(twin) == strip(on), '(E) %s: OFF less its plain enc rows == ON (hits, files, counts, next= identical)' % pat)
    # S
    saved = len(off) - len(on); rowbytes = sum(len(r) for r in rows)
    say(saved > 0 and saved >= rowbytes - 200, '(S) %s: ON %d B < OFF %d B (rows %d B)' % (pat, len(on), len(off), rowbytes))
    # L
    lon, loff = LEG.search(on).group(0), LEG.search(off).group(0)
    say('enc_cut=N:' in lon and 'callers=N: 1-hop' not in lon and 'callers=N: 1-hop' in loff and 'enc_cut' not in loff,
        '(L) %s: ON legend defines enc_cut= without the callers= clause; OFF the reverse' % pat)
say(cases >= 3, '(N0) premise: %d of %d patterns had plain enc rows to cut (%d rows)' % (cases, n, removed_total))
for j in range(1, n + 1):
    pat = rd('pat', j).strip()
    fon, foff, on = rd('fon', j), rd('foff', j), rd('on', j)
    cutting = 'enc_cut="' in on
    same_payload = LEG.sub('', fon).replace(' schema="ripwire.grep/v1"', '') == LEG.sub('', on).replace(' schema="ripwire.grep/v1"', '')
    defined = ('enc_cut= on the root counts' in fon) == cutting and 'enc_cut' not in foff
    say(same_payload and defined, '(K) %s: legend=full payload == compact payload (cut=%s), its prose defines enc_cut= iff printed; OFF never' % (pat, cutting))
    hon, hoff = rd('hon', j), rd('hoff', j)
    say(hon == hoff, '(K2) %s: --handles keeps every enc row (ON == OFF)' % pat)
sys.exit(1 if fails else 0)
PY
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
