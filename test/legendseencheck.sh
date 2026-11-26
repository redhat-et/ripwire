#!/usr/bin/env bash
# legendseencheck.sh — --legend-seen=FILE: an answer leaves out the legend definitions its caller says it HOLDS.
#
# WHAT THIS GUARDS (lane LS1, 2026-11-18). A CLI agent makes many calls a session and re-receives the same legend
# definitions each time (a --for page 1 is ~12 KB of rows plus ~4 KB of legend). --legend-seen=FILE names, by content
# hash, the dictionary entries the caller already holds; `ripwire --legend-dict=seen` turns RECEIVED answers into
# those hashes. The bar is not the saving. It is that the saving is LOSSLESS and HONEST:
#   lossless — with every comment and the est_tokens= value set aside, the reduced answer is the plain answer, byte
#              for byte (rows, CDATA, every other root attribute, their order);
#   honest   — every `name=` a plain answer's comments define is still defined, in the reduced answer's comments or
#              in a dictionary line whose hash FILE holds. Nothing is ever left to a dictionary the caller only
#              could have read.
#   safe     — FILE can never turn a good call into a failure: missing, unreadable, corrupt or oversized, the answer
#              is the plain answer and stderr says so.
# Each arm has a negative control where one is meaningful (C*), so a predicate that cannot fail is caught here.
set -u
# θ5 (src/forpages.h): this gate pins the FULL page-1 legend (every attribute defined in its own answer); the default's core legend
# is pinned by test/corelegendcheck.sh, so the full legend is switched back on here.
export RIPWIRE_NO_CORE_LEGEND=1
# FMT2 (ROWLINES + RANKSEQ, src/forrowlines.h): the default answer-first --for answer serves its <sigs>/<tail> rows as text lines in
# one CDATA (lossless; test/rowlinescheck.sh pins it: (L1) decodes the answer back to this element form byte for byte). This gate
# reads those rows as elements for another rule, so the line form is off here.
export RIPWIRE_NO_ROWLINES=1
BIN="${RIPWIRE_BIN:-${1:-./build/ripwire}}"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; fi
fail=0
pass() { printf '  PASS  %s\n' "$1" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$1"; }; return 0; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

DICT="$WORK/dict.txt"
"$BIN" --legend-dict >"$DICT" 2>/dev/null
DV=$(sed -n '1s/.*dictv=\([0-9a-f]\{16\}\).*/\1/p' "$DICT")
[ -n "$DV" ] || { bad "(S0) --legend-dict prints no dictv="; echo "FAILURES"; exit 1; }

# The checker: FNV-1a 64 of a dictionary line + newline is its hash; lossless and coverage predicates.
cat >"$WORK/chk.py" <<'PY'
import re, sys
def fnv(s):
    h = 14695981039346656037
    for b in s.encode():
        h = ((h ^ b) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return "%016x" % h
def dict_lines(path):
    return [l for l in open(path, encoding="utf-8").read().split("\n")[1:] if l]
def hashes(path):
    return {fnv(l + "\n"): l for l in dict_lines(path)}
CDATA = re.compile(r"<!\[CDATA\[.*?\]\]>", re.S)
COMMENT = re.compile(r"<!--.*?-->", re.S)
def comments(doc):
    return COMMENT.findall(CDATA.sub("", doc))
def strip(doc):
    # every comment (outside CDATA) out, and the est_tokens= VALUE, which prices what was delivered
    out, i = [], 0
    for m in re.finditer(r"<!\[CDATA\[.*?\]\]>|<!--.*?-->", doc, re.S):
        out.append(doc[i:m.start()])
        if m.group().startswith("<![CDATA["): out.append(m.group())
        i = m.end()
    out.append(doc[i:])
    return re.sub(r'est_tokens="\d+"', 'est_tokens=""', "".join(out))
def names(text):
    return set(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)=", text))
cmd = sys.argv[1]
if cmd == "valid":                      # every printed hash is a dictionary line's hash; sorted, unique
    hs = [l for l in open(sys.argv[3]).read().split("\n") if l]
    known = hashes(sys.argv[2])
    bad = [h for h in hs if h not in known]
    print(len(hs), len(bad), int(hs == sorted(set(hs))))
elif cmd == "lossless":
    a, b = open(sys.argv[2]).read(), open(sys.argv[3]).read()
    print(int(strip(a) == strip(b)))
elif cmd == "cover":                    # names defined by the plain answer's comments, missing from reduced+held
    plain, red, held = open(sys.argv[2]).read(), open(sys.argv[3]).read(), sys.argv[5]
    known = hashes(sys.argv[4])
    heldtext = " ".join(known.get(h, "") for h in open(held).read().split("\n") if h) if held != "-" else ""
    need = names(" ".join(comments(plain)))
    have = names(" ".join(comments(red)) + " " + heldtext)
    miss = sorted(need - have)
    print(len(miss), " ".join(miss[:8]))
PY
py() { python3 "$WORK/chk.py" "$@"; }

# ── (S0) the dictionary holds the CLI --for document legend ─────────────────────────────────────────────────────────
for clause in "for: t p= file outside sigs (weaker)" "for: d: cx= ccx= complexity" "for: page=K of pages=N: an answer-first page"; do
    if grep -qF -- "$clause" "$DICT"; then pass "(S0) the dictionary holds the --for clause \"${clause}…\""
    else bad "(S0) the dictionary has no line \"${clause}…\" — the CLI --for legend is not dictionary-backed"; fi
done

TASK="how is a compact legend reduced to the ref posture"
run() { "$BIN" . "$@" 2>"$WORK/last.err"; }
run --for="$TASK" >"$WORK/for.plain"
run --callers=applyRefPosture >"$WORK/callers.plain"
run --impact=applyRefPosture >"$WORK/impact.plain"
for f in for callers impact; do
    [ -s "$WORK/$f.plain" ] || bad "(S0) the plain --$f answer is empty"
done

# ── (S1) --legend-dict=seen: received text -> the hashes of the entries it carries ─────────────────────────────────
"$BIN" --legend-dict=seen <"$WORK/for.plain" >"$WORK/for.seen" 2>"$WORK/seen.err"; rc=$?
read -r n nbad sorted <<<"$(py valid "$DICT" "$WORK/for.seen")"
if [ "$rc" -eq 0 ] && [ "${n:-0}" -ge 20 ] && [ "$nbad" -eq 0 ] && [ "$sorted" -eq 1 ]; then
    pass "(S1) --legend-dict=seen finds $n entries in a --for page 1, every one a dictionary line's hash, sorted and unique"
else bad "(S1) --legend-dict=seen rc=$rc n=$n unknown=$nbad sorted=$sorted — $(head -c 200 "$WORK/seen.err")"; fi
"$BIN" --legend-dict=seen </dev/null >"$WORK/empty.seen" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$WORK/empty.seen" ]; then pass "(S1b) empty input: no hash, rc 0"
else bad "(S1b) empty input printed $(wc -c <"$WORK/empty.seen") B, rc=$rc"; fi
# (S1c) CDATA is not a comment: the same answer's legend text wrapped in CDATA yields nothing
printf '<x><![CDATA[' >"$WORK/cdata.xml"; tr -d ']' <"$WORK/for.plain" >>"$WORK/cdata.xml"; printf ']]></x>' >>"$WORK/cdata.xml"
"$BIN" --legend-dict=seen <"$WORK/cdata.xml" >"$WORK/cdata.seen" 2>/dev/null
if [ ! -s "$WORK/cdata.seen" ]; then pass "(S1c) legend text inside CDATA (a code body) is never counted as received"
else bad "(S1c) $(wc -l <"$WORK/cdata.seen") hash(es) read out of CDATA"; fi
# (S1d) a comment cut before its close (a `| head` on the answer) is not counted
head -c "$(( $(wc -c <"$WORK/for.plain") - 200 ))" "$WORK/for.plain" | "$BIN" --legend-dict=seen >"$WORK/cut.seen" 2>/dev/null
if [ "$(wc -l <"$WORK/cut.seen")" -lt "$(wc -l <"$WORK/for.seen")" ]; then pass "(S1d) an answer cut inside its last comment yields fewer hashes ($(wc -l <"$WORK/cut.seen" | tr -d ' ') < $(wc -l <"$WORK/for.seen" | tr -d ' '))"
else bad "(S1d) a cut comment still counted as received"; fi

# ── (S2) a file holding nothing changes nothing ────────────────────────────────────────────────────────────────────
printf '# a comment line\n\n' >"$WORK/nothing"
run --for="$TASK" --legend-seen="$WORK/nothing" >"$WORK/for.nothing"
if cmp -s "$WORK/for.plain" "$WORK/for.nothing"; then pass "(S2) a FILE holding no hash: the plain answer, byte for byte"
else bad "(S2) a FILE holding nothing changed the answer"; fi

# ── (S3..S6) the reduced answers: lossless, honest, smaller, marked ────────────────────────────────────────────────
cat "$WORK/for.seen" >"$WORK/held"
"$BIN" --legend-dict=seen <"$WORK/callers.plain" >>"$WORK/held"
for f in for callers impact; do
    case "$f" in for) args=(--for="$TASK") ;; *) args=(--$f=applyRefPosture) ;; esac
    run "${args[@]}" --legend-seen="$WORK/held" >"$WORK/$f.red"; rc=$?
    p=$(wc -c <"$WORK/$f.plain" | tr -d ' '); r=$(wc -c <"$WORK/$f.red" | tr -d ' ')
    [ "$rc" -eq 0 ] || bad "(S3) --$f with --legend-seen exited $rc"
    if [ "$(py lossless "$WORK/$f.plain" "$WORK/$f.red")" = 1 ]; then pass "(S3) --$f: comments and est_tokens= aside, byte-identical to the plain answer"
    else bad "(S3) --$f: a row, CDATA or root attribute differs from the plain answer"; fi
    read -r miss list <<<"$(py cover "$WORK/$f.plain" "$WORK/$f.red" "$DICT" "$WORK/held")"
    if [ "$miss" -eq 0 ]; then pass "(S4) --$f: every name= the plain legend defines is defined inline or in a held line"
    else bad "(S4) --$f: $miss name(s) defined nowhere the reader holds: $list"; fi
    if [ "$r" -le "$p" ]; then pass "(S6) --$f: never longer ($r <= $p B)"; else bad "(S6) --$f: reduced $r B > plain $p B"; fi
    if xmllint --noout "$WORK/$f.red" 2>/dev/null; then pass "(S9b) --$f reduced answer is well-formed XML"; else bad "(S9b) --$f reduced answer is not well-formed"; fi
done
saved=$(( $(wc -c <"$WORK/for.plain") - $(wc -c <"$WORK/for.red") ))
if [ "$saved" -ge 1500 ]; then pass "(S5) a second --for page 1 leaves out $saved B of legend it already holds"
else bad "(S5) a second --for page 1 saved only $saved B"; fi
if grep -q "<!-- legend-seen: [0-9]* definitions you hold were left out; the legend-dict flag prints every one (dictv=$DV) -->" "$WORK/for.red"; then
    pass "(S5b) the omission is marked in the answer, with its count and the dictionary version"
else bad "(S5b) no legend-seen marker naming dictv=$DV in the reduced --for answer"; fi
# (C4) negative control for (S4): the same reduced answer against an EMPTY holding must show missing definitions
read -r miss _ <<<"$(py cover "$WORK/for.plain" "$WORK/for.red" "$DICT" -)"
if [ "$miss" -gt 0 ]; then pass "(C4) the coverage predicate bites: without the held lines, $miss name(s) are undefined"
else bad "(C4) the coverage predicate cannot fail — it found nothing missing with nothing held"; fi
# (C3) negative control for (S3): a dropped row must break the lossless predicate
sed 's/<d /<d dropped=\"1\" /' "$WORK/for.red" >"$WORK/for.mut"
if [ "$(py lossless "$WORK/for.plain" "$WORK/for.mut")" = 0 ]; then pass "(C3) the lossless predicate bites on a changed row"
else bad "(C3) the lossless predicate cannot fail"; fi

# ── (S7) a FILE that cannot be trusted: the plain answer, said on stderr, rc 0 ─────────────────────────────────────
printf 'zzzz-not-a-hash\n' >"$WORK/corrupt"
cat "$WORK/held" >"$WORK/corrupt2"; printf 'ABCDEF0123456789\n' >>"$WORK/corrupt2"
for case in "missing:$WORK/does-not-exist" "corrupt:$WORK/corrupt" "corrupt-tail:$WORK/corrupt2" "directory:$WORK"; do
    label=${case%%:*}; file=${case#*:}
    "$BIN" . --callers=applyRefPosture --legend-seen="$file" >"$WORK/deg.out" 2>"$WORK/deg.err"; rc=$?
    if [ "$rc" -eq 0 ] && cmp -s "$WORK/deg.out" "$WORK/callers.plain" && grep -q "legend-seen" "$WORK/deg.err"; then
        pass "(S7) $label FILE: rc 0, the plain answer whole, stderr says so"
    else bad "(S7) $label FILE: rc=$rc same=$(cmp -s "$WORK/deg.out" "$WORK/callers.plain" && echo 1 || echo 0) stderr=$(head -c 160 "$WORK/deg.err")"; fi
done
# (S7b) a hash this binary does not know is not an error: it simply matches nothing (a file from another build)
{ printf '0000000000000000\n'; cat "$WORK/held"; } >"$WORK/foreign"
run --callers=applyRefPosture --legend-seen="$WORK/foreign" >"$WORK/foreign.out"
if cmp -s "$WORK/foreign.out" "$WORK/callers.red"; then pass "(S7b) an unknown hash beside known ones: the known ones still hold, nothing refused"
else bad "(S7b) an unknown hash changed the answer"; fi

# ── (S8) refusals at intake: rc != 0, stdout empty ─────────────────────────────────────────────────────────────────
for args in "--legend-seen=" "--legend-seen=$WORK/held --legend=full" "--legend-seen=$WORK/held --legend=dict" \
            "--legend-seen=$WORK/held --legend-have=$("$BIN" --legend-dict=core | sed -n '1s/.*have=\([0-9a-f]*\).*/\1/p')"; do
    # shellcheck disable=SC2086
    "$BIN" . --callers=applyRefPosture $args >"$WORK/ref.out" 2>"$WORK/ref.err"; rc=$?
    if [ "$rc" -ne 0 ] && [ ! -s "$WORK/ref.out" ] && grep -q "legend-seen" "$WORK/ref.err"; then pass "(S8) refused: ${args//$WORK/W}"
    else bad "(S8) not refused: ${args//$WORK/W} (rc=$rc, $(wc -c <"$WORK/ref.out") B out)"; fi
done
"$BIN" --mcp --legend-seen="$WORK/held" </dev/null >"$WORK/ref.out" 2>"$WORK/ref.err"; rc=$?
if [ "$rc" -ne 0 ] && grep -q "legend-seen" "$WORK/ref.err"; then pass "(S8) refused beside a server transport (--mcp)"
else bad "(S8) --mcp --legend-seen not refused (rc=$rc)"; fi

# ── (S9) determinism: same argv + same FILE bytes, twice ───────────────────────────────────────────────────────────
run --for="$TASK" --legend-seen="$WORK/held" >"$WORK/for.red2"
if cmp -s "$WORK/for.red" "$WORK/for.red2"; then pass "(S9) same argv + same FILE: byte-identical"
else bad "(S9) two runs with the same FILE differ"; fi
sort -r "$WORK/held" | awk '{print} NR%3==0{print}' >"$WORK/held.shuffled"
run --for="$TASK" --legend-seen="$WORK/held.shuffled" >"$WORK/for.red3"
if cmp -s "$WORK/for.red" "$WORK/for.red3"; then pass "(S9c) order and duplicates in FILE do not matter"
else bad "(S9c) a reordered FILE with duplicates changed the answer"; fi

# ── (S10) a continuation page carries no legend: unchanged ─────────────────────────────────────────────────────────
run --for="$TASK" --page-bytes=12000:2 >"$WORK/p2.plain"
run --for="$TASK" --page-bytes=12000:2 --legend-seen="$WORK/held" >"$WORK/p2.red"
if [ -s "$WORK/p2.plain" ] && [ "$(py lossless "$WORK/p2.plain" "$WORK/p2.red")" = 1 ]; then pass "(S10) page 2 with a FILE: rows byte-identical"
else bad "(S10) page 2 rows differ under --legend-seen"; fi

# ── (S11) everything held: the reduced legend still reads (opener kept), and the scan of a REDUCED answer is a subset
"$BIN" --legend-dict | tail -n +2 | python3 -c '
import sys
for l in sys.stdin.read().split("\n"):
    if not l: continue
    h = 14695981039346656037
    for b in (l + "\n").encode(): h = ((h ^ b) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    print("%016x" % h)' >"$WORK/all"
run --callers=applyRefPosture --legend-seen="$WORK/all" >"$WORK/callers.all"
if grep -q "<!-- ripwire callers schema=ripwire.callers/v1:" "$WORK/callers.all" && [ "$(py lossless "$WORK/callers.plain" "$WORK/callers.all")" = 1 ]; then
    pass "(S11) every definition held: the compact opener stays, rows byte-identical ($(wc -c <"$WORK/callers.all" | tr -d ' ') of $(wc -c <"$WORK/callers.plain" | tr -d ' ') B)"
else bad "(S11) holding everything lost the compact opener or a row"; fi
"$BIN" --legend-dict=seen <"$WORK/for.red" >"$WORK/red.seen"
if [ -z "$(comm -13 "$WORK/for.seen" "$WORK/red.seen")" ] || [ ! -s "$WORK/red.seen" ]; then pass "(S11b) a reduced answer carries no entry its plain answer did not"
else bad "(S11b) the reduced answer yields hashes the plain one did not: $(comm -13 "$WORK/for.seen" "$WORK/red.seen" | head -3 | tr '\n' ' ')"; fi

# ── (S12) a BLOCK-LOCAL legend (`<!-- ripwire for lit …`, carried with its section) is left out WHERE IT STANDS ──────
# Re-pinned 2026-11-22 (lane CL1b): "the --page-bytes flag"'s <lit> grew past page 1 on this tree (it is deferred now, so the
# plain answer carries no lit legend and the arm went vacuous-red). The probe needs a lit section ON page 1; see
# foranswerfirstcheck.sh (G6/G7) for the measurement and the shared choice.
LQ="the --sections flag"
run --for="$LQ" >"$WORK/lit.plain"
"$BIN" --legend-dict=seen <"$WORK/lit.plain" >"$WORK/lit.held"
run --for="$LQ" --legend-seen="$WORK/lit.held" >"$WORK/lit.red"
nb=$(grep -o '<!-- ripwire for lit' "$WORK/lit.plain" | wc -l | tr -d ' ')
if [ "$nb" -gt 0 ]; then pass "(S12) non-vacuous: the plain answer carries $nb block-local lit legend(s)"; else bad "(S12) no block-local legend on the probe — the arm below asserts nothing"; fi
python3 - "$WORK/lit.plain" "$WORK/lit.red" >"$WORK/lit.pos" <<'PY'
import re, sys
def blocks(path):
    d = open(path).read()
    # the position of each comment, as the index of the element it precedes (CDATA stripped)
    d = re.sub(r"<!\[CDATA\[.*?\]\]>", "", d, flags=re.S)
    out, k = [], 0
    for m in re.finditer(r"<!--.*?-->|<[a-zA-Z_]", d, re.S):
        if m.group().startswith("<!--"): out.append((k, m.group()))
        else: k += 1
    return out
p, r = blocks(sys.argv[1]), blocks(sys.argv[2])
lit = [k for k, c in p if c.startswith("<!-- ripwire for lit")]
ref = {k for k, c in r if "legend-seen: " in c}
left = [c for k, c in r if c.startswith("<!-- ripwire for lit")]
print(len(lit), sum(1 for k in lit if k in ref), len(left))
PY
read -r nlit nref nleft <"$WORK/lit.pos"
# A block legend whose emitted text is no entry (a present-only clause cut from a constant) stays whole — a missed
# saving, never a missing definition; every one that WAS left out must say so where it stood.
if [ "${nlit:-0}" -gt 0 ] && [ "$nref" -gt 0 ] && [ "$nref" -ge $(( nlit - nleft )) ]; then
    pass "(S12) $(( nlit - nleft )) of $nlit block-local legends left out in place, each place says legend-seen ($nleft not an entry, kept whole)"
else bad "(S12) block-local legends: $nlit in the plain answer, $nref referred to in place, $nleft still whole"; fi
if [ "$(py lossless "$WORK/lit.plain" "$WORK/lit.red")" = 1 ] && xmllint --noout "$WORK/lit.red" 2>/dev/null; then pass "(S12) rows byte-identical, well-formed"
else bad "(S12) the block-legend reduction moved a row or broke the XML"; fi

# ── (S13) the pieces: the est_tokens= sentence and a legend cut down per answer are entries too ────────────────────
ne=$(grep -c "est_tokens= prices this bundle in tokens" "$WORK/for.plain"); nr=$(grep -c "est_tokens= prices this bundle in tokens" "$WORK/for.red")
if [ "$ne" -gt 0 ] && [ "$nr" -eq 0 ]; then pass "(S13) the est_tokens= sentence is an entry: carried by the plain answer, left out once held"
else bad "(S13) est_tokens= sentence: $ne in the plain answer, $nr still in the reduced one"; fi
if grep -qF "for: fold kind=bodies: b t= n= p= l= top ranked rows' whole bodies, not the answer; served= of total= in budget_bytes=; slice/skip p= n= l=;" "$DICT" \
   && ! grep -qF "slice/skip p= n= l=; slice members= of=" "$DICT"; then
    pass "(S13) a legend whose present-only clause is erased per answer is held as its pieces, not as one string no answer prints"
else bad "(S13) the body-fold legend is not split at its present-only members clause"; fi

if [ "$fail" -eq 0 ]; then echo "legendseencheck: all arms PASS"; exit 0; fi
echo "legendseencheck: FAILURES"; exit 1
