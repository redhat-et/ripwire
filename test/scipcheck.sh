#!/usr/bin/env bash
# scipcheck.sh — the W4-#15 SCIP precision-overlay gate.
#
#   test/scipcheck.sh                       # uses build/ripwire on test/scipfix
#   RIPWIRE_BIN=asan/ripwire test/scipcheck.sh
#
# The fixture test/scipfix/ has two sibling files (alpha.cpp, beta.cpp) that each define a same-named
# free function `handler`, and caller.cpp whose `run()` makes a bare `handler()` call. ripwire's name
# resolver keeps BOTH defs (same dir → tier 2) → an AMBIGUOUS split edge. The generated SCIP index
# (index.scip, from make_index.py — hand-rolled protobuf, stdlib only) pins the call to alpha.cpp's
# `handler`. This gate asserts the overlay contract:
#   * WITHOUT --scip → ambiguous>0 and run→handler is a SPLIT edge (two <c n="handler"/>)
#   * WITH    --scip → exactly ONE precise edge, prov="scip" present, ambiguous reduced (to 0 here), and
#                      precise=1 in the summary
#   * deterministic (run twice → byte-identical), xmllint-clean well-formed XML
#   * a CORRUPT (truncated) index → a stderr alert AND output byte-IDENTICAL to the no---scip run
#     (degrade, never fail); a MISSING index → same
#   * FUZZ: 20 random truncations / byte-flips of the index → ripwire never crashes (exit 0/degrades)
# Exits non-zero on any failure. Does NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/scipfix"
GEN="$CORPUS/make_index.py"
IDX="$CORPUS/index.scip"
EXC="--exclude=make_index.py"                         # keep the python generator out of the C++ map
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "scipcheck: BIN=$BIN  CORPUS=$CORPUS"

# 0) (re)generate the index from the checked-in generator so the gate is self-contained + reproducible.
python3 "$GEN" "$TMP/index.scip" 2>/dev/null && ok "make_index.py generated an index ($(wc -c <"$TMP/index.scip" | tr -d ' ') B)" \
    || { no "make_index.py failed to generate an index"; echo "  (need python3)"; }
# the checked-in index.scip must match a freshly generated one (the generator is the source of truth).
if [ -f "$IDX" ]; then
    cmp -s "$IDX" "$TMP/index.scip" && ok "checked-in index.scip == freshly generated" \
        || no "checked-in index.scip differs from make_index.py output (regenerate: python3 $GEN)"
else
    no "checked-in index.scip missing (run: python3 $GEN)"
fi
IDX="$TMP/index.scip"    # use the fresh one for the rest of the gate

# 1) BASELINE (no --scip): ambiguous>0 and the run→handler call is a SPLIT edge (two handler children).
BASE="$( "$BIN" "$CORPUS" $EXC --no-cache 2>/dev/null )"
AMB_BASE="$( printf '%s' "$BASE" | grep -o 'ambiguous=[0-9]*' | head -1 | grep -o '[0-9]*' )"
[ -n "$AMB_BASE" ] && [ "$AMB_BASE" -gt 0 ] && ok "baseline ambiguous=$AMB_BASE (>0, resolver guessed)" \
    || { no "baseline ambiguous not >0 (got '${AMB_BASE:-none}')"; printf '    %s\n' "$BASE"; }
# run's <s>…</s> block should carry TWO <c n="handler"/> (the split) in the baseline.
RUN_BASE="$( printf '%s' "$BASE" | tr '>' '\n' | awk '/n="run"/{f=1} f{print} /<\/s/{if(f)exit}' )"
N_BASE="$( printf '%s' "$RUN_BASE" | grep -c 'n="handler"' )"
[ "$N_BASE" -eq 2 ] && ok "baseline run→handler is a SPLIT edge (2 candidates)" \
    || { no "baseline run→handler not split (found $N_BASE handler edges, want 2)"; printf '    %s\n' "$RUN_BASE"; }

# 2) OVERLAY (--scip): exactly ONE precise handler edge with prov="scip", ambiguous reduced, precise=1.
OV="$( "$BIN" "$CORPUS" --scip="$IDX" $EXC --no-cache 2>/dev/null )"
AMB_OV="$( printf '%s' "$OV" | grep -o 'ambiguous=[0-9]*' | head -1 | grep -o '[0-9]*' )"
[ -n "$AMB_OV" ] && [ "$AMB_OV" -lt "$AMB_BASE" ] && ok "ambiguous reduced by SCIP ($AMB_BASE → $AMB_OV)" \
    || { no "ambiguous not reduced (baseline=$AMB_BASE overlay=${AMB_OV:-none})"; printf '    %s\n' "$OV"; }
printf '%s' "$OV" | grep -o 'precise=[0-9]*' | grep -q 'precise=1' && ok "summary reports precise=1" \
    || { no "summary precise!=1"; printf '    %s\n' "$OV"; }
RUN_OV="$( printf '%s' "$OV" | tr '>' '\n' | awk '/n="run"/{f=1} f{print} /<\/s/{if(f)exit}' )"
N_OV="$( printf '%s' "$RUN_OV" | grep -c 'n="handler"' )"
[ "$N_OV" -eq 1 ] && ok "overlay run→handler collapsed to ONE edge" \
    || { no "overlay run→handler not single (found $N_OV, want 1)"; printf '    %s\n' "$RUN_OV"; }
printf '%s' "$RUN_OV" | grep -q 'n="handler" prov="scip"' && ok "the precise edge carries prov=\"scip\"" \
    || { no "no prov=\"scip\" on the precise edge"; printf '    %s\n' "$RUN_OV"; }
# and run is no longer flagged ambiguous (amb= absent on the run symbol).
printf '%s' "$RUN_OV" | grep -q 'amb=' && { no "run still carries amb= under --scip"; printf '    %s\n' "$RUN_OV"; } \
    || ok "run no longer carries amb= (pinned by SCIP)"

# 3) DETERMINISM — the overlay run is byte-identical run-to-run.
"$BIN" "$CORPUS" --scip="$IDX" $EXC --no-cache >"$TMP/ov1" 2>/dev/null
"$BIN" "$CORPUS" --scip="$IDX" $EXC --no-cache >"$TMP/ov2" 2>/dev/null
diff -q "$TMP/ov1" "$TMP/ov2" >/dev/null && ok "determinism (overlay byte-identical, $(wc -c <"$TMP/ov1" | tr -d ' ') B)" \
    || no "determinism (overlay non-deterministic)"

# 4) WELL-FORMED — the overlay output is valid XML (extract the <r>…</r> document; ripwire emits it raw).
if command -v xmllint >/dev/null 2>&1; then
# §P8 (2026-07-28) — REPINNED: the map root is now `<r est_tokens="N">` (the flagship map's own size
# became a machine-readable ATTRIBUTE instead of comment-only text). These extractions matched the literal
# `<r>` with no attributes, so they silently produced an EMPTY document and xmllint failed on nothing at
# all. Matching `<r` followed by a space-or-'>' is attribute-agnostic and will not need repinning again.
    printf '%s' "$OV" | grep -o '<r[ >].*</r>' >"$TMP/doc.xml"
    xmllint --noout "$TMP/doc.xml" 2>/dev/null && ok "overlay XML is well-formed (xmllint clean)" \
        || { no "overlay XML not well-formed"; head -c 400 "$TMP/doc.xml"; }
else
    printf '  SKIP  xmllint not installed\n'
fi

# 5) CORRUPT index → stderr alert AND output byte-IDENTICAL to the no---scip run (degrade, never change map).
NOSCIP="$( "$BIN" "$CORPUS" $EXC --no-cache 2>/dev/null )"
head -c 40 "$IDX" >"$TMP/trunc.scip"
"$BIN" "$CORPUS" --scip="$TMP/trunc.scip" $EXC --no-cache >"$TMP/corrupt.out" 2>"$TMP/corrupt.err"; rc=$?
[ $rc -eq 0 ] && ok "corrupt index → exit 0 (did not fail)" || no "corrupt index → nonzero exit ($rc)"
diff -q <(printf '%s' "$NOSCIP") "$TMP/corrupt.out" >/dev/null && ok "corrupt index → output IDENTICAL to no---scip" \
    || { no "corrupt index changed the map"; diff <(printf '%s' "$NOSCIP") "$TMP/corrupt.out" | head; }
grep -qi 'scip' "$TMP/corrupt.err" && ok "corrupt index → stderr alert emitted" || no "corrupt index → no stderr alert"

# 5b) MISSING index → same degrade contract.
"$BIN" "$CORPUS" --scip="$TMP/does_not_exist.scip" $EXC --no-cache >"$TMP/miss.out" 2>"$TMP/miss.err"; rcm=$?
[ $rcm -eq 0 ] && diff -q <(printf '%s' "$NOSCIP") "$TMP/miss.out" >/dev/null && grep -qi 'scip' "$TMP/miss.err" \
    && ok "missing index → exit 0, output identical, alert emitted" || no "missing index degrade contract broken"

# 6) FUZZ — 20 random truncations / byte-flips of the index must never crash ripwire (it degrades).
SZ="$( wc -c <"$IDX" | tr -d ' ' )"
crashes=0
for i in $( seq 1 20 ); do
    cp "$IDX" "$TMP/fuzz.scip"
    if [ $(( i % 2 )) -eq 0 ]; then
        # truncate to a random length in [0, SZ)
        n=$(( RANDOM % ( SZ + 1 ) ))
        head -c "$n" "$IDX" >"$TMP/fuzz.scip"
    else
        # flip a random byte
        off=$(( RANDOM % SZ ))
        val=$(( RANDOM % 256 ))
        printf "$(printf '\\%o' "$val")" | dd of="$TMP/fuzz.scip" bs=1 seek="$off" count=1 conv=notrunc 2>/dev/null
    fi
    "$BIN" "$CORPUS" --scip="$TMP/fuzz.scip" $EXC --no-cache >/dev/null 2>&1
    rcf=$?
    # a crash is signal-death (rc >= 128); a clean degrade is rc 0. Anything 128+ (SIGSEGV/SIGABRT) fails.
    if [ $rcf -ge 128 ]; then crashes=$(( crashes + 1 )); echo "    fuzz iter $i: crash (rc=$rcf)"; fi
done
[ "$crashes" -eq 0 ] && ok "fuzz: 20 mangled indexes, ZERO crashes" || no "fuzz: $crashes/20 mangled indexes crashed"

# 7) S5 FRESH-INDEX MATCH RATIO — the overlay run now emits a one-line match-ratio note on STDERR (only
#    when --scip is active), and it must NOT leak into stdout (the map). Fresh index → 100%, no stale hint.
OV_ERR="$( "$BIN" "$CORPUS" --scip="$IDX" $EXC --no-cache 2>&1 >/dev/null )"
printf '%s\n' "$OV_ERR" | grep -q 'SCIP matched 100% of occurrences (1/1)' \
    && ok "fresh index → match-ratio note fires (100%, 1/1)" \
    || { no "fresh index → no/incorrect match-ratio note"; printf '    %s\n' "$OV_ERR"; }
printf '%s\n' "$OV_ERR" | grep -q 'older commit' \
    && { no "fresh index note wrongly claims 'older commit'"; printf '    %s\n' "$OV_ERR"; } \
    || ok "fresh index note omits the 'older commit' hint (not stale)"
# the note is stderr-only: stdout must carry no 'SCIP matched' text.
"$BIN" "$CORPUS" --scip="$IDX" $EXC --no-cache 2>/dev/null | grep -q 'SCIP matched' \
    && no "match-ratio note leaked into STDOUT (must be stderr-only)" \
    || ok "match-ratio note is stderr-only (absent from stdout)"

# 7b) A4-F21 — S5 ratio denominator must EXCLUDE external (unmatchable) ref occurrences, and the note must
#     report matched-PRE-DEDUP over internal-only occurrences, not deduped-edges over ALL occurrences. The
#     old ratio was edgesPinned/refOccurrences: refOccurrences counts EVERY ref occurrence including ones
#     whose symbol never resolves to any def in the index (external std::/library refs — the majority in
#     real code), so a perfectly fresh, fully-matched index still read low. make_index.py --external adds
#     ONE such unmatchable occurrence alongside the one real (internal, matched) handler reference: the OLD
#     formula would have reported 50% (1 pinned edge / 2 total occurrences); the FIX must still report 100%
#     (1 matched / 1 internal — the external occurrence is excluded from the denominator, not folded in as
#     a miss) and separately surface that one external occurrence was skipped.
python3 "$GEN" --external "$TMP/external.scip" 2>/dev/null && ok "make_index.py --external generated an index with one external occurrence" \
    || no "make_index.py --external failed"
EXT_ERR="$( "$BIN" "$CORPUS" --scip="$TMP/external.scip" $EXC --no-cache 2>&1 >"$TMP/external.out" )"; rce=$?
[ $rce -eq 0 ] && ok "external-occurrence index → exit 0" || no "external-occurrence index → nonzero exit ($rce)"
printf '%s\n' "$EXT_ERR" | grep -q 'SCIP matched 100% of occurrences (1/1)' \
    && ok "A4-F21: external occurrence excluded from denominator — still reports 100% (1/1), not 50% (1/2)" \
    || { no "A4-F21: ratio deflated by the external occurrence"; printf '    %s\n' "$EXT_ERR"; }
printf '%s\n' "$EXT_ERR" | grep -q '1 external (unmatchable) occurrences skipped' \
    && ok "A4-F21: the external occurrence is reported separately, not silently dropped" \
    || { no "A4-F21: no separate external-occurrence count in the diagnostic"; printf '    %s\n' "$EXT_ERR"; }
printf '%s\n' "$EXT_ERR" | grep -q 'older commit' \
    && { no "A4-F21: a fully-matched (internal) index wrongly claims 'older commit' staleness"; printf '    %s\n' "$EXT_ERR"; } \
    || ok "A4-F21: fully-matched index (ignoring the external ref) omits the 'older commit' hint"
# the precise edge itself must still be pinned correctly (the external occurrence must not perturb it).
grep -q 'n="handler" prov="scip"' "$TMP/external.out" \
    && ok "A4-F21: precise handler edge still pinned correctly alongside the external occurrence" \
    || { no "A4-F21: precise edge missing/altered with an external occurrence present"; printf '    %s\n' "$(cat "$TMP/external.out")"; }

# 8) S5 STALE-INDEX MIS-ATTRIBUTION GATE — an index from an OLDER commit (make_index.py --stale) records
#    the caller's `handler` reference ONE LINE OFF the real call site. The OLD line-scan trusted that stale
#    line and pinned run→handler prov="scip" (silent mis-attribution). The fix keys the enclosing symbol on
#    ripwire's OWN reference at that exact (file,line): no parsed reference there → the occurrence is DROPPED.
#    ASSERT: (a) the match-ratio note fires flagging staleness; (b) NO wrong precise edge — no prov="scip"
#    anywhere, no precise= in the header, run reverts to the honest name-based ambiguous split; (c) valid xml.
python3 "$GEN" --stale "$TMP/stale.scip" 2>/dev/null && ok "make_index.py --stale generated a stale index" \
    || no "make_index.py --stale failed"
STALE_ERR="$( "$BIN" "$CORPUS" --scip="$TMP/stale.scip" $EXC --no-cache 2>&1 >"$TMP/stale.out" )"; rcs=$?
[ $rcs -eq 0 ] && ok "stale index → exit 0 (degrades, never fails)" || no "stale index → nonzero exit ($rcs)"
printf '%s\n' "$STALE_ERR" | grep -Eq 'SCIP matched [0-9]+% of occurrences.*older commit' \
    && ok "stale index → match-ratio note fires with 'older commit' staleness hint" \
    || { no "stale index → no staleness match-ratio note"; printf '    %s\n' "$STALE_ERR"; }
# (b) the mis-attribution gate: the stale ref must be DROPPED, not pinned to a wrong current symbol.
grep -q 'prov="scip"' "$TMP/stale.out" \
    && { no "STALE INDEX EMITTED A prov=\"scip\" EDGE — mis-attribution NOT prevented"; } \
    || ok "stale index → NO prov=\"scip\" edge (stale ref dropped, not mis-attributed)"
grep -q 'precise=' "$TMP/stale.out" \
    && { no "stale index → header still reports precise= (a wrong precise edge slipped through)"; } \
    || ok "stale index → header carries no precise= (zero precise edges, none wrong)"
STALE_RUN="$( tr '>' '\n' <"$TMP/stale.out" | awk '/n="run"/{f=1} f{print} /<\/s/{if(f)exit}' )"
printf '%s' "$STALE_RUN" | grep -q 'amb=' \
    && ok "stale index → run reverts to honest name-based ambiguous split (amb= present)" \
    || { no "stale index → run not restored to name-based ambiguity"; printf '    %s\n' "$STALE_RUN"; }
if command -v xmllint >/dev/null 2>&1; then
    grep -o '<r[ >].*</r>' "$TMP/stale.out" >"$TMP/stale.doc.xml"   # §P8: attribute-agnostic, see note above
    xmllint --noout "$TMP/stale.doc.xml" 2>/dev/null && ok "stale index → stdout still valid XML" \
        || { no "stale index → stdout not well-formed"; head -c 300 "$TMP/stale.doc.xml"; }
fi
# (d) DETERMINISM on the stale-index run — twice, byte-identical (note is a deterministic fn of index+tree).
"$BIN" "$CORPUS" --scip="$TMP/stale.scip" $EXC --no-cache >"$TMP/st1" 2>"$TMP/ste1"
"$BIN" "$CORPUS" --scip="$TMP/stale.scip" $EXC --no-cache >"$TMP/st2" 2>"$TMP/ste2"
diff -q "$TMP/st1" "$TMP/st2" >/dev/null && diff -q "$TMP/ste1" "$TMP/ste2" >/dev/null \
    && ok "stale index → deterministic (stdout AND stderr byte-identical run-to-run)" \
    || no "stale index → non-deterministic output"

# 9) MUTATION TEST — corrupt the stale index's KNOWN-GOOD 'no prov=scip' assertion by feeding the FRESH
#    index through the same check: the fresh index DOES pin one prov="scip" edge, so a check that passed on
#    "no prov=scip" must FAIL here. This proves the assertion in step 8(b) actually discriminates.
if grep -q 'prov="scip"' <( "$BIN" "$CORPUS" --scip="$IDX" $EXC --no-cache 2>/dev/null ); then
    ok "mutation: the 'no prov=scip' assertion discriminates (fresh index DOES emit prov=scip)"
else
    no "mutation: fresh index unexpectedly lacks prov=scip — step-8(b) assertion is vacuous"
fi

echo
[ "$fail" -eq 0 ] && { echo "scipcheck: ALL PASS"; exit 0; } || { echo "scipcheck: FAILURES above"; exit 1; }
