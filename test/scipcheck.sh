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
#     (degrade, never fail); a MISSING index REFUSES, exit 1 (arm 5b) — and so do an empty file and a
#     directory (namedfileinputcheck.sh arm F)
#   * FUZZ: 20 random truncations / byte-flips of the index → ripwire never crashes (exit 0 and degrades, or
#     the exit-1 refusal when a truncation leaves 0 bytes)
#   * TYPED RANGES: an index carrying scip.proto's `typed_range` oneof (single_line_range = 8,
#     multi_line_range = 9) instead of the deprecated `range` joins the same way, and the typed form
#     outranks a deprecated `range` on the same occurrence regardless of which arrives first
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
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
if [ $rc -eq 0 ]; then ok "corrupt index → exit 0 (did not fail)"; else no "corrupt index → nonzero exit ($rc)"; fi
diff -q <(printf '%s' "$NOSCIP") "$TMP/corrupt.out" >/dev/null && ok "corrupt index → output IDENTICAL to no---scip" \
    || { no "corrupt index changed the map"; diff <(printf '%s' "$NOSCIP") "$TMP/corrupt.out" | head; }
if grep -qi 'scip' "$TMP/corrupt.err"; then ok "corrupt index → stderr alert emitted"; else no "corrupt index → no stderr alert"; fi

# 5b) MISSING index → a REFUSAL, not a degrade. RE-PINNED 2026-09-04 (capture-audit M7, lens 6 F6): this
#     arm used to assert "exit 0, output identical, alert emitted", i.e. the caller who named a precision
#     index by path was handed the NAME-BASED map they were trying to improve on, under a stderr note no
#     pipeline reads. A path that cannot be OPENED is a caller mistake, and the eight sibling FILE inputs
#     all refuse it. Arm 5 above is untouched and is the reason the two cases are separated: a file that
#     opens and fails to DECODE still degrades byte-identically, which is what arm 6's fuzz depends on.
"$BIN" "$CORPUS" --scip="$TMP/does_not_exist.scip" $EXC --no-cache >"$TMP/miss.out" 2>"$TMP/miss.err"; rcm=$?
[ $rcm -eq 1 ] && [ ! -s "$TMP/miss.out" ] && grep -qi 'scip' "$TMP/miss.err" \
    && ok "missing index → exit 1, stdout empty, the refusal names --scip" \
    || no "missing index: expected a refusal (exit 1, empty stdout), got exit $rcm with $( wc -c <"$TMP/miss.out" ) B on stdout"

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
if [ "$crashes" -eq 0 ]; then ok "fuzz: 20 mangled indexes, ZERO crashes"; else no "fuzz: $crashes/20 mangled indexes crashed"; fi

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
if [ $rce -eq 0 ]; then ok "external-occurrence index → exit 0"; else no "external-occurrence index → nonzero exit ($rce)"; fi
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
if [ $rcs -eq 0 ]; then ok "stale index → exit 0 (degrades, never fails)"; else no "stale index → nonzero exit ($rcs)"; fi
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

# 10) TYPED_RANGE — scip.proto deprecated `Occurrence.range` (field 1) in favour of the `typed_range` oneof
#     (single_line_range = 8, multi_line_range = 9) and requires the typed form to win when both are set.
#     Every arm above feeds the reader an index make_index.py wrote with the deprecated field, so the reader
#     was only ever exercised against its own generator and a reader blind to fields 8/9 passed all of them.
#     make_index.py --typed re-encodes the same fixture in the typed form, spreading the three cases over
#     four occurrences: the `handler` def as a lone multi_line_range, the `helperAlpha` def as a lone
#     single_line_range, and the two refs each carrying BOTH a typed range and a deprecated one that points
#     at a line past EOF — one with the deprecated field first on the wire, one with the typed field first.
#     ASSERT: both refs pin (so the typed form wins in either order), the ratio reads 100% (2/2), and no def
#     goes unmatched. --typed --blind re-emits the same index with fields 8/9 stripped — precisely what a
#     typed_range-blind reader sees — and must pin NOTHING, which is what makes this arm discriminate.
python3 "$GEN" --typed "$TMP/typed.scip" 2>/dev/null && ok "make_index.py --typed generated a typed_range index" \
    || no "make_index.py --typed failed"
TYPED_ERR="$( "$BIN" "$CORPUS" --scip="$TMP/typed.scip" $EXC --no-cache 2>&1 >"$TMP/typed.out" )"; rct=$?
if [ $rct -eq 0 ]; then ok "typed_range index → exit 0"; else no "typed_range index → nonzero exit ($rct)"; fi
printf '%s\n' "$TYPED_ERR" | grep -q 'SCIP matched 100% of occurrences (2/2)' \
    && ok "typed_range: both ref occurrences matched (100%, 2/2)" \
    || { no "typed_range: refs not matched — the reader is not reading fields 8/9"; printf '    %s\n' "$TYPED_ERR"; }
# that the two defs BOUND at all is what the 2/2 above proves (a ref only counts toward the ratio once its
# symbol resolved into a def in this tree). This line guards the other direction: a typed range decoded to
# the WRONG line — end_line read as start_line, say — binds no def and shows up here.
printf '%s\n' "$TYPED_ERR" | grep -q '0 defs unmatched' \
    && ok "typed_range: no def bound to a wrong line (0 defs unmatched)" \
    || { no "typed_range: a def went unmatched — a typed range decoded to the wrong line"; printf '    %s\n' "$TYPED_ERR"; }
printf '%s\n' "$TYPED_ERR" | grep -q 'older commit' \
    && { no "typed_range: a fully-matched index wrongly claims 'older commit' staleness"; printf '    %s\n' "$TYPED_ERR"; } \
    || ok "typed_range: fully-matched index omits the 'older commit' hint"
grep -o 'precise=[0-9]*' "$TMP/typed.out" | grep -qx 'precise=2' && ok "typed_range: summary reports precise=2" \
    || { no "typed_range: summary precise!=2"; grep -o 'files=3[^-]*' "$TMP/typed.out"; }
# the caller ref carries typed-FIRST: its deprecated half points past EOF, so this edge exists only if the
# typed range won despite arriving before the deprecated one.
TYPED_RUN="$( tr '>' '\n' <"$TMP/typed.out" | awk '/n="run"/{f=1} f{print} /<\/s/{if(f)exit}' )"
N_TYPED="$( printf '%s' "$TYPED_RUN" | grep -c 'n="handler"' )"
[ "$N_TYPED" -eq 1 ] && printf '%s' "$TYPED_RUN" | grep -q 'n="handler" prov="scip"' \
    && ok "typed_range: typed-first occurrence wins — run→handler is ONE prov=\"scip\" edge" \
    || { no "typed_range: run→handler not a single prov=\"scip\" edge (found $N_TYPED handler edges)"; printf '    %s\n' "$TYPED_RUN"; }
printf '%s' "$TYPED_RUN" | grep -q 'amb=' \
    && { no "typed_range: run still carries amb="; printf '    %s\n' "$TYPED_RUN"; } \
    || ok "typed_range: run no longer carries amb= (pinned by the typed range)"
# the alpha.cpp ref carries deprecated-FIRST, and its target def came in as a lone single_line_range.
grep -q '<c n="helperAlpha" prov="scip"/>' "$TMP/typed.out" \
    && ok "typed_range: deprecated-first occurrence wins too — handler→helperAlpha carries prov=\"scip\"" \
    || { no "typed_range: handler→helperAlpha not pinned (deprecated field beat the typed one)"; grep -o '<r[ >].*</r>' "$TMP/typed.out"; }
if command -v xmllint >/dev/null 2>&1; then
    grep -o '<r[ >].*</r>' "$TMP/typed.out" >"$TMP/typed.doc.xml"   # §P8: attribute-agnostic, see note above
    xmllint --noout "$TMP/typed.doc.xml" 2>/dev/null && ok "typed_range: stdout still valid XML" \
        || { no "typed_range: stdout not well-formed"; head -c 300 "$TMP/typed.doc.xml"; }
fi
"$BIN" "$CORPUS" --scip="$TMP/typed.scip" $EXC --no-cache >"$TMP/ty1" 2>"$TMP/tye1"
"$BIN" "$CORPUS" --scip="$TMP/typed.scip" $EXC --no-cache >"$TMP/ty2" 2>"$TMP/tye2"
diff -q "$TMP/ty1" "$TMP/ty2" >/dev/null && diff -q "$TMP/tye1" "$TMP/tye2" >/dev/null \
    && ok "typed_range: deterministic (stdout AND stderr byte-identical run-to-run)" \
    || no "typed_range: non-deterministic output"

# 10b) DISCRIMINATION — the same index with fields 8/9 stripped. Both defs lose their range entirely and
#      both refs keep only their past-EOF deprecated line, so a reader that passes 10 must fail everything
#      here: zero precise edges and run back to the honest name-based split.
python3 "$GEN" --typed --blind "$TMP/blind.scip" 2>/dev/null && ok "make_index.py --typed --blind generated the typed_range-stripped index" \
    || no "make_index.py --typed --blind failed"
"$BIN" "$CORPUS" --scip="$TMP/blind.scip" $EXC --no-cache >"$TMP/blind.out" 2>/dev/null; rcb=$?
if [ $rcb -eq 0 ]; then ok "typed_range-stripped index → exit 0 (degrades, never fails)"; else no "typed_range-stripped index → nonzero exit ($rcb)"; fi
grep -q 'prov="scip"' "$TMP/blind.out" \
    && { no "discrimination: the stripped index still pinned an edge — arm 10 is vacuous"; } \
    || ok "discrimination: stripped index pins NOTHING (arm 10 measures the typed_range read, nothing else)"
BLIND_RUN="$( tr '>' '\n' <"$TMP/blind.out" | awk '/n="run"/{f=1} f{print} /<\/s/{if(f)exit}' )"
printf '%s' "$BLIND_RUN" | grep -q 'amb=' \
    && ok "discrimination: stripped index → run reverts to the name-based ambiguous split" \
    || { no "discrimination: stripped index → run not restored to name-based ambiguity"; printf '    %s\n' "$BLIND_RUN"; }

echo
[ "$fail" -eq 0 ] && { echo "scipcheck: ALL PASS"; exit 0; } || { echo "scipcheck: FAILURES above"; exit 1; }
