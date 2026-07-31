#!/usr/bin/env bash
# notescheck.sh — gate for L3 repo field notes (B11, PLAN_agentLeverage2026.md §L3): committed, human-reviewable
# WRITE-side memory keyed to symbols/files, surfaced at retrieval.
#
# Covers, per the plan's gate spec:
#   • --note-add appends+re-sorts+prints the written line; the date is git's committer clock (deterministic)
#   • a note on a SYMBOL appears as a <note> child when --for emits that symbol, and when --expand emits its body
#   • a note on a FILE appears as a <note> child on the <f> that --for emits
#   • INERTNESS: an ABSENT or EMPTY notes file → byte-identical output on --for / --expand / the default map (cmp)
#   • sorted round-trip stability (the file self-heals to canonical order; two adds stay sorted)
#   • a DANGLING target (no matching indexed symbol/file) is flagged in --notes but surfaces NOWHERE else
#   • HOSTILE note text (XML metachars, a "]]>" CDATA-close) is emitted safely (xmllint-clean)
#   • determinism ×3, xmllint on every emitting verb, refuse-loudly on a malformed --note-add
#   • MCP parity for BOTH the `for` verb (<note> children) and the `fetch_body` body verb (JSON notes array)
#
# Operates on a private temp git repo (never touches the real repo). Needs git.
# Usage:  CTXPACK_BIN=build/ctxpack bash test/notescheck.sh   |   CTXPACK_BIN=asan/ctxpack bash …

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# Both seams: a positional argument wins, then CTXPACK_BIN, then the dev build. The positional form is what
# a red-first run uses (`bash test/notescheck.sh <scratch>/base_w3`) and this gate only had the env one.
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src"
cat > "$WORK/src/a.cpp" <<'EOF'
struct Widget {
    int compute( int x ) { return helper( x ); }
};
int helper( int x ) { return x + 1; }
int lonely( int y ) { return y * 2; }
EOF
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )

echo "notescheck: BIN=$BIN  (temp git repo)"

run(){ ( cd "$WORK" && "$BIN" . --no-cache "$@" 2>/dev/null ); }

# canonical forms EXACTLY as this run spells them (the target must match what serialization emits) — discover
# them so the gate is independent of how ing spells the root prefix.
MAP0="$( run )"
FILE_TARGET="$( printf '%s' "$MAP0" | grep -oE '<f p="[^"]*a\.cpp"' | head -1 | sed -E 's/<f p="([^"]*)"/\1/' )"
COMPUTE_ID="$( printf '%s' "$MAP0" | grep -oE 'id="[^"]*compute"' | head -1 | sed -E 's/id="([^"]*)"/\1/' )"
[ -n "$FILE_TARGET" ] && ok "discovered file target: $FILE_TARGET" || no "could not discover the a.cpp file path"
[ -n "$COMPUTE_ID" ]  && ok "discovered scoped canonical id: $COMPUTE_ID" || no "could not discover Widget::compute canonical id"
# D5: --note-add normalizes a target's path component to ROOT-RELATIVE on write, stripping any leading
# "./" the crawl (root=".") spells its paths with — the NORMALIZED forms are what actually land on disk.
NORM_FILE_TARGET="${FILE_TARGET#./}"
NORM_COMPUTE_ID="${COMPUTE_ID#./}"

# ── INERTNESS: capture the pre-notes output of every emitting verb (absent notes file) ─────────────────────
FOR_ABSENT="$( run --for="widget compute helper lonely" )"
EXP_ABSENT="$( run --expand=helper )"
MAP_ABSENT="$( run )"

# an EMPTY notes file must be byte-identical to an absent one
: > "$WORK/.ctxpack_notes"
[ "$FOR_ABSENT" = "$( run --for="widget compute helper lonely" )" ] && ok "inert: empty notes file → --for byte-identical" || no "empty notes file changed --for output"
[ "$EXP_ABSENT" = "$( run --expand=helper )" ]                       && ok "inert: empty notes file → --expand byte-identical" || no "empty notes file changed --expand output"
[ "$MAP_ABSENT" = "$( run )" ]                                       && ok "inert: empty notes file → default map byte-identical" || no "empty notes file changed the default map"
# a header-comment-only file is still empty of notes → still inert
printf '# ctxpack field notes v1 — just the header\n' > "$WORK/.ctxpack_notes"
[ "$FOR_ABSENT" = "$( run --for="widget compute helper lonely" )" ] && ok "inert: comment-only notes file → --for byte-identical" || no "comment-only notes file changed --for output"
rm -f "$WORK/.ctxpack_notes"

# ── --note-add: prints the written line, writes a sorted file, date from git committer clock ───────────────
GIT_DATE="$( cd "$WORK" && git log -1 --format=%cs HEAD )"
GIT_SHA_FULL="$( cd "$WORK" && git rev-parse HEAD )"
GIT_SHA="${GIT_SHA_FULL:0:7}"
GIT_BRANCH="$( cd "$WORK" && git rev-parse --abbrev-ref HEAD )"
LINE_F="$( run --note-add="$FILE_TARGET: watch the arena lifetime here" )"
printf '%s' "$LINE_F" | grep -qF "$NORM_FILE_TARGET" && printf '%s' "$LINE_F" | grep -qF "watch the arena lifetime here" \
    && ok "--note-add prints the exact written line (D5-normalized root-relative target + text)" || { no "--note-add did not print the written line"; printf '%s\n' "$LINE_F"; }
printf '%s' "$LINE_F" | grep -qF "$GIT_DATE" \
    && ok "--note-add dates the note with git's committer clock ($GIT_DATE), not wall time" || { no "--note-add date != git committer date"; printf '%s\n' "$LINE_F"; }
[ -f "$WORK/.ctxpack_notes" ] && ok "--note-add created $WORK/.ctxpack_notes" || no "--note-add did not create the notes file"

# ── provenance stamp: --note-add prints (and .ctxpack_notes stores) the writing repo's FULL HEAD sha +
#    branch, tab-appended after the 3 legacy fields — the printed line is the exact 5-field data line. ──────
printf '%s' "$LINE_F" | grep -qF "$( printf '%s\t%s\t%s\t%s\t%s' "$NORM_FILE_TARGET" "$GIT_DATE" "watch the arena lifetime here" "$GIT_SHA_FULL" "$GIT_BRANCH" )" \
    && ok "--note-add's printed line carries the FULL HEAD sha + branch (5-field provenance shape)" \
    || { no "--note-add's printed line is missing/wrong provenance fields"; printf '%s\n' "$LINE_F"; }
grep -qF "$( printf '%s\t%s\t%s\t%s\t%s' "$NORM_FILE_TARGET" "$GIT_DATE" "watch the arena lifetime here" "$GIT_SHA_FULL" "$GIT_BRANCH" )" "$WORK/.ctxpack_notes" \
    && ok ".ctxpack_notes stores the FULL sha on disk (abbreviation happens only at surfacing)" \
    || no ".ctxpack_notes does not store the full sha for a freshly-stamped note"

# add two MORE (a symbol note and a scoped-id note) that sort in a different order than added → self-heals sorted
run --note-add="helper: off-by-one lives here" >/dev/null
run --note-add="$COMPUTE_ID: scoped method note" >/dev/null
# the DATA lines (strip the '#' header) must be in sorted order
DATA="$( grep -v '^#' "$WORK/.ctxpack_notes" )"
[ "$DATA" = "$( printf '%s\n' "$DATA" | LC_ALL=C sort )" ] && ok "notes file stays SORTED across appends (merge-friendly round-trip)" || { no "notes file is not sorted"; printf '%s\n' "$DATA"; }
# idempotence: re-adding an identical triple does not duplicate
run --note-add="helper: off-by-one lives here" >/dev/null
[ "$( grep -c 'off-by-one lives here' "$WORK/.ctxpack_notes" )" = 1 ] && ok "--note-add is idempotent (no duplicate line for an identical triple)" || no "--note-add duplicated an identical note"

# ── surfacing in --for: file note on <f>, symbol note on <d> — both stamped, so both carry sha=/branch= ────
NOTE_OPEN='<note d="'"$GIT_DATE"'" sha="'"$GIT_SHA"'" branch="'"$GIT_BRANCH"'">'   # abbreviated (7-hex) sha at surfacing, full sha only on disk
FOR_OUT="$( run --for="widget compute helper lonely" )"
printf '%s' "$FOR_OUT" | grep -qF "$NOTE_OPEN"'<![CDATA[watch the arena lifetime here]]></note>' \
    && ok "--for surfaces the FILE note as a <note> child (CDATA-wrapped, dated, sha/branch-stamped)" || { no "--for did not surface the file note"; printf '%s\n' "$FOR_OUT" | head -c 600; echo; }
printf '%s' "$FOR_OUT" | grep -qF "$NOTE_OPEN"'<![CDATA[off-by-one lives here]]></note>' \
    && ok "--for surfaces the SYMBOL note (helper) as a <note> child, sha/branch-stamped" || { no "--for did not surface the symbol note"; printf '%s\n' "$FOR_OUT" | head -c 600; echo; }
printf '%s' "$FOR_OUT" | xmllint --noout - 2>/dev/null && ok "--for with notes is xmllint-clean" || no "--for with notes is not well-formed"

# ── surfacing in --expand: symbol note on <b> ─────────────────────────────────────────────────────────────
EXP_OUT="$( run --expand=helper )"
printf '%s' "$EXP_OUT" | grep -qF "$NOTE_OPEN"'<![CDATA[off-by-one lives here]]></note>' \
    && ok "--expand surfaces the symbol note on the <b> body, sha/branch-stamped" || { no "--expand did not surface the note"; printf '%s\n' "$EXP_OUT" | head -c 600; echo; }
printf '%s' "$EXP_OUT" | xmllint --noout - 2>/dev/null && ok "--expand with notes is xmllint-clean" || no "--expand with notes is not well-formed"

# ── dangling: a target with no matching symbol/file — flagged in --notes, surfaces NOWHERE else ────────────
run --note-add="ghost::nope::vanished: this dangling target does not exist" >/dev/null
NOTES_OUT="$( run --notes )"
printf '%s' "$NOTES_OUT" | grep -qF '<target id="ghost::nope::vanished" dangling="1">' \
    && ok "--notes flags the dangling target dangling=\"1\"" || { no "--notes did not flag the dangling target"; printf '%s\n' "$NOTES_OUT"; }
printf '%s' "$NOTES_OUT" | grep -qF '<target id="helper" dangling="0">' \
    && ok "--notes marks a live target dangling=\"0\"" || no "--notes mis-flagged a live target"
# inert elsewhere: the dangling note text must NOT appear in a --for / default-map / --expand emission
if run --for="ghost vanished dangling helper" | grep -qF 'this dangling target does not exist' \
   || run | grep -qF 'this dangling target does not exist' ; then
    no "dangling note leaked into a retrieval emission (must be listed ONLY by --notes)"
else
    ok "dangling note is inert everywhere except --notes"
fi
printf '%s' "$NOTES_OUT" | xmllint --noout - 2>/dev/null && ok "--notes is xmllint-clean" || no "--notes is not well-formed"

# ── hostile note text: XML metachars + a "]]>" CDATA-close must emit safely ────────────────────────────────
run --note-add="helper: danger ]]> <script>alpha & beta --> end" >/dev/null
run --for="helper" | xmllint --noout - 2>/dev/null && ok "hostile note text (incl. ]]>) keeps --for xmllint-clean" || no "hostile note text broke --for well-formedness"
run --notes        | xmllint --noout - 2>/dev/null && ok "hostile note text keeps --notes xmllint-clean" || no "hostile note text broke --notes well-formedness"
run --expand=helper | xmllint --noout - 2>/dev/null && ok "hostile note text keeps --expand xmllint-clean" || no "hostile note text broke --expand well-formedness"

# ── determinism ×3 (fixed notes file + fixed HEAD) ─────────────────────────────────────────────────────────
D1="$( run --for="widget compute helper" )"; D2="$( run --for="widget compute helper" )"; D3="$( run --for="widget compute helper" )"
{ [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ]; } && ok "--for with notes is deterministic (byte-identical ×3)" || no "--for with notes is non-deterministic"
N1="$( run --notes )"; N2="$( run --notes )"; N3="$( run --notes )"
{ [ "$N1" = "$N2" ] && [ "$N2" = "$N3" ]; } && ok "--notes is deterministic (byte-identical ×3)" || no "--notes is non-deterministic"

# ── refuse loudly on a malformed --note-add (no ': ' separator) ────────────────────────────────────────────
ERR="$( cd "$WORK" && "$BIN" . --no-cache --note-add="noSeparatorHere" 2>&1 >/dev/null )"
RC="$( cd "$WORK" && "$BIN" . --no-cache --note-add="noSeparatorHere" >/dev/null 2>&1; echo $? )"
{ [ "$RC" -ne 0 ] && printf '%s' "$ERR" | grep -qi 'TARGET'; } \
    && ok "malformed --note-add refuses loudly (exit $RC, names the format)" || { no "malformed --note-add should refuse loudly"; printf 'rc=%s err=%s\n' "$RC" "$ERR"; }

# ── MCP parity: `for` verb surfaces <note>, `fetch_body` surfaces a JSON notes array ───────────────────────
if command -v python3 >/dev/null 2>&1; then
    mcp(){ printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }
    FOR_MCP="$( mcp \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$WORK"'","task":"helper off by one"}}}' \
        | tail -1 | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["content"][0]["text"])' )"
    printf '%s' "$FOR_MCP" | grep -qF 'off-by-one lives here' \
        && ok "MCP for verb surfaces the <note> (parity with CLI --for)" || no "MCP for verb did not surface the note"

    H="$( mcp \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$WORK"'","symbol":"helper"}}}' \
        | tail -1 | python3 -c 'import sys,json; print(json.loads(json.load(sys.stdin)["result"]["content"][0]["text"])["symbol"]["handle"])' )"
    if printf '%s' "$H" | grep -Eq '^sym#[0-9a-f]{16}@[0-9a-f]{16}$'; then
        FB="$( mcp \
            '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
            '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$WORK"'","handle":"'"$H"'"}}}' \
            | tail -1 | python3 -c 'import sys,json
b=json.loads(json.load(sys.stdin)["result"]["content"][0]["text"])
ns=b.get("notes") or []
print("FOUND" if any("off-by-one lives here"==n.get("text") for n in ns) else "MISSING")' )"
        [ "$FB" = "FOUND" ] && ok "MCP fetch_body serves the note in its JSON notes array (body-verb parity)" || no "MCP fetch_body did not carry the note ($FB)"

        # provenance parity: the same note's JSON entry carries the abbreviated sha + branch (matching the
        # XML <note sha= branch=> shape), never the empty/legacy form for a note THIS run stamped.
        FB_PROV="$( mcp \
            '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
            '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$WORK"'","handle":"'"$H"'"}}}' \
            | tail -1 | python3 -c 'import sys,json
b=json.loads(json.load(sys.stdin)["result"]["content"][0]["text"])
ns=b.get("notes") or []
m=[n for n in ns if n.get("text")=="off-by-one lives here"]
print(m[0].get("sha","") + "|" + m[0].get("branch","") if m else "MISSING")' )"
        [ "$FB_PROV" = "$GIT_SHA|$GIT_BRANCH" ] \
            && ok "MCP fetch_body notes array carries the abbreviated sha + branch (provenance parity)" \
            || no "MCP fetch_body provenance mismatch: got '$FB_PROV', want '$GIT_SHA|$GIT_BRANCH'"
    else
        no "could not obtain a fetch_body handle for the MCP parity check (got '$H')"
    fi
else
    printf '  SKIP  MCP parity (no python3)\n'
fi

# ── D5 (AUDIT5 / plan X8): root-relative field-notes portability ───────────────────────────────────────────
# The committed .ctxpack_notes design is only merge-friendly/portable if targets are ROOT-RELATIVE — an
# absolute target dies on any other checkout's crawl root. normalizeNoteTarget() is the write+read seam:
# canonicalize an absolute in-root target to root-relative on write, refuse an outside-root target loudly,
# and re-normalize on read so a LEGACY absolute-target file (pre-fix) keeps surfacing without a rewrite.
rm -f "$WORK/.ctxpack_notes"
runAbs(){ ( cd "$WORK" && "$BIN" "$WORK" --no-cache "$@" 2>/dev/null ); }

# (1) a root-relative file target (no leading "./") is accepted as-is, surfaces on --for, and is NOT dangling.
run --note-add="src/a.cpp: D5 root-relative file note" >/dev/null
D5_FOR="$( run --for="widget compute helper lonely" )"
printf '%s' "$D5_FOR" | grep -qF "$NOTE_OPEN"'<![CDATA[D5 root-relative file note]]></note>' \
    && ok "D5(1): a root-relative file target (src/a.cpp) surfaces on --for" || { no "D5(1): root-relative file target did not surface"; printf '%s\n' "$D5_FOR" | head -c 400; echo; }
D5_NOTES="$( run --notes )"
printf '%s' "$D5_NOTES" | grep -qF '<target id="src/a.cpp" dangling="0">' \
    && ok "D5(1): the root-relative file target is NOT dangling" || { no "D5(1): root-relative file target flagged dangling"; printf '%s\n' "$D5_NOTES"; }

# (2) an ABSOLUTE in-root target normalizes to root-relative on write (root invoked absolute, so the crawl's
#     own path spelling is absolute too — the case the normalization exists for) and then surfaces.
LINE_ABS="$( runAbs --note-add="$WORK/src/a.cpp: D5 absolute in-root note" )"
printf '%s' "$LINE_ABS" | grep -qE '^src/a\.cpp[[:space:]]' \
    && ok "D5(2): an absolute in-root target normalizes to root-relative (src/a.cpp) on write" \
    || { no "D5(2): absolute in-root target did not normalize to src/a.cpp"; printf '%s\n' "$LINE_ABS"; }
D5_FOR_ABS="$( runAbs --for="widget compute helper lonely" )"
printf '%s' "$D5_FOR_ABS" | grep -qF "$NOTE_OPEN"'<![CDATA[D5 absolute in-root note]]></note>' \
    && ok "D5(2): the normalized absolute-in-root note surfaces on --for" || { no "D5(2): absolute-in-root note did not surface"; printf '%s\n' "$D5_FOR_ABS" | head -c 400; echo; }

# (3) an OUTSIDE-root target refuses loudly: non-zero exit, names the offending path/root, writes nothing.
#     (calls the binary directly, not runAbs — runAbs mutes stderr, and the refusal message lives there.)
OUTSIDE_ERR="$( cd "$WORK" && "$BIN" "$WORK" --no-cache --note-add="/etc/passwd: should never be written" 2>&1 >/dev/null )"
OUTSIDE_RC="$(  cd "$WORK" && "$BIN" "$WORK" --no-cache --note-add="/etc/passwd: should never be written" >/dev/null 2>&1; echo $? )"
{ [ "$OUTSIDE_RC" -ne 0 ] && printf '%s' "$OUTSIDE_ERR" | grep -qi 'outside'; } \
    && ok "D5(3): an outside-root absolute target refuses loudly (exit $OUTSIDE_RC)" || { no "D5(3): outside-root target was not refused"; printf 'rc=%s err=%s\n' "$OUTSIDE_RC" "$OUTSIDE_ERR"; }
grep -qF '/etc/passwd' "$WORK/.ctxpack_notes" \
    && no "D5(3): the refused outside-root target was written to .ctxpack_notes anyway" \
    || ok "D5(3): the refused outside-root target left .ctxpack_notes untouched"

# (4) a LEGACY absolute-target entry (as a pre-D5 ctxpack would have written it — never normalized) still
#     surfaces: readNotesRelative re-relativizes it against THIS run's root on load, no rewrite needed.
printf '%s\t2020-01-01\tD5 legacy absolute note\n' "$WORK/src/a.cpp" >> "$WORK/.ctxpack_notes"
D5_LEGACY="$( runAbs --for="widget compute helper lonely" )"
printf '%s' "$D5_LEGACY" | grep -qF '<![CDATA[D5 legacy absolute note]]>' \
    && ok "D5(4): a legacy (pre-fix) absolute-target entry still surfaces (read-side normalization)" || { no "D5(4): legacy absolute-target entry did not surface"; printf '%s\n' "$D5_LEGACY" | head -c 400; echo; }
D5_LEGACY_NOTES="$( runAbs --notes )"
printf '%s' "$D5_LEGACY_NOTES" | grep -qF '<target id="src/a.cpp" dangling="0">' \
    && ok "D5(4): the re-normalized legacy target is NOT dangling" || { no "D5(4): re-normalized legacy target flagged dangling"; printf '%s\n' "$D5_LEGACY_NOTES"; }

# ── provenance backward-compat: a genuinely LEGACY 3-field line (no sha/branch — exactly what a pre-this-
#    round .ctxpack_notes contains) reads correctly and surfaces with NO sha=/branch= attribute at all (never
#    a hollow sha="" — an absent attribute, per the "no sha shown rather than a wrong one" contract), sitting
#    in the SAME file as provenance-stamped entries added earlier in this run. ─────────────────────────────
printf '%s' "$D5_LEGACY" | grep -qE '<note d="2020-01-01"[^>]*sha=' \
    && no "D5(4b): the legacy 3-field note wrongly surfaced with a sha= attribute" \
    || ok "D5(4b): the legacy 3-field note surfaces with NO sha/branch attribute (backward-compat)"
printf '%s' "$D5_LEGACY" | grep -qF '<note d="2020-01-01"><![CDATA[D5 legacy absolute note]]></note>' \
    && ok "D5(4b): the legacy note's exact unstamped <note> shape is byte-for-byte the pre-provenance form" \
    || { no "D5(4b): legacy note shape changed"; printf '%s\n' "$D5_LEGACY" | head -c 400; echo; }
# the mixed file (legacy 3-field lines alongside 5-field stamped ones) round-trips through a re-sort/write
# (any further --note-add rewrites the whole file): legacy lines stay 3-field, stamped ones stay 5-field.
runAbs --note-add="$WORK/src/a.cpp: D5 trigger a rewrite" >/dev/null
LEGACY_LINE="$( grep -F 'D5 legacy absolute note' "$WORK/.ctxpack_notes" )"
[ "$( awk -F'\t' '{print NF}' <<< "$LEGACY_LINE" )" = 3 ] \
    && ok "D5(4c): round-trip keeps the legacy line 3-field (no padded-empty sha/branch tabs)" \
    || { no "D5(4c): legacy line gained extra fields on rewrite"; printf '%s\n' "$LEGACY_LINE"; }
STAMPED_LINE="$( grep -F 'D5 root-relative file note' "$WORK/.ctxpack_notes" )"
[ "$( awk -F'\t' '{print NF}' <<< "$STAMPED_LINE" )" = 5 ] \
    && ok "D5(4c): round-trip keeps a stamped line 5-field" \
    || { no "D5(4c): stamped line lost its provenance fields on rewrite"; printf '%s\n' "$STAMPED_LINE"; }

# (5) det-gate on an output containing notes in every form this section exercised (root-relative,
#     normalized-absolute, and re-normalized-legacy targets all resolving to the same live symbol/file).
DG1="$( runAbs --for="widget compute helper lonely" )"; DG2="$( runAbs --for="widget compute helper lonely" )"; DG3="$( runAbs --for="widget compute helper lonely" )"
{ [ "$DG1" = "$DG2" ] && [ "$DG2" = "$DG3" ]; } && ok "D5(5): det-gate — --for with mixed-form notes is byte-identical ×3" || no "D5(5): det-gate failed on mixed-form notes"
printf '%s' "$DG1" | xmllint --noout - 2>/dev/null && ok "D5(5): mixed-form notes output is xmllint-clean" || no "D5(5): mixed-form notes output is not well-formed"

# (6) SYM (bare-name) targets are unaffected by the D5 path normalization — a scope-less free function's
#     canonical id has no path component at all, so it must round-trip byte-for-byte, exactly as before D5.
run --note-add="lonely: D5 sym-target regression check" >/dev/null
D5_SYM="$( run --for="widget compute helper lonely" )"
printf '%s' "$D5_SYM" | grep -qF "$NOTE_OPEN"'<![CDATA[D5 sym-target regression check]]></note>' \
    && ok "D5(6): a bare-name SYM target is unaffected by root-relative normalization" || { no "D5(6): bare-name SYM target regressed"; printf '%s\n' "$D5_SYM" | head -c 400; echo; }

# ── R6: decision-shaped note nudge — gentle stderr tip, never a refusal, never touches stdout/XML ──────────
rm -f "$WORK/.ctxpack_notes"
runSplit(){ ( cd "$WORK" && "$BIN" . --no-cache "$@" ) >"$OUT_F" 2>"$ERR_F"; }   # splits stdout/stderr into $OUT_F/$ERR_F
OUT_F="$( mktemp )"; ERR_F="$( mktemp )"

# (1) a decision-shaped note (carries a causal/decision marker) produces NO nudge on stderr.
runSplit --note-add="helper: chose refcount over raw pointer because the arena outlives the handle"
DECISION_OUT="$( cat "$OUT_F" )"; DECISION_ERR="$( cat "$ERR_F" )"
[ -n "$DECISION_OUT" ] && printf '%s' "$DECISION_OUT" | grep -qF "chose refcount over raw pointer" \
    && ok "R6: decision-shaped note still writes normally (stdout has the written line)" || { no "R6: decision-shaped note-add produced no stdout"; printf '%s\n' "$DECISION_OUT"; }
[ -z "$DECISION_ERR" ] && ok "R6: decision-shaped note text produces NO nudge on stderr" || { no "R6: decision-shaped note text unexpectedly nudged"; printf '%s\n' "$DECISION_ERR"; }

# (2) a plain-prose note (no marker) produces the nudge on stderr, but still writes (never a refusal) and the
#     nudge text never lands on stdout.
runSplit --note-add="lonely: watch the arena lifetime here"
PROSE_OUT="$( cat "$OUT_F" )"; PROSE_ERR="$( cat "$ERR_F" )"
[ -n "$PROSE_OUT" ] && printf '%s' "$PROSE_OUT" | grep -qF "watch the arena lifetime here" \
    && ok "R6: prose note still writes normally despite the nudge (never a refusal)" || { no "R6: prose note-add did not write"; printf '%s\n' "$PROSE_OUT"; }
printf '%s' "$PROSE_ERR" | grep -qi 'tip:' && printf '%s' "$PROSE_ERR" | grep -qi 'chose X over Y because Z' \
    && ok "R6: prose note text (no causal/decision marker) produces the suggested-shape nudge on stderr" || { no "R6: prose note text did not produce the expected nudge"; printf '%s\n' "$PROSE_ERR"; }
printf '%s' "$PROSE_OUT" | grep -qi 'tip:' && no "R6: the nudge leaked into stdout" || ok "R6: the nudge never touches stdout"

# (3) XML output (a later --for emission of the same symbols) is byte-identical whether or not a nudge fired —
#     the nudge is stderr-only, so it can never perturb what a downstream tool consumes on stdout.
XML_A="$( run --for="widget compute helper lonely" )"
XML_B="$( run --for="widget compute helper lonely" )"
[ "$XML_A" = "$XML_B" ] && ok "R6: --for XML is byte-identical regardless of nudge history (det-gate)" || no "R6: --for XML changed across nudge-triggering note-adds"
printf '%s' "$XML_A" | grep -qi 'tip:' && no "R6: the nudge text leaked into --for XML output" || ok "R6: --for XML carries no nudge text"
printf '%s' "$XML_A" | xmllint --noout - 2>/dev/null && ok "R6: --for XML after nudge-triggering adds is still xmllint-clean" || no "R6: --for XML after nudge-triggering adds is not well-formed"

> "$OUT_F"; > "$ERR_F"

# ── §S3 (capture-audit-4): --note-add's blank-payload predicate ────────────────────────────────────────────
#
# --note-add decided "present but carries nothing" with notes::sanitizeField (\t \n \r -> space, ASCII-space
# trim) plus .empty(). That refused an ASCII-blank note and ACCEPTED six other blank classes, committing an
# invisible row into .ctxpack_notes — a file the tool tells users to commit and merge. The verdict now comes
# from ctx::hasVisibleContent (src/blanktext.h), the SAME derived table the MCP edit verbs read, so this gate
# and mcpframehonestycheck's (K) arms are two callers of one rule rather than two rules.
#
# The classes are the ones the audit measured, one per Unicode reason: NBSP (Zs), ZWSP (Cf), BOM (Cf),
# BRAILLE PATTERN BLANK (the glyph no property calls blank), a bidi RLO (Trojan-Source Cf) and a raw VT
# (a C0 control sanitizeField does not map). Each is asserted THREE ways — exit 1, nothing appended to the
# file, and the refusal SPELLS the code point rather than echoing the invisible bytes.
rm -f "$WORK/.ctxpack_notes"
noteAddBlank(){ ( cd "$WORK" && "$BIN" . --no-cache --note-add="alpha: $1" ) >"$OUT_F" 2>"$ERR_F"; }

blankRows(){ [ -f "$WORK/.ctxpack_notes" ] && grep -c . "$WORK/.ctxpack_notes" || echo 0; }
ROWS_BEFORE="$( blankRows )"

# NB the payloads are built with printf so the bytes are exact — a literal in this file would be at the mercy
# of whatever normalized it last.
for probe in "NBSP:\302\240:U+00A0" "ZWSP:\342\200\213:U+200B" "BOM:\357\273\277:U+FEFF" \
             "BRAILLE:\342\240\200:U+2800" "RLO:\342\200\256:U+202E" "VT:\013:U+000B"; do
    label="${probe%%:*}"; rest="${probe#*:}"; bytes="${rest%%:*}"; want="${rest##*:}"
    noteAddBlank "$( printf "$bytes" )"; rc=$?
    [ "$rc" -eq 1 ] && ok "§S3 --note-add refuses a $label-only note (exit 1)" \
                    || no "§S3 --note-add accepted a $label-only note (exit $rc) — it would be committed to .ctxpack_notes"
    [ ! -s "$OUT_F" ] && ok "§S3 the $label refusal wrote no line to stdout" \
                      || no "§S3 the $label refusal still printed a written line: [$( head -c 120 "$OUT_F" )]"
    grep -qF "$want" "$ERR_F" && ok "§S3 the $label refusal SPELLS the code point ($want), it does not echo the bytes" \
                              || no "§S3 the $label refusal does not name $want: [$( grep -v 'tip:' "$ERR_F" | head -c 160 )]"
done
ROWS_AFTER="$( blankRows )"
[ "$ROWS_BEFORE" = "$ROWS_AFTER" ] && ok "§S3 six blank classes appended ZERO rows to .ctxpack_notes ($ROWS_AFTER)" \
                                   || no "§S3 .ctxpack_notes grew from $ROWS_BEFORE to $ROWS_AFTER rows across the blank probes"

# the TARGET half — the sibling-completeness lens. Both fields go through the same predicate, so a blank
# target must refuse for the same reason a blank text does; nothing in the audit had probed it.
noteAddBlank_target(){ ( cd "$WORK" && "$BIN" . --no-cache --note-add="$1: some real text" ) >"$OUT_F" 2>"$ERR_F"; }
noteAddBlank_target "$( printf '\302\240' )"; rc=$?
{ [ "$rc" -eq 1 ] && grep -qF "U+00A0" "$ERR_F"; } \
    && ok "§S3 a blank TARGET refuses too, spelled (the sibling half)" \
    || no "§S3 a blank TARGET was accepted (exit $rc): [$( grep -v 'tip:' "$ERR_F" | head -c 160 )]"

# the two shapes that were ALREADY refused keep their sentence byte-for-byte: this fix must widen the refusal
# set, never re-word the cases that were correct. An empty and an ASCII-blank field both have nothing to
# spell, so they must still read `text=''`.
for pay in "" "   "; do
    noteAddBlank "$pay"; rc=$?
    { [ "$rc" -eq 1 ] && grep -qF "text=''" "$ERR_F"; } \
        && ok "§S3 the pre-existing refusal for an ASCII-blank/empty text is unchanged (text='')" \
        || no "§S3 the ASCII-blank/empty refusal was re-worded (exit $rc): [$( grep -v 'tip:' "$ERR_F" | head -c 160 )]"
done

# the CONTROL: content that merely CONTAINS an invisible code point still writes. Without this the arms above
# would pass on a binary that refuses every note.
noteAddBlank "$( printf 'chose a\302\240b over c because d' )"; rc=$?
{ [ "$rc" -eq 0 ] && [ -s "$OUT_F" ]; } \
    && ok "§S3 control: a note whose text merely CONTAINS an NBSP still writes (exit 0)" \
    || no "§S3 control: a note with real content was refused (exit $rc) — the predicate over-refuses"

rm -f "$OUT_F" "$ERR_F"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
# CA4 §B15 / trap #27: this file used to stop at the line above and return 0 — `||`'s echo succeeds, so
# every FAIL printed above rode along green, because regression.sh's verdict is the EXIT CODE. Wave 3's own
# §S3 arms (c72f230) landed INTO this un-failable gate. test/gateexitcheck.sh is the sweep that keeps it true.
exit "$fail"
