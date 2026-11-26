#!/usr/bin/env bash
# legendseenblockcheck.sh — the block-local --for notes a SESSION re-receives are dictionary entries, so
# --legend-seen=FILE leaves a held one out where it stands (lane SM1, 2026-11-21).
#
# WHAT THIS GUARDS. legendseen.h removes only text that IS a dictionary entry; a legend constant missing from
# forlegendentries.h's table "costs bytes, never a reading" and rides every answer of a session whole. Three notes
# written after that table was (lane LS1, 2026-11-18) did exactly that with the legend-seen hook ON — MEASURED on GA1
# DEV's 89 as 11 one-repo sessions, 229 non-first calls (results/SM1_SMALL_FIXES_1121/READOUT.md §2):
#   sigx     `<!-- sigx: a sigs row d with r above 10 …`           77 verbatim repeats, 14,476 B
#   unread   `<!-- hops value_refs_unread_for_lang=L: …`           18 repeats, 3,150 B
#   keybody  `<!-- bodies of=key: the definition body of each …`    5 repeats, 1,940 B
# The bar is LS1's, unchanged: the saving is LOSSLESS (comments and est_tokens= aside, the reduced answer is the plain
# one byte for byte), HONEST (each note left out is a dictionary line whose hash FILE holds, and the place says
# legend-seen) and PER DEFINITION (a FILE without that note's hash keeps the note inline, whole).
#
# WHICH PROOF EACH ARM CARRIES (LANE_CONSTRAINTS §17). (K1) (K2) are NEW assertions: red on the parent binary, where
# the notes are no entries. (K0) is the population (§18): a probe that no longer prints a note fails loudly instead of
# passing vacuously. (K3n) (K4) are mutation controls: the lossless predicate must bite on a dropped row byte, and the
# "note is gone" predicate must bite when FILE lacks that one hash.
set -u
BIN="${RIPWIRE_BIN:-${1:-./build/ripwire}}"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; fi
fail=0
pass() { printf '  PASS  %s\n' "$1" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$1"; }; return 0; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

DICT="$WORK/dict.txt"
"$BIN" --legend-dict >"$DICT" 2>"$WORK/dict.err"
[ -s "$DICT" ] || { bad "(K0) --legend-dict printed nothing: $(head -c 200 "$WORK/dict.err")"; echo "legendseenblockcheck: FAILURES"; exit 1; }

cat >"$WORK/chk.py" <<'PY'
import re, sys
def fnv(s):
    h = 14695981039346656037
    for b in s.encode():
        h = ((h ^ b) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return "%016x" % h
def strip(doc):
    # every comment outside CDATA out, and the est_tokens= VALUE (it prices what was delivered)
    out, i = [], 0
    for m in re.finditer(r"<!\[CDATA\[.*?\]\]>|<!--.*?-->", doc, re.S):
        out.append(doc[i:m.start()])
        if m.group().startswith("<![CDATA["): out.append(m.group())
        i = m.end()
    out.append(doc[i:])
    return re.sub(r'est_tokens="\d+"', 'est_tokens=""', "".join(out))
def comments(doc):
    return re.findall(r"<!--.*?-->", re.sub(r"<!\[CDATA\[.*?\]\]>", "", doc, flags=re.S), re.S)
cmd = sys.argv[1]
if cmd == "linehash":        # the hash of the ONE dictionary line that starts with the given text ("" when not exactly one)
    ls = [l for l in open(sys.argv[2], encoding="utf-8").read().split("\n")[1:] if l.startswith(sys.argv[3])]
    print(fnv(ls[0] + "\n") if len(ls) == 1 else "")
elif cmd == "lossless":
    print(int(strip(open(sys.argv[2]).read()) == strip(open(sys.argv[3]).read())))
elif cmd == "count":         # comments (outside CDATA) that contain the text
    print(sum(1 for c in comments(open(sys.argv[2]).read()) if sys.argv[3] in c))
elif cmd == "inplace":       # every comment of the plain answer that carries the note is, at the same comment index, one that says legend-seen
    p, r = comments(open(sys.argv[2]).read()), comments(open(sys.argv[3]).read())
    r = [c for c in r if not c.startswith("<!-- legend-seen: ") or " held -->" in c]     # the answer's one marker is an inserted comment
    at = [k for k, c in enumerate(p) if sys.argv[4] in c]
    print(int(len(p) == len(r) and len(at) > 0 and all("legend-seen: " in r[k] for k in at)))
elif cmd == "commentbytes":
    print(sum(len(c.encode()) for c in comments(open(sys.argv[2]).read())))
PY
py() { python3 "$WORK/chk.py" "$@"; }
run() { "$BIN" . "$@" 2>"$WORK/last.err"; }

# The probes, on this repo. P3 is a DEFAULT page 1 (the call a session repeats) of a question naming a symbol in
# backticks: the key body rides it. P1 and P2 are unpaged: on this repo the sigx block and the hops block with its unread
# note land past page 1 (measured 2026-11-21; on GA1 DEV sigx rides 88 of 229 non-first answers, page 1s among them).
Q_p1="how is a compact legend reduced to the ref posture"
Q_p2="how does the nudge hook script decide to print a hint in ripwire-nudge.sh"
Q_p3="how does \`applyRefPosture\` reduce a compact legend to the ref posture"
X_p1="--page-bytes=0"; X_p2="--page-bytes=0"; X_p3=""
probe() { local p="$1"; shift; local q="Q_$p" x="X_$p"; run --for="${!q}" ${!x} "$@"; }   # ${!x}: unquoted on purpose, empty = no argument
for p in p1 p2 p3; do
    probe "$p" >"$WORK/$p.plain"
    "$BIN" --legend-dict=seen <"$WORK/$p.plain" >"$WORK/$p.held" 2>/dev/null
    probe "$p" --legend-seen="$WORK/$p.held" >"$WORK/$p.red"
    probe "$p" --legend-seen="$WORK/$p.held" >"$WORK/$p.red2"
done

# name | probe | the note's opening text in an answer | the start of its dictionary line
NOTES='sigx|p1|sigx: a sigs row d with r above|for: sigx: a sigs row d with r above
keybody|p3|bodies of=key: the definition body of each symbol|for: bodies of=key: the definition body of each symbol
unread|p2|hops value_refs_unread_for_lang=L: a printed h row|for: hops value_refs_unread_for_lang=L: a printed h row'

while IFS='|' read -r name p text line; do
    # ── (K0) population: the probe really carries the note, once ────────────────────────────────────────────────
    n=$(py count "$WORK/$p.plain" "$text")
    if [ "$n" -eq 1 ]; then pass "(K0) $name: the plain probe answer carries the note (non-vacuous)"
    else bad "(K0) $name: the plain probe carries the note $n times, expected 1 — the arms below assert nothing; pick a probe that prints it"; fi
    # ── (K1) the note is a dictionary entry (NEW: red on the parent) ────────────────────────────────────────────
    h=$(py linehash "$DICT" "$line")
    if [ -n "$h" ]; then pass "(K1) $name: the dictionary holds exactly one line \"${line}…\" ($h)"
    else bad "(K1) $name: the dictionary has no single line \"${line}…\" — the note is no entry, so no FILE can ever leave it out"; fi
    # ── (K1b) and the harvest of the plain answer finds it ───────────────────────────────────────────────────────
    if [ -n "$h" ] && grep -qx "$h" "$WORK/$p.held"; then pass "(K1b) $name: --legend-dict=seen reads its hash out of the received answer"
    else bad "(K1b) $name: the harvest of the plain answer does not print the note's hash"; fi
    # ── (K2) held -> left out where it stands, and the place says so (NEW: red on the parent) ───────────────────
    n=$(py count "$WORK/$p.red" "$text")
    if [ "$n" -eq 0 ] && [ "$(py inplace "$WORK/$p.plain" "$WORK/$p.red" "$text")" = 1 ]; then
        pass "(K2) $name: a caller that holds it gets the answer without it, and that place says legend-seen"
    else bad "(K2) $name: still $n time(s) in the answer of a caller that holds it (or the place does not say legend-seen)"; fi
    # ── (K4) mutation control for (K2): a FILE without THIS hash keeps the note inline, whole ───────────────────
    if [ -n "$h" ]; then
        grep -vx "$h" "$WORK/$p.held" >"$WORK/$p.$name.minus"
        probe "$p" --legend-seen="$WORK/$p.$name.minus" >"$WORK/$p.$name.out"
        whole=$(python3 - "$WORK/$p.plain" "$WORK/$p.$name.out" "$text" <<'PY'
import re, sys
def note(path, text):
    d = re.sub(r"<!\[CDATA\[.*?\]\]>", "", open(path).read(), flags=re.S)
    cs = [c for c in re.findall(r"<!--.*?-->", d, re.S) if text in c]
    return cs[0] if len(cs) == 1 else None
a, b = note(sys.argv[1], sys.argv[3]), note(sys.argv[2], sys.argv[3])
print(int(a is not None and a == b))
PY
)
        if [ "$whole" = 1 ]; then pass "(K4) $name: a FILE that lacks only this hash keeps the note inline, byte for byte (the (K2) predicate bites)"
        else bad "(K4) $name: the note was changed or left out for a caller that does not hold it"; fi
    else bad "(K4) $name: no hash to withhold"; fi
done <<<"$NOTES"

# ── (K3) lossless, well-formed, never longer, deterministic ─────────────────────────────────────────────────────────
for p in p1 p2 p3; do
    a=$(wc -c <"$WORK/$p.plain" | tr -d ' '); b=$(wc -c <"$WORK/$p.red" | tr -d ' ')
    ca=$(py commentbytes "$WORK/$p.plain"); cb=$(py commentbytes "$WORK/$p.red")
    if [ "$(py lossless "$WORK/$p.plain" "$WORK/$p.red")" = 1 ]; then pass "(K3) $p: comments and est_tokens= aside, byte-identical to the plain answer"
    else bad "(K3) $p: a row, CDATA or root attribute differs from the plain answer"; fi
    # every byte that went is a comment byte, up to the digits of the repriced est_tokens= value
    d=$(( (a - b) - (ca - cb) ))
    if [ "$b" -lt "$a" ] && [ "$d" -ge 0 ] && [ "$d" -le 4 ]; then pass "(K3b) $p: $(( a - b )) B shorter, $(( ca - cb )) B of it comment bytes (the rest is est_tokens= digits)"
    else bad "(K3b) $p: plain $a B, reduced $b B, comment bytes $ca -> $cb"; fi
    if xmllint --noout "$WORK/$p.red" 2>/dev/null; then pass "(K3c) $p: the reduced answer is well-formed XML"; else bad "(K3c) $p: the reduced answer is not well-formed"; fi
    if cmp -s "$WORK/$p.red" "$WORK/$p.red2"; then pass "(K3d) $p: same argv + same FILE, byte-identical"; else bad "(K3d) $p: two runs with the same FILE differ"; fi
    "$BIN" --legend-dict=seen <"$WORK/$p.red" >"$WORK/$p.red.seen" 2>/dev/null
    if [ -z "$(comm -13 "$WORK/$p.held" "$WORK/$p.red.seen")" ]; then pass "(K3e) $p: the reduced answer carries no entry its plain answer did not"
    else bad "(K3e) $p: the reduced answer yields hashes the plain one did not"; fi
done
# (K3n) mutation control for (K3): one row byte dropped must break the lossless predicate
python3 - "$WORK/p1.red" "$WORK/p1.mut" <<'PY'
import re, sys
d = open(sys.argv[1]).read()
m = re.search(r'<d [^>]* n="', d)
assert m, "no <d … n= row in the probe to mutate"
out = d[:m.end()] + d[m.end() + 1:]
open(sys.argv[2], "w").write(out)
PY
[ -s "$WORK/p1.mut" ] || bad "(K3n) the mutant was not written — the control below proves nothing"
if [ "$(py lossless "$WORK/p1.plain" "$WORK/p1.mut")" = 0 ]; then pass "(K3n) the lossless predicate bites on one dropped row byte"
else bad "(K3n) the lossless predicate cannot fail"; fi

if [ "$fail" -eq 0 ]; then echo "legendseenblockcheck: all arms PASS"; exit 0; fi
echo "legendseenblockcheck: FAILURES"; exit 1
